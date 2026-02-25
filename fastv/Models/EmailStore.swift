//
//  EmailStore.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine
import GRDB

/// 本地“已发送”文件夹的 IMAP 路径（仅本地存在，不来自服务器）
let kLocalSentFolderPath = "__LocalSent__"

/// 邮箱数据管理器（类似ChatManager）
@MainActor
class EmailStore: ObservableObject {
    static let shared = EmailStore()
    
    @Published private(set) var accounts: [EmailAccount] = []
    @Published private(set) var folders: [UUID: [EmailFolder]] = [:] // accountId -> folders
    @Published private(set) var messages: [UUID: [EmailMessage]] = [:] // folderId -> messages
    
    private let database = EmailDatabase.shared
    private var saveTimer: Timer?
    private let saveDelay: TimeInterval = 2.0
    
    private func notifyChange() {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    private init() {
        // 立即加载账号和文件夹（高优先级，确保快速显示）
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            await self.loadAccounts()
            
            // 迁移：修复 Gmail 账号的 SMTP 配置（587+SSL -> 465+SSL）
            await self.migrateGmailSmtpConfig()
            
            await self.loadFolders()
            
            // 预加载邮件缓存（低优先级，后台执行）
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                await self.preloadMessageCache()
            }
            
            // SQLite 后台优化：延迟执行，避免与启动争抢；VACUUM 最多每天一次
            Task.detached(priority: .background) { [weak self] in
                guard self != nil else { return }
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 秒
                let key = "EmailStore.lastSqliteVacuumDate"
                let last = UserDefaults.standard.object(forKey: key) as? Date
                let oneDay: TimeInterval = 86400
                let includeVacuum = last == nil || Date().timeIntervalSince(last!) > oneDay
                if includeVacuum {
                    UserDefaults.standard.set(Date(), forKey: key)
                }
                EmailDatabase.shared.optimizeInBackground(includeVacuum: includeVacuum)
            }
            
            // 重复邮件清理：后台静默执行，最多每 24 小时一次
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(nanoseconds: 120_000_000_000) // 启动后 2 分钟再执行，避免与预加载争抢
                let key = "EmailStore.lastDuplicateCleanupDate"
                let last = UserDefaults.standard.object(forKey: key) as? Date
                let oneDay: TimeInterval = 86400
                guard last == nil || Date().timeIntervalSince(last!) > oneDay else { return }
                UserDefaults.standard.set(Date(), forKey: key)
                do {
                    let deleted = try await self.cleanupDuplicateMessages()
                    if deleted > 0 {
                        print("🧹 [EmailStore] 后台已清理 \(deleted) 封重复邮件")
                    }
                } catch {
                    print("⚠️ [EmailStore] 后台清理重复邮件失败: \(error)")
                }
            }
        }
    }
    
    /// 迁移 Gmail 账号的 SMTP 配置
    /// 修复错误的 587 端口配置为正确的 465+SSL
    private func migrateGmailSmtpConfig() async {
        print("🔧 [EmailStore] 开始检查 Gmail SMTP 配置迁移...")
        var needsMigration: [EmailAccount] = []
        
        for account in accounts {
            print("🔧 [EmailStore] 检查账号: \(account.emailAddress), serviceType=\(account.serviceType.rawValue), smtpHost=\(account.smtpHost), smtpPort=\(account.smtpPort), smtpEncryption=\(account.smtpEncryption.rawValue)")
            
            // 检查是否是 Gmail 账号且使用了 587 端口（不管加密方式，都应该改为 465+SSL）
            if account.serviceType == .gmail &&
               account.smtpHost == "smtp.gmail.com" &&
               account.smtpPort == 587 {
                print("🔧 [EmailStore] 发现需要迁移的 Gmail 账号: \(account.emailAddress) (当前: 587+\(account.smtpEncryption.rawValue))")
                needsMigration.append(account)
            }
        }
        
        print("🔧 [EmailStore] 需要迁移的账号数量: \(needsMigration.count)")
        
        for account in needsMigration {
            var updated = account
            updated.smtpPort = 465  // 修复为正确的端口
            updated.smtpEncryption = .ssl  // 确保使用 SSL
            updated.updatedAt = Date()
            
            do {
                try await database.write { db in
                    try self.saveAccount(updated, db: db)
                }
                print("✅ [EmailStore] Gmail 账号 SMTP 配置已迁移: \(account.emailAddress) -> 465+SSL")
            } catch {
                print("❌ [EmailStore] Gmail 账号迁移失败: \(error)")
            }
        }
        
        // 如果有迁移，重新加载账号
        if !needsMigration.isEmpty {
            await loadAccounts()
            print("✅ [EmailStore] 账号列表已重新加载")
        }
    }
    
    /// 预加载邮件缓存（后台执行，智能优先级）
    private func preloadMessageCache() async {
        print("📦 [EmailStore] 开始预加载邮件缓存...")
        let startTime = Date()
        
        // 获取所有文件夹
        let allFolders = folders.values.flatMap { $0 }
        
        // 按优先级排序：收件箱 > 垃圾邮件 > 已发送 > 草稿 > 回收站
        let priorityOrder: [EmailFolderType] = [.inbox, .spam, .sent, .drafts, .trash]
        var sortedFolders: [EmailFolder] = []
        
        for type in priorityOrder {
            let foldersOfType = allFolders.filter { $0.type == type }
            sortedFolders.append(contentsOf: foldersOfType)
        }
        
        print("📦 [EmailStore] 需要预加载 \(sortedFolders.count) 个重要文件夹")
        
        // 串行预加载（避免同时大量数据库操作造成卡顿）
        for (index, folder) in sortedFolders.prefix(8).enumerated() {
            print("📦 [EmailStore] 预加载 [\(index+1)/\(min(8, sortedFolders.count))]: \(folder.name) (\(folder.type.rawValue))")
            await loadMessages(for: folder.id)
            
            // 每加载一个文件夹后稍微延迟，避免占用过多资源
            if index < sortedFolders.count - 1 {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let totalMessages = messages.values.reduce(0) { $0 + $1.count }
        print("📦 [EmailStore] 邮件缓存预加载完成，总计: \(totalMessages)封，耗时: \(String(format: "%.2f", elapsed))秒")
    }
    
    // MARK: - Account Management
    
    /// 添加账号
    func addAccount(_ account: EmailAccount) async throws {
        try await database.write { db in
            try self.saveAccount(account, db: db)
        }
        await loadAccounts()
    }
    
    /// 更新账号
    func updateAccount(_ account: EmailAccount) async throws {
        var updated = account
        updated.updatedAt = Date()
        
        try await database.write { db in
            try self.saveAccount(updated, db: db)
        }
        await loadAccounts()
    }
    
    /// 删除账号
    func deleteAccount(_ account: EmailAccount) async throws {
        // 删除Keychain中的密码
        EmailCredentialStore.shared.deletePassword(accountId: account.id)
        
        try await database.write { db in
            try db.execute(sql: "DELETE FROM email_accounts WHERE id = ?", arguments: [account.id.uuidString])
        }
        await loadAccounts()
    }
    
    /// 获取账号
    func getAccount(id: UUID) -> EmailAccount? {
        return accounts.first { $0.id == id }
    }
    
    /// 获取默认账号
    func getDefaultAccount() -> EmailAccount? {
        return accounts.first { $0.isDefault && $0.isEnabled }
    }
    
    // MARK: - Folder Management
    
    /// 添加文件夹（检查重复）
    /// 返回实际保存的文件夹（如果已存在则返回数据库中的版本，否则返回新创建的）
    @discardableResult
    func addFolder(_ folder: EmailFolder) async throws -> EmailFolder {
        let normalizedPath = folder.path.lowercased()
        let existingFolders = folders[folder.accountId] ?? []
        if let existing = existingFolders.first(where: { $0.path.lowercased() == normalizedPath }) {
            let updatedFolder = EmailFolder(
                id: existing.id,
                accountId: folder.accountId,
                name: folder.name,
                type: folder.type,
                path: existing.path,
                unreadCount: folder.unreadCount,
                totalCount: folder.totalCount,
                lastSyncDate: folder.lastSyncDate
            )
            try await updateFolder(updatedFolder)
            return updatedFolder  // 返回使用数据库ID的文件夹
        }
        
        try await database.write { db in
            try self.saveFolder(folder, db: db)
        }
        await loadFolders()
        return folder  // 新文件夹，返回原始对象
    }
    
    /// 更新文件夹
    func updateFolder(_ folder: EmailFolder) async throws {
        try await database.write { db in
            try self.saveFolder(folder, db: db)
        }
        await loadFolders()
    }
    
    /// 删除文件夹
    func deleteFolder(_ folder: EmailFolder) async throws {
        // 检查文件夹是否为空
        let messageCount = getMessageCount(for: folder.id)
        guard messageCount == 0 else {
            throw NSError(domain: "EmailStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法删除非空文件夹"])
        }
        
        // 删除数据库中的文件夹记录
        try await database.write { db in
            try db.execute(sql: "DELETE FROM email_folders WHERE id = ?", arguments: [folder.id.uuidString])
        }
        
        // 删除内存中的文件夹
        if var accountFolders = folders[folder.accountId] {
            accountFolders.removeAll { $0.id == folder.id }
            folders[folder.accountId] = accountFolders
        }
        
        // 删除该文件夹的所有邮件
        messages.removeValue(forKey: folder.id)
        
        await loadFolders()
        notifyChange()
    }
    
    /// 获取账号的文件夹列表
    func getFolders(for accountId: UUID) -> [EmailFolder] {
        return folders[accountId] ?? []
    }
    
    /// 获取“本地已发送”文件夹（仅本地存在，用于存放本机发出的邮件）
    func getLocalSentFolder(for accountId: UUID) -> EmailFolder? {
        return folders[accountId]?.first { $0.path == kLocalSentFolderPath }
    }
    
    /// 确保当前账号存在“本地已发送”文件夹，不存在则创建
    func ensureLocalSentFolder(for accountId: UUID) async throws {
        if getLocalSentFolder(for: accountId) != nil { return }
        let localSent = EmailFolder(
            id: UUID(),
            accountId: accountId,
            name: NSLocalizedString("email.folder.local_sent", value: "已发送(本地)", comment: "Local sent folder name"),
            type: .sent,
            path: kLocalSentFolderPath,
            unreadCount: 0,
            totalCount: 0
        )
        try await database.write { db in
            try self.saveFolder(localSent, db: db)
        }
        await loadFolders()
    }
    
    // MARK: - Message Management
    
    /// 添加邮件（批量，增量更新，深度去重）
    func addMessages(_ newMessages: [EmailMessage], folderId: UUID) async throws {
        // 由于 @MainActor，这里已经在主线程，但我们可以将耗时操作移到后台
        let existingMessages = messages[folderId] ?? []
        var updatedMessages: [EmailMessage] = []
        var hasNewMessages = false
        
        // 快速合并邮件（在主线程，但操作很快）
        var workingMessages = existingMessages
        for message in newMessages {
            if let existingIndex = workingMessages.firstIndex(where: { $0.uid == message.uid }) {
                let existing = workingMessages[existingIndex]
                var updated = message
                if existing.isBodyLoaded {
                    updated.textBody = existing.textBody
                    updated.htmlBody = existing.htmlBody
                    updated.isBodyLoaded = true
                    updated.bodyCachedAt = existing.bodyCachedAt // 保留缓存时间
                }
                // 保留已有邮件的状态标记（服务端 FLAGS 优先；无 FLAGS 时保留本地状态）
                updated.isRead = message.isRead ? message.isRead : existing.isRead
                updated.isStarred = message.isStarred ? message.isStarred : existing.isStarred
                updatedMessages.append(updated)
                workingMessages[existingIndex] = updated
            } else {
                updatedMessages.append(message)
                workingMessages.append(message)
                hasNewMessages = true
            }
        }
        
        // 统一在后台线程排序（无论数据量大小，确保零卡顿）
        print("📊 [EmailStore] 开始后台排序，数量: \(workingMessages.count)封")
        
        // 在后台线程排序，然后回到主线程更新
        let sortedMessages = await Task.detached(priority: .userInitiated) {
            var sorted = workingMessages
            sorted.sort { $0.date > $1.date }
            return sorted
        }.value
        
        // 在主线程更新 @Published 属性
        self.messages[folderId] = sortedMessages
        FolderMessageCountCache.shared.updateCount(for: folderId, count: sortedMessages.count)
        self.notifyChange()
        print("✅ [EmailStore] 后台排序完成，通知UI更新")
        
        // 在后台线程异步写入数据库(不阻塞UI)
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            do {
                // 应用规则引擎处理邮件
                let ruleEngine = EmailRuleEngine.shared
                let deduplicationService = EmailDeduplicationService.shared
                var processedMessages: [EmailMessage] = []
                var newMessageCount = 0
                
                // 处理每个邮件
                for message in updatedMessages {
                    // 深度去重检查：检查数据库中是否已存在
                    let existingMessage = try await self.database.asyncRead { db in
                        return try deduplicationService.checkDuplicate(message, in: db)
                    }
                    
                    if let existingMessage = existingMessage {
                        // 发现重复，合并数据（保留更完整的版本）
                        var merged = message
                        
                        // 保留已有邮件的正文（如果新邮件没有正文）
                        if !message.isBodyLoaded && existingMessage.isBodyLoaded {
                            merged.textBody = existingMessage.textBody
                            merged.htmlBody = existingMessage.htmlBody
                            merged.isBodyLoaded = true
                            merged.bodyCachedAt = existingMessage.bodyCachedAt
                        }
                        
                        // 保留已有邮件的标签和AI信息
                        if existingMessage.tags.isEmpty == false {
                            merged.tags = Array(Set(merged.tags + existingMessage.tags))
                        }
                        if existingMessage.aiTags.isEmpty == false {
                            merged.aiTags = Array(Set(merged.aiTags + existingMessage.aiTags))
                        }
                        if merged.aiSummary == nil, let summary = existingMessage.aiSummary {
                            merged.aiSummary = summary
                        }
                        if merged.aiPriority == nil, let priority = existingMessage.aiPriority {
                            merged.aiPriority = priority
                        }
                        
                        // 保留已有邮件的状态标记
                        merged.isRead = merged.isRead || existingMessage.isRead
                        merged.isStarred = merged.isStarred || existingMessage.isStarred
                        merged.isImportant = merged.isImportant || existingMessage.isImportant
                        merged.hasAttachments = merged.hasAttachments || existingMessage.hasAttachments
                        merged.isSpam = merged.isSpam || existingMessage.isSpam
                        merged.isDeleted = merged.isDeleted || existingMessage.isDeleted
                        merged.hasBeenReplied = merged.hasBeenReplied || existingMessage.hasBeenReplied
                        
                        // 更新数据库
                        try await self.database.asyncWrite { db in
                            try self.updateMessageInDatabase(merged, existingId: existingMessage.id, db: db)
                        }
                        print("🔄 [EmailStore] 发现重复邮件，已合并: \(merged.subject)")
                    } else {
                        // 新邮件，应用规则引擎
                        if hasNewMessages {
                            let processed = await ruleEngine.processMessage(message)
                            processedMessages.append(processed)
                            newMessageCount += 1
                        } else {
                            processedMessages.append(message)
                        }
                    }
                }
                
                // 批量保存新邮件
                if !processedMessages.isEmpty {
                    try await self.database.asyncWrite { db in
                        for message in processedMessages {
                            try self.saveMessage(message, db: db)
                        }
                    }
                }
                
                if newMessageCount > 0 {
                    print("✅ [EmailStore] 后台保存了 \(newMessageCount) 封新邮件到数据库（已应用规则引擎和深度去重）")
                }
            } catch {
                print("❌ [EmailStore] 后台保存邮件失败: \(error)")
            }
        }
    }
    
    /// 更新邮件（完全异步，不阻塞调用线程）
    func updateMessage(_ message: EmailMessage) async throws {
        var updated = message
        updated.updatedAt = Date()
        
        // 先更新内存（在主线程，快速操作）
        if let folderId = message.folderId,
           var folderMessages = messages[folderId],
           let index = folderMessages.firstIndex(where: { $0.id == message.id }) {
            let existingMessage = folderMessages[index]
            let existingHasBody = existingMessage.isBodyLoaded || (existingMessage.textBody?.isEmpty == false) || (existingMessage.htmlBody?.isEmpty == false)
            let updatedHasBody = updated.isBodyLoaded || (updated.textBody?.isEmpty == false) || (updated.htmlBody?.isEmpty == false)
            if existingHasBody && !updatedHasBody {
                if updated.textBody?.isEmpty != false {
                    updated.textBody = existingMessage.textBody
                }
                if updated.htmlBody?.isEmpty != false {
                    updated.htmlBody = existingMessage.htmlBody
                }
                updated.isBodyLoaded = true
                if updated.bodyCachedAt == nil {
                    updated.bodyCachedAt = existingMessage.bodyCachedAt
                }
                if updated.preview.isEmpty {
                    updated.preview = existingMessage.preview
                }
                if !updated.containsRemoteResources {
                    updated.containsRemoteResources = existingMessage.containsRemoteResources
                }
            }
            folderMessages[index] = updated
            messages[folderId] = folderMessages
            let hasBody = updated.isBodyLoaded || (updated.textBody?.isEmpty == false) || (updated.htmlBody?.isEmpty == false)
            print("✅ [EmailStore] 更新内存中的邮件: \(updated.subject), folderId=\(folderId), hasBody=\(hasBody), htmlBody长度=\(updated.htmlBody?.count ?? 0)")
            notifyChange()
        } else {
            print("⚠️ [EmailStore] 无法更新邮件（未找到）: \(updated.subject), folderId=\(message.folderId?.uuidString ?? "nil")")
        }
        
        // 后台异步写入数据库（fire-and-forget，不等待完成）
        // 使用 .background 优先级，避免与 UI 操作竞争资源
        Task.detached(priority: .background) { [weak self, updated] in
            guard let self = self else { return }
            do {
                // 使用同步 write 方法，因为已经在后台线程
                try await self.database.asyncWrite { db in
                    try self.saveMessage(updated, db: db)
                }
            } catch {
                print("❌ [EmailStore] 后台更新邮件失败: \(error)")
            }
        }
    }
    
    /// 获取文件夹的邮件列表（分页）
    func getMessages(for folderId: UUID, limit: Int = 50, offset: Int = 0) -> [EmailMessage] {
        let allMessages = messages[folderId] ?? []
        let sorted = allMessages.sorted { $0.date > $1.date }
        let endIndex = min(offset + limit, sorted.count)
        return Array(sorted[offset..<endIndex])
    }
    
    /// 获取邮件总数（侧栏数字）
    /// 优先使用来自数据库的数量缓存，避免只加载部分邮件时显示不全
    func getMessageCount(for folderId: UUID) -> Int {
        let cached = FolderMessageCountCache.shared.getCount(for: folderId)
        if cached > 0 { return cached }
        if let count = messages[folderId]?.count, count > 0 {
            FolderMessageCountCache.shared.updateCount(for: folderId, count: count)
            return count
        }
        return 0
    }
    
    /// 获取某个账号的所有邮件总数（去重后，与「所有邮件」视图显示逻辑一致）
    func getTotalMessageCount(for accountId: UUID) -> Int {
        // 按 message_id 去重：同一封邮件可能存在于多个文件夹，只计一次
        // 与 ViewModel 中 updateMessagesForAllFolders 的去重逻辑保持一致
        // 有 message_id 时按 message_id 分组，否则按 subject|from_email|date 分组
        let count = try? database.read { db -> Int in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM (
                    SELECT 1 FROM email_messages 
                    WHERE account_id = ? 
                    AND is_draft = 0 
                    AND is_spam = 0 
                    AND is_deleted = 0
                    GROUP BY CASE 
                        WHEN message_id IS NOT NULL AND TRIM(message_id) != '' THEN TRIM(message_id)
                        ELSE COALESCE(subject, '') || '|' || COALESCE(from_email, '') || '|' || CAST(date AS TEXT)
                    END
                )
            """, arguments: [accountId.uuidString]) ?? 0
        }
        
        if let count = count, count > 0 {
            return count
        }
        
        // 降级方案：如果数据库查询失败或为0，尝试从内存缓存累加（并排除重复）
        guard let accountFolders = folders[accountId] else { return 0 }
        var seenMessageIds = Set<String>()
        var fallbackCount = 0
        for folder in accountFolders {
            if folder.type == .drafts || folder.type == .spam || folder.type == .trash {
                continue
            }
            let folderMessages = messages[folder.id] ?? []
            for msg in folderMessages where !msg.isDeleted && !msg.isSpam {
                let key = msg.messageId.flatMap { $0.isEmpty ? nil : $0 } ?? "\(msg.subject)|\(msg.from.email)|\(msg.date.timeIntervalSince1970)"
                if seenMessageIds.insert(key).inserted {
                    fallbackCount += 1
                }
            }
        }
        return fallbackCount
    }
    
    /// 获取所有邮件（用于 AI 摘要汇总）
    func getAllMessages(limit: Int = 100) -> [EmailMessage] {
        var allMessages: [EmailMessage] = []
        for (_, folderMessages) in messages {
            allMessages.append(contentsOf: folderMessages)
        }
        // 按日期排序，取最新的
        return Array(allMessages.sorted { $0.date > $1.date }.prefix(limit))
    }
    
    // MARK: - 深度去重和清理
    
    /// 清理数据库中的重复邮件
    /// - Parameters:
    ///   - accountId: 账号ID（可选，如果为nil则清理所有账号）
    ///   - folderId: 文件夹ID（可选，如果为nil则清理所有文件夹）
    /// - Returns: 删除的重复邮件数量
    func cleanupDuplicateMessages(accountId: UUID? = nil, folderId: UUID? = nil) async throws -> Int {
        let deletedCount = try await EmailDeduplicationService.shared.cleanupDuplicateMessages(
            accountId: accountId,
            folderId: folderId
        )
        
        // 清理后重新加载受影响的文件夹
        if let folderId = folderId {
            await loadMessages(for: folderId, forceLoadMore: false)
        } else if let accountId = accountId {
            // 重新加载该账号的所有文件夹
            let accountFolders = folders[accountId] ?? []
            for folder in accountFolders {
                await loadMessages(for: folder.id, forceLoadMore: false)
            }
        } else {
            // 重新加载所有文件夹
            let allFolders = folders.values.flatMap { $0 }
            for folder in allFolders {
                await loadMessages(for: folder.id, forceLoadMore: false)
            }
        }
        
        // 从数据库刷新各文件夹数量缓存，确保侧栏数字正确
        await refreshFolderCountsFromDatabase()
        notifyChange()
        return deletedCount
    }
    
    // MARK: - Draft Management
    
    /// 保存草稿
    /// - Parameters:
    ///   - draftId: 草稿ID（用于标识草稿，可以是原邮件的ID或新生成的UUID）
    ///   - accountId: 账号ID
    ///   - to: 收件人
    ///   - cc: 抄送
    ///   - bcc: 密送
    ///   - subject: 主题
    ///   - body: 正文
    ///   - htmlBody: HTML正文（可选）
    ///   - attachments: 附件
    ///   - originalMessageId: 原邮件ID（如果是回复/转发）
    func saveDraft(
        draftId: UUID,
        accountId: UUID,
        to: [EmailContact],
        cc: [EmailContact] = [],
        bcc: [EmailContact] = [],
        subject: String,
        body: String,
        htmlBody: String? = nil,
        attachments: [EmailAttachment] = [],
        originalMessageId: UUID? = nil
    ) async throws {
        // 创建草稿邮件对象
        let draftMessage = EmailMessage(
            id: draftId,
            accountId: accountId,
            folderId: nil, // 草稿没有文件夹
            subject: subject,
            from: EmailContact(email: getAccount(id: accountId)?.emailAddress ?? ""),
            to: to,
            cc: cc,
            bcc: bcc,
            textBody: body,
            htmlBody: htmlBody,
            preview: String(body.prefix(200)),
            date: Date(),
            isDraft: true,
            attachments: attachments
        )
        
        // 保存到数据库
        try await database.asyncWrite { db in
            try self.saveMessage(draftMessage, db: db)
        }
        
        print("✅ [EmailStore] 草稿已保存: \(subject), draftId=\(draftId)")
    }
    
    /// 加载草稿
    /// - Parameter draftId: 草稿ID
    /// - Returns: 草稿邮件，如果不存在则返回 nil
    func loadDraft(draftId: UUID) async -> EmailMessage? {
        do {
            return try await database.asyncRead { db -> EmailMessage? in
                let row = try Row.fetchOne(db, sql: """
                    SELECT * FROM email_messages
                    WHERE id = ? AND is_draft = 1
                """, arguments: [draftId.uuidString])
                
                guard let row = row else { return nil }
                return try self.parseMessage(from: row, db: db)
            }
        } catch {
            print("❌ [EmailStore] 加载草稿失败: \(error)")
            return nil
        }
    }
    
    /// 删除草稿
    /// - Parameter draftId: 草稿ID
    func deleteDraft(draftId: UUID) async throws {
        try await database.asyncWrite { db in
            try db.execute(sql: """
                DELETE FROM email_messages
                WHERE id = ? AND is_draft = 1
            """, arguments: [draftId.uuidString])
        }
        print("✅ [EmailStore] 草稿已删除: draftId=\(draftId)")
    }
    
    /// 获取账号的所有草稿
    /// - Parameter accountId: 账号ID
    /// - Returns: 草稿列表
    func getDrafts(for accountId: UUID) async -> [EmailMessage] {
        do {
            return try await database.asyncRead { db -> [EmailMessage] in
                var drafts: [EmailMessage] = []
                let rows = try Row.fetchAll(db, sql: """
                    SELECT * FROM email_messages
                    WHERE account_id = ? AND is_draft = 1
                    ORDER BY updated_at DESC
                """, arguments: [accountId.uuidString])
                
                for row in rows {
                    let draft = try self.parseMessage(from: row, db: db)
                    drafts.append(draft)
                }
                return drafts
            }
        } catch {
            print("❌ [EmailStore] 获取草稿列表失败: \(error)")
            return []
        }
    }
    
    // MARK: - Database Operations
    
    private func saveAccount(_ account: EmailAccount, db: Database) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO email_accounts (
                id, email_address, display_name, service_type,
                imap_host, imap_port, imap_encryption,
                smtp_host, smtp_port, smtp_encryption,
                is_enabled, is_default, last_sync_date, connection_status,
                password_keychain_identifier, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            account.id.uuidString,
            account.emailAddress,
            account.displayName,
            account.serviceType.rawValue,
            account.imapHost,
            account.imapPort,
            account.imapEncryption.rawValue,
            account.smtpHost,
            account.smtpPort,
            account.smtpEncryption.rawValue,
            account.isEnabled ? 1 : 0,
            account.isDefault ? 1 : 0,
            account.lastSyncDate?.timeIntervalSince1970,
            account.connectionStatus.rawValue,
            account.passwordKeychainIdentifier,
            account.createdAt.timeIntervalSince1970,
            account.updatedAt.timeIntervalSince1970
        ])
    }
    
    private func saveFolder(_ folder: EmailFolder, db: Database) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO email_folders (
                id, account_id, name, type, path,
                unread_count, total_count, last_sync_date
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            folder.id.uuidString,
            folder.accountId.uuidString,
            folder.name,
            folder.type.rawValue,
            folder.path,
            folder.unreadCount,
            folder.totalCount,
            folder.lastSyncDate?.timeIntervalSince1970
        ])
    }
    
    /// 合并数据库中已缓存的正文，避免空正文覆盖
    nonisolated private func mergeCachedBodyIfNeeded(_ message: EmailMessage, messageId: UUID, db: Database) throws -> EmailMessage {
        let hasTextBody = message.textBody?.isEmpty == false
        let hasHtmlBody = message.htmlBody?.isEmpty == false
        let hasBody = message.isBodyLoaded || hasTextBody || hasHtmlBody
        if hasBody {
            return message
        }
        
        if let row = try Row.fetchOne(db, sql: """
            SELECT text_body, html_body, is_body_loaded, body_cached_at, contains_remote_resources, preview
            FROM email_messages WHERE id = ?
        """, arguments: [messageId.uuidString]) {
            var updated = message
            let cachedTextBody = row["text_body"] as? String
            let cachedHtmlBody = row["html_body"] as? String
            let cachedIsBodyLoaded = (row["is_body_loaded"] as? Int64 ?? 0) != 0
            let cachedBodyCachedAt = (row["body_cached_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            let cachedPreview = row["preview"] as? String
            let cachedContainsRemoteResources = (row["contains_remote_resources"] as? Int64 ?? 0) != 0
            
            if message.textBody?.isEmpty != false, let cachedTextBody, !cachedTextBody.isEmpty {
                updated.textBody = cachedTextBody
            }
            if message.htmlBody?.isEmpty != false, let cachedHtmlBody, !cachedHtmlBody.isEmpty {
                updated.htmlBody = cachedHtmlBody
            }
            if !updated.isBodyLoaded, cachedIsBodyLoaded || (updated.textBody?.isEmpty == false) || (updated.htmlBody?.isEmpty == false) {
                updated.isBodyLoaded = true
            }
            if updated.bodyCachedAt == nil {
                updated.bodyCachedAt = cachedBodyCachedAt
            }
            if updated.preview.isEmpty, let cachedPreview, !cachedPreview.isEmpty {
                updated.preview = cachedPreview
            }
            if !updated.containsRemoteResources, cachedContainsRemoteResources {
                updated.containsRemoteResources = true
            }
            return updated
        }
        
        return message
    }
    
    /// 更新已有邮件（使用指定的ID）
    nonisolated private func updateMessageInDatabase(_ message: EmailMessage, existingId: UUID, db: Database) throws {
        let message = try mergeCachedBodyIfNeeded(message, messageId: existingId, db: db)
        // 序列化联系人列表
        let toContacts = try? JSONEncoder().encode(message.to)
        let ccContacts = try? JSONEncoder().encode(message.cc)
        let bccContacts = try? JSONEncoder().encode(message.bcc)
        let replyToContacts = try? JSONEncoder().encode(message.replyTo)
        let tags = try? JSONEncoder().encode(message.tags)
        let aiTags = try? JSONEncoder().encode(message.aiTags)
        
        // 验证外键
        let accountIdString = message.accountId.uuidString
        let accountExists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM email_accounts WHERE id = ?", arguments: [accountIdString]) ?? 0
        if accountExists == 0 {
            print("⚠️ [EmailStore] 跳过更新邮件: account_id 不存在于数据库中 (\(accountIdString))")
            return
        }
        
        var validFolderId: String? = nil
        if let folderId = message.folderId {
            let folderIdString = folderId.uuidString
            let folderExists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM email_folders WHERE id = ?", arguments: [folderIdString]) ?? 0
            if folderExists > 0 {
                validFolderId = folderIdString
            }
        }
        
        // 更新邮件（使用已有ID）
        try db.execute(sql: """
            UPDATE email_messages SET
                account_id = ?, folder_id = ?, uid = ?, message_id = ?, thread_id = ?,
                subject = ?, from_name = ?, from_email = ?, to_contacts = ?, cc_contacts = ?,
                bcc_contacts = ?, reply_to_contacts = ?, text_body = ?, html_body = ?, preview = ?,
                date = ?, received_date = ?, is_read = ?, is_starred = ?, is_important = ?,
                is_no_reply = ?, has_attachments = ?, is_spam = ?, is_deleted = ?, contains_remote_resources = ?,
                tags = ?, ai_tags = ?, ai_summary = ?,
                ai_priority = ?, synced_at = ?, updated_at = ?, is_body_loaded = ?, body_cached_at = ?, has_been_replied = ?, is_draft = ?
            WHERE id = ?
        """, arguments: [
            message.accountId.uuidString,
            validFolderId,
            message.uid.map { Int64($0) },
            message.messageId,
            message.threadId,
            message.subject,
            message.from.name,
            message.from.email,
            toContacts,
            ccContacts,
            bccContacts,
            replyToContacts,
            message.textBody,
            message.htmlBody,
            message.preview,
            message.date.timeIntervalSince1970,
            message.receivedDate?.timeIntervalSince1970,
            message.isRead ? 1 : 0,
            message.isStarred ? 1 : 0,
            message.isImportant ? 1 : 0,
            message.isNoReply ? 1 : 0,
            message.hasAttachments ? 1 : 0,
            message.isSpam ? 1 : 0,
            message.isDeleted ? 1 : 0,
            message.containsRemoteResources ? 1 : 0,
            tags,
            aiTags,
            message.aiSummary,
            message.aiPriority?.rawValue,
            message.syncedAt.timeIntervalSince1970,
            Date().timeIntervalSince1970,
            message.isBodyLoaded ? 1 : 0,
            message.bodyCachedAt?.timeIntervalSince1970,
            message.hasBeenReplied ? 1 : 0,
            message.isDraft ? 1 : 0,
            existingId.uuidString
        ])
        
        // 更新附件
        // 先删除旧附件
        try db.execute(sql: "DELETE FROM email_attachments WHERE message_id = ?", arguments: [existingId.uuidString])
        // 保存新附件
        for attachment in message.attachments {
            try saveAttachment(attachment, messageId: existingId, db: db)
        }
    }
    
    nonisolated private func saveMessage(_ message: EmailMessage, db: Database) throws {
        let message = try mergeCachedBodyIfNeeded(message, messageId: message.id, db: db)
        // 序列化联系人列表
        let toContacts = try? JSONEncoder().encode(message.to)
        let ccContacts = try? JSONEncoder().encode(message.cc)
        let bccContacts = try? JSONEncoder().encode(message.bcc)
        let replyToContacts = try? JSONEncoder().encode(message.replyTo)
        let tags = try? JSONEncoder().encode(message.tags)
        let aiTags = try? JSONEncoder().encode(message.aiTags)
        
        // 验证外键：检查 account_id 是否存在
        let accountIdString = message.accountId.uuidString
        let accountExists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM email_accounts WHERE id = ?", arguments: [accountIdString]) ?? 0
        if accountExists == 0 {
            print("⚠️ [EmailStore] 跳过保存邮件: account_id 不存在于数据库中 (\(accountIdString)), subject=\(message.subject)")
            // 不抛出错误，直接跳过（账号可能已被删除）
            return
        }
        
        // 验证外键：检查 folder_id 是否存在（如果有的话）
        // 注意：folder_id 的外键约束是 ON DELETE SET NULL，所以如果文件夹不存在，我们设为 NULL
        var validFolderId: String? = nil
        if let folderId = message.folderId {
            let folderIdString = folderId.uuidString
            let folderExists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM email_folders WHERE id = ?", arguments: [folderIdString]) ?? 0
            if folderExists > 0 {
                validFolderId = folderIdString
            } else {
                print("⚠️ [EmailStore] folder_id 不存在于数据库中 (\(folderIdString))，将设为 NULL, subject=\(message.subject)")
            }
        }
        
        try db.execute(sql: """
            INSERT OR REPLACE INTO email_messages (
                id, account_id, folder_id, uid, message_id, thread_id,
                subject, from_name, from_email, to_contacts, cc_contacts,
                bcc_contacts, reply_to_contacts, text_body, html_body, preview,
                date, received_date, is_read, is_starred, is_important,
                is_no_reply, has_attachments, is_spam, is_deleted, contains_remote_resources,
                tags, ai_tags, ai_summary,
                ai_priority, synced_at, updated_at, is_body_loaded, body_cached_at, has_been_replied, is_draft
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            message.id.uuidString,
            message.accountId.uuidString,
            validFolderId,
            message.uid.map { Int64($0) },
            message.messageId,
            message.threadId,
            message.subject,
            message.from.name,
            message.from.email,
            toContacts,
            ccContacts,
            bccContacts,
            replyToContacts,
            message.textBody,
            message.htmlBody,
            message.preview,
            message.date.timeIntervalSince1970,
            message.receivedDate?.timeIntervalSince1970,
            message.isRead ? 1 : 0,
            message.isStarred ? 1 : 0,
            message.isImportant ? 1 : 0,
            message.isNoReply ? 1 : 0,
            message.hasAttachments ? 1 : 0,
            message.isSpam ? 1 : 0,
            message.isDeleted ? 1 : 0,
            message.containsRemoteResources ? 1 : 0,
            tags,
            aiTags,
            message.aiSummary,
            message.aiPriority?.rawValue,
            message.syncedAt.timeIntervalSince1970,
            message.updatedAt.timeIntervalSince1970,
            message.isBodyLoaded ? 1 : 0,
            message.bodyCachedAt?.timeIntervalSince1970,
            message.hasBeenReplied ? 1 : 0,
            message.isDraft ? 1 : 0
        ])
        
        // 保存附件
        for attachment in message.attachments {
            try saveAttachment(attachment, messageId: message.id, db: db)
        }
    }
    
    nonisolated private func saveAttachment(_ attachment: EmailAttachment, messageId: UUID, db: Database) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO email_attachments (
                id, message_id, filename, mime_type, size,
                content_id, is_inline, local_path
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            attachment.id.uuidString,
            messageId.uuidString,
            attachment.filename,
            attachment.mimeType,
            attachment.size,
            attachment.contentId,
            attachment.isInline ? 1 : 0,
            attachment.localPath
        ])
    }
    
    private func loadAccounts() async {
        do {
            let loaded = try await database.asyncRead { db -> [EmailAccount] in
                var accounts: [EmailAccount] = []
                let rows = try Row.fetchAll(db, sql: "SELECT * FROM email_accounts ORDER BY is_default DESC, created_at DESC")
                
                for row in rows {
                    let account = try self.parseAccount(from: row)
                    accounts.append(account)
                }
                return accounts
            }
            
            accounts = loaded
        } catch {
            print("❌ [EmailStore] 加载账号失败: \(error)")
        }
    }
    
    private func loadFolders() async {
        do {
            let loaded = try await database.asyncRead { db -> [UUID: [EmailFolder]] in
                var foldersDict: [UUID: [EmailFolder]] = [:]
                let rows = try Row.fetchAll(db, sql: "SELECT * FROM email_folders ORDER BY type, name")
                
                for row in rows {
                    let folder = try self.parseFolder(from: row)
                    let accountId = folder.accountId
                    if foldersDict[accountId] == nil {
                        foldersDict[accountId] = []
                    }
                    foldersDict[accountId]?.append(folder)
                }

                for (accountId, folderList) in foldersDict {
                    foldersDict[accountId] = self.deduplicatedFolders(folderList)
                }
                return foldersDict
            }
            
            folders = loaded
            
            // 从数据库刷新各文件夹邮件数量，保证侧栏数字正确
            await refreshFolderCountsFromDatabase()
        } catch {
            print("❌ [EmailStore] 加载文件夹失败: \(error)")
        }
    }
    
    /// 从数据库刷新所有文件夹的邮件数量到缓存（启动或切换账号后数字准确）
    private func refreshFolderCountsFromDatabase() async {
        let folderIds = folders.values.flatMap { $0 }.map(\.id)
        guard !folderIds.isEmpty else { return }
        do {
            let counts = try await database.asyncRead { db -> [UUID: Int] in
                var result: [UUID: Int] = [:]
                let rows = try Row.fetchAll(db, sql: """
                    SELECT folder_id, COUNT(*) AS cnt FROM email_messages
                    WHERE folder_id IS NOT NULL 
                    AND is_deleted = 0 
                    AND is_spam = 0
                    GROUP BY folder_id
                """)
                for row in rows {
                    if let idString = row["folder_id"] as? String, let id = UUID(uuidString: idString) {
                        result[id] = row["cnt"] as? Int ?? 0
                    }
                }
                return result
            }
            FolderMessageCountCache.shared.updateCounts(counts)
            print("📊 [EmailStore] 已从数据库刷新 \(counts.count) 个文件夹的邮件数量")
        } catch {
            print("⚠️ [EmailStore] 刷新文件夹数量失败: \(error)")
        }
    }
    
    nonisolated private func deduplicatedFolders(_ folders: [EmailFolder]) -> [EmailFolder] {
        var seen = Set<String>()
        var result: [EmailFolder] = []
        for folder in folders {
            let key = folder.path.lowercased()
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            result.append(folder)
        }
        return result
    }
    
    /// 从数据库加载文件夹的邮件缓存（超高速版本）
    /// - Parameters:
    ///   - folderId: 文件夹ID
    ///   - forceLoadMore: 如果为 true，即使已有缓存也加载更多邮件（用于"所有邮件"视图）
    func loadMessages(for folderId: UUID, forceLoadMore: Bool = false) async {
        // 如果已经有缓存且不强制加载更多，跳过
        if !forceLoadMore, let existing = messages[folderId], !existing.isEmpty {
            print("📦 [EmailStore] 文件夹 \(folderId) 已有缓存 \(existing.count) 封邮件，跳过加载")
            return
        }
        
        print("📦 [EmailStore] 开始从数据库加载文件夹 \(folderId) 的邮件...")
        let loadStart = Date()
        
        do {
            let currentCount = messages[folderId]?.count ?? 0
            let offset = forceLoadMore ? currentCount : 0
            let limit = forceLoadMore ? 500 : 100 // 加载更多时增加到500封，确保能加载足够多的邮件
            
            // 分批加载：先加载一批立即显示，同时查询总数以判断是否还有更多
            let (firstBatch, totalCount) = try await database.asyncRead { db -> ([EmailMessage], Int) in
                // 先查询总数（过滤掉已删除和垃圾邮件，除非是在对应的文件夹中）
                // 先获取文件夹类型
                let folderRow = try Row.fetchOne(db, sql: "SELECT type FROM email_folders WHERE id = ?", arguments: [folderId.uuidString])
                let folderType = folderRow?["type"] as? String
                
                var countSql = "SELECT COUNT(*) FROM email_messages WHERE folder_id = ?"
                if folderType != "trash" && folderType != "spam" {
                    countSql += " AND is_deleted = 0 AND is_spam = 0"
                }
                
                let totalCount = try Int.fetchOne(db, sql: countSql, arguments: [folderId.uuidString]) ?? 0
                
                // 再加载一批
                var messages: [EmailMessage] = []
                var fetchSql = "SELECT * FROM email_messages WHERE folder_id = ?"
                if folderType != "trash" && folderType != "spam" {
                    fetchSql += " AND is_deleted = 0 AND is_spam = 0"
                }
                fetchSql += " ORDER BY date DESC LIMIT ? OFFSET ?"
                
                let rows = try Row.fetchAll(db, sql: fetchSql, arguments: [folderId.uuidString, limit, offset])
                
                for row in rows {
                    let message = try self.parseMessage(from: row, db: db)
                    messages.append(message)
                }
                return (messages, totalCount)
            }
            
            let loadElapsed = Date().timeIntervalSince(loadStart)
            let hasMoreInDatabase = (offset + firstBatch.count) < totalCount
            print("📦 [EmailStore] 加载完成: \(firstBatch.count) 封邮件，数据库总数: \(totalCount)，已加载: \(offset + firstBatch.count)，还有更多: \(hasMoreInDatabase)，耗时: \(String(format: "%.3f", loadElapsed * 1000))ms")
            
            // 用数据库真实总数更新数量缓存，保证侧栏数字正确
            await MainActor.run {
                FolderMessageCountCache.shared.updateCount(for: folderId, count: totalCount)
            }
            
            // 立即更新UI
            await MainActor.run {
                if forceLoadMore {
                    // 如果是强制加载更多，追加到现有列表
                    var existing = messages[folderId] ?? []
                    existing.append(contentsOf: firstBatch)
                    messages[folderId] = existing
                } else {
                    // 否则替换现有列表
                    messages[folderId] = firstBatch
                }
                notifyChange()
            }
            
            // 后台加载剩余邮件（只在非强制加载模式下，且数据库中有更多邮件时）
            if !forceLoadMore && firstBatch.count >= 100 && hasMoreInDatabase {
                Task.detached(priority: .background) { [weak self] in
                    guard let self = self else { return }
                    
                    do {
                        let remainingMessages = try await self.database.asyncRead { db -> [EmailMessage] in
                            // 获取文件夹类型
                            let folderRow = try Row.fetchOne(db, sql: "SELECT type FROM email_folders WHERE id = ?", arguments: [folderId.uuidString])
                            let folderType = folderRow?["type"] as? String
                            
                            var fetchSql = "SELECT * FROM email_messages WHERE folder_id = ?"
                            if folderType != "trash" && folderType != "spam" {
                                fetchSql += " AND is_deleted = 0 AND is_spam = 0"
                            }
                            fetchSql += " ORDER BY date DESC LIMIT 900 OFFSET 100"
                            
                            var messages: [EmailMessage] = []
                            let rows = try Row.fetchAll(db, sql: fetchSql, arguments: [folderId.uuidString])
                            
                            for row in rows {
                                let message = try self.parseMessage(from: row, db: db)
                                messages.append(message)
                            }
                            return messages
                        }
                        
                        if !remainingMessages.isEmpty {
                            await MainActor.run {
                                var combined = self.messages[folderId] ?? []
                                combined.append(contentsOf: remainingMessages)
                                self.messages[folderId] = combined
                                self.notifyChange()
                                print("📦 [EmailStore] 后台加载完成，新增: \(remainingMessages.count) 封邮件")
                            }
                        }
                    } catch {
                        print("❌ [EmailStore] 后台加载剩余邮件失败: \(error)")
                    }
                }
            }
        } catch {
            print("❌ [EmailStore] 加载邮件失败: \(error)")
        }
    }
    
    // MARK: - Parsing
    
    nonisolated private func parseAccount(from row: Row) throws -> EmailAccount {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString) else {
            throw EmailDatabaseError.invalidData
        }
        
        // 端口字段在 SQLite 中可能以 Int / Int64 / String 等不同底层类型存储，
        // 直接使用 `as? Int` 很容易失败并导致总是回退到默认值（993 / 587）。
        // 这里使用统一的解析函数，确保能正确读回已保存的端口。
        let imapPort = parsePort(from: row, column: "imap_port", defaultPort: 993)
        let smtpPort = parsePort(from: row, column: "smtp_port", defaultPort: 587)
        
        return EmailAccount(
            id: id,
            emailAddress: row["email_address"] as? String ?? "",
            displayName: row["display_name"] as? String ?? "",
            serviceType: EmailServiceType(rawValue: row["service_type"] as? String ?? "custom") ?? .custom,
            imapHost: row["imap_host"] as? String ?? "",
            imapPort: imapPort,
            imapEncryption: EmailEncryption(rawValue: row["imap_encryption"] as? String ?? "ssl") ?? .ssl,
            smtpHost: row["smtp_host"] as? String ?? "",
            smtpPort: smtpPort,
            smtpEncryption: EmailEncryption(rawValue: row["smtp_encryption"] as? String ?? "startTLS") ?? .startTLS,
            isEnabled: (row["is_enabled"] as? Int ?? 1) == 1,
            isDefault: (row["is_default"] as? Int ?? 0) == 1,
            lastSyncDate: (row["last_sync_date"] as? Double).map { Date(timeIntervalSince1970: $0) },
            connectionStatus: ConnectionStatus(rawValue: row["connection_status"] as? String ?? "disconnected") ?? .disconnected,
            passwordKeychainIdentifier: row["password_keychain_identifier"] as? String,
            createdAt: Date(timeIntervalSince1970: row["created_at"] as? Double ?? 0),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"] as? Double ?? 0),
            applyServiceDefaults: false
        )
    }

    /// 稳健解析端口字段，避免因为底层类型差异导致总是回落到默认值
    nonisolated private func parsePort(from row: Row, column: String, defaultPort: Int) -> Int {
        // 1. 直接按 Int 读取（GRDB 通常会帮忙做转换）
        if let intValue = row[column] as? Int {
            return intValue
        }
        // 2. 尝试 Int64
        if let int64Value = row[column] as? Int64 {
            return Int(int64Value)
        }
        // 3. 尝试 String -> Int
        if let stringValue = row[column] as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let intValue = Int(trimmed), intValue > 0 && intValue < 65536 {
                return intValue
            }
        }
        // 4. 兜底：使用默认端口
        return defaultPort
    }
    
    nonisolated private func parseFolder(from row: Row) throws -> EmailFolder {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString),
              let accountIdString = row["account_id"] as? String,
              let accountId = UUID(uuidString: accountIdString) else {
            throw EmailDatabaseError.invalidData
        }
        
        return EmailFolder(
            id: id,
            accountId: accountId,
            name: row["name"] as? String ?? "",
            type: EmailFolderType(rawValue: row["type"] as? String ?? "custom") ?? .custom,
            path: row["path"] as? String ?? "",
            unreadCount: row["unread_count"] as? Int ?? 0,
            totalCount: row["total_count"] as? Int ?? 0,
            lastSyncDate: (row["last_sync_date"] as? Double).map { Date(timeIntervalSince1970: $0) }
        )
    }
    
    nonisolated private func parseMessage(from row: Row, db: Database) throws -> EmailMessage {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString),
              let accountIdString = row["account_id"] as? String,
              let accountId = UUID(uuidString: accountIdString) else {
            throw EmailDatabaseError.invalidData
        }
        
        let folderIdString = row["folder_id"] as? String
        let folderId = folderIdString.flatMap { UUID(uuidString: $0) }
        
        // 解析联系人
        let from = EmailContact(
            name: row["from_name"] as? String,
            email: row["from_email"] as? String ?? ""
        )
        
        let to = (try? JSONDecoder().decode([EmailContact].self, from: row["to_contacts"] as? Data ?? Data())) ?? []
        let cc = (try? JSONDecoder().decode([EmailContact].self, from: row["cc_contacts"] as? Data ?? Data())) ?? []
        let bcc = (try? JSONDecoder().decode([EmailContact].self, from: row["bcc_contacts"] as? Data ?? Data())) ?? []
        let replyTo = (try? JSONDecoder().decode([EmailContact].self, from: row["reply_to_contacts"] as? Data ?? Data())) ?? []
        
        // 解析标签
        let tags = (try? JSONDecoder().decode([String].self, from: row["tags"] as? Data ?? Data())) ?? []
        let aiTags = (try? JSONDecoder().decode([String].self, from: row["ai_tags"] as? Data ?? Data())) ?? []
        
        // 加载附件
        let attachments = try loadAttachments(messageId: id, db: db)
        
        // 检查数据库中是否有正文内容，自动设置 isBodyLoaded
        let textBody = row["text_body"] as? String
        let htmlBody = row["html_body"] as? String
        let hasTextBody = textBody?.isEmpty == false
        let hasHtmlBody = htmlBody?.isEmpty == false
        let dbIsBodyLoaded = (row["is_body_loaded"] as? Int ?? 0) == 1
        // 如果数据库标记为已加载，或者有正文内容，则标记为已加载
        let isBodyLoaded = dbIsBodyLoaded || hasTextBody || hasHtmlBody
        
        // 读取正文缓存时间（如果字段存在）
        let bodyCachedAt = (row["body_cached_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
        
        return EmailMessage(
            id: id,
            accountId: accountId,
            folderId: folderId,
            uid: (row["uid"] as? Int64).map { UInt32($0) },
            messageId: row["message_id"] as? String,
            threadId: row["thread_id"] as? String,
            subject: row["subject"] as? String ?? "",
            from: from,
            to: to,
            cc: cc,
            bcc: bcc,
            replyTo: replyTo,
            textBody: textBody,
            htmlBody: htmlBody,
            preview: row["preview"] as? String ?? "",
            date: Date(timeIntervalSince1970: row["date"] as? Double ?? 0),
            receivedDate: (row["received_date"] as? Double).map { Date(timeIntervalSince1970: $0) },
            isRead: (row["is_read"] as? Int ?? 0) == 1,
            isStarred: (row["is_starred"] as? Int ?? 0) == 1,
            isImportant: (row["is_important"] as? Int ?? 0) == 1,
            isNoReply: (row["is_no_reply"] as? Int ?? 0) == 1,
            hasAttachments: (row["has_attachments"] as? Int ?? 0) == 1,
            isSpam: (row["is_spam"] as? Int ?? 0) == 1,
            isDeleted: (row["is_deleted"] as? Int ?? 0) == 1,
            containsRemoteResources: (row["contains_remote_resources"] as? Int ?? 0) == 1,
            hasBeenReplied: (row["has_been_replied"] as? Int ?? 0) == 1,
            isDraft: (row["is_draft"] as? Int ?? 0) == 1,
            tags: tags,
            aiTags: aiTags,
            aiSummary: row["ai_summary"] as? String,
            aiPriority: (row["ai_priority"] as? String).flatMap { EmailPriority(rawValue: $0) },
            attachments: attachments,
            syncedAt: Date(timeIntervalSince1970: row["synced_at"] as? Double ?? 0),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"] as? Double ?? 0),
            isBodyLoaded: isBodyLoaded,
            bodyCachedAt: bodyCachedAt
        )
    }
    
    nonisolated private func loadAttachments(messageId: UUID, db: Database) throws -> [EmailAttachment] {
        var attachments: [EmailAttachment] = []
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM email_attachments WHERE message_id = ?", arguments: [messageId.uuidString])
        
        for row in rows {
            guard let idString = row["id"] as? String,
                  let id = UUID(uuidString: idString) else {
                continue
            }
            
            let attachment = EmailAttachment(
                id: id,
                filename: row["filename"] as? String ?? "",
                mimeType: row["mime_type"] as? String ?? "",
                size: row["size"] as? Int64 ?? 0,
                contentId: row["content_id"] as? String,
                isInline: (row["is_inline"] as? Int ?? 0) == 1,
                localPath: row["local_path"] as? String
            )
            attachments.append(attachment)
        }
        
        return attachments
    }
}

// MARK: - 文件夹邮件数量缓存管理器

/// 文件夹邮件数量缓存管理器
/// 用于在应用启动时快速显示文件夹邮件数量
class FolderMessageCountCache {
    static let shared = FolderMessageCountCache()
    
    private let cacheKey = "folder_message_count_cache"
    private let defaults = UserDefaults.standard
    private var cache: [String: Int] = [:]  // folderId -> count
    
    private init() {
        loadCache()
    }
    
    /// 从 UserDefaults 加载缓存
    private func loadCache() {
        if let data = defaults.dictionary(forKey: cacheKey) as? [String: Int] {
            cache = data
            print("📦 [FolderMessageCountCache] 已加载 \(cache.count) 个文件夹的邮件数量缓存")
        }
    }
    
    /// 保存缓存到 UserDefaults
    private func saveCache() {
        defaults.set(cache, forKey: cacheKey)
    }
    
    /// 获取文件夹的邮件数量
    func getCount(for folderId: UUID) -> Int {
        return cache[folderId.uuidString] ?? 0
    }
    
    /// 更新文件夹的邮件数量
    func updateCount(for folderId: UUID, count: Int) {
        let key = folderId.uuidString
        if cache[key] != count {
            cache[key] = count
            saveCache()
        }
    }
    
    /// 批量更新文件夹的邮件数量
    func updateCounts(_ counts: [UUID: Int]) {
        var changed = false
        for (folderId, count) in counts {
            let key = folderId.uuidString
            if cache[key] != count {
                cache[key] = count
                changed = true
            }
        }
        if changed {
            saveCache()
        }
    }
    
    /// 清除缓存
    func clearCache() {
        cache.removeAll()
        defaults.removeObject(forKey: cacheKey)
        print("✅ [FolderMessageCountCache] 缓存已清除")
    }
}

