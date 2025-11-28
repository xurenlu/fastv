//
//  ChatSession.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// 聊天会话数据模型
struct ChatSession: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var model: String  // 使用的模型名称
    let createdAt: Date
    var updatedAt: Date
    var lastMessagePreview: String?  // 最后一条消息预览
    var messageCount: Int  // 消息数量
    var summary: String?  // 聊天总结
    
    init(
        id: UUID = UUID(),
        title: String = "",
        model: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastMessagePreview: String? = nil,
        messageCount: Int = 0,
        summary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMessagePreview = lastMessagePreview
        self.messageCount = messageCount
        self.summary = summary
    }
    
    /// 自动生成标题（基于时间）
    static func generateDefaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "新对话 \(formatter.string(from: Date()))"
    }
    
    /// 格式化日期显示
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: updatedAt)
    }
    
    /// 格式化简短日期显示（用于列表）
    var formattedShortDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(updatedAt) {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            formatter.locale = Locale(identifier: "zh_CN")
            return formatter.string(from: updatedAt)
        } else if calendar.isDateInYesterday(updatedAt) {
            return "昨天"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd"
            return formatter.string(from: updatedAt)
        }
    }
}

