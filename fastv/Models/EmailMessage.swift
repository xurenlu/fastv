//
//  EmailMessage.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// 邮件消息模型
struct EmailMessage: Identifiable, Codable {
    let id: UUID
    let accountId: UUID
    let folderId: UUID?
    var uid: UInt32? // IMAP UID
    var messageId: String? // Message-ID header
    var threadId: String? // Thread-ID或In-Reply-To
    
    // 基本信息
    var subject: String
    var from: EmailContact
    var to: [EmailContact]
    var cc: [EmailContact]
    var bcc: [EmailContact]
    var replyTo: [EmailContact]
    
    // 内容
    var textBody: String?
    var htmlBody: String?
    var preview: String // 预览文本（前200字符）
    
    // 元数据
    var date: Date
    var receivedDate: Date?
    var isRead: Bool
    var isStarred: Bool
    var isImportant: Bool
    var isNoReply: Bool // 是否no-reply地址
    var hasAttachments: Bool
    
    // 标签和分类
    var tags: [String]
    var aiTags: [String] // AI生成的标签
    var aiSummary: String? // AI生成的摘要
    var aiPriority: EmailPriority? // AI识别的优先级
    
    // 附件
    var attachments: [EmailAttachment]
    
    // 同步信息
    var syncedAt: Date
    var updatedAt: Date
    
    // 正文是否已加载（懒加载）
    var isBodyLoaded: Bool
    
    init(
        id: UUID = UUID(),
        accountId: UUID,
        folderId: UUID? = nil,
        uid: UInt32? = nil,
        messageId: String? = nil,
        threadId: String? = nil,
        subject: String = "",
        from: EmailContact,
        to: [EmailContact] = [],
        cc: [EmailContact] = [],
        bcc: [EmailContact] = [],
        replyTo: [EmailContact] = [],
        textBody: String? = nil,
        htmlBody: String? = nil,
        preview: String = "",
        date: Date = Date(),
        receivedDate: Date? = nil,
        isRead: Bool = false,
        isStarred: Bool = false,
        isImportant: Bool = false,
        isNoReply: Bool = false,
        hasAttachments: Bool = false,
        tags: [String] = [],
        aiTags: [String] = [],
        aiSummary: String? = nil,
        aiPriority: EmailPriority? = nil,
        attachments: [EmailAttachment] = [],
        syncedAt: Date = Date(),
        updatedAt: Date = Date(),
        isBodyLoaded: Bool = false
    ) {
        self.id = id
        self.accountId = accountId
        self.folderId = folderId
        self.uid = uid
        self.messageId = messageId
        self.threadId = threadId
        self.subject = subject
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.replyTo = replyTo
        self.textBody = textBody
        self.htmlBody = htmlBody
        self.preview = preview.isEmpty && textBody != nil ? String(textBody!.prefix(200)) : preview
        self.date = date
        self.receivedDate = receivedDate ?? date
        self.isRead = isRead
        self.isStarred = isStarred
        self.isImportant = isImportant
        self.isNoReply = isNoReply
        self.hasAttachments = hasAttachments
        self.tags = tags
        self.aiTags = aiTags
        self.aiSummary = aiSummary
        self.aiPriority = aiPriority
        self.attachments = attachments
        self.syncedAt = syncedAt
        self.updatedAt = updatedAt
        self.isBodyLoaded = isBodyLoaded
    }
}

/// 邮件优先级（AI识别）
enum EmailPriority: String, Codable {
    case low = "low"
    case normal = "normal"
    case high = "high"
    case urgent = "urgent"
    
    var displayName: String {
        switch self {
        case .low:
            return "低"
        case .normal:
            return "普通"
        case .high:
            return "高"
        case .urgent:
            return "紧急"
        }
    }
    
    var color: String {
        switch self {
        case .low:
            return "gray"
        case .normal:
            return "blue"
        case .high:
            return "orange"
        case .urgent:
            return "red"
        }
    }
}

/// 邮件联系人
struct EmailContact: Codable, Hashable {
    var name: String?
    var email: String
    
    var displayName: String {
        if let name = name, !name.isEmpty {
            return "\(name) <\(email)>"
        }
        return email
    }
    
    init(name: String? = nil, email: String) {
        self.name = name
        self.email = email
    }
}

/// 邮件附件
struct EmailAttachment: Identifiable, Codable {
    let id: UUID
    var filename: String
    var mimeType: String
    var size: Int64 // 字节
    var contentId: String? // Content-ID（用于内嵌图片）
    var isInline: Bool // 是否内嵌图片
    var localPath: String? // 本地缓存路径
    
    init(
        id: UUID = UUID(),
        filename: String,
        mimeType: String,
        size: Int64 = 0,
        contentId: String? = nil,
        isInline: Bool = false,
        localPath: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.contentId = contentId
        self.isInline = isInline
        self.localPath = localPath
    }
    
    var sizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

