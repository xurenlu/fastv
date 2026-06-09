//
//  EmailIdleService.swift
//  fastv
//
//  IMAP IDLE 长连接 push 通知服务。
//  为默认邮件账号的 INBOX 维持一条独立的 IMAP 长连接，服务器有新邮件到达时
//  通过 untagged EXISTS 通知 socket 变为可读；本服务捕捉到后退出 IDLE 并
//  触发 `onNewMessage` 回调，由 ViewModel 决定是否同步收件箱。
//
//  设计要点：
//    - 与 EmailService.shared 完全独立 —— EmailService 的 session 是
//      "用完即弃"，这里则要求长寿命 session，必须隔离避免互相释放。
//    - 单账号单 Task；新建之前自动停掉旧 Task，防止账号删除/切换后泄漏。
//    - poll/select fd 超时 = 25 分钟（IMAP RFC 推荐 ≤ 29 分钟），到点主动
//      idle_done + idle 续期。
//    - 异常 (网络断开/服务器踢出/参数错误) → 指数退避重连，避免在没网时
//      狂打 CPU。
//

import Foundation
import Darwin
import Combine

@MainActor
final class EmailIdleService {
    static let shared = EmailIdleService()
    private init() {}

    /// 收到 IMAP 新邮件 push 时发出。userInfo["accountId"] = UUID。
    /// 通知发布可能在后台线程，订阅方负责切回主线程；多个 EmailViewModel 都能订阅，不会互相覆盖。
    static let newMessageNotification = Notification.Name("EmailIdleService.newMessage")
    /// IDLE 连接状态变化通知。userInfo["accountId"] = UUID, ["status"] = IdleStatus.rawValue
    static let statusChangedNotification = Notification.Name("EmailIdleService.statusChanged")
    static let accountIdKey = "accountId"
    static let statusKey = "status"

    /// 单账号 IDLE 连接状态，UI 用来显示一个小徽章。
    enum IdleStatus: String, Sendable {
        case idle           // 已经在 IDLE 等推送
        case connecting     // 正在建连 / select / 进入 IDLE
        case reconnecting   // 异常退避中，等待下一次重连
        case unsupported    // 服务器不支持 IDLE
        case stopped        // 没启动 / 已主动停止
    }

    /// 当前各账号的 IDLE 状态快照，UI 直接读最新值。MainActor 隔离即可。
    @Published private(set) var statuses: [UUID: IdleStatus] = [:]

    /// 内部：发新邮件通知（可在后台线程被调用）
    nonisolated fileprivate func postNewMessageNotification(accountId: UUID) {
        NotificationCenter.default.post(
            name: Self.newMessageNotification,
            object: nil,
            userInfo: [Self.accountIdKey: accountId]
        )
    }

    /// 内部：更新某账号的 IDLE 状态。可从任意线程调用，会跳回 MainActor 更新 @Published。
    nonisolated fileprivate func updateStatus(_ status: IdleStatus, for accountId: UUID) {
        Task { @MainActor in
            self.statuses[accountId] = status
        }
        NotificationCenter.default.post(
            name: Self.statusChangedNotification,
            object: nil,
            userInfo: [
                Self.accountIdKey: accountId,
                Self.statusKey: status.rawValue
            ]
        )
    }

    // MARK: - Public API

    /// 为指定账号开启 IDLE 监听。重复调用会停掉旧 Task 再开新的。
    /// 默认仅监听 INBOX；找不到 INBOX 时静默跳过。
    func start(for account: EmailAccount) {
        stop(accountId: account.id)
        let task: Task<Void, Never> = Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            await self.runLoop(account: account)
        }
        Self.setTask(task, for: account.id)
    }

    /// 停止指定账号的 IDLE 监听。
    /// 同时把 `statuses[accountId]` 清掉，避免账号已删除但 UI 端的状态徽章
    /// （通过 idleStatusByAccount 字典）仍残留绿点 / 重连点。
    func stop(accountId: UUID) {
        Self.cancelTask(for: accountId)
        statuses.removeValue(forKey: accountId)
        // 同步广播一次 .stopped，让 EmailViewModel.idleStatusByAccount 也清掉
        NotificationCenter.default.post(
            name: Self.statusChangedNotification,
            object: nil,
            userInfo: [
                Self.accountIdKey: accountId,
                Self.statusKey: IdleStatus.stopped.rawValue
            ]
        )
    }

    /// 停止全部 IDLE 监听（应用退出 / cleanupAllSessions 调用）。
    func stopAll() {
        for id in Self.snapshotAccountIds() {
            stop(accountId: id)
        }
    }

    // MARK: - Background task table（与 EmailService.backgroundSyncTasks 同款锁）

    nonisolated(unsafe) private static var idleTasks: [UUID: Task<Void, Never>] = [:]
    nonisolated(unsafe) private static let idleTasksLock = NSLock()

    nonisolated private static func setTask(_ task: Task<Void, Never>, for accountId: UUID) {
        idleTasksLock.lock()
        let old = idleTasks[accountId]
        idleTasks[accountId] = task
        idleTasksLock.unlock()
        old?.cancel()
    }

    nonisolated private static func cancelTask(for accountId: UUID) {
        idleTasksLock.lock()
        let task = idleTasks.removeValue(forKey: accountId)
        idleTasksLock.unlock()
        task?.cancel()
    }

    nonisolated private static func snapshotAccountIds() -> [UUID] {
        idleTasksLock.lock()
        defer { idleTasksLock.unlock() }
        return Array(idleTasks.keys)
    }

    // MARK: - Loop

    /// IDLE 主循环：每一轮负责"建连 → idle → 等可读 → idle_done → 触发刷新 → 续期"。
    /// 任意一步失败都会跳到 reconnect 路径，受指数退避保护。
    nonisolated private func runLoop(account: EmailAccount) async {
        var attempt = 0

        while !Task.isCancelled {
            do {
                try await runOneIdleSession(account: account)
                attempt = 0 // 一次成功 idle_done 视为健康，重置退避
            } catch let error as IdleError where error.isNoIdleCapability {
                // 服务器不支持 IDLE：标记状态后退出 runLoop，避免每 10-15 分钟反复 reconnect 招风控
                print("ℹ️ [EmailIdleService] 账号 \(account.emailAddress) 服务器不支持 IDLE，停止 IDLE 循环")
                updateStatus(.unsupported, for: account.id)
                return
            } catch {
                if Task.isCancelled {
                    updateStatus(.stopped, for: account.id)
                    return
                }
                attempt = min(attempt + 1, 6)
                let backoffSec = backoffSeconds(for: attempt)
                updateStatus(.reconnecting, for: account.id)
                print("⚠️ [EmailIdleService] 账号 \(account.emailAddress) IDLE 循环异常: \(error.localizedDescription)；将在 \(backoffSec)s 后重连")
                try? await Task.sleep(nanoseconds: UInt64(backoffSec) * 1_000_000_000)
            }
        }
        // 循环正常退出（被外部 cancel）
        updateStatus(.stopped, for: account.id)
    }

    /// 跑完一轮：connect → select inbox → idle → wait → idle_done → 通知 → disconnect。
    /// 每轮都新建独立 session，避免 LibEtPan CFStream 跨线程复用问题。
    nonisolated private func runOneIdleSession(account: EmailAccount) async throws {
        updateStatus(.connecting, for: account.id)

        // 1) 取密码
        guard let password = try? EmailCredentialStore.shared.getPassword(accountId: account.id),
              !password.isEmpty else {
            throw IdleError.missingPassword
        }

        // 2) 建会话
        guard let imap = LibEtPanIMAPSession(
            host: account.imapHost,
            port: account.imapPort,
            encryption: encryptionString(from: account.imapEncryption),
            username: account.emailAddress,
            password: password
        ) else {
            throw IdleError.cannotCreateSession
        }
        // 记录"是否当前还卡在 IDLE 状态"，给 cleanup 用
        // （由于 IDLE 不会自动跳出，cancel/throw 前必须先发 DONE，否则服务器把这条连接挂到 ~29 分钟超时）
        var inIdleState = false
        defer {
            if inIdleState {
                _ = try? imap.idleDone()
                inIdleState = false
            }
            imap.disconnect()
        }

        do {
            try imap.connect()
            try imap.login()
        } catch {
            throw IdleError.connectFailed(error)
        }

        guard imap.hasIdleCapability() else {
            // runLoop 收到 noIdleCapability 后会标记 .unsupported 并停止，不再反复 connect
            throw IdleError.noIdleCapability
        }

        // 3) 找 INBOX
        guard let inbox = await MainActor.run(body: {
            EmailStore.shared.getFolders(for: account.id).first(where: { $0.type == .inbox })
        }) else {
            throw IdleError.inboxNotFound
        }

        do {
            try imap.selectFolder(inbox.name)
        } catch {
            throw IdleError.selectFolderFailed(error)
        }

        // 4) 持续 IDLE，每 25 分钟续期一次
        while !Task.isCancelled {
            do {
                try imap.idle()
                inIdleState = true
                updateStatus(.idle, for: account.id)
            } catch {
                throw IdleError.idleStartFailed(error)
            }

            let fd = imap.idleFd()
            guard fd >= 0 else {
                _ = try? imap.idleDone()
                inIdleState = false
                throw IdleError.invalidFd
            }

            // 等可读 / 超时（25 分钟），同时受 Task.cancellation 影响
            let outcome = waitReadableOrTimeout(fd: fd, timeoutSec: 25 * 60)

            do {
                try imap.idleDone()
                inIdleState = false
            } catch {
                inIdleState = false // 即使 idleDone 失败，状态也不再是 IDLE；defer 不重复发
                throw IdleError.idleDoneFailed(error)
            }

            switch outcome {
            case .cancelled:
                return
            case .timedOut:
                // 续期：继续下一轮 idle
                continue
            case .readable:
                // 有 untagged response（多半是 EXISTS / RECENT / EXPUNGE）→ 通知上层去拉收件箱
                postNewMessageNotification(accountId: account.id)
                // 继续 idle
                continue
            case .error(let err):
                throw IdleError.pollFailed(err)
            }
        }
    }

    // MARK: - Helpers

    /// 阻塞当前后台线程，直到 fd 可读、超时、或调用方取消（每秒检查一次 Task.isCancelled）。
    nonisolated private func waitReadableOrTimeout(fd: Int32, timeoutSec: Int) -> WaitOutcome {
        var remaining = timeoutSec
        while remaining > 0 {
            if Task.isCancelled { return .cancelled }

            // 1 秒粒度的 poll，便于响应取消
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let timeoutMs: Int32 = 1000
            let r = poll(&pfd, 1, timeoutMs)
            if r < 0 {
                if errno == EINTR { continue }
                return .error(NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                                       userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]))
            }
            if r > 0 {
                // POLLHUP / POLLERR 视作 readable（让上层 idle_done 然后会触发异常退出重连）
                return .readable
            }
            remaining -= 1
        }
        return .timedOut
    }

    nonisolated private func encryptionString(from encryption: EmailEncryption) -> String {
        switch encryption {
        case .ssl: return "ssl"
        case .startTLS: return "startTLS"
        case .none: return "none"
        }
    }

    /// 指数退避，但封顶 5 分钟。
    nonisolated private func backoffSeconds(for attempt: Int) -> Int {
        let base = 5
        let raw = base * (1 << min(attempt, 6))
        return min(raw, 300)
    }

    private enum WaitOutcome {
        case readable
        case timedOut
        case cancelled
        case error(Error)
    }

    private enum IdleError: LocalizedError {
        case missingPassword
        case cannotCreateSession
        case connectFailed(Error)
        case noIdleCapability
        case inboxNotFound
        case selectFolderFailed(Error)
        case idleStartFailed(Error)
        case idleDoneFailed(Error)
        case invalidFd
        case pollFailed(Error)

        var isNoIdleCapability: Bool {
            if case .noIdleCapability = self { return true }
            return false
        }

        var errorDescription: String? {
            switch self {
            case .missingPassword: return "未找到账号密码"
            case .cannotCreateSession: return "无法创建 IMAP 会话"
            case .connectFailed(let e): return "连接失败: \(e.localizedDescription)"
            case .noIdleCapability: return "服务器不支持 IDLE"
            case .inboxNotFound: return "未找到 INBOX 文件夹"
            case .selectFolderFailed(let e): return "选择 INBOX 失败: \(e.localizedDescription)"
            case .idleStartFailed(let e): return "进入 IDLE 失败: \(e.localizedDescription)"
            case .idleDoneFailed(let e): return "退出 IDLE 失败: \(e.localizedDescription)"
            case .invalidFd: return "IDLE fd 无效"
            case .pollFailed(let e): return "poll 失败: \(e.localizedDescription)"
            }
        }
    }
}
