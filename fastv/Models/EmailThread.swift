//
//  EmailThread.swift
//  fastv
//
//  Created for Email Thread Management
//

import Foundation

/// 邮件线程模型
struct EmailThread: Identifiable, Codable {
    let id: UUID
    let accountId: UUID
    var subject: String?
    var messageId: String? // 根邮件的Message-ID
    var rootMessageId: String? // 根邮件ID
    var participantEmails: [String] // 参与者邮箱列表
    var messageCount: Int // 邮件数量
    var unreadCount: Int // 未读数量
    var lastMessageDate: Date // 最后一条消息的日期
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        accountId: UUID,
        subject: String? = nil,
        messageId: String? = nil,
        rootMessageId: String? = nil,
        participantEmails: [String] = [],
        messageCount: Int = 0,
        unreadCount: Int = 0,
        lastMessageDate: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.subject = subject
        self.messageId = messageId
        self.rootMessageId = rootMessageId
        self.participantEmails = participantEmails
        self.messageCount = messageCount
        self.unreadCount = unreadCount
        self.lastMessageDate = lastMessageDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 线程关系信息
struct ThreadRelationship {
    let messageId: String
    let inReplyTo: String?
    let references: [String]
    
    var rootMessageId: String? {
        // 如果In-Reply-To存在，使用它；否则使用References的第一个
        return inReplyTo ?? references.first
    }
}

