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
    private var cancellables = Set<AnyCancellable>()
    
    @Published var accounts: [EmailAccount] = []
    @Published var folders: [EmailFolder] = []
    @Published var messages: [EmailMessage] = []
    
    // 分页加载状态
    @Published var isLoadingMore = false
    @Published var hasMoreMessages = true
    private var currentPage = 0
    private let pageSize = 50 // 每页加载50封邮件
    private var loadedDateRange: Date? // 已加载的最早邮件日期
    
    var currentAccount: EmailAccount? {
        guard let accountId = selectedAccountId else { return nil }
        return emailStore.getAccount(id: accountId)
    }
    
    var selectedMessage: EmailMessage? {
        guard let messageId = selectedMessageId else { return nil }
        return messages.first { $0.id == messageId }
    }
    
    init() {
        // 加载设置
        showAttachments = preferences.emailShowAttachments
        showImages = preferences.emailShowImages
        
        // 订阅 EmailStore 的账号变化
        emailStore.$accounts
            .receive(on: DispatchQueue.main)
            .assign(to: &$accounts)
        
        // 订阅 EmailStore 的文件夹变化
        emailStore.$folders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] foldersDict in
                guard let self = self else { return }
                if let accountId = self.selectedAccountId {
                    self.folders = foldersDict[accountId] ?? []
                } else {
                    self.folders = []
                }
            }
            .store(in: &cancellables)
        
        // 订阅 EmailStore 的邮件变化（使用 objectWillChange 确保实时更新）
        emailStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateMessagesFromStore()
            }
            .store(in: &cancellables)
        
        // 初始加载
        updateMessagesFromStore()
        
        // 监听账号列表变化，自动选择账号并加载数据
        $accounts
            .dropFirst() // 跳过初始值
            .sink { [weak self] accounts in
                guard let self = self else { return }
                Task { @MainActor in
                    // 如果还没有选择账号，选择默认账号或第一个账号
                    if self.selectedAccountId == nil {
                        if let defaultAccount = self.emailStore.getDefaultAccount() {
                            self.selectedAccountId = defaultAccount.id
                        } else if let firstAccount = accounts.first {
                            self.selectedAccountId = firstAccount.id
                        }
                    }
                    
                    // 如果选择了账号，加载数据
                    if let accountId = self.selectedAccountId {
                        await self.loadInitialData()
                    }
                }
            }
            .store(in: &cancellables)
        
        // 监听选择的账号变化，更新文件夹列表
        $selectedAccountId
            .sink { [weak self] accountId in
                guard let self = self else { return }
                if let accountId = accountId {
                    self.folders = self.emailStore.getFolders(for: accountId)
                } else {
                    self.folders = []
                }
            }
            .store(in: &cancellables)
        
        // 初始化时也尝试加载
        Task {
            // 等待一下，确保 EmailStore 已经加载完成
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            await loadInitialData()
        }
    }
    
    /// 从 EmailStore 更新邮件列表（实时更新）
    private func updateMessagesFromStore() {
        guard let folderId = selectedFolderId else {
            messages = []
            return
        }
        
        // 从 EmailStore 获取所有邮件
        let allMessages = emailStore.messages[folderId] ?? []
        let sorted = allMessages.sorted { $0.date > $1.date }
        
        // 只显示当前页的邮件
        let endIndex = min((currentPage + 1) * pageSize, sorted.count)
        messages = Array(sorted[0..<endIndex])
        hasMoreMessages = sorted.count > endIndex
    }
    
    /// 加载初始数据（文件夹列表和邮件列表）
    func loadInitialData() async {
        guard let accountId = selectedAccountId,
              let account = emailStore.getAccount(id: accountId) else {
            return
        }
        
        // 如果文件夹列表为空，尝试从服务器加载
        let existingFolders = emailStore.getFolders(for: accountId)
        if existingFolders.isEmpty {
            await loadFolders(account: account)
        }
        
        // 如果选择了文件夹，加载邮件列表
        if let folderId = selectedFolderId {
            await loadMessagesAsync()
        }
    }
    
    /// 加载文件夹列表
    func loadFolders(account: EmailAccount) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let folders = try await emailService.fetchFolders(account: account)
            for folder in folders {
                try await emailStore.addFolder(folder)
            }
            
            // 如果还没有选择文件夹，选择收件箱
            if selectedFolderId == nil {
                let inbox = folders.first { $0.type == .inbox }
                selectedFolderId = inbox?.id
            }
        } catch {
            errorMessage = "加载文件夹失败: \(error.localizedDescription)"
            print("❌ [EmailViewModel] 加载文件夹失败: \(error)")
        }
        
        isLoading = false
    }
    
    /// 异步加载邮件列表（增量加载，实时更新）
    func loadMessagesAsync(loadMore: Bool = false) async {
        guard let folderId = selectedFolderId,
              let account = currentAccount else {
            return
        }
        
        if loadMore {
            isLoadingMore = true
            currentPage += 1
        } else {
            isLoading = true
            currentPage = 0
            loadedDateRange = nil
            messages = [] // 清空当前列表
        }
        
        errorMessage = nil
        
        do {
            let folder = folders.first { $0.id == folderId }
            
            // 计算时间范围：首次加载最近30天，加载更多时扩展到更早的日期
            let sinceDate: Date?
            if loadMore, let earliestDate = messages.last?.date {
                // 加载更多时，从当前最旧的邮件开始往前加载
                sinceDate = Calendar.current.date(byAdding: .day, value: -30, to: earliestDate)
                loadedDateRange = sinceDate
            } else {
                // 首次加载：最近30天
                sinceDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())
                loadedDateRange = sinceDate
            }
            
            // 分批加载邮件，每批20封，实时更新UI
            let batchSize = 20
            var allMessages: [EmailMessage] = []
            
            // 先加载一批，立即显示（减少到10封，更快响应）
            let firstBatchSize = 10
            let firstBatch = try await emailService.syncMessages(
                account: account,
                folder: folder ?? EmailFolder(accountId: account.id, name: "Inbox", type: .inbox),
                since: sinceDate,
                limit: firstBatchSize,
                batchSize: firstBatchSize
            )
            
            if !firstBatch.isEmpty {
                try await emailStore.addMessages(firstBatch, folderId: folderId)
                allMessages.append(contentsOf: firstBatch)
                
                // 立即更新 UI（实时显示）
                await MainActor.run {
                    self.updateMessagesFromStore()
                }
                
                // 发送通知（只对新邮件）- 后台处理，不阻塞
                Task.detached(priority: .background) { [weak self] in
                    guard let self = self else { return }
                    for message in firstBatch {
                        await self.notificationService.notifyNewEmail(message)
                        
                        if await self.preferences.emailAutoReplyEnabled {
                            await EmailAutoReplyScheduler.shared.processNewMessage(message)
                        }
                    }
                }
            }
            
            // 继续加载剩余邮件（后台加载，不阻塞UI）
            if !loadMore {
                let accountToSync = account
                let folderIdToSync = folderId
                let folderToSync = folder ?? EmailFolder(accountId: account.id, name: "Inbox", type: .inbox)
                let sinceDateToSync = sinceDate
                
                Task.detached(priority: .background) { [weak self] in
                    guard let self = self else { return }
                    
                    var offset = batchSize
                    while true {
                        let batch = try? await self.emailService.syncMessages(
                            account: accountToSync,
                            folder: folderToSync,
                            since: sinceDateToSync,
                            limit: batchSize,
                            batchSize: batchSize
                        )
                        
                        guard let batch = batch, !batch.isEmpty else { break }
                        
                        try? await self.emailStore.addMessages(batch, folderId: folderIdToSync)
                        
                        // 发送通知
                        for message in batch {
                            await self.notificationService.notifyNewEmail(message)
                            
                            if await self.preferences.emailAutoReplyEnabled {
                                await EmailAutoReplyScheduler.shared.processNewMessage(message)
                            }
                        }
                        
                        offset += batchSize
                        
                        // 限制总加载数量，避免一次性加载太多
                        if offset >= 200 { // 最多加载200封邮件
                            break
                        }
                        
                        // 让出控制权
                        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            print("❌ [EmailViewModel] 加载邮件失败: \(error)")
        }
        
        isLoading = false
        isLoadingMore = false
    }
    
    /// 加载更多邮件（滚动到底部时调用）
    func loadMoreMessages() {
        guard !isLoadingMore && hasMoreMessages else { return }
        Task {
            await loadMessagesAsync(loadMore: true)
        }
    }
    
    // 选择账号
    func selectAccount(_ account: EmailAccount) {
        selectedAccountId = account.id
        selectedMessageId = nil
        
        // 加载文件夹列表（如果为空）
        let existingFolders = emailStore.getFolders(for: account.id)
        if existingFolders.isEmpty {
            Task {
                await loadFolders(account: account)
            }
        } else {
            // 选择收件箱
            let inbox = existingFolders.first { $0.type == .inbox }
            selectedFolderId = inbox?.id
            
            // 加载邮件列表
            if let folderId = selectedFolderId {
                Task {
                    await loadMessagesAsync()
                }
            }
        }
    }
    
    /// 选择文件夹（优化：避免卡顿）
    func selectFolder(_ folder: EmailFolder) {
        selectedFolderId = folder.id
        selectedMessageId = nil
        currentPage = 0
        hasMoreMessages = true
        loadedDateRange = nil
        messages = [] // 清空当前列表
        
        // 异步加载，不阻塞 UI
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            await self.loadMessagesAsync(loadMore: false)
        }
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
    
    /// 加载邮件正文（懒加载）
    func loadMessageBody(_ message: EmailMessage) async {
        guard let account = currentAccount,
              !message.isBodyLoaded,
              let uid = message.uid else { return }
        
        // TODO: 实现邮件正文加载
        // 需要在 EmailService 中添加 fetchMessageBody 方法
        // 目前先标记为已加载，避免重复请求
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
    
    /// 同步账号
    func syncAccount(_ account: EmailAccount) async {
        isLoading = true
        syncProgress = 0.0
        syncStatus = "正在同步..."
        errorMessage = nil
        
        do {
            // 获取文件夹列表
            let folders = try await emailService.fetchFolders(account: account)
            
            syncProgress = 0.3
            syncStatus = "已获取 \(folders.count) 个文件夹"
            
            // 同步每个文件夹
            for (index, folder) in folders.enumerated() {
                try await emailStore.addFolder(folder)
                
                let messages = try await emailService.syncMessages(
                    account: account,
                    folder: folder,
                    since: nil
                )
                try await emailStore.addMessages(messages, folderId: folder.id)
                
                syncProgress = 0.3 + (Double(index + 1) / Double(folders.count)) * 0.7
                syncStatus = "正在同步 \(folder.name)..."
                
                // 发送通知
                for message in messages {
                    notificationService.notifyNewEmail(message)
                }
            }
            
            syncStatus = "同步完成"
            syncProgress = 1.0
            
            // 更新账号最后同步时间
            var updatedAccount = account
            updatedAccount.lastSyncDate = Date()
            updatedAccount.connectionStatus = .connected
            try await emailStore.updateAccount(updatedAccount)
            
            // 刷新当前视图
            if selectedAccountId == account.id {
                await loadMessagesAsync()
            }
        } catch {
            errorMessage = error.localizedDescription
            syncStatus = "同步失败"
        }
        
        isLoading = false
        
        // 2秒后清除状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.syncStatus = ""
            self.syncProgress = 0.0
        }
    }
    
    /// 搜索邮件
    func searchMessages(query: String) -> [EmailMessage] {
        guard !query.isEmpty else { return messages }
        
        let lowercasedQuery = query.lowercased()
        return messages.filter { message in
            message.subject.lowercased().contains(lowercasedQuery) ||
            message.from.email.lowercased().contains(lowercasedQuery) ||
            (message.from.name?.lowercased().contains(lowercasedQuery) ?? false) ||
            message.preview.lowercased().contains(lowercasedQuery)
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
    
}

