//
//  EmailDeduplicationService.swift
//  fastv
//
//  Created by rocky on 2025/02/06.
//

import Foundation
import CryptoKit
import GRDB

/// 邮件深度去重服务
class EmailDeduplicationService {
    static let shared = EmailDeduplicationService()
    
    private let database = EmailDatabase.shared
    
    private init() {}
    
    // MARK: - 去重键生成
    
    /// 生成邮件的去重键（多层策略）
    enum DeduplicationKey {
        case messageId(String)  // 最可靠：Message-ID
        case uid(accountId: UUID, folderId: UUID, uid: UInt32)  // IMAP UID
        case contentHash(String)  // 内容哈希
        case fallback(String)  // 降级方案
        
        var value: String {
            switch self {
            case .messageId(let id):
                return "msgid:\(id)"
            case .uid(let accountId, let folderId, let uid):
                return "uid:\(accountId.uuidString):\(folderId.uuidString):\(uid)"
            case .contentHash(let hash):
                return "hash:\(hash)"
            case .fallback(let key):
                return "fallback:\(key)"
            }
        }
    }
    
    /// 为邮件生成去重键
    func generateDeduplicationKey(for message: EmailMessage) -> DeduplicationKey {
        // 策略1: 使用 Message-ID（最可靠）
        if let messageId = message.messageId, !messageId.isEmpty {
            return .messageId(messageId)
        }
        
        // 策略2: 使用 IMAP UID（如果可用）
        if let uid = message.uid,
           let folderId = message.folderId {
            return .uid(accountId: message.accountId, folderId: folderId, uid: uid)
        }
        
        // 策略3: 生成内容哈希
        let contentHash = generateContentHash(for: message)
        return .contentHash(contentHash)
        
        // 策略4: 降级方案（subject + from + date）
        // 注意：这个不会被执行，因为上面已经返回了
    }
    
    /// 生成内容哈希（用于深度去重）
    private func generateContentHash(for message: EmailMessage) -> String {
        // 组合关键字段
        let normalizedSubject = message.subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedFrom = message.from.email.lowercased()
        let dateString = String(format: "%.0f", message.date.timeIntervalSince1970)
        let normalizedPreview = message.preview.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(100)
        
        let combined = "\(normalizedSubject)|\(normalizedFrom)|\(dateString)|\(normalizedPreview)"
        
        // 使用 SHA256 生成哈希
        let data = Data(combined.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - 检查重复
    
    /// 检查邮件是否已存在于数据库中
    func checkDuplicate(_ message: EmailMessage, in database: Database) throws -> EmailMessage? {
        let key = generateDeduplicationKey(for: message)
        
        // 根据不同的键类型查询
        switch key {
        case .messageId(let messageId):
            // 查询 Message-ID
            if let existing = try findMessageByMessageId(messageId, in: database) {
                return existing
            }
            
        case .uid(let accountId, let folderId, let uid):
            // 查询 UID
            if let existing = try findMessageByUID(accountId: accountId, folderId: folderId, uid: uid, in: database) {
                return existing
            }
            
        case .contentHash(_):
            // 查询内容哈希（需要计算其他邮件的哈希进行比较）
            // 这里我们使用更简单的方法：查询相同 subject + from + date 的邮件
            if let existing = try findMessageByContent(message: message, in: database) {
                return existing
            }
            
        case .fallback(_):
            // 降级方案：使用 subject + from + date
            if let existing = try findMessageByContent(message: message, in: database) {
                return existing
            }
        }
        
        return nil
    }
    
    /// 通过 Message-ID 查找邮件
    private func findMessageByMessageId(_ messageId: String, in db: Database) throws -> EmailMessage? {
        let row = try Row.fetchOne(db, sql: """
            SELECT * FROM email_messages
            WHERE message_id = ?
            LIMIT 1
        """, arguments: [messageId])
        
        guard let row = row else { return nil }
        return try parseMessage(from: row, db: db)
    }
    
    /// 通过 UID 查找邮件
    private func findMessageByUID(accountId: UUID, folderId: UUID, uid: UInt32, in db: Database) throws -> EmailMessage? {
        let row = try Row.fetchOne(db, sql: """
            SELECT * FROM email_messages
            WHERE account_id = ? AND folder_id = ? AND uid = ?
            LIMIT 1
        """, arguments: [accountId.uuidString, folderId.uuidString, Int64(uid)])
        
        guard let row = row else { return nil }
        return try parseMessage(from: row, db: db)
    }
    
    /// 通过内容查找邮件（subject + from + date）
    private func findMessageByContent(message: EmailMessage, in db: Database) throws -> EmailMessage? {
        // 使用 subject + from_email + date 进行匹配
        // 允许时间误差在5分钟内（考虑时区差异）
        let timeTolerance: TimeInterval = 300 // 5分钟
        let messageTime = message.date.timeIntervalSince1970
        
        let rows = try Row.fetchAll(db, sql: """
            SELECT * FROM email_messages
            WHERE account_id = ? 
            AND LOWER(TRIM(subject)) = LOWER(TRIM(?))
            AND LOWER(from_email) = LOWER(?)
            AND ABS(date - ?) <= ?
            LIMIT 10
        """, arguments: [
            message.accountId.uuidString,
            message.subject.trimmingCharacters(in: .whitespacesAndNewlines),
            message.from.email.lowercased(),
            messageTime,
            timeTolerance
        ])
        
        // 进一步比较预览文本（如果可用）
        for row in rows {
            let existingMessage = try parseMessage(from: row, db: db)
            let existingPreview = existingMessage.preview.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let newPreview = message.preview.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            
            // 如果预览文本相似度很高（前50个字符相同），认为是重复
            if !existingPreview.isEmpty && !newPreview.isEmpty {
                let existingPrefix = String(existingPreview.prefix(50))
                let newPrefix = String(newPreview.prefix(50))
                if existingPrefix == newPrefix {
                    return existingMessage
                }
            }
        }
        
        return nil
    }
    
    /// 解析邮件（从数据库行）
    private func parseMessage(from row: Row, db: Database) throws -> EmailMessage {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString),
              let accountIdString = row["account_id"] as? String,
              let accountId = UUID(uuidString: accountIdString) else {
            throw EmailDatabaseError.invalidData
        }
        
        let folderIdString = row["folder_id"] as? String
        let folderId = folderIdString.flatMap { UUID(uuidString: $0) }
        
        let from = EmailContact(
            name: row["from_name"] as? String,
            email: row["from_email"] as? String ?? ""
        )
        
        let to = (try? JSONDecoder().decode([EmailContact].self, from: row["to_contacts"] as? Data ?? Data())) ?? []
        let cc = (try? JSONDecoder().decode([EmailContact].self, from: row["cc_contacts"] as? Data ?? Data())) ?? []
        let bcc = (try? JSONDecoder().decode([EmailContact].self, from: row["bcc_contacts"] as? Data ?? Data())) ?? []
        let replyTo = (try? JSONDecoder().decode([EmailContact].self, from: row["reply_to_contacts"] as? Data ?? Data())) ?? []
        
        let tags = (try? JSONDecoder().decode([String].self, from: row["tags"] as? Data ?? Data())) ?? []
        let aiTags = (try? JSONDecoder().decode([String].self, from: row["ai_tags"] as? Data ?? Data())) ?? []
        
        // 加载附件
        let attachments = try loadAttachments(messageId: id, db: db)
        
        let textBody = row["text_body"] as? String
        let htmlBody = row["html_body"] as? String
        let hasTextBody = textBody?.isEmpty == false
        let hasHtmlBody = htmlBody?.isEmpty == false
        let dbIsBodyLoaded = (row["is_body_loaded"] as? Int ?? 0) == 1
        let isBodyLoaded = dbIsBodyLoaded || hasTextBody || hasHtmlBody
        
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
    
    /// 加载附件
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
    
    // MARK: - 清理重复邮件
    
    /// 清理数据库中的重复邮件
    /// - Parameters:
    ///   - accountId: 账号ID（可选，如果为nil则清理所有账号）
    ///   - folderId: 文件夹ID（可选，如果为nil则清理所有文件夹）
    /// - Returns: 删除的重复邮件数量
    func cleanupDuplicateMessages(accountId: UUID? = nil, folderId: UUID? = nil) async throws -> Int {
        return try await database.asyncWrite { [weak self] db -> Int in
            guard let strongSelf = self else { return 0 }
            var deletedCount = 0
            
            // 策略1: 基于 Message-ID 去重
            deletedCount += try strongSelf.cleanupByMessageId(db: db, accountId: accountId, folderId: folderId)
            
            // 策略2: 基于 UID 去重（同一文件夹内）
            deletedCount += try strongSelf.cleanupByUID(db: db, accountId: accountId, folderId: folderId)
            
            // 策略3: 基于内容哈希去重（跨文件夹）
            deletedCount += try strongSelf.cleanupByContentHash(db: db, accountId: accountId)
            
            print("🧹 [EmailDeduplicationService] 清理完成，共删除 \(deletedCount) 封重复邮件")
            return deletedCount
        }
    }
    
    /// 基于 Message-ID 清理重复
    private func cleanupByMessageId(db: Database, accountId: UUID?, folderId: UUID?) throws -> Int {
        var deletedCount = 0
        
        // 构建查询条件
        var conditions: [String] = []
        var arguments: [String] = []
        
        if let accountId = accountId {
            conditions.append("account_id = ?")
            arguments.append(accountId.uuidString)
        }
        
        if let folderId = folderId {
            conditions.append("folder_id = ?")
            arguments.append(folderId.uuidString)
        }
        
        conditions.append("message_id IS NOT NULL AND message_id != ''")
        let whereClause = "WHERE " + conditions.joined(separator: " AND ")
        
        // 查找有重复 Message-ID 的邮件
        let duplicateRows = try Row.fetchAll(db, sql: """
            SELECT message_id, COUNT(*) as count, GROUP_CONCAT(id) as ids
            FROM email_messages
            \(whereClause)
            GROUP BY message_id
            HAVING count > 1
        """, arguments: StatementArguments(arguments))
        
        for row in duplicateRows {
            guard let messageIds = row["ids"] as? String else { continue }
            let ids = messageIds.split(separator: ",").map { String($0) }
            
            // 保留最新的邮件，删除其他的
            let keepId = try selectBestMessage(ids: ids, db: db)
            let deleteIds = ids.filter { $0 != keepId }
            
            for idToDelete in deleteIds {
                try db.execute(sql: "DELETE FROM email_messages WHERE id = ?", arguments: [idToDelete])
                deletedCount += 1
            }
        }
        
        return deletedCount
    }
    
    /// 基于 UID 清理重复（同一文件夹内）
    private func cleanupByUID(db: Database, accountId: UUID?, folderId: UUID?) throws -> Int {
        var deletedCount = 0
        
        var conditions: [String] = []
        var arguments: [String] = []
        
        if let accountId = accountId {
            conditions.append("account_id = ?")
            arguments.append(accountId.uuidString)
        }
        
        if let folderId = folderId {
            conditions.append("folder_id = ?")
            arguments.append(folderId.uuidString)
        }
        
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        
        // 查找有重复 UID 的邮件（同一账号、同一文件夹）
        let duplicateRows = try Row.fetchAll(db, sql: """
            SELECT account_id, folder_id, uid, COUNT(*) as count, GROUP_CONCAT(id) as ids
            FROM email_messages
            \(whereClause)
            AND uid IS NOT NULL
            GROUP BY account_id, folder_id, uid
            HAVING count > 1
        """, arguments: StatementArguments(arguments))
        
        for row in duplicateRows {
            guard let messageIds = row["ids"] as? String else { continue }
            let ids = messageIds.split(separator: ",").map { String($0) }
            
            let keepId = try selectBestMessage(ids: ids, db: db)
            let deleteIds = ids.filter { $0 != keepId }
            
            for idToDelete in deleteIds {
                try db.execute(sql: "DELETE FROM email_messages WHERE id = ?", arguments: [idToDelete])
                deletedCount += 1
            }
        }
        
        return deletedCount
    }
    
    /// 基于内容哈希清理重复（跨文件夹）
    private func cleanupByContentHash(db: Database, accountId: UUID?) throws -> Int {
        var deletedCount = 0
        
        // 获取所有邮件
        var query = """
            SELECT id, account_id, folder_id, subject, from_email, date, preview
            FROM email_messages
            WHERE is_draft = 0
        """
        var arguments: [String] = []
        
        if let accountId = accountId {
            query += " AND account_id = ?"
            arguments.append(accountId.uuidString)
        }
        
        query += " ORDER BY date DESC"
        
        let rows = try Row.fetchAll(db, sql: query, arguments: StatementArguments(arguments))
        
        // 使用字典跟踪已见过的邮件
        var seenHashes: [String: String] = [:] // hash -> messageId (保留的)
        
        for row in rows {
            guard let id = row["id"] as? String,
                  let accountIdString = row["account_id"] as? String,
                  let _ = UUID(uuidString: accountIdString),
                  let subject = row["subject"] as? String,
                  let fromEmail = row["from_email"] as? String,
                  let date = row["date"] as? Double,
                  let preview = row["preview"] as? String else {
                continue
            }
            
            // 生成内容哈希
            let normalizedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedFrom = fromEmail.lowercased()
            let dateString = String(format: "%.0f", date)
            let normalizedPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(100)
            
            let combined = "\(normalizedSubject)|\(normalizedFrom)|\(dateString)|\(normalizedPreview)"
            let data = Data(combined.utf8)
            let hash = SHA256.hash(data: data)
            let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
            
            // 检查是否已存在
            if seenHashes[hashString] != nil {
                // 发现重复，删除当前邮件（保留已见过的）
                try db.execute(sql: "DELETE FROM email_messages WHERE id = ?", arguments: [id])
                deletedCount += 1
            } else {
                // 首次见到，保留
                seenHashes[hashString] = id
            }
        }
        
        return deletedCount
    }
    
    /// 从多个重复邮件中选择最好的一个（保留最新的、最完整的）
    private func selectBestMessage(ids: [String], db: Database) throws -> String {
        // 查询这些邮件的详细信息
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, date, synced_at, 
                   CASE WHEN text_body IS NOT NULL AND text_body != '' THEN 1 ELSE 0 END as has_text_body,
                   CASE WHEN html_body IS NOT NULL AND html_body != '' THEN 1 ELSE 0 END as has_html_body
            FROM email_messages
            WHERE id IN (\(placeholders))
        """, arguments: StatementArguments(ids))
        
        // 评分规则：
        // 1. 有正文的优先（text_body 或 html_body）
        // 2. 同步时间最新的优先
        // 3. 日期最新的优先
        
        var bestId = ids[0]
        var bestScore = 0.0
        
        for row in rows {
            guard let id = row["id"] as? String else { continue }
            
            let date = row["date"] as? Double ?? 0
            let syncedAt = row["synced_at"] as? Double ?? 0
            let hasTextBody = (row["has_text_body"] as? Int ?? 0) == 1
            let hasHtmlBody = (row["has_html_body"] as? Int ?? 0) == 1
            
            var score = 0.0
            if hasTextBody || hasHtmlBody {
                score += 1000 // 有正文的优先
            }
            score += syncedAt // 同步时间越新越好
            score += date / 1000000 // 日期越新越好（除以1000000避免数值过大）
            
            if score > bestScore {
                bestScore = score
                bestId = id
            }
        }
        
        return bestId
    }
}

