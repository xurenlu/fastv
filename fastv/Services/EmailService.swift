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
@MainActor
class EmailService {
    static let shared = EmailService()
    
    // nonisolated(unsafe): 允许后台线程访问这些属性
    nonisolated(unsafe) private var imapSessions: [UUID: LibEtPanIMAPSession] = [:]
    nonisolated(unsafe) private var smtpSessions: [UUID: LibEtPanSMTPSession] = [:]
    nonisolated(unsafe) var initialLoadLimit = 1000 // 可配置
    nonisolated(unsafe) private var backgroundSyncTasks: [UUID: Task<Void, Never>] = [:]
    
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
        
        var stages: [EmailConnectionStageResult] = []
        stages.append(testIMAPStage(account: account, password: password))
        stages.append(testSMTPStage(account: account, password: password))
        
        return EmailConnectionTestReport(stages: stages)
    }
    
    private func testIMAPStage(account: EmailAccount, password: String) -> EmailConnectionStageResult {
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
    
    private func testSMTPStage(account: EmailAccount, password: String) -> EmailConnectionStageResult {
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
    
    /// 获取或创建 IMAP 会话
    /// 注意：LibEtPan 的 CFStream 必须在主线程的 run loop 上运行
    nonisolated private func getOrCreateIMAPSession(account: EmailAccount) async throws -> LibEtPanIMAPSession {
        // 检查是否已有会话
        if let existing = imapSessions[account.id] {
            return existing
        }
        
        // LibEtPan 的 CFStream 操作必须在主线程执行
        return try await MainActor.run {
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
            } catch {
                throw EmailServiceError.connectionFailed(error.localizedDescription)
            }
            
            do {
                try imap.login()
            } catch {
                imap.disconnect()
                throw EmailServiceError.authenticationFailed(error.localizedDescription)
            }
            
            self.imapSessions[account.id] = imap
            return imap
        }
    }
    
    /// 同步邮件（增量同步，支持时间范围和限制数量）
    /// nonisolated: 允许在后台线程执行,避免阻塞UI
    nonisolated func syncMessages(
        account: EmailAccount,
        folder: EmailFolder,
        since: Date? = nil,
        limit: Int? = nil,
        batchSize: Int = 20
    ) async throws -> [EmailMessage] {
        // LibEtPan 的 CFStream 操作必须在主线程执行
        // 先获取 session（在主线程）
        let imap = try await getOrCreateIMAPSession(account: account)
        
        // 将所有 LibEtPan 操作包装在主线程执行
        return try await MainActor.run {
            
            do {
                try imap.selectFolder(folder.name)
            } catch {
                throw EmailServiceError.connectionFailed(error.localizedDescription)
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
            let maxCount = limit ?? Int.max
            
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
        }
    }
    
    /// 后台同步剩余邮件
    nonisolated private func scheduleBackgroundSync(
        account: EmailAccount,
        folder: EmailFolder,
        remainingUIDs: [Any],
        sinceDate: Date?
    ) {
        // 取消之前的后台任务(如果有)
        backgroundSyncTasks[account.id]?.cancel()
        
        let task = Task.detached(priority: .background) {
            print("🔄 [EmailService] 开始后台同步剩余 \(remainingUIDs.count) 封邮件...")
            
            var syncedCount = 0
            let totalCount = remainingUIDs.count
            
            for msgDictAny in remainingUIDs {
                // 检查是否被取消
                if Task.isCancelled {
                    print("⚠️ [EmailService] 后台同步被取消")
                    break
                }
                
                guard let msgDict = msgDictAny as? NSDictionary,
                      let uidValue = msgDict["uid"] as? NSNumber else { continue }
                let uid = uidValue.uint32Value
                
                do {
                    // LibEtPan 的 CFStream 操作必须在主线程执行
                    let imap = try await self.getOrCreateIMAPSession(account: account)
                    let headers = try await MainActor.run {
                        try imap.selectFolder(folder.name)
                        let headerDict = try imap.fetchMessageHeaders(withUID: uid)
                        return headerDict as? [String: Any] ?? [:]
                    }
                    
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
                        
                        // 保存到本地数据库
                        try await EmailStore.shared.addMessages([emailMessage], folderId: folder.id)
                        syncedCount += 1
                        
                        // 每处理100封打印进度
                        if syncedCount % 100 == 0 {
                            print("🔄 [EmailService] 后台已同步 \(syncedCount)/\(totalCount) 封邮件")
                        }
                        
                        // 让出CPU,避免占用过多资源
                        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    }
                } catch {
                    print("⚠️ [EmailService] 后台同步邮件失败，UID: \(uid), 错误: \(error.localizedDescription)")
                }
            }
            
            print("✅ [EmailService] 后台同步完成: \(syncedCount) 封邮件")
        }
        
        backgroundSyncTasks[account.id] = task
    }
    
    /// 取消后台同步任务
    nonisolated func cancelBackgroundSync(accountId: UUID) {
        backgroundSyncTasks[accountId]?.cancel()
        backgroundSyncTasks.removeValue(forKey: accountId)
    }
    
    /// 获取邮件正文
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
        
        // LibEtPan 的 CFStream 操作必须在主线程执行
        let imap = try await getOrCreateIMAPSession(account: account)
        let bodyData = try await MainActor.run {
            do {
                try imap.selectFolder(folder.name)
                print("📧 [EmailService] fetchMessageBody: 文件夹选择成功")
            } catch {
                print("❌ [EmailService] fetchMessageBody: 选择文件夹失败: \(error)")
                throw EmailServiceError.connectionFailed(error.localizedDescription)
            }
            
            let data = try imap.fetchMessageBody(withUID: uid)
            print("📧 [EmailService] fetchMessageBody: 获取到数据 \(data.count) 字节")
            return data
        }
        
        if bodyData.isEmpty {
            print("❌ [EmailService] fetchMessageBody: 邮件正文为空")
            throw EmailServiceError.parseError("未获取到邮件正文")
        }
        
        // 解析可以在后台线程执行
        let content = EmailContentDecoder.parseBody(data: bodyData)
        print("📧 [EmailService] fetchMessageBody: 解析完成, textBody=\(content.textBody?.count ?? 0)字符, htmlBody=\(content.htmlBody?.count ?? 0)字符, hasRemote=\(content.containsRemoteResources)")
        
        return content
    }
    
    /// 获取文件夹列表
    nonisolated func fetchFolders(account: EmailAccount) async throws -> [EmailFolder] {
        // LibEtPan 的 CFStream 操作必须在主线程执行
        let imap = try await getOrCreateIMAPSession(account: account)
        let folderNames: [String] = try await MainActor.run {
            do {
                return try imap.fetchFolders() ?? []
            } catch {
                throw EmailServiceError.connectionFailed(error.localizedDescription)
            }
        }
        
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
    /// 注意：LibEtPan 的 CFStream 必须在主线程的 run loop 上运行
    nonisolated func markAsRead(account: EmailAccount, message: EmailMessage) async throws {
        guard let uid = message.uid else {
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }
        
        // LibEtPan 的 CFStream 操作必须在主线程执行
        let imap = try await getOrCreateIMAPSession(account: account)
        try await MainActor.run {
            do {
                try imap.markAsRead(withUID: uid)
            } catch {
                throw EmailServiceError.networkError(error)
            }
        }
    }
    
    /// 删除邮件
    nonisolated func deleteMessage(account: EmailAccount, message: EmailMessage) async throws {
        guard let uid = message.uid else {
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }
        
        // LibEtPan 的 CFStream 操作必须在主线程执行
        let imap = try await getOrCreateIMAPSession(account: account)
        
        // 获取邮件所在的文件夹
        guard let folderId = message.folderId,
              let folder = try await EmailStore.shared.getFolders(for: account.id).first(where: { $0.id == folderId }) else {
            throw EmailServiceError.invalidConfiguration("找不到邮件所在文件夹")
        }
        
        try await MainActor.run {
            do {
                try imap.selectFolder(folder.name)
                // TODO: 使用 LibEtPan 的删除功能（STORE +DELETE 或 MOVE 到 Trash）
                // 目前先标记为已删除，实际删除功能需要 LibEtPan 支持
                print("⚠️ [EmailService] 删除邮件功能需要 LibEtPan 支持，当前仅标记为已删除")
            } catch {
                throw EmailServiceError.networkError(error)
            }
        }
    }
    
    /// 切换星标状态
    nonisolated func toggleStar(account: EmailAccount, message: EmailMessage) async throws {
        guard let uid = message.uid else {
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }
        
        // LibEtPan 的 CFStream 操作必须在主线程执行
        let imap = try await getOrCreateIMAPSession(account: account)
        
        guard let folderId = message.folderId,
              let folder = try await EmailStore.shared.getFolders(for: account.id).first(where: { $0.id == folderId }) else {
            throw EmailServiceError.invalidConfiguration("找不到邮件所在文件夹")
        }
        
        try await MainActor.run {
            do {
                try imap.selectFolder(folder.name)
                // TODO: 使用 LibEtPan 的 STORE 命令添加/移除 \Flagged 标志
                // 目前先更新本地状态
                print("⚠️ [EmailService] 星标功能需要 LibEtPan 支持，当前仅更新本地状态")
            } catch {
                throw EmailServiceError.networkError(error)
            }
        }
    }
    
    /// 标记为垃圾邮件
    nonisolated func markAsSpam(account: EmailAccount, message: EmailMessage) async throws {
        guard let uid = message.uid else {
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }
        
        // 查找垃圾邮件文件夹
        let folders = try await EmailStore.shared.getFolders(for: account.id)
        guard let spamFolder = folders.first(where: { $0.type == .spam }) else {
            throw EmailServiceError.invalidConfiguration("找不到垃圾邮件文件夹")
        }
        
        try await moveMessage(account: account, message: message, to: spamFolder)
    }
    
    /// 取消垃圾邮件标记
    nonisolated func unmarkSpam(account: EmailAccount, message: EmailMessage) async throws {
        guard let uid = message.uid else {
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }
        
        // 移动到收件箱
        let folders = try await EmailStore.shared.getFolders(for: account.id)
        guard let inboxFolder = folders.first(where: { $0.type == .inbox }) else {
            throw EmailServiceError.invalidConfiguration("找不到收件箱")
        }
        
        try await moveMessage(account: account, message: message, to: inboxFolder)
    }
    
    /// 下载附件
    nonisolated func downloadAttachment(
        account: EmailAccount,
        folder: EmailFolder,
        message: EmailMessage,
        attachment: EmailAttachment
    ) async throws -> URL {
        guard let uid = message.uid else {
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }
        
        // LibEtPan 的 CFStream 操作必须在主线程执行
        let imap = try await getOrCreateIMAPSession(account: account)
        let bodyData = try await MainActor.run {
            try imap.selectFolder(folder.name)
            
            // TODO: 使用 LibEtPan 获取附件的具体部分
            // 目前先获取完整邮件，然后解析附件
            return try imap.fetchMessageBody(withUID: uid)
        }
        
        // 解析 MIME 结构，提取附件
        // 这里需要解析 multipart 结构，找到对应的附件部分
        // 简化实现：保存到临时目录
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(attachment.filename)
        
        // TODO: 从 bodyData 中提取附件内容
        // 目前先创建一个占位文件
        try Data().write(to: fileURL)
        
        print("📎 [EmailService] 附件下载完成: \(attachment.filename)")
        return fileURL
    }
    
    /// 移动邮件到文件夹
    nonisolated func moveMessage(account: EmailAccount, message: EmailMessage, to folder: EmailFolder) async throws {
        guard let uid = message.uid else {
            throw EmailServiceError.invalidConfiguration("邮件 UID 不存在")
        }
        
        // LibEtPan 的 CFStream 操作必须在主线程执行
        let imap = try await getOrCreateIMAPSession(account: account)
        
        guard let folderId = message.folderId,
              let sourceFolder = try await EmailStore.shared.getFolders(for: account.id).first(where: { $0.id == folderId }) else {
            throw EmailServiceError.invalidConfiguration("找不到源文件夹")
        }
        
        try await MainActor.run {
            do {
                try imap.selectFolder(sourceFolder.name)
                // TODO: 使用 LibEtPan 的 MOVE 或 COPY + STORE +DELETE 命令
                // 目前先更新本地状态
                print("⚠️ [EmailService] 移动邮件功能需要 LibEtPan 支持，当前仅更新本地状态")
            } catch {
                throw EmailServiceError.networkError(error)
            }
        }
    }
    
    // MARK: - SMTP Operations
    
    /// 获取或创建 SMTP 会话
    /// 注意：LibEtPan 的 CFStream 必须在主线程的 run loop 上运行
    nonisolated private func getOrCreateSMTPSession(account: EmailAccount) async throws -> LibEtPanSMTPSession {
        // 检查是否已有会话
        if let existing = smtpSessions[account.id] {
            print("📧 [EmailService] 使用现有 SMTP 会话: \(account.emailAddress)")
            return existing
        }
        
        // LibEtPan 的 CFStream 操作必须在主线程执行
        return try await MainActor.run {
            print("📧 [EmailService] 开始创建 SMTP 会话")
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
                    }
                }
            }
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
            
            self.smtpSessions[account.id] = smtp
            print("✅ [EmailService] SMTP 会话创建并保存成功")
            return smtp
        }
    }
    
    /// 发送邮件
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
        print("📧 [EmailService] 开始发送邮件")
        print("📧 [EmailService] 发件人: \(account.emailAddress)")
        print("📧 [EmailService] 收件人: \(to.map { $0.email }.joined(separator: ", "))")
        if !cc.isEmpty {
            print("📧 [EmailService] 抄送: \(cc.map { $0.email }.joined(separator: ", "))")
        }
        if !bcc.isEmpty {
            print("📧 [EmailService] 密送: \(bcc.map { $0.email }.joined(separator: ", "))")
        }
        print("📧 [EmailService] 主题: \(subject)")
        print("📧 [EmailService] 正文长度: \(body.count) 字符")
        if let htmlBody = htmlBody {
            print("📧 [EmailService] HTML 正文长度: \(htmlBody.count) 字符")
        }
        print("📧 [EmailService] 附件数量: \(attachments.count)")
        
        // LibEtPan 的 CFStream 操作必须在主线程执行
        let smtp = try await getOrCreateSMTPSession(account: account)
        
        try await MainActor.run {
            print("📧 [EmailService] 正在准备邮件数据...")
            
            let toAddresses: [String] = to.map { $0.email }
            let ccAddresses: [String] = cc.map { $0.email }
            let bccAddresses: [String] = bcc.map { $0.email }
            let attachmentData: [Data] = attachments.compactMap { attachment -> Data? in
                guard let path = attachment.localPath,
                      let data = NSData(contentsOfFile: path) else {
                    print("⚠️ [EmailService] 无法读取附件: \(attachment.filename)")
                    return nil
                }
                print("📎 [EmailService] 附件已加载: \(attachment.filename) (\(data.length) 字节)")
                return data as Data
            }
            
            print("📧 [EmailService] 正在调用 SMTP sendMessage...")
            do {
                let ccOpt: [String]? = ccAddresses.isEmpty ? nil : ccAddresses
                let bccOpt: [String]? = bccAddresses.isEmpty ? nil : bccAddresses
                let attachmentsOpt: [Data]? = attachmentData.isEmpty ? nil : attachmentData
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
        }
    }
    
    // MARK: - Session Management
    
    /// 清理账户的所有会话和后台任务
    nonisolated func cleanupAccount(accountId: UUID) {
        // 取消后台同步任务
        cancelBackgroundSync(accountId: accountId)
        
        // LibEtPan 的断开操作必须在主线程执行
        Task { @MainActor in
            // 断开IMAP连接
            if let imapSession = self.imapSessions[accountId] {
                imapSession.disconnect()
                self.imapSessions.removeValue(forKey: accountId)
            }
            
            // 断开SMTP连接
            if let smtpSession = self.smtpSessions[accountId] {
                smtpSession.disconnect()
                self.smtpSessions.removeValue(forKey: accountId)
            }
            
            print("🧹 [EmailService] 已清理账户会话和后台任务")
        }
    }
    
    /// 清理所有会话
    nonisolated func cleanupAllSessions() {
        // 取消所有后台任务
        let accountIds = backgroundSyncTasks.keys
        for accountId in accountIds {
            cancelBackgroundSync(accountId: accountId)
        }
        
        // LibEtPan 的断开操作必须在主线程执行
        Task { @MainActor in
            // 断开所有IMAP连接
            for (_, session) in self.imapSessions {
                session.disconnect()
            }
            self.imapSessions.removeAll()
            
            // 断开所有SMTP连接
            for (_, session) in self.smtpSessions {
                session.disconnect()
            }
            self.smtpSessions.removeAll()
            
            print("🧹 [EmailService] 已清理所有会话")
        }
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
        
        // 解析日期
        let date = parseEmailDate(dateString) ?? Date()
        
        // 检测是否为no-reply地址
        let isNoReply = isNoReplyAddress(from.email)
        
        // 生成预览文本（使用主题作为初始预览）
        let preview = subject.isEmpty ? "" : subject
        
        return EmailMessage(
            id: UUID(),
            accountId: accountId,
            folderId: folderId,
            uid: uid,
            messageId: messageId,
            subject: subject,
            from: from,
            to: to,
            preview: preview,
            date: date,
            isNoReply: isNoReply,
            isBodyLoaded: false
        )
    }
    
    /// 解析邮件地址列表（逗号分隔）
    nonisolated private func parseEmailAddresses(_ addressString: String) -> [EmailContact] {
        guard !addressString.isEmpty else { return [] }
        
        let addresses = addressString.components(separatedBy: ",")
        return addresses.compactMap { parseEmailAddress($0.trimmingCharacters(in: .whitespaces)) }
    }
    
    /// 解析邮件日期
    nonisolated private func parseEmailDate(_ dateString: String) -> Date? {
        guard !dateString.isEmpty else { return nil }
        
        // 使用多种日期格式解析
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "d MMM yyyy HH:mm:ss Z"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "EEE, d MMM yyyy HH:mm:ss zzz"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }()
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        
        return nil
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
