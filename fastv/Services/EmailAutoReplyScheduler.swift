//
//  EmailAutoReplyScheduler.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// 自动回复调度器
@MainActor
class EmailAutoReplyScheduler {
    static let shared = EmailAutoReplyScheduler()
    
    private let emailService = EmailService.shared
    private let emailAIService = EmailAIService.shared
    private let emailStore = EmailStore.shared
    private let preferences = UserPreferences.shared
    
    private var processedMessageIds: Set<UUID> = []
    
    private init() {}
    
    /// 处理新邮件（检查是否需要自动回复）
    func processNewMessage(_ message: EmailMessage) async {
        // 检查是否启用自动回复
        guard preferences.emailAutoReplyEnabled else {
            return
        }
        
        // 如果超级隐私模式开启，不发送邮件内容给 AI 生成自动回复
        guard !preferences.emailSuperPrivacyMode else {
            print("🔒 [EmailAutoReplyScheduler] 超级隐私模式已启用，跳过自动回复")
            return
        }
        
        // 检查是否已处理过
        guard !processedMessageIds.contains(message.id) else {
            return
        }
        
        // 检查是否为no-reply地址
        guard !message.isNoReply else {
            processedMessageIds.insert(message.id)
            return
        }
        
        // 检查是否已读（避免对已读邮件自动回复）
        guard !message.isRead else {
            return
        }
        
        // 获取账号
        guard let account = emailStore.getAccount(id: message.accountId) else {
            return
        }
        
        // 生成并发送自动回复
        do {
            let replyBody = try await emailAIService.generateAutoReply(for: message)
            
            // 发送回复
            try await emailService.sendMessage(
                account: account,
                to: [message.from],
                subject: "Re: \(message.subject)",
                body: replyBody,
                readReceipt: false
            )
            
            // 标记为已处理
            processedMessageIds.insert(message.id)
            
            print("✅ [EmailAutoReplyScheduler] 已自动回复邮件: \(message.subject)")
        } catch {
            print("❌ [EmailAutoReplyScheduler] 自动回复失败: \(error)")
        }
    }
    
    /// 清除已处理记录（定期清理）
    func clearProcessedRecords() {
        // 保留最近1000条记录
        if processedMessageIds.count > 1000 {
            let toRemove = processedMessageIds.prefix(processedMessageIds.count - 1000)
            processedMessageIds.subtract(toRemove)
        }
    }
}

