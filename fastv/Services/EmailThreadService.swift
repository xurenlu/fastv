//
//  EmailThreadService.swift
//  fastv
//
//  Created for Email Thread Management Service
//

import Foundation
import GRDB

/// 邮件线程管理服务
@MainActor
class EmailThreadService {
    static let shared = EmailThreadService()
    
    private let database = EmailDatabase.shared
    private let emailStore = EmailStore.shared
    
    private init() {}
    
    // MARK: - Thread CRUD
    
    /// 获取账号的所有线程
    func getThreads(for accountId: UUID) async throws -> [EmailThread] {
        return try await database.asyncRead { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM email_threads
                WHERE account_id = ?
                ORDER BY last_message_date DESC
            """, arguments: [accountId.uuidString])
            
            return try rows.map { row in
                try self.parseThread(from: row)
            }
        }
    }
    
    /// 获取线程
    func getThread(id: UUID) async throws -> EmailThread? {
        return try await database.asyncRead { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT * FROM email_threads
                WHERE id = ?
            """, arguments: [id.uuidString])
            
            guard let row = row else { return nil }
            return try self.parseThread(from: row)
        }
    }
    
    /// 根据Message-ID查找线程
    func findThreadByMessageId(_ messageId: String, accountId: UUID) async throws -> EmailThread? {
        return try await database.asyncRead { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT * FROM email_threads
                WHERE account_id = ? AND (message_id = ? OR root_message_id = ?)
                LIMIT 1
            """, arguments: [accountId.uuidString, messageId, messageId])
            
            guard let row = row else { return nil }
            return try self.parseThread(from: row)
        }
    }
    
    /// 保存或更新线程
    func saveThread(_ thread: EmailThread) async throws {
        var updated = thread
        updated.updatedAt = Date()
        
        try await database.asyncWrite { db in
            try self.saveThreadToDB(updated, db: db)
        }
    }
    
    /// 删除线程
    func deleteThread(id: UUID) async throws {
        try await database.asyncWrite { db in
            try db.execute(sql: """
                DELETE FROM email_threads
                WHERE id = ?
            """, arguments: [id.uuidString])
        }
    }
    
    // MARK: - Thread Relationship Building
    
    /// 为邮件建立线程关系
    /// - Parameter message: 邮件消息
    /// - Returns: 线程ID（如果成功建立关系）
    func buildThreadRelationship(for message: EmailMessage) async throws -> UUID? {
        guard let messageId = message.messageId else {
            return nil
        }
        
        // 解析邮件头中的In-Reply-To和References
        // 注意：这里需要从原始邮件头中获取，EmailMessage模型可能没有这些字段
        // 我们需要从EmailService获取原始邮件头
        
        // 先尝试根据Message-ID查找现有线程
        if let existingThread = try await findThreadByMessageId(messageId, accountId: message.accountId) {
            // 更新线程统计
            var updated = existingThread
            updated.messageCount += 1
            if !message.isRead {
                updated.unreadCount += 1
            }
            if message.date > updated.lastMessageDate {
                updated.lastMessageDate = message.date
            }
            
            // 更新参与者列表
            let participantEmail = message.from.email
            if !updated.participantEmails.contains(participantEmail) {
                updated.participantEmails.append(participantEmail)
            }
            for contact in message.to {
                if !updated.participantEmails.contains(contact.email) {
                    updated.participantEmails.append(contact.email)
                }
            }
            
            try await saveThread(updated)
            return existingThread.id
        }
        
        // 创建新线程
        let newThread = EmailThread(
            accountId: message.accountId,
            subject: message.subject,
            messageId: messageId,
            rootMessageId: messageId,
            participantEmails: [message.from.email] + message.to.map { $0.email },
            messageCount: 1,
            unreadCount: message.isRead ? 0 : 1,
            lastMessageDate: message.date
        )
        
        try await saveThread(newThread)
        return newThread.id
    }
    
    /// 获取线程中的所有邮件
    func getMessagesInThread(_ threadId: UUID) async throws -> [EmailMessage] {
        // 从EmailStore中获取所有邮件，然后过滤出属于该线程的邮件
        let allMessages = emailStore.messages.values.flatMap { $0 }
        return allMessages.filter { message in
            message.threadId == threadId.uuidString
        }
    }
    
    /// 更新线程统计信息
    func updateThreadStats(_ threadId: UUID) async throws {
        let messages = try await getMessagesInThread(threadId)
        
        guard let thread = try await getThread(id: threadId) else {
            return
        }
        
        var updated = thread
        updated.messageCount = messages.count
        updated.unreadCount = messages.filter { !$0.isRead }.count
        if let lastMessage = messages.max(by: { $0.date < $1.date }) {
            updated.lastMessageDate = lastMessage.date
        }
        
        // 更新参与者列表
        var participants = Set<String>()
        for message in messages {
            participants.insert(message.from.email)
            for contact in message.to {
                participants.insert(contact.email)
            }
        }
        updated.participantEmails = Array(participants)
        
        try await saveThread(updated)
    }
    
    // MARK: - Private Helpers
    
    private func saveThreadToDB(_ thread: EmailThread, db: Database) throws {
        let participantEmailsJson = try JSONEncoder().encode(thread.participantEmails)
        let participantEmailsString = String(data: participantEmailsJson, encoding: .utf8) ?? "[]"
        
        try db.execute(sql: """
            INSERT OR REPLACE INTO email_threads (
                id, account_id, subject, message_id, root_message_id,
                participant_emails, message_count, unread_count,
                last_message_date, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            thread.id.uuidString,
            thread.accountId.uuidString,
            thread.subject,
            thread.messageId,
            thread.rootMessageId,
            participantEmailsString,
            thread.messageCount,
            thread.unreadCount,
            thread.lastMessageDate.timeIntervalSince1970,
            thread.createdAt.timeIntervalSince1970,
            thread.updatedAt.timeIntervalSince1970
        ])
    }
    
    private func parseThread(from row: Row) throws -> EmailThread {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString),
              let accountIdString = row["account_id"] as? String,
              let accountId = UUID(uuidString: accountIdString) else {
            throw EmailDatabaseError.invalidData
        }
        
        let subject = row["subject"] as? String
        let messageId = row["message_id"] as? String
        let rootMessageId = row["root_message_id"] as? String
        let participantEmailsString = row["participant_emails"] as? String ?? "[]"
        let messageCount = row["message_count"] as? Int64 ?? 0
        let unreadCount = row["unread_count"] as? Int64 ?? 0
        let lastMessageDate = Date(timeIntervalSince1970: row["last_message_date"] as? Double ?? 0)
        let createdAt = Date(timeIntervalSince1970: row["created_at"] as? Double ?? 0)
        let updatedAt = Date(timeIntervalSince1970: row["updated_at"] as? Double ?? 0)
        
        // 解析参与者邮箱列表
        var participantEmails: [String] = []
        if let data = participantEmailsString.data(using: .utf8),
           let emails = try? JSONDecoder().decode([String].self, from: data) {
            participantEmails = emails
        }
        
        return EmailThread(
            id: id,
            accountId: accountId,
            subject: subject,
            messageId: messageId,
            rootMessageId: rootMessageId,
            participantEmails: participantEmails,
            messageCount: Int(messageCount),
            unreadCount: Int(unreadCount),
            lastMessageDate: lastMessageDate,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

