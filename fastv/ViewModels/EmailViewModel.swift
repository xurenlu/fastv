//
//  EmailViewModel.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine
import SwiftUI

/// 邮箱主视图模型
@MainActor
class EmailViewModel: ObservableObject {
    @Published var selectedAccountId: UUID?
    @Published var selectedFolderId: UUID?
    @Published var selectedMessageId: UUID?
    
    @Published var isLoading = false
    @Published var syncProgress: Double = 0.0
    @Published var syncStatus: String = ""
    
    @Published var searchText: String = ""
    @Published var showAttachments: Bool = false
    @Published var showImages: Bool = false
    
    @Published var errorMessage: String?
    
    private let emailStore = EmailStore.shared
    private let emailService = EmailService.shared
    private let emailAIService = EmailAIService.shared
    private let notificationService = EmailNotificationService.shared
    private let preferences = UserPreferences.shared
    
    var accounts: [EmailAccount] {
        emailStore.accounts
    }
    
    var currentAccount: EmailAccount? {
        guard let accountId = selectedAccountId else { return nil }
        return emailStore.getAccount(id: accountId)
    }
    
    var folders: [EmailFolder] {
        guard let accountId = selectedAccountId else { return [] }
        return emailStore.getFolders(for: accountId)
    }
    
    var messages: [EmailMessage] {
        guard let folderId = selectedFolderId else { return [] }
        return emailStore.getMessages(for: folderId, limit: 100, offset: 0)
    }
    
    var selectedMessage: EmailMessage? {
        guard let messageId = selectedMessageId else { return nil }
        return messages.first { $0.id == messageId }
    }
    
    init() {
        // 加载设置
        showAttachments = preferences.emailShowAttachments
        showImages = preferences.emailShowImages
        
        // 选择默认账号
        if let defaultAccount = emailStore.getDefaultAccount() {
            selectedAccountId = defaultAccount.id
        } else if let firstAccount = emailStore.accounts.first {
            selectedAccountId = firstAccount.id
        }
        
        // 选择收件箱
        if let accountId = selectedAccountId {
            let inbox = emailStore.getFolders(for: accountId).first { $0.type == .inbox }
            selectedFolderId = inbox?.id
        }
    }
    
    // 选择账号
    func selectAccount(_ account: EmailAccount) {
        selectedAccountId = account.id
        // 选择收件箱
        let inbox = emailStore.getFolders(for: account.id).first { $0.type == .inbox }
        selectedFolderId = inbox?.id
        selectedMessageId = nil
    }
    
    /// 选择文件夹
    func selectFolder(_ folder: EmailFolder) {
        selectedFolderId = folder.id
        selectedMessageId = nil
        loadMessages()
    }
    
    /// 选择邮件
    func selectMessage(_ message: EmailMessage) {
        selectedMessageId = message.id
        
        // 标记为已读
        if !message.isRead {
            Task {
                await markAsRead(message)
            }
        }
        
        // 加载正文（如果未加载）
        if !message.isBodyLoaded {
            Task {
                await loadMessageBody(message)
            }
        }
        
        // 触发AI分析（如果启用）
        if preferences.emailAISmartTaggingEnabled {
            Task {
                await analyzeMessageWithAI(message)
            }
        }
    }
    
    /// 加载邮件列表
    func loadMessages() {
        guard let folderId = selectedFolderId,
              let account = currentAccount else {
            return
        }
        
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                let folder = folders.first { $0.id == folderId }
                let messages = try await emailService.syncMessages(
                    account: account,
                    folder: folder ?? EmailFolder(accountId: account.id, name: "Inbox", type: .inbox),
                    since: nil as Date?
                )
                
                try await emailStore.addMessages(messages, folderId: folderId)
                
                // 发送通知
                for message in messages {
                    notificationService.notifyNewEmail(message)
                    
                    // 检查是否需要自动回复
                    if preferences.emailAutoReplyEnabled {
                        await EmailAutoReplyScheduler.shared.processNewMessage(message)
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            
            isLoading = false
        }
    }
    
    /// 加载邮件正文
    func loadMessageBody(_ message: EmailMessage) async {
        guard let account = currentAccount else { return }
        
        // TODO: 实现正文加载逻辑
        // 这里应该从服务器获取完整邮件内容
        
        var updated = message
        updated.isBodyLoaded = true
        try? await emailStore.updateMessage(updated)
    }
    
    /// 标记为已读
    func markAsRead(_ message: EmailMessage) async {
        guard let account = currentAccount else { return }
        
        do {
            try await emailService.markAsRead(account: account, message: message)
            
            var updated = message
            updated.isRead = true
            try await emailStore.updateMessage(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// 删除邮件
    func deleteMessage(_ message: EmailMessage) async {
        guard let account = currentAccount else { return }
        
        do {
            try await emailService.deleteMessage(account: account, message: message)
            // 从本地数据库删除
            // TODO: 实现删除逻辑
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// 发送邮件
    func sendMessage(
        to: [EmailContact],
        cc: [EmailContact] = [],
        bcc: [EmailContact] = [],
        subject: String,
        body: String,
        htmlBody: String? = nil,
        attachments: [EmailAttachment] = []
    ) async throws {
        guard let account = currentAccount else {
            throw EmailServiceError.invalidConfiguration("未选择账号")
        }
        
        try await emailService.sendMessage(
            account: account,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            body: body,
            htmlBody: htmlBody,
            attachments: attachments,
            readReceipt: preferences.emailReadReceiptEnabled
        )
    }
    
    /// 使用AI分析邮件
    func analyzeMessageWithAI(_ message: EmailMessage) async {
        do {
            // 生成标签
            let tags = try await emailAIService.generateSmartTags(for: message)
            
            // 检测优先级
            let priority = try await emailAIService.detectPriority(for: message)
            
            // 生成摘要
            let summary = try await emailAIService.generateSummary(for: message)
            
            var updated = message
            updated.aiTags = tags
            updated.aiPriority = priority
            updated.aiSummary = summary
            
            try await emailStore.updateMessage(updated)
        } catch {
            print("❌ [EmailViewModel] AI分析失败: \(error)")
        }
    }
    
    /// 同步账号
    func syncAccount(_ account: EmailAccount) async {
        isLoading = true
        syncProgress = 0.0
        syncStatus = "正在同步..."
        
        do {
            // 获取文件夹列表
            let folders = try await emailService.fetchFolders(account: account)
            
            syncProgress = 0.3
            syncStatus = "已获取 \(folders.count) 个文件夹"
            
            // 同步每个文件夹
            for (index, folder) in folders.enumerated() {
                try await emailStore.addFolder(folder)
                
                let messages = try await emailService.syncMessages(account: account, folder: folder)
                try await emailStore.addMessages(messages, folderId: folder.id)
                
                syncProgress = 0.3 + (Double(index + 1) / Double(folders.count)) * 0.7
                syncStatus = "正在同步 \(folder.name)..."
            }
            
            syncStatus = "同步完成"
            
            // 更新账号最后同步时间
            var updatedAccount = account
            updatedAccount.lastSyncDate = Date()
            updatedAccount.connectionStatus = .connected
            try await emailStore.updateAccount(updatedAccount)
            
        } catch {
            errorMessage = error.localizedDescription
            syncStatus = "同步失败"
        }
        
        isLoading = false
    }
    
    /// 搜索邮件
    func searchMessages(query: String) -> [EmailMessage] {
        guard !query.isEmpty else { return messages }
        
        let lowercasedQuery = query.lowercased()
        return messages.filter { message in
            message.subject.lowercased().contains(lowercasedQuery) ||
            message.from.email.lowercased().contains(lowercasedQuery) ||
            message.from.name?.lowercased().contains(lowercasedQuery) == true ||
            message.preview.lowercased().contains(lowercasedQuery)
        }
    }
}

