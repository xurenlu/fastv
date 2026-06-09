//
//  EmailService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// 邮件服务错误
enum EmailServiceError: LocalizedError {
    case connectionFailed(String)
    case authenticationFailed(String)
    case invalidConfiguration(String)
    case networkError(Error)
    case parseError(String)
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "连接失败: \(message)"
        case .authenticationFailed(let message):
            return "认证失败: \(message)"
        case .invalidConfiguration(let message):
            return "配置无效: \(message)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .parseError(let message):
            return "解析错误: \(message)"
        case .timedOut(let message):
            return "请求超时: \(message)"
        }
    }
}

struct EmailConnectionStageResult {
    let name: String
    let success: Bool
    let detail: String
}

struct EmailConnectionTestReport {
    let stages: [EmailConnectionStageResult]
    
    var isSuccess: Bool {
        stages.allSatisfy { $0.success }
    }
    
    var failureSummary: String? {
        stages.first(where: { !$0.success })?.detail
    }
}

/// 邮件服务
/// 使用 LibEtPan C 库实现 IMAP/SMTP 协议
/// 
/// 重要：LibEtPan 的 CFStream 实现不是线程安全的。
/// 每个操作必须使用独立的 IMAP/SMTP session，不能跨线程共享。
/// 所有 session 在操作完成后立即断开，不再缓存。
@MainActor
class EmailService {
    static let shared = EmailService()

    /// 单封邮件正文 / 原始邮件超过该字节数时，截断为 maxBodyBytes，并在 EmailBodyContent 中置 `wasTruncated = true`。
    /// 默认 10 MB，覆盖绝大多数富文本邮件；超过通常是包含巨型附件或多张高分辨率内嵌图，硬解析会卡 UI 甚至 OOM。
    nonisolated(unsafe) static let maxBodyBytes: Int = 10 * 1024 * 1024

    /// fetchMessageBody 整体（connect+login+select+fetch+parse）的超时上限。
    /// 选 45 秒：LibEtPan socket 没有原生 cancel，超时不能切断底层 I/O，但可以把 await 这边松开，
    /// 让上层把状态切到「加载失败 → 重试」。45 秒覆盖正常网络下绝大多数邮件，又不至于让用户对着 loading 干瞪眼一分钟。
    nonisolated(unsafe) static let fetchBodyTimeoutSeconds: UInt64 = 45

    // nonisolated(unsafe): 允许后台线程访问这些属性
    nonisolated(unsafe) var initialLoadLimit = 1000 // 可配置
    /// 用 NSLock 保护 backgroundSyncTasks 的所有读写，避免多任务并发改字典桶结构导致崩溃 / 句柄泄漏。
    nonisolated(unsafe) private var backgroundSyncTasks: [UUID: Task<Void, Never>] = [:]
    nonisolated(unsafe) private let backgroundSyncTasksLock = NSLock()

    /// 取消并移除指定账号的后台同步任务（线程安全）
    nonisolated private func cancelBackgroundSyncTask(for accountId: UUID) {
        backgroundSyncTasksLock.lock()
        let task = backgroundSyncTasks.removeValue(forKey: accountId)
        backgroundSyncTasksLock.unlock()
        task?.cancel()
    }

    /// 设置账号的后台同步任务（线程安全；旧任务会被自动取消）
    nonisolated private func setBackgroundSyncTask(_ task: Task<Void, Never>, for accountId: UUID) {
        backgroundSyncTasksLock.lock()
        let old = backgroundSyncTasks[accountId]
        backgroundSyncTasks[accountId] = task
        backgroundSyncTasksLock.unlock()
        old?.cancel()
    }

    /// 快照所有账号 id（线程安全）
    nonisolated private func snapshotBackgroundSyncAccountIds() -> [UUID] {
        backgroundSyncTasksLock.lock()
        defer { backgroundSyncTasksLock.unlock() }
        return Array(backgroundSyncTasks.keys)
    }

    private init() {}
    
    // MARK: - Helper Methods
    
    /// 将 EmailEncryption 转换为 LibEtPan 需要的字符串格式
    nonisolated private func encryptionString(from encryption: EmailEncryption) -> String {
        switch encryption {
        case .ssl:
            return "ssl"
        case .startTLS:
            return "startTLS"
        case .none:
            return "none"
        }
    }
    
    // MARK: - Connection Testing
    
    /// 测试账号连接（同时验证 IMAP / SMTP），返回详细阶段结果
    func testConnection(account: EmailAccount, password: String) async throws -> EmailConnectionTestReport {
        // 验证基本配置
        guard !account.imapHost.isEmpty,
              !account.smtpHost.isEmpty,
              !password.isEmpty else {
            throw EmailServiceError.invalidConfiguration("服务器地址或密码不能为空")
        }
        
        // 在后台线程执行测试，避免阻塞主线程
        return try await Task.detached(priority: .utility) {
            var stages: [EmailConnectionStageResult] = []
            stages.append(self.testIMAPStage(account: account, password: password))
            stages.append(self.testSMTPStage(account: account, password: password))
            
            return EmailConnectionTestReport(stages: stages)
        }.value
    }
    
    nonisolated private func testIMAPStage(account: EmailAccount, password: String) -> EmailConnectionStageResult {
        guard let imap = LibEtPanIMAPSession(
            host: account.imapHost,
            port: account.imapPort,
            encryption: encryptionString(from: account.imapEncryption),
            username: account.emailAddress,
            password: password
        ) else {
            return EmailConnectionStageResult(
                name: "接收服务器 (IMAP)",
                success: false,
                detail: "无法创建 IMAP 会话，请检查配置是否正确"
            )
        }
        
        defer {
            imap.disconnect()
        }
        
        print("🔌 [EmailService] 测试 IMAP 连接: \(account.imapHost):\(account.imapPort)")
        do {
            try imap.connect()
            print("✅ [EmailService] IMAP 连接成功")
        } catch {
            return EmailConnectionStageResult(
                name: "接收服务器 (IMAP)",
                success: false,
                detail: "IMAP 连接失败: \(error.localizedDescription)"
            )
        }
        
        print("🔐 [EmailService] 测试 IMAP 登录…")
        do {
            try imap.login()
            print("✅ [EmailService] IMAP 登录成功")
            return EmailConnectionStageResult(
                name: "接收服务器 (IMAP)",
                success: true,
                detail: "连接和登录成功"
            )
        } catch {
            return EmailConnectionStageResult(
                name: "接收服务器 (IMAP)",
                success: false,
                detail: "IMAP 登录失败: \(error.localizedDescription)"
            )
        }
    }
    
    nonisolated private func testSMTPStage(account: EmailAccount, password: String) -> EmailConnectionStageResult {
        guard let smtp = LibEtPanSMTPSession(
            host: account.smtpHost,
            port: account.smtpPort,
            encryption: encryptionString(from: account.smtpEncryption),
            username: account.emailAddress,
            password: password
        ) else {
            return EmailConnectionStageResult(
                name: "发送服务器 (SMTP)",
                success: false,
                detail: "无法创建 SMTP 会话，请检查配置是否正确"
            )
        }
        
        defer {
            smtp.disconnect()
        }
        
        print("🔌 [EmailService] 测试 SMTP 连接: \(account.smtpHost):\(account.smtpPort)")
        do {
            try smtp.connect()
            print("✅ [EmailService] SMTP 连接成功")
        } catch {
            return EmailConnectionStageResult(
                name: "发送服务器 (SMTP)",
                success: false,
                detail: "SMTP 连接失败: \(error.localizedDescription)"
            )
        }
        
        print("🔐 [EmailService] 测试 SMTP 登录…")
        do {
            try smtp.login()
            print("✅ [EmailService] SMTP 登录成功")
            return EmailConnectionStageResult(
                name: "发送服务器 (SMTP)",
                success: true,
                detail: "连接和登录成功"
            )
        } catch {
            return EmailConnectionStageResult(
                name: "发送服务器 (SMTP)",
                success: false,
                detail: "SMTP 登录失败: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - IMAP Operations
    
    /// 创建新的 IMAP 会话
    /// 
    /// 重要：LibEtPan 的 CFStream 实现不是线程安全的。
    /// 每次操作都必须创建独立的 session，操作完成后立即断开。
    /// 不要在多个线程之间共享 IMAP session。
    nonisolated private func createIMAPSession(account: EmailAccount) async throws -> LibEtPanIMAPSession {
        // 在后台线程执行 IMAP 操作，避免主线程阻塞
        return try await Task.detached(priority: .utility) {
            print("🔌 [EmailService] 创建新的 IMAP 会话: \(account.emailAddress)")
            
            guard let password = try? EmailCredentialStore.shared.getPassword(accountId: account.id) else {
                throw EmailServiceError.authenticationFailed("密码未找到")
            }
            
            guard let imap = LibEtPanIMAPSession(
                host: account.imapHost,
                port: account.imapPort,
                encryption: self.encryptionString(from: account.imapEncryption),
                username: account.emailAddress,
                password: password
            ) else {
                throw EmailServiceError.connectionFailed("无法创建 IMAP 会话")
            }
            
            do {
                try imap.connect()
                print("✅ [EmailService] IMAP 连接成功")
            } catch {
                throw EmailServiceError.connectionFailed(error.localizedDescription)
            }
            
            do {
                try imap.login()
                print("✅ [EmailService] IMAP 登录成功")
            } catch {
                imap.disconnect()
                throw EmailServiceError.authenticationFailed(error.localizedDescription)
            }
            
            return imap
        }.value
    }
    
    /// 同步邮件（增量同步，支持时间范围和限制数量）
    /// nonisolated: 允许在后台线程执行,避免阻塞UI
    /// 
    /// 重要：每次同步都会创建独立的 IMAP session，操作完成后自动断开。
    /// 这是为了避免 LibEtPan CFStream 的多线程竞态条件问题。
    nonisolated func syncMessages(
        account: EmailAccount,
        folder: EmailFolder,
        since: Date? = nil,
        limit: Int? = nil,
        batchSize: Int = 20
    ) async throws -> [EmailMessage] {
        // 创建独立的 IMAP session
        let imap = try await createIMAPSession(account: account)
        
        // 确保操作完成后断开连接
        defer {
            print("🔌 [EmailService] 断开 IMAP 连接 (syncMessages)")
            imap.disconnect()
        }
        
        // 在后台线程执行所有 IMAP 操作
        return try await Task.detached(priority: .utility) { [imap] in
            
            do {
                try imap.selectFolder(folder.name)
            } catch {
                throw EmailServiceError.connectionFailed("选择文件夹失败: \(error.localizedDescription)")
            }
            
            // 计算时间范围：默认只获取最近30天的邮件
            let defaultSince = since ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())
            
            // 获取邮件UID列表
            let messageUIDs: [Any]
            do {
                let limitValue = limit ?? 200 // 默认最多200封
                var result: [Any]?
                
                // 优化策略:
                // 1. 如果指定了limit且较小(<=200),使用快速方法直接获取最新的N封
                // 2. 如果指定了since日期,使用日期搜索
                // 3. 否则使用快速方法
                let shouldUseFastMethod = (limit != nil && limitValue <= 200) || since == nil
                
                do {
                    if shouldUseFastMethod {
                        print("⚡️ [EmailService] 使用快速方法获取最新 \(limitValue) 封邮件")
                        result = try imap.fetchLatestMessages(withLimit: UInt(limitValue))
                    } else {
                        print("🔍 [EmailService] 使用日期搜索，since: \(String(describing: defaultSince))")
                    result = try imap.fetchMessages(since: defaultSince, limit: UInt(limitValue))
                    }
                } catch {
                    throw EmailServiceError.parseError(error.localizedDescription)
                }
                
                messageUIDs = result as? [NSDictionary] ?? []
            } catch {
                throw EmailServiceError.parseError(error.localizedDescription)
            }
            
            // 解析每个邮件的头信息并转换为 EmailMessage（分批处理）
            var emailMessages: [EmailMessage] = []
            var processedCount = 0
            
            // 限制初始加载数量,避免阻塞UI
            let uidCount = messageUIDs.count
            let shouldLimitInitialLoad = uidCount > self.initialLoadLimit
            let processLimit = shouldLimitInitialLoad ? self.initialLoadLimit : uidCount
            
            if shouldLimitInitialLoad {
                print("📊 [EmailService] 邮件数量(\(uidCount))超过限制,先加载前\(self.initialLoadLimit)封,剩余将在后台同步")
            }
            
            // 收集要处理的UID
            var uidsToProcess: [NSNumber] = []
            for (index, msgDictAny) in messageUIDs.enumerated() {
                if index >= processLimit {
                    // 剩余的留给后台同步
                    self.scheduleBackgroundSync(
                        account: account,
                        folder: folder,
                        remainingUIDs: Array(messageUIDs[processLimit...]),
                        sinceDate: defaultSince
                    )
                    break
                }
                
                if let msgDict = msgDictAny as? NSDictionary,
                   let uidValue = msgDict["uid"] as? NSNumber {
                    uidsToProcess.append(uidValue)
                }
            }
            
            // 批量获取所有邮件头(一次请求)
            print("📦 [EmailService] 批量获取 \(uidsToProcess.count) 封邮件头...")
            let batchStartTime = Date()
            
            var allHeaders: [[String: Any]] = []
            do {
                let headersArray = try imap.fetchBatchMessageHeaders(withUIDs: uidsToProcess)
                allHeaders = headersArray.compactMap { $0 as? [String: Any] }
            } catch {
                print("❌ [EmailService] 批量获取失败，降级为逐个获取")
                // 降级为逐个获取
                for uidNum in uidsToProcess {
                    let uid = uidNum.uint32Value
                    do {
                        let headerDict = try imap.fetchMessageHeaders(withUID: uid)
                        if let headers = headerDict as? [String: Any] {
                            allHeaders.append(headers)
                        }
                    } catch {
                        print("⚠️ [EmailService] 无法获取邮件头，UID: \(uid)")
                        continue
                    }
                }
            }
            
            let batchElapsed = Date().timeIntervalSince(batchStartTime)
            print("⏱️ [EmailService] 批量获取完成，耗时: \(String(format: "%.2f", batchElapsed))秒")
            
            // 解析邮件头（可以在后台线程执行，不涉及 LibEtPan）
            for headers in allHeaders {
                guard let uidValue = headers["uid"] as? NSNumber else { continue }
                let uid = uidValue.uint32Value
                
                if let emailMessage = self.parseEmailMessage(from: headers, accountId: account.id, folderId: folder.id, uid: uid) {
                    if let sinceDate = defaultSince, emailMessage.date < sinceDate {
                        continue
                    }
                    
                    emailMessages.append(emailMessage)
                    processedCount += 1
                    
                    if processedCount % 100 == 0 {
                        print("📧 [EmailService] 已解析 \(processedCount) 封邮件...")
                    }
                }
            }
            
            print("✅ [EmailService] 初始加载完成: \(emailMessages.count) 封邮件")
            return emailMessages
        }.value
    }
    
    /// 后台同步剩余邮件
    ///
    /// 重要：后台同步使用独立的 IMAP session，批量处理邮件以提高效率。
    nonisolated private func scheduleBackgroundSync(
        account: EmailAccount,
        folder: EmailFolder,
        remainingUIDs: [Any],
        sinceDate: Date?
    ) {
        let task = Task.detached(priority: .background) {
            print("🔄 [EmailService] 开始后台同步剩余 \(remainingUIDs.count) 封邮件...")
            
            var syncedCount = 0
            let totalCount = remainingUIDs.count
            let batchSize = 50 // 每批处理50封
            
            // 分批处理，每批使用独立的 IMAP session
            var currentBatch: [NSNumber] = []
            
            for msgDictAny in remainingUIDs {
                // 检查是否被取消
                if Task.isCancelled {
                    print("⚠️ [EmailService] 后台同步被取消")
                    break
                }
                
                guard let msgDict = msgDictAny as? NSDictionary,
                      let uidValue = msgDict["uid"] as? NSNumber else { continue }
                
                currentBatch.append(uidValue)
                
                // 当批次满了或者是最后一个，处理这批
                if currentBatch.count >= batchSize || msgDictAny as AnyObject === remainingUIDs.last as AnyObject {
                    do {
                        // 创建独立的 IMAP session 处理这批邮件
                        let imap = try await self.createIMAPSession(account: account)
                        defer {
                            imap.disconnect()
                        }
                        
                        try imap.selectFolder(folder.name)
                        
                        // 批量获取邮件头
                        let headersArray = try imap.fetchBatchMessageHeaders(withUIDs: currentBatch)
                        let allHeaders = headersArray.compactMap { $0 as? [String: Any] }
                        
                        var messagesToSave: [EmailMessage] = []
                        
                        for headers in allHeaders {
                            guard let uidValue = headers["uid"] as? NSNumber else { continue }
                            let uid = uidValue.uint32Value
                            
                            if let emailMessage = self.parseEmailMessage(
                                from: headers,
                                accountId: account.id,
                                folderId: folder.id,
                                uid: uid
                            ) {
                                // 检查日期范围
                                if let sinceDate = sinceDate, emailMessage.date < sinceDate {
                                    continue
                                }
                                messagesToSave.append(emailMessage)
                            }
                        }
                        
                        // 批量保存到本地数据库
                        if !messagesToSave.isEmpty {
                            try await EmailStore.shared.addMessages(messagesToSave, folderId: folder.id)
                            syncedCount += messagesToSave.count
                        }
                        
                        // 每处理100封打印进度
                        if syncedCount % 100 < batchSize {
                            print("🔄 [EmailService] 后台已同步 \(syncedCount)/\(totalCount) 封邮件")
                        }
                        
                        // 让出CPU,避免占用过多资源
                        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                        
                    } catch {
                        print("⚠️ [EmailService] 后台同步批次失败: \(error.localizedDescription)")
                    }
                    
                    currentBatch.removeAll()
                }
            }
            
            print("✅ [EmailService] 后台同步完成: \(syncedCount) 封邮件")
        }

        // 注册新任务（同时取消同账号上一次未完成的任务）
        setBackgroundSyncTask(task, for: account.id)
    }

    /// 取消后台同步任务
    nonisolated func cancelBackgroundSync(accountId: UUID) {
        cancelBackgroundSyncTask(for: accountId)
    }
    
    /// 获取邮件正文
    /// 
    /// 重要：每次获取正文都会创建独立的 IMAP session，操作完成后自动断开。
    nonisolated func fetchMessageBody(
        account: EmailAccount,
        folder: EmailFolder,
        message: EmailMessage
    ) async throws -> EmailBodyContent {
        guard let uid = message.uid else {
            print("❌ [EmailService] fetchMessageBody: 邮件 UID 不存在")
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }

        print("📧 [EmailService] fetchMessageBody: 开始获取正文, folder=\(folder.name), uid=\(uid)")

        // 用 TaskGroup 跑「真正干活」+「计时器」两条腿，谁先回来用谁的结果。
        // LibEtPan 的阻塞 socket 无法真正取消：超时分支让工作子任务在后台继续跑完 / disconnect / 自然结束，
        // 上层提前拿到 timedOut，把 UI 切到「加载失败」并放出重试入口。
        return try await withThrowingTaskGroup(of: EmailBodyContent.self) { group in
            group.addTask { [weak self] in
                guard let self else { throw EmailServiceError.connectionFailed("EmailService 已释放") }
                return try await self.fetchMessageBodyUnchecked(account: account, folder: folder, uid: uid)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.fetchBodyTimeoutSeconds * 1_000_000_000)
                throw EmailServiceError.timedOut("拉取邮件正文超过 \(Self.fetchBodyTimeoutSeconds) 秒")
            }
            // first 拿第一个返回（成功或失败）的结果，再 cancelAll 把另一条腿掐掉。
            // 注意：cancelAll 只对 Task.sleep 这种 cancellation-aware 的步骤生效，对 LibEtPan I/O 是 no-op。
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw EmailServiceError.connectionFailed("fetchMessageBody 未返回任何结果")
            }
            return first
        }
    }

    /// fetchMessageBody 真正干活的部分：建会话 → selectFolder → fetch → parse。
    /// 抽出来是为了让外层套超时；本函数不感知超时存在。
    nonisolated private func fetchMessageBodyUnchecked(
        account: EmailAccount,
        folder: EmailFolder,
        uid: UInt32
    ) async throws -> EmailBodyContent {
        // 创建独立的 IMAP session
        let imap = try await createIMAPSession(account: account)

        // 确保操作完成后断开连接
        defer {
            print("🔌 [EmailService] 断开 IMAP 连接 (fetchMessageBody)")
            imap.disconnect()
        }

        let bodyData = try await Task.detached(priority: .utility) { [imap] in
            do {
                try imap.selectFolder(folder.name)
                print("📧 [EmailService] fetchMessageBody: 文件夹选择成功")
            } catch {
                print("❌ [EmailService] fetchMessageBody: 选择文件夹失败: \(error)")
                throw EmailServiceError.connectionFailed("选择文件夹失败: \(error.localizedDescription)")
            }

            let data = try imap.fetchMessageBody(withUID: uid)
            print("📧 [EmailService] fetchMessageBody: 获取到数据 \(data.count) 字节")
            return data
        }.value

        if bodyData.isEmpty {
            print("❌ [EmailService] fetchMessageBody: 邮件正文为空")
            throw EmailServiceError.parseError("未获取到邮件正文")
        }

        // 超大邮件保护：超阈值时只解析前 maxBodyBytes，并在 content 上打上 wasTruncated 标记由 UI 提示。
        let originalSize = bodyData.count
        let wasTruncated = originalSize > Self.maxBodyBytes
        let dataToParse: Data
        if wasTruncated {
            print("⚠️ [EmailService] fetchMessageBody: 正文大小 \(originalSize) 字节超过阈值 \(Self.maxBodyBytes)，将截断后解析")
            dataToParse = bodyData.prefix(Self.maxBodyBytes)
        } else {
            dataToParse = bodyData
        }

        let parsed = EmailContentDecoder.parseBody(data: dataToParse)
        // 附件元信息扫描走**全量** data：附件通常排在邮件后半段，截断后正文虽然只解析前 10MB，
        // 但附件清单还得对得上服务器实际 MIME 结构；扫描只做字符串遍历，10MB → 50MB 也就多几毫秒。
        let attachmentMetas = EmailContentDecoder.parseAttachments(data: bodyData)
        let content = EmailBodyContent(
            textBody: parsed.textBody,
            htmlBody: parsed.htmlBody,
            containsRemoteResources: parsed.containsRemoteResources,
            originalSize: originalSize,
            wasTruncated: wasTruncated,
            attachments: attachmentMetas
        )
        print("📧 [EmailService] fetchMessageBody: 解析完成, textBody=\(content.textBody?.count ?? 0)字符, htmlBody=\(content.htmlBody?.count ?? 0)字符, hasRemote=\(content.containsRemoteResources), truncated=\(content.wasTruncated), attachments=\(attachmentMetas.count)")

        return content
    }
    
    /// 获取完整原始邮件数据（包括所有邮件头）
    /// 
    /// 重要：每次获取都会创建独立的 IMAP session，操作完成后自动断开。
    nonisolated func fetchRawMessage(
        account: EmailAccount,
        folder: EmailFolder,
        message: EmailMessage
    ) async throws -> Data {
        guard let uid = message.uid else {
            print("❌ [EmailService] fetchRawMessage: 邮件 UID 不存在")
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }
        
        print("📧 [EmailService] fetchRawMessage: 开始获取原始邮件, folder=\(folder.name), uid=\(uid)")
        
        // 创建独立的 IMAP session
        let imap = try await createIMAPSession(account: account)
        
        // 确保操作完成后断开连接
        defer {
            print("🔌 [EmailService] 断开 IMAP 连接 (fetchRawMessage)")
            imap.disconnect()
        }
        
        let rawData = try await Task.detached(priority: .utility) { [imap] in
            do {
                try imap.selectFolder(folder.name)
                print("📧 [EmailService] fetchRawMessage: 文件夹选择成功")
            } catch {
                print("❌ [EmailService] fetchRawMessage: 选择文件夹失败: \(error)")
                throw EmailServiceError.connectionFailed("选择文件夹失败: \(error.localizedDescription)")
            }
            
            // fetchMessageBodyWithUID 使用 MAILIMAP_MSG_ATT_RFC822，返回完整原始邮件
            let data = try imap.fetchMessageBody(withUID: uid)
            print("📧 [EmailService] fetchRawMessage: 获取到原始邮件数据 \(data.count) 字节")
            return data
        }.value
        
        if rawData.isEmpty {
            print("❌ [EmailService] fetchRawMessage: 原始邮件数据为空")
            throw EmailServiceError.parseError("未获取到原始邮件数据")
        }
        
        return rawData
    }
    
    /// 搜索邮件（通过 IMAP 服务器搜索）
    /// 
    /// 重要：每次搜索都会创建独立的 IMAP session，操作完成后自动断开。
    nonisolated func searchMessages(
        account: EmailAccount,
        folder: EmailFolder,
        query: String,
        limit: Int = 100
    ) async throws -> [EmailMessage] {
        guard !query.isEmpty else {
            return []
        }
        
        // 创建独立的 IMAP session
        let imap = try await createIMAPSession(account: account)
        
        // 确保操作完成后断开连接
        defer {
            print("🔌 [EmailService] 断开 IMAP 连接 (searchMessages)")
            imap.disconnect()
        }
        
        // 在后台线程执行所有 IMAP 操作
        return try await Task.detached(priority: .utility) { [imap] in
            do {
                try imap.selectFolder(folder.name)
            } catch {
                throw EmailServiceError.connectionFailed("选择文件夹失败: \(error.localizedDescription)")
            }
            
            // 使用 IMAP 搜索
            let messageUIDs: [Any]
            do {
                print("🔍 [EmailService] 开始搜索邮件，查询: \(query), 文件夹: \(folder.name)")
                let result = try imap.searchMessages(withQuery: query, limit: UInt(limit))
                if let dictArray = result as? [NSDictionary] {
                    messageUIDs = dictArray
                } else {
                    messageUIDs = []
                }
                print("✅ [EmailService] 搜索完成，找到 \(messageUIDs.count) 封邮件")
            } catch {
                throw EmailServiceError.parseError("搜索失败: \(error.localizedDescription)")
            }
            
            // 如果没有找到邮件，返回空数组
            guard !messageUIDs.isEmpty else {
                return []
            }
            
            // 获取邮件头信息（批量获取，性能优化）
            var emailMessages: [EmailMessage] = []
            let uids = messageUIDs.compactMap { ($0 as? NSDictionary)?["uid"] as? NSNumber }
            
            if !uids.isEmpty {
                let headers = try imap.fetchBatchMessageHeaders(withUIDs: uids)
                
                for headerDictAny in headers {
                    guard let headerDict = headerDictAny as? [String: Any],
                          let uidNum = headerDict["uid"] as? NSNumber else { continue }
                    let uid = uidNum.uint32Value
                    
                    // 使用 EmailService 的私有方法解析邮件
                    if let message = self.parseEmailMessage(
                        from: headerDict,
                        accountId: account.id,
                        folderId: folder.id,
                        uid: uid
                    ) {
                        emailMessages.append(message)
                    }
                }
            }
            
            return emailMessages
        }.value
    }
    
    /// 获取文件夹列表
    /// 
    /// 重要：每次获取文件夹列表都会创建独立的 IMAP session，操作完成后自动断开。
    nonisolated func fetchFolders(account: EmailAccount) async throws -> [EmailFolder] {
        // 创建独立的 IMAP session
        let imap = try await createIMAPSession(account: account)
        
        // 确保操作完成后断开连接
        defer {
            print("🔌 [EmailService] 断开 IMAP 连接 (fetchFolders)")
            imap.disconnect()
        }
        
        let folderNames: [String] = try await Task.detached(priority: .utility) { [imap] in
            do {
                return try imap.fetchFolders() ?? []
            } catch {
                throw EmailServiceError.connectionFailed("获取文件夹列表失败: \(error.localizedDescription)")
            }
        }.value
        
        // 去重：使用 Set 存储已处理的文件夹名称
        var seenNames = Set<String>()
        return folderNames.compactMap { name in
            // 跳过重复的文件夹名称
            if seenNames.contains(name) {
                return nil
            }
            seenNames.insert(name)
            
            let folderType: EmailFolderType
            let upperName = name.uppercased()
            if upperName == "INBOX" {
                folderType = .inbox
            } else if upperName.contains("SENT") {
                folderType = .sent
            } else if upperName.contains("DRAFT") {
                folderType = .drafts
            } else if upperName.contains("TRASH") || upperName.contains("DELETED") {
                folderType = .trash
            } else if upperName.contains("SPAM") || upperName.contains("JUNK") {
                folderType = .spam
            } else if upperName.contains("ARCHIVE") {
                folderType = .archive
            } else {
                folderType = .custom
            }
            
            return EmailFolder(
                id: UUID(),
                accountId: account.id,
                name: name,
                type: folderType,
                path: name,
                unreadCount: 0
            )
        }
    }
    
    /// 标记邮件为已读
    /// 
    /// 重要：每次标记操作都会创建独立的 IMAP session，操作完成后自动断开。
    nonisolated func markAsRead(account: EmailAccount, folder: EmailFolder, message: EmailMessage) async throws {
        guard let uid = message.uid else {
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }
        
        // 创建独立的 IMAP session
        let imap = try await createIMAPSession(account: account)
        
        // 确保操作完成后断开连接
        defer {
            print("🔌 [EmailService] 断开 IMAP 连接 (markAsRead)")
            imap.disconnect()
        }
        
        try await Task.detached(priority: .utility) { [imap] in
            do {
                try imap.selectFolder(folder.name)
                try imap.markAsRead(withUID: uid)
            } catch {
                throw EmailServiceError.networkError(error)
            }
        }.value
    }
    
    /// 删除邮件
    ///
    /// IMAP 真实现：STORE +FLAGS (\Deleted) + EXPUNGE。
    /// 每次操作创建独立 IMAP session，完成后立即断开。
    nonisolated func deleteMessage(account: EmailAccount, message: EmailMessage) async throws {
        guard let uid = message.uid else {
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }

        guard let folderId = message.folderId,
              let folder = await EmailStore.shared.getFolders(for: account.id).first(where: { $0.id == folderId }) else {
            throw EmailServiceError.invalidConfiguration("找不到邮件所在文件夹")
        }

        let imap = try await createIMAPSession(account: account)
        defer {
            print("🔌 [EmailService] 断开 IMAP 连接 (deleteMessage)")
            imap.disconnect()
        }

        try await Task.detached(priority: .utility) { [imap] in
            do {
                try imap.selectFolder(folder.name)
                try imap.deleteAndExpunge(withUID: uid)
            } catch {
                throw EmailServiceError.networkError(error)
            }
        }.value
    }

    /// 切换星标状态
    ///
    /// IMAP 真实现：根据当前 `message.isStarred` 推断要 +FLAGS 还是 -FLAGS (\Flagged)。
    /// 注意：调用方传入的 `message` 应反映 IMAP 切换前的状态，调用方自行 toggle 本地缓存。
    nonisolated func toggleStar(account: EmailAccount, message: EmailMessage) async throws {
        guard let uid = message.uid else {
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }

        guard let folderId = message.folderId,
              let folder = await EmailStore.shared.getFolders(for: account.id).first(where: { $0.id == folderId }) else {
            throw EmailServiceError.invalidConfiguration("找不到邮件所在文件夹")
        }

        let willBeStarred = !message.isStarred
        let imap = try await createIMAPSession(account: account)
        defer {
            print("🔌 [EmailService] 断开 IMAP 连接 (toggleStar)")
            imap.disconnect()
        }

        try await Task.detached(priority: .utility) { [imap] in
            do {
                try imap.selectFolder(folder.name)
                if willBeStarred {
                    try imap.addFlagged(withUID: uid)
                } else {
                    try imap.removeFlagged(withUID: uid)
                }
            } catch {
                throw EmailServiceError.networkError(error)
            }
        }.value
    }
    
    /// 标记为垃圾邮件
    nonisolated func markAsSpam(account: EmailAccount, message: EmailMessage) async throws {
        guard message.uid != nil else {
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }
        
        // 查找垃圾邮件文件夹
        let folders = await EmailStore.shared.getFolders(for: account.id)
        guard let spamFolder = folders.first(where: { $0.type == .spam }) else {
            throw EmailServiceError.invalidConfiguration("找不到垃圾邮件文件夹")
        }
        
        try await moveMessage(account: account, message: message, to: spamFolder)
    }
    
    /// 取消垃圾邮件标记
    nonisolated func unmarkSpam(account: EmailAccount, message: EmailMessage) async throws {
        guard message.uid != nil else {
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }
        
        // 移动到收件箱
        let folders = await EmailStore.shared.getFolders(for: account.id)
        guard let inboxFolder = folders.first(where: { $0.type == .inbox }) else {
            throw EmailServiceError.invalidConfiguration("找不到收件箱")
        }
        
        try await moveMessage(account: account, message: message, to: inboxFolder)
    }
    
    /// 下载附件
    ///
    /// 真实现：用 IMAP `BODY.PEEK[<partPath>]` 只抓取目标 part 的原始字节，
    /// 再按 Content-Transfer-Encoding 解码后写入临时目录。
    /// 兼容老数据：如果 attachment 没有 partPath（升级前抓的邮件），
    /// 退回到"取整封邮件 + MIME 解析"路径，并尝试用 filename 匹配。
    nonisolated func downloadAttachment(
        account: EmailAccount,
        folder: EmailFolder,
        message: EmailMessage,
        attachment: EmailAttachment
    ) async throws -> URL {
        guard let uid = message.uid else {
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }

        let imap = try await createIMAPSession(account: account)
        defer {
            print("🔌 [EmailService] 断开 IMAP 连接 (downloadAttachment)")
            imap.disconnect()
        }

        // 真路径：partPath 已知，直接抓那个 part
        if let partPath = attachment.partPath, !partPath.isEmpty {
            let rawPartBytes = try await Task.detached(priority: .utility) { [imap] in
                try imap.selectFolder(folder.name)
                return try imap.fetchMessagePart(withUID: uid, partPath: partPath)
            }.value

            let decoded = EmailContentDecoder.decodePartBytes(rawPartBytes, encoding: attachment.encoding)
            let fileURL = Self.makeAttachmentFileURL(filename: attachment.filename)
            try decoded.write(to: fileURL)
            print("📎 [EmailService] 附件下载完成: mime=\(attachment.mimeType), partPath=\(partPath), bytes=\(decoded.count)")
            return fileURL
        }

        // 兼容路径：老附件没有 partPath，回退到拉全文 + 用 filename 匹配。
        print("ℹ️ [EmailService] downloadAttachment: 没有 partPath，回退到整封邮件解析模式")
        let rawData = try await Task.detached(priority: .utility) { [imap] in
            try imap.selectFolder(folder.name)
            return try imap.fetchMessageBody(withUID: uid)
        }.value

        let metas = EmailContentDecoder.parseAttachments(data: rawData)
        guard let meta = metas.first(where: { $0.filename == attachment.filename })
                       ?? metas.first(where: { $0.mimeType == attachment.mimeType }) else {
            throw EmailServiceError.parseError("未在邮件中找到附件：\(attachment.filename)")
        }
        // 再抓一次 part（这次有 partPath 了）
        let rawPartBytes = try await Task.detached(priority: .utility) { [imap] in
            try imap.selectFolder(folder.name)
            return try imap.fetchMessagePart(withUID: uid, partPath: meta.partPath)
        }.value
        let decoded = EmailContentDecoder.decodePartBytes(rawPartBytes, encoding: meta.encoding)
        let fileURL = Self.makeAttachmentFileURL(filename: meta.filename)
        try decoded.write(to: fileURL)
        print("📎 [EmailService] 附件下载完成 (回退路径): mime=\(meta.mimeType), partPath=\(meta.partPath), bytes=\(decoded.count)")
        return fileURL
    }

    /// 为附件构造一个安全的临时文件名。
    /// 安全策略：
    ///   - 不允许路径分隔符 `/` `\`，避免被恶意 filename 越权写到其他目录
    ///   - 拒绝以 `.` 开头的隐藏文件 / `.` / `..`（避免 dotfile 或目录穿越遗留风险）
    ///   - 控制字符 (U+0000–U+001F、U+007F)、文件系统保留符 (`:"?*<>|`) 全部替换为 `_`
    ///   - 字母数字 / CJK / `_` / `-` / `.` 保留；其它"安全"字符也保留（兼容法语 é 等）
    ///   - 始终前置 UUID 短前缀，使同邮件多附件 + 不同邮件同名附件都不会撞名
    nonisolated private static func makeAttachmentFileURL(filename: String) -> URL {
        let cleaned: String = {
            var s = filename
            // 1) 取最后一个路径分量（挡 "../../tmp/x" 之类）
            if let lastSlash = s.range(of: "/", options: .backwards) { s = String(s[lastSlash.upperBound...]) }
            if let lastBack = s.range(of: "\\", options: .backwards) { s = String(s[lastBack.upperBound...]) }
            // 2) 控制字符 / 文件系统保留符替换为 `_`
            let forbidden = CharacterSet.controlCharacters
                .union(CharacterSet(charactersIn: ":\"?*<>|/\\"))
            let mapped = String(s.unicodeScalars.map { forbidden.contains($0) ? Character("_") : Character($0) })
            // 3) trim 空白
            var trimmed = mapped.trimmingCharacters(in: .whitespacesAndNewlines)
            // 4) 拒绝以 `.` 开头（隐藏文件、`.` / `..`）；保留扩展名中间的 `.`
            while trimmed.hasPrefix(".") { trimmed.removeFirst() }
            // 5) 限长 240 字节，避免触发 macOS 文件名长度上限（255 字节 UTF-8）
            if trimmed.utf8.count > 240 {
                trimmed = String(trimmed.prefix(120)) // 简单截，UTF-8 安全粒度
            }
            return trimmed.isEmpty ? "attachment.bin" : trimmed
        }()
        // 加一段 UUID 前缀，避免不同邮件同名附件互相覆盖
        let unique = "\(UUID().uuidString.prefix(8))-\(cleaned)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(unique)
    }
    
    /// 移动邮件到文件夹
    ///
    /// IMAP 真实现：UID COPY 到目标 mailbox，再在源 mailbox 上 +FLAGS (\Deleted) + EXPUNGE。
    nonisolated func moveMessage(account: EmailAccount, message: EmailMessage, to folder: EmailFolder) async throws {
        guard let uid = message.uid else {
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }

        guard let folderId = message.folderId,
              let sourceFolder = await EmailStore.shared.getFolders(for: account.id).first(where: { $0.id == folderId }) else {
            throw EmailServiceError.invalidConfiguration("找不到源文件夹")
        }

        guard sourceFolder.id != folder.id else {
            // 同文件夹移动等同 no-op，避免误删
            print("ℹ️ [EmailService] moveMessage 源/目标相同，跳过")
            return
        }

        let imap = try await createIMAPSession(account: account)
        defer {
            print("🔌 [EmailService] 断开 IMAP 连接 (moveMessage)")
            imap.disconnect()
        }

        try await Task.detached(priority: .utility) { [imap] in
            do {
                try imap.selectFolder(sourceFolder.name)
                try imap.moveMessage(withUID: uid, toFolder: folder.name)
            } catch {
                throw EmailServiceError.networkError(error)
            }
        }.value
    }
    
    // MARK: - SMTP Operations
    
    /// 创建 SMTP 会话
    /// 
    /// 重要：与 IMAP 类似，SMTP session 也不再缓存，每次操作创建新的 session。
    /// 这样可以确保使用最新的账户配置，避免配置更新后仍使用旧连接。
    nonisolated private func createSMTPSession(account: EmailAccount) async throws -> LibEtPanSMTPSession {
        // 在后台线程执行 SMTP 操作，避免主线程阻塞
        return try await Task.detached(priority: .utility) {
            print("📧 [EmailService] 创建新的 SMTP 会话")
            print("📧 [EmailService] SMTP 服务器: \(account.smtpHost):\(account.smtpPort)")
            print("📧 [EmailService] SMTP 加密方式: \(self.encryptionString(from: account.smtpEncryption))")
            print("📧 [EmailService] 用户名: \(account.emailAddress)")
            
            guard let password = try? EmailCredentialStore.shared.getPassword(accountId: account.id) else {
                print("❌ [EmailService] SMTP 密码未找到")
                throw EmailServiceError.authenticationFailed("密码未找到")
            }
            
            print("📧 [EmailService] 正在创建 LibEtPan SMTP 会话对象...")
            guard let smtp = LibEtPanSMTPSession(
                host: account.smtpHost,
                port: account.smtpPort,
                encryption: self.encryptionString(from: account.smtpEncryption),
                username: account.emailAddress,
                password: password
            ) else {
                print("❌ [EmailService] 无法创建 SMTP 会话对象")
                throw EmailServiceError.connectionFailed("无法创建 SMTP 会话")
            }
            
            print("📧 [EmailService] SMTP 会话对象创建成功，正在连接服务器...")
            do {
                try smtp.connect()
                print("✅ [EmailService] SMTP 连接成功")
            } catch {
                let errorDesc = error.localizedDescription
                // 避免重复包装错误信息
                let errorMessage = errorDesc.hasPrefix("连接失败") ? errorDesc : "连接失败: \(errorDesc)"
                print("❌ [EmailService] SMTP 连接失败: \(errorMessage)")
                print("❌ [EmailService] 错误详情: \(error)")
                if let nsError = error as NSError? {
                    print("❌ [EmailService] 错误域: \(nsError.domain), 错误代码: \(nsError.code)")
                    if let failureReason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
                        print("❌ [EmailService] 失败原因: \(failureReason)")
                    }
                    if let libetpanCode = nsError.userInfo["LibEtPanErrorCode"] as? Int {
                        print("❌ [EmailService] LibEtPan 错误代码: \(libetpanCode)")
                        // 根据错误代码提供建议
                        if libetpanCode == 24 { // MAILSMTP_ERROR_STARTTLS_NOT_SUPPORTED
                            print("💡 [EmailService] 建议: STARTTLS 握手失败，可以尝试使用 SSL 直接连接（端口 465）")
                        } else if libetpanCode == 27 { // MAILSMTP_ERROR_SSL
                            print("💡 [EmailService] 建议: SSL/TLS 错误，请检查端口和加密方式是否匹配（SSL 通常用 465，STARTTLS 用 587）")
                        }
                    }
                }
                smtp.disconnect()
                throw EmailServiceError.connectionFailed(errorMessage)
            }
            
            print("📧 [EmailService] 正在登录 SMTP 服务器...")
            do {
                try smtp.login()
                print("✅ [EmailService] SMTP 登录成功")
            } catch {
                let errorDesc = error.localizedDescription
                let errorMessage = errorDesc.hasPrefix("登录失败") || errorDesc.hasPrefix("认证失败") ? errorDesc : "认证失败: \(errorDesc)"
                print("❌ [EmailService] SMTP 登录失败: \(errorMessage)")
                print("❌ [EmailService] 错误详情: \(error)")
                if let nsError = error as NSError? {
                    print("❌ [EmailService] 错误域: \(nsError.domain), 错误代码: \(nsError.code)")
                }
                smtp.disconnect()
                throw EmailServiceError.authenticationFailed(errorMessage)
            }
            
            print("✅ [EmailService] SMTP 会话创建成功")
            return smtp
        }.value
    }
    
    /// 发送邮件
    /// 
    /// 重要：每次发送都会创建独立的 SMTP session，操作完成后自动断开。
    /// 这样可以确保使用最新的账户配置。
    nonisolated func sendMessage(
        account: EmailAccount,
        to: [EmailContact],
        cc: [EmailContact] = [],
        bcc: [EmailContact] = [],
        subject: String,
        body: String,
        htmlBody: String? = nil,
        attachments: [EmailAttachment] = [],
        readReceipt: Bool = false
    ) async throws {
        // 隐私：不再 print 具体的收件人 / 主题 / 正文，只输出数量与长度等指标。
        let bodyChars = body.count
        let htmlChars = htmlBody?.count ?? 0
        print("📧 [EmailService] 开始发送邮件: to=\(to.count), cc=\(cc.count), bcc=\(bcc.count), attachments=\(attachments.count), bodyChars=\(bodyChars), htmlChars=\(htmlChars)")
        
        // 创建独立的 SMTP session
        let smtp = try await createSMTPSession(account: account)
        
        // 确保操作完成后断开连接
        defer {
            print("🔌 [EmailService] 断开 SMTP 连接 (sendMessage)")
            smtp.disconnect()
        }
        
        try await Task.detached(priority: .utility) { [smtp] in
            print("📧 [EmailService] 正在准备邮件数据（后台线程）...")
            
            let toAddresses: [String] = to.map { $0.email }
            let ccAddresses: [String] = cc.map { $0.email }
            let bccAddresses: [String] = bcc.map { $0.email }
            
            // 准备附件信息（包含 data, filename, mimeType）
            // 隐私：不再打印附件原始文件名，只打印 mime/size。
            let attachmentInfos: [[String: Any]] = attachments.compactMap { attachment -> [String: Any]? in
                guard let path = attachment.localPath,
                      let data = NSData(contentsOfFile: path) else {
                    print("⚠️ [EmailService] 无法读取附件 (mime=\(attachment.mimeType))")
                    return nil
                }
                print("📎 [EmailService] 附件已加载: mime=\(attachment.mimeType), bytes=\(data.length)")
                return [
                    "data": data as Data,
                    "filename": attachment.filename,
                    "mimeType": attachment.mimeType
                ]
            }
            
            print("📧 [EmailService] 正在调用 SMTP sendMessage...")
            do {
                let ccOpt: [String]? = ccAddresses.isEmpty ? nil : ccAddresses
                let bccOpt: [String]? = bccAddresses.isEmpty ? nil : bccAddresses
                let attachmentsOpt: [[String: Any]]? = attachmentInfos.isEmpty ? nil : attachmentInfos
                try smtp.sendMessage(to: toAddresses,
                                    cc: ccOpt,
                                    bcc: bccOpt,
                                    subject: subject,
                                    body: body,
                                    htmlBody: htmlBody,
                                    attachments: attachmentsOpt,
                                    readReceipt: readReceipt)
                print("✅ [EmailService] 邮件发送成功")
            } catch {
                let errorDesc = error.localizedDescription
                print("❌ [EmailService] 邮件发送失败: \(errorDesc)")
                print("❌ [EmailService] 错误详情: \(error)")
                if let nsError = error as NSError? {
                    print("❌ [EmailService] 错误域: \(nsError.domain), 错误代码: \(nsError.code)")
                    print("❌ [EmailService] 错误信息: \(nsError.userInfo)")
                }
                // 检查是否是连接错误，如果是则抛出连接失败错误
                if errorDesc.contains("连接失败") || errorDesc.contains("连接") {
                    let errorMessage = errorDesc.hasPrefix("连接失败") ? errorDesc : "连接失败: \(errorDesc)"
                    throw EmailServiceError.connectionFailed(errorMessage)
                }
                throw EmailServiceError.networkError(error)
            }
        }.value
    }
    
    // MARK: - Session Management
    
    /// 清理账户的后台任务
    /// 
    /// 注意：IMAP/SMTP session 现在都是每次操作独立创建的，不再缓存。
    /// 这里只需要取消后台同步任务。
    nonisolated func cleanupAccount(accountId: UUID) {
        // 取消后台同步任务
        cancelBackgroundSync(accountId: accountId)
        print("🧹 [EmailService] 已清理账户后台任务")
    }
    
    /// 清理所有后台任务
    ///
    /// 注意：IMAP/SMTP session 现在都是每次操作独立创建的，不再缓存。
    /// 这里需要取消后台同步任务，以及全部 IDLE 长连接。
    nonisolated func cleanupAllSessions() {
        for accountId in snapshotBackgroundSyncAccountIds() {
            cancelBackgroundSync(accountId: accountId)
        }
        Task { @MainActor in
            EmailIdleService.shared.stopAll()
        }
        print("🧹 [EmailService] 已清理所有后台任务（含 IDLE）")
    }
    
    // MARK: - Helper Methods
    
    /// 从邮件头信息解析 EmailMessage
    nonisolated private func parseEmailMessage(from headers: [String: Any], accountId: UUID, folderId: UUID, uid: UInt32) -> EmailMessage? {
        let subject = EmailContentDecoder.decodeRFC2047String((headers["subject"] as? String) ?? "")
        let fromString = EmailContentDecoder.decodeRFC2047String((headers["from"] as? String) ?? "")
        let toString = EmailContentDecoder.decodeRFC2047String((headers["to"] as? String) ?? "")
        let dateString = (headers["date"] as? String) ?? ""
        let messageId = headers["message-id"] as? String
        
        // 解析发件人
        let from = parseEmailAddress(fromString)
        
        // 解析收件人
        let to = parseEmailAddresses(toString)
        
        // 解析日期（邮件发送时间）
        // 重要：如果解析失败，使用一个很早的日期（1970-01-01）而不是当前时间
        // 这样可以避免将同步时间误认为是邮件发送时间
        let date = parseEmailDate(dateString) ?? Date(timeIntervalSince1970: 0)
        
        // 解析接收时间（如果有 Received 头）
        // 注意：Received 头可能有多行，取最后一个（最接近服务器的）
        let receivedDateString = (headers["received"] as? String) ?? ""
        let receivedDate = parseReceivedDate(receivedDateString) ?? date
        
        // 检测是否为no-reply地址
        let isNoReply = isNoReplyAddress(from.email)
        
        // 解析 IMAP FLAGS（已读、星标等，来自 LibEtPan fetch FLAGS）
        let isRead = (headers["seen"] as? NSNumber)?.boolValue ?? false
        let isStarred = (headers["flagged"] as? NSNumber)?.boolValue ?? false
        
        // 生成预览文本（使用主题作为初始预览）
        let preview = subject.isEmpty ? "" : subject
        
        // 计算线程ID（基于主题规范化，去除Re:/Fw:等前缀）
        let normalizedSubject = normalizeSubjectForThreading(subject)
        let threadId = messageId ?? normalizedSubject
        
        return EmailMessage(
            id: UUID(),
            accountId: accountId,
            folderId: folderId,
            uid: uid,
            messageId: messageId,
            threadId: threadId,
            subject: subject,
            from: from,
            to: to,
            preview: preview,
            date: date,  // 使用邮件发送时间
            receivedDate: receivedDate,  // 设置接收时间
            isRead: isRead,
            isStarred: isStarred,
            isNoReply: isNoReply,
            isBodyLoaded: false
        )
    }
    
    /// 规范化主题用于线程分组（去除Re:/Fw:等前缀）
    nonisolated private func normalizeSubjectForThreading(_ subject: String) -> String {
        var normalized = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 去除常见的回复/转发前缀（支持中英文）
        let prefixes = ["Re:", "RE:", "re:", "Fwd:", "FWD:", "fwd:", "Fw:", "FW:", "fw:", 
                       "回复:", "转发:", "Re：", "RE：", "Fwd：", "FWD：", "Fw：", "FW："]
        
        for prefix in prefixes {
            if normalized.hasPrefix(prefix) {
                normalized = String(normalized.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        
        return normalized.lowercased()
    }
    
    /// 解析邮件地址列表（逗号分隔）
    nonisolated private func parseEmailAddresses(_ addressString: String) -> [EmailContact] {
        guard !addressString.isEmpty else { return [] }
        
        let addresses = addressString.components(separatedBy: ",")
        return addresses.compactMap { parseEmailAddress($0.trimmingCharacters(in: .whitespaces)) }
    }
    
    /// 解析邮件日期
    /// 使用 RFC 2822 标准格式和多种常见格式解析邮件日期
    nonisolated private func parseEmailDate(_ dateString: String) -> Date? {
        guard !dateString.isEmpty else { return nil }
        
        // 清理日期字符串（移除可能的注释和多余空格）
        var cleaned = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        // 移除括号中的注释，如 "Mon, 1 Jan 2024 12:00:00 +0800 (CST)"
        if let commentRange = cleaned.range(of: " (", options: .backwards) {
            cleaned = String(cleaned[..<commentRange.lowerBound])
        }
        
        // 使用多种日期格式解析（按 RFC 2822 标准）
        let formatters: [DateFormatter] = [
            // RFC 2822 标准格式：Mon, 1 Jan 2024 12:00:00 +0800
            {
                let f = DateFormatter()
                f.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone(secondsFromGMT: 0)
                return f
            }(),
            // 不带星期：1 Jan 2024 12:00:00 +0800
            {
                let f = DateFormatter()
                f.dateFormat = "d MMM yyyy HH:mm:ss Z"
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone(secondsFromGMT: 0)
                return f
            }(),
            // 带时区名称：Mon, 1 Jan 2024 12:00:00 CST
            {
                let f = DateFormatter()
                f.dateFormat = "EEE, d MMM yyyy HH:mm:ss zzz"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            // ISO 8601 格式：2024-01-01T12:00:00+08:00
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            // 另一种 ISO 格式：2024-01-01T12:00:00+0800
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            // 简单格式：1 Jan 2024 12:00:00
            {
                let f = DateFormatter()
                f.dateFormat = "d MMM yyyy HH:mm:ss"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }()
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: cleaned) {
                return date
            }
        }
        
        // 如果所有格式都失败，尝试使用系统解析器（作为最后手段）
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let matches = detector.matches(in: cleaned, options: [], range: NSRange(location: 0, length: cleaned.utf16.count))
            if let match = matches.first, let date = match.date {
                return date
            }
        }
        
        return nil
    }
    
    /// 解析 Received 头中的日期（取最后一个 Received 头，即最接近服务器的）
    nonisolated private func parseReceivedDate(_ receivedString: String) -> Date? {
        guard !receivedString.isEmpty else { return nil }
        
        // Received 头可能有多行，用换行符分割，取最后一个
        let lines = receivedString.components(separatedBy: "\n")
        let lastLine = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? receivedString
        
        // Received 头格式通常是：from ... by ... with ...; Mon, 1 Jan 2024 12:00:00 +0800
        // 提取分号后的日期部分
        if let semicolonRange = lastLine.range(of: ";", options: .backwards) {
            let datePart = String(lastLine[semicolonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return parseEmailDate(datePart)
        }
        
        // 如果没有分号，尝试解析整个字符串
        return parseEmailDate(lastLine)
    }
    
    /// 检测是否为no-reply地址
    nonisolated func isNoReplyAddress(_ email: String) -> Bool {
        let lowercased = email.lowercased()
        return lowercased.contains("noreply") ||
               lowercased.contains("no-reply") ||
               lowercased.contains("donotreply") ||
               lowercased.contains("do-not-reply") ||
               lowercased.contains("mailer-daemon") ||
               lowercased.contains("postmaster")
    }
    
    /// 解析邮件地址
    nonisolated func parseEmailAddress(_ addressString: String) -> EmailContact {
        let trimmed = addressString.trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = EmailContentDecoder.decodeRFC2047String(trimmed)
        
        // 解析 "Name <email@example.com>" 格式
        if let range = decoded.range(of: "<", options: .backwards),
           let endRange = decoded.range(of: ">", options: [], range: range.upperBound..<decoded.endIndex) {
            let email = String(decoded[range.upperBound..<endRange.lowerBound])
            var name = String(decoded[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return EmailContact(name: name.isEmpty ? nil : name, email: email)
        }
        
        return EmailContact(email: decoded)
    }
}
