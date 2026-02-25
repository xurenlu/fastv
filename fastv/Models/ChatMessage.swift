//
//  ChatMessage.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// 消息角色
enum ChatMessageRole: String, Codable {
    case user = "user"
    case assistant = "assistant"
    case system = "system"
}

/// 消息内容类型
enum ChatMessageContentType: String, Codable {
    case text = "text"
    case image = "image"
    case audio = "audio"
    case video = "video"
    case mixed = "mixed"  // 包含多种类型
}

/// 附件信息
struct ChatAttachment: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ChatMessageContentType
    let url: String?  // 文件URL（OSS或其他）
    let base64Data: String?  // Base64编码的数据（临时方案）
    let fileName: String?
    let mimeType: String?
    let fileSize: Int64?  // 文件大小（字节）
    
    init(
        id: UUID = UUID(),
        type: ChatMessageContentType,
        url: String? = nil,
        base64Data: String? = nil,
        fileName: String? = nil,
        mimeType: String? = nil,
        fileSize: Int64? = nil
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.base64Data = base64Data
        self.fileName = fileName
        self.mimeType = mimeType
        self.fileSize = fileSize
    }
}

/// 聊天消息数据模型
struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let sessionId: UUID
    var role: ChatMessageRole
    var content: String  // 文本内容
    var contentType: ChatMessageContentType
    var attachments: [ChatAttachment]  // 附件列表
    let createdAt: Date
    var updatedAt: Date
    var isSending: Bool  // 是否正在发送
    var sendError: String?  // 发送错误信息
    var thinking: String?  // 思考过程（仅用于 qwen3 系列模型）
    
    init(
        id: UUID = UUID(),
        sessionId: UUID,
        role: ChatMessageRole,
        content: String = "",
        contentType: ChatMessageContentType = .text,
        attachments: [ChatAttachment] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isSending: Bool = false,
        sendError: String? = nil,
        thinking: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.contentType = contentType
        self.attachments = attachments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isSending = isSending
        self.sendError = sendError
        self.thinking = thinking
    }
    
    /// 格式化时间显示
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: createdAt)
    }
    
    /// 格式化日期时间显示
    var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: createdAt)
    }
    
    /// 是否有附件
    var hasAttachments: Bool {
        !attachments.isEmpty
    }
    
    /// 是否为用户消息
    var isUserMessage: Bool {
        role == .user
    }
    
    /// 是否为AI消息
    var isAIMessage: Bool {
        role == .assistant
    }
}

