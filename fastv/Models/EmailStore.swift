//
//  EmailStore.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine
import GRDB

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
            await self.loadFolders()
            
            // 预加载邮件缓存（低优先级，后台执行）
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                await self.preloadMessageCache()
            }
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
    func addFolder(_ folder: EmailFolder) async throws {
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
            return
        }
        
        try await database.write { db in
            try self.saveFolder(folder, db: db)
        }
        await loadFolders()
    }
    
    /// 更新文件夹
    func updateFolder(_ folder: EmailFolder) async throws {
        try await database.write { db in
            try self.saveFolder(folder, db: db)
        }
        await loadFolders()
    }
    
    /// 获取账号的文件夹列表
    func getFolders(for accountId: UUID) -> [EmailFolder] {
        return folders[accountId] ?? []
    }
    
    // MARK: - Message Management
    
    /// 添加邮件（批量，增量更新）
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
        self.notifyChange()
        print("✅ [EmailStore] 后台排序完成，通知UI更新")
        
        // 在后台线程异步写入数据库(不阻塞UI)
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            do {
                // 应用规则引擎处理邮件
                let ruleEngine = EmailRuleEngine.shared
                var processedMessages: [EmailMessage] = []
                
                for message in updatedMessages {
                    // 只对新邮件应用规则（避免重复处理）
                    if hasNewMessages {
                        let processed = await ruleEngine.processMessage(message)
                        processedMessages.append(processed)
                    } else {
                        processedMessages.append(message)
                    }
                }
                
                try await self.database.asyncWrite { db in
                    for message in processedMessages {
                        try self.saveMessage(message, db: db)
                    }
                }
                print("✅ [EmailStore] 后台保存了 \(processedMessages.count) 封邮件到数据库（已应用规则引擎）")
            } catch {
                print("❌ [EmailStore] 后台保存邮件失败: \(error)")
            }
        }
    }
    
    /// 更新邮件
    func updateMessage(_ message: EmailMessage) async throws {
        var updated = message
        updated.updatedAt = Date()
        
        // 先更新内存
        if let folderId = message.folderId,
           var folderMessages = messages[folderId],
           let index = folderMessages.firstIndex(where: { $0.id == message.id }) {
            folderMessages[index] = updated
            messages[folderId] = folderMessages
            let hasBody = updated.isBodyLoaded || (updated.textBody?.isEmpty == false) || (updated.htmlBody?.isEmpty == false)
            print("✅ [EmailStore] 更新内存中的邮件: \(updated.subject), folderId=\(folderId), hasBody=\(hasBody), htmlBody长度=\(updated.htmlBody?.count ?? 0)")
            notifyChange()
        } else {
            print("⚠️ [EmailStore] 无法更新邮件（未找到）: \(updated.subject), folderId=\(message.folderId?.uuidString ?? "nil")")
        }
        
        // 后台异步写入数据库
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            do {
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
    
    /// 获取邮件总数
    func getMessageCount(for folderId: UUID) -> Int {
        return messages[folderId]?.count ?? 0
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
    
    private func saveMessage(_ message: EmailMessage, db: Database) throws {
        // 序列化联系人列表
        let toContacts = try? JSONEncoder().encode(message.to)
        let ccContacts = try? JSONEncoder().encode(message.cc)
        let bccContacts = try? JSONEncoder().encode(message.bcc)
        let replyToContacts = try? JSONEncoder().encode(message.replyTo)
        let tags = try? JSONEncoder().encode(message.tags)
        let aiTags = try? JSONEncoder().encode(message.aiTags)
        
        try db.execute(sql: """
            INSERT OR REPLACE INTO email_messages (
                id, account_id, folder_id, uid, message_id, thread_id,
                subject, from_name, from_email, to_contacts, cc_contacts,
                bcc_contacts, reply_to_contacts, text_body, html_body, preview,
                date, received_date, is_read, is_starred, is_important,
                is_no_reply, has_attachments, is_spam, is_deleted, contains_remote_resources,
                tags, ai_tags, ai_summary,
                ai_priority, synced_at, updated_at, is_body_loaded, body_cached_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            message.id.uuidString,
            message.accountId.uuidString,
            message.folderId?.uuidString,
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
            message.bodyCachedAt?.timeIntervalSince1970
        ])
        
        // 保存附件
        for attachment in message.attachments {
            try saveAttachment(attachment, messageId: message.id, db: db)
        }
    }
    
    private func saveAttachment(_ attachment: EmailAttachment, messageId: UUID, db: Database) throws {
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
        } catch {
            print("❌ [EmailStore] 加载文件夹失败: \(error)")
        }
    }
    
    private func deduplicatedFolders(_ folders: [EmailFolder]) -> [EmailFolder] {
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
    func loadMessages(for folderId: UUID) async {
        // 如果已经有缓存，跳过
        if let existing = messages[folderId], !existing.isEmpty {
            print("📦 [EmailStore] 文件夹 \(folderId) 已有缓存 \(existing.count) 封邮件，跳过加载")
            return
        }
        
        print("📦 [EmailStore] 开始从数据库加载文件夹 \(folderId) 的邮件...")
        let loadStart = Date()
        
        do {
            // 分批加载：先加载100封立即显示，再加载剩余的
            let firstBatch = try await database.asyncRead { db -> [EmailMessage] in
                var messages: [EmailMessage] = []
                let rows = try Row.fetchAll(db, sql: """
                    SELECT * FROM email_messages
                    WHERE folder_id = ?
                    ORDER BY date DESC
                    LIMIT 100
                """, arguments: [folderId.uuidString])
                
                for row in rows {
                    let message = try self.parseMessage(from: row, db: db)
                    messages.append(message)
                }
                return messages
            }
            
            let loadElapsed = Date().timeIntervalSince(loadStart)
            print("📦 [EmailStore] 首批加载完成: \(firstBatch.count) 封邮件，耗时: \(String(format: "%.3f", loadElapsed * 1000))ms")
            
            // 立即更新UI
            await MainActor.run {
                messages[folderId] = firstBatch
                notifyChange()
            }
            
            // 后台加载剩余邮件
            if firstBatch.count >= 100 {
                Task.detached(priority: .background) { [weak self] in
                    guard let self = self else { return }
                    
                    do {
                        let remainingMessages = try await self.database.asyncRead { db -> [EmailMessage] in
                            var messages: [EmailMessage] = []
                            let rows = try Row.fetchAll(db, sql: """
                                SELECT * FROM email_messages
                                WHERE folder_id = ?
                                ORDER BY date DESC
                                LIMIT 900 OFFSET 100
                            """, arguments: [folderId.uuidString])
                            
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
    
    private func parseAccount(from row: Row) throws -> EmailAccount {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString) else {
            throw EmailDatabaseError.invalidData
        }
        
        return EmailAccount(
            id: id,
            emailAddress: row["email_address"] as? String ?? "",
            displayName: row["display_name"] as? String ?? "",
            serviceType: EmailServiceType(rawValue: row["service_type"] as? String ?? "custom") ?? .custom,
            imapHost: row["imap_host"] as? String ?? "",
            imapPort: row["imap_port"] as? Int ?? 993,
            imapEncryption: EmailEncryption(rawValue: row["imap_encryption"] as? String ?? "ssl") ?? .ssl,
            smtpHost: row["smtp_host"] as? String ?? "",
            smtpPort: row["smtp_port"] as? Int ?? 587,
            smtpEncryption: EmailEncryption(rawValue: row["smtp_encryption"] as? String ?? "startTLS") ?? .startTLS,
            isEnabled: (row["is_enabled"] as? Int ?? 1) == 1,
            isDefault: (row["is_default"] as? Int ?? 0) == 1,
            lastSyncDate: (row["last_sync_date"] as? Double).map { Date(timeIntervalSince1970: $0) },
            connectionStatus: ConnectionStatus(rawValue: row["connection_status"] as? String ?? "disconnected") ?? .disconnected,
            passwordKeychainIdentifier: row["password_keychain_identifier"] as? String,
            createdAt: Date(timeIntervalSince1970: row["created_at"] as? Double ?? 0),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"] as? Double ?? 0)
        )
    }
    
    private func parseFolder(from row: Row) throws -> EmailFolder {
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
    
    private func parseMessage(from row: Row, db: Database) throws -> EmailMessage {
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
    
    private func loadAttachments(messageId: UUID, db: Database) throws -> [EmailAttachment] {
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

