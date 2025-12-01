//
//  EmailViewModel.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine
import SwiftUI

/// 回复草稿模型
struct ReplyDraft {
    var to: [EmailContact] = []
    var cc: [EmailContact] = []
    var bcc: [EmailContact] = []
    var subject: String = ""
    var body: String = ""
    var htmlBody: String? = nil
    var attachments: [EmailAttachment] = []
    var replyType: ReplyType = .reply
    
    enum ReplyType {
        case reply      // 回复
        case replyAll   // 回复全部
        case forward    // 转发
    }
}

/// 邮箱主视图模型
@MainActor
class EmailViewModel: ObservableObject {
    @Published var selectedAccountId: UUID?
    @Published var selectedFolderId: UUID?
    @Published var selectedMessageId: UUID?
    
    @Published var isLoading = false // 邮件列表加载
    @Published var isLoadingFolders = false
    @Published var syncProgress: Double = 0.0
    @Published var syncStatus: String = ""
    
    @Published var searchText: String = ""
    @Published var searchResults: [EmailMessage] = [] // 搜索结果缓存
    @Published var showAttachments: Bool = false
    @Published var showImages: Bool = false
    
    @Published var errorMessage: String?
    
    // 搜索防抖任务
    private var searchTask: Task<Void, Never>?
    
    // 回复相关状态
    @Published var replyDraft: ReplyDraft?
    @Published var showReplyPanel: Bool = false
    @Published var showCcBcc: Bool = false
    
    // 编写相关状态
    @Published var composeDraft: ReplyDraft?
    @Published var showComposePanel: Bool = false
    
    private let emailStore = EmailStore.shared
    private let emailService = EmailService.shared
    private let emailAIService = EmailAIService.shared
    private let notificationService = EmailNotificationService.shared
    private let preferences = UserPreferences.shared
    private let imageDisplayPreferences = EmailImageDisplayPreferences.shared
    private var cancellables = Set<AnyCancellable>()
    
    // 防抖机制：避免短时间内多次排序
    private var updateMessagesTask: Task<Void, Never>?
    private let updateDebounceInterval: TimeInterval = 0.05 // 50ms防抖
    
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
        
        // 订阅 EmailStore 的邮件变化（使用防抖机制避免重复排序）
        emailStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                // 取消之前的更新任务
                self.updateMessagesTask?.cancel()
                
                // 创建新的防抖任务
                self.updateMessagesTask = Task { [weak self] in
                    guard let self = self else { return }
                    
                    // 等待防抖间隔
                    try? await Task.sleep(nanoseconds: UInt64(self.updateDebounceInterval * 1_000_000_000))
                    
                    // 检查是否被取消
                    guard !Task.isCancelled else {
                        print("🚫 [EmailViewModel] 更新任务被取消（防抖）")
                        return
                    }
                    
                    print("🔄 [EmailViewModel] 执行防抖后的邮件列表更新")
                    await self.updateMessagesFromStore()
                }
            }
            .store(in: &cancellables)
        
        // 监听账号列表变化，自动选择账号并加载数据
        $accounts
            .dropFirst() // 跳过初始值
            .sink { [weak self] accounts in
                guard let self = self else { return }
                // 在主线程更新selectedAccountId
                Task { @MainActor in
                    if self.selectedAccountId == nil {
                        if let defaultAccount = self.emailStore.getDefaultAccount() {
                            self.selectedAccountId = defaultAccount.id
                        } else if let firstAccount = accounts.first {
                            self.selectedAccountId = firstAccount.id
                        }
                    }
                }
                
                // 在后台线程加载数据,不阻塞UI
                Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self = self else { return }
                    if await self.selectedAccountId != nil {
                        await self.loadInitialData()
                    }
                }
            }
            .store(in: &cancellables)
        
        // 监听选中邮件变化，自动更新图片显示偏好
        $selectedMessageId
            .sink { [weak self] messageId in
                guard let self = self else { return }
                if let messageId = messageId,
                   let message = self.messages.first(where: { $0.id == messageId }) {
                    // 检查是否有记住的偏好设置
                    if let shouldShow = self.imageDisplayPreferences.shouldShowImages(for: message.from) {
                        self.showImages = shouldShow
                    } else {
                        // 没有记住的偏好，使用全局设置
                        self.showImages = self.preferences.emailShowImages
                    }
                } else {
                    // 没有选中邮件，使用全局设置
                    self.showImages = self.preferences.emailShowImages
                }
            }
            .store(in: &cancellables)
        
        // 监听选择的账号变化，更新文件夹列表
        $selectedAccountId
            .sink { [weak self] accountId in
                guard let self = self else { return }
                if let accountId = accountId {
                    // 立即从 EmailStore 读取文件夹（如果已加载）
                    let folders = self.emailStore.getFolders(for: accountId)
                    self.folders = folders
                    
                    // 如果文件夹为空，可能是 EmailStore 还在加载，稍后重试
                    if folders.isEmpty {
                        Task.detached(priority: .userInitiated) { [weak self] in
                            guard let self = self else { return }
                            // 等待一下，让 EmailStore 完成初始化
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                            
                            // 再次尝试读取
                            await MainActor.run {
                                if let accountId = self.selectedAccountId {
                                    let folders = self.emailStore.getFolders(for: accountId)
                                    if !folders.isEmpty {
                                        self.folders = folders
                                    }
                                }
                            }
                        }
                    }
                } else {
                    self.folders = []
                }
            }
            .store(in: &cancellables)
        
        // 初始化时立即尝试读取文件夹（如果 EmailStore 已加载）
        // 注意：这里在 init 中直接读取，因为 EmailStore 是单例，可能在应用启动时就已经初始化
        if let accountId = selectedAccountId {
            folders = emailStore.getFolders(for: accountId)
        } else if let defaultAccount = emailStore.getDefaultAccount() {
            selectedAccountId = defaultAccount.id
            folders = emailStore.getFolders(for: defaultAccount.id)
        } else if let firstAccount = accounts.first {
            selectedAccountId = firstAccount.id
            folders = emailStore.getFolders(for: firstAccount.id)
        }
        
        // 如果文件夹为空，等待 EmailStore 加载完成
        if folders.isEmpty {
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                // 等待 EmailStore 完成初始化（最多等待 1 秒）
                for _ in 0..<10 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                    
                    await MainActor.run {
                        if let accountId = self.selectedAccountId {
                            let folders = self.emailStore.getFolders(for: accountId)
                            if !folders.isEmpty {
                                self.folders = folders
                                return // 找到了，退出循环
                            }
                        }
                    }
                }
            }
        }
        
        // 监听搜索文本变化，异步执行搜索（使用防抖）
        $searchText
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self = self else { return }
                self.performSearch(query: query)
            }
            .store(in: &cancellables)
        
        // 监听邮件列表变化，更新搜索结果
        $messages
            .sink { [weak self] _ in
                guard let self = self else { return }
                // 如果当前有搜索文本，重新搜索
                if !self.searchText.isEmpty {
                    self.performSearch(query: self.searchText)
                } else {
                    self.searchResults = []
                }
            }
            .store(in: &cancellables)
        
        // 初始化时也尝试加载(后台执行,不阻塞UI)
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            // 等待一下，确保 EmailStore 已经加载完成
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            await self.loadInitialData()
        }
    }
    
    /// 从 EmailStore 更新邮件列表（终极优化，零卡顿）
    private func updateMessagesFromStore() async {
        guard let folderId = selectedFolderId else {
            await updateMessagesForAllFolders()
            return
        }
        
        // 快速读取数据（在主线程，极快）
        let allMessages = emailStore.messages[folderId] ?? []
        let currentPageValue = currentPage
        let pageSizeValue = pageSize
        
        // 统一在后台线程处理排序（无论数据量大小，确保零卡顿）
        print("📊 [EmailViewModel] 开始后台处理邮件，数量: \(allMessages.count)")
        let sortStart = Date()
        
        let processedMessages = await Task.detached(priority: .userInitiated) {
            // 排序
            let sorted = allMessages.sorted { $0.date > $1.date }
            let endIndex = min((currentPageValue + 1) * pageSizeValue, sorted.count)
            let newMessages = Array(sorted.prefix(endIndex))
            return (messages: newMessages, hasMore: sorted.count > endIndex)
        }.value
        
        let sortElapsed = Date().timeIntervalSince(sortStart)
        print("📊 [EmailViewModel] 后台处理完成，耗时: \(String(format: "%.3f", sortElapsed * 1000))ms，结果: \(processedMessages.messages.count)封")
        
        // 在主线程更新 UI，同时保留已加载的正文数据
        // 重要：在这里读取最新的 messages，而不是方法开始时的快照
        let existingMessages = messages
        var finalMessages = processedMessages.messages
        
        // 保留已加载正文的邮件（优先使用 ViewModel 中已有的正文数据）
        for (index, newMsg) in finalMessages.enumerated() {
            if let existingMsg = existingMessages.first(where: { $0.id == newMsg.id }) {
                // 检查 ViewModel 中是否有正文数据
                let existingHasTextBody = existingMsg.textBody?.isEmpty == false
                let existingHasHtmlBody = existingMsg.htmlBody?.isEmpty == false
                let existingHasBody = existingMsg.isBodyLoaded || existingHasTextBody || existingHasHtmlBody
                
                // 检查 Store 中是否有正文数据
                let newHasTextBody = newMsg.textBody?.isEmpty == false
                let newHasHtmlBody = newMsg.htmlBody?.isEmpty == false
                let newHasBody = newMsg.isBodyLoaded || newHasTextBody || newHasHtmlBody
                
                // 如果 ViewModel 中有正文但 Store 中没有，保留 ViewModel 的数据
                if existingHasBody && !newHasBody {
                    var merged = newMsg
                    merged.textBody = existingMsg.textBody
                    merged.htmlBody = existingMsg.htmlBody
                    merged.isBodyLoaded = true
                    merged.bodyCachedAt = existingMsg.bodyCachedAt
                    merged.containsRemoteResources = existingMsg.containsRemoteResources
                    merged.preview = existingMsg.preview.isEmpty ? newMsg.preview : existingMsg.preview
                    finalMessages[index] = merged
                    print("🔄 [EmailViewModel] 保留邮件正文: \(merged.subject)")
                }
            }
        }
        
        messages = finalMessages
        hasMoreMessages = processedMessages.hasMore
    }
    
    /// 更新所有文件夹的邮件（完全异步）
    private func updateMessagesForAllFolders() async {
        // 快速读取必要数据（注意：这里已经在 MainActor 上下文中）
        let accountId = selectedAccountId
        let currentPageValue = currentPage
        let pageSizeValue = pageSize
        
        guard let accountId = accountId else {
            messages = []
            hasMoreMessages = false
            return
        }
        
        // 读取文件夹和邮件
        let foldersForAccount = emailStore.getFolders(for: accountId)
        let allFolderMessages = emailStore.messages
        
        print("📊 [EmailViewModel] 开始合并所有文件夹的邮件，文件夹数: \(foldersForAccount.count)")
        let mergeStart = Date()
        
        // 在后台线程处理合并和排序
        let processedMessages = await Task.detached(priority: .userInitiated) {
            // 合并所有文件夹的邮件
            var combined: [EmailMessage] = []
            for folder in foldersForAccount {
                if let folderMsgs = allFolderMessages[folder.id] {
                    combined.append(contentsOf: folderMsgs)
                }
            }
            
            // 排序
            let sorted = combined.sorted { $0.date > $1.date }
            let endIndex = min((currentPageValue + 1) * pageSizeValue, sorted.count)
            let newMessages = Array(sorted.prefix(endIndex))
            
            // 检查合并后的邮件是否有正文
            let messagesWithBody = newMessages.filter { msg in
                msg.isBodyLoaded || (msg.textBody?.isEmpty == false) || (msg.htmlBody?.isEmpty == false)
            }
            print("📊 [EmailViewModel-AllFolders] 合并后邮件统计: 总数=\(newMessages.count), 有正文=\(messagesWithBody.count)")
            
            return (messages: newMessages, hasMore: sorted.count > endIndex, totalCount: combined.count)
        }.value
        
        let mergeElapsed = Date().timeIntervalSince(mergeStart)
        print("📊 [EmailViewModel] 邮件合并完成，总计: \(processedMessages.totalCount)封，耗时: \(String(format: "%.3f", mergeElapsed * 1000))ms")
        
        // 在主线程更新 UI，同时保留已加载的正文数据
        // 重要：在这里读取最新的 messages，而不是方法开始时的快照
        let existingMessages = messages
        var finalMessages = processedMessages.messages
        
        // 检查当前选中的邮件状态
        if let selectedId = selectedMessageId {
            let existingSelected = existingMessages.first(where: { $0.id == selectedId })
            let newSelected = finalMessages.first(where: { $0.id == selectedId })
            let existingHasBody = existingSelected?.isBodyLoaded == true || (existingSelected?.textBody?.isEmpty == false) || (existingSelected?.htmlBody?.isEmpty == false)
            let newHasBody = newSelected?.isBodyLoaded == true || (newSelected?.textBody?.isEmpty == false) || (newSelected?.htmlBody?.isEmpty == false)
            print("📋 [EmailViewModel-AllFolders] 选中邮件检查: existingHasBody=\(existingHasBody), newHasBody=\(newHasBody)")
        }
        
        // 保留已加载正文的邮件（优先使用 ViewModel 中已有的正文数据）
        for (index, newMsg) in finalMessages.enumerated() {
            if let existingMsg = existingMessages.first(where: { $0.id == newMsg.id }) {
                // 检查 ViewModel 中是否有正文数据
                let existingHasTextBody = existingMsg.textBody?.isEmpty == false
                let existingHasHtmlBody = existingMsg.htmlBody?.isEmpty == false
                let existingHasBody = existingMsg.isBodyLoaded || existingHasTextBody || existingHasHtmlBody
                
                // 检查 Store 中是否有正文数据
                let newHasTextBody = newMsg.textBody?.isEmpty == false
                let newHasHtmlBody = newMsg.htmlBody?.isEmpty == false
                let newHasBody = newMsg.isBodyLoaded || newHasTextBody || newHasHtmlBody
                
                // 如果 ViewModel 中有正文但 Store 中没有，保留 ViewModel 的数据
                if existingHasBody && !newHasBody {
                    var merged = newMsg
                    merged.textBody = existingMsg.textBody
                    merged.htmlBody = existingMsg.htmlBody
                    merged.isBodyLoaded = true
                    merged.bodyCachedAt = existingMsg.bodyCachedAt
                    merged.containsRemoteResources = existingMsg.containsRemoteResources
                    merged.preview = existingMsg.preview.isEmpty ? newMsg.preview : existingMsg.preview
                    finalMessages[index] = merged
                    print("🔄 [EmailViewModel-AllFolders] 保留邮件正文: \(merged.subject)")
                }
            }
        }
        
        messages = finalMessages
        hasMoreMessages = processedMessages.hasMore
    }
    
    private func aggregatedMessagesForCurrentAccount() -> [EmailMessage] {
        guard let accountId = selectedAccountId else { return [] }
        let foldersForAccount = emailStore.getFolders(for: accountId)
        var combined: [EmailMessage] = []
        for folder in foldersForAccount {
            combined.append(contentsOf: emailStore.messages[folder.id] ?? [])
        }
        return combined
    }
    
    private func prefetchDefaultFolderIfNeeded(for account: EmailAccount) async {
        let folders = emailStore.getFolders(for: account.id)
        guard let targetFolder = folders.first(where: { $0.type == .inbox }) ?? folders.first else {
            return
        }
        
        let existingMessages = emailStore.messages[targetFolder.id] ?? []
        if existingMessages.isEmpty {
            await loadMessagesAsync(
                loadMore: false,
                folderIdOverride: targetFolder.id,
                affectsCurrentList: selectedFolderId == targetFolder.id
            )
        }
    }
    
    private func folder(for id: UUID) -> EmailFolder? {
        if let cached = folders.first(where: { $0.id == id }) {
            return cached
        }
        guard let accountId = selectedAccountId else { return nil }
        return emailStore.getFolders(for: accountId).first(where: { $0.id == id })
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
        } else {
            await prefetchDefaultFolderIfNeeded(for: account)
        }
        
        if selectedFolderId != nil {
            await loadMessagesAsync()
        } else {
            await updateMessagesFromStore()
        }
    }
    
    /// 加载文件夹列表
    func loadFolders(account: EmailAccount) async {
        isLoadingFolders = true
        errorMessage = nil
        
        do {
            // 后台获取文件夹列表,不阻塞UI
            let folders = try await emailService.fetchFolders(account: account)
            
            // 快速保存到数据库,立即显示文件夹
            for folder in folders {
                try await emailStore.addFolder(folder)
            }
            
            isLoadingFolders = false
            
            // 后台预加载默认文件夹的邮件,不阻塞UI
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                await self.prefetchDefaultFolderIfNeeded(for: account)
            }
            
            if selectedFolderId == nil {
                Task {
                    await updateMessagesFromStore()
                }
            }
        } catch {
            errorMessage = "加载文件夹失败: \(error.localizedDescription)"
            print("❌ [EmailViewModel] 加载文件夹失败: \(error)")
            isLoadingFolders = false
        }
    }
    
    /// 异步加载邮件列表（增量加载，实时更新）
    func loadMessagesAsync(
        loadMore: Bool = false,
        folderIdOverride: UUID? = nil,
        affectsCurrentList: Bool = true
    ) async {
        guard let account = currentAccount else { return }
        
        let activeFolderId = folderIdOverride ?? selectedFolderId
        guard let folderId = activeFolderId,
              let folder = folder(for: folderId) else {
            if selectedFolderId == nil && folderIdOverride == nil && loadMore {
                currentPage += 1
                await updateMessagesFromStore()
            }
            return
        }
        
        let shouldAffectUI = affectsCurrentList && folderIdOverride == nil
        
        // 在主线程更新 UI 状态
        if loadMore {
            isLoadingMore = true
            currentPage += 1
        } else if shouldAffectUI {
            isLoading = true
            currentPage = 0
            loadedDateRange = nil
        }
        
        errorMessage = nil
        
        do {
            let sinceDate: Date?
            if loadMore {
                let existing = emailStore.messages[folderId] ?? []
                let earliest = existing.last?.date ?? Date()
                sinceDate = Calendar.current.date(byAdding: .day, value: -30, to: earliest)
            } else {
                sinceDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())
            }
            loadedDateRange = sinceDate
            
            print("📥 [EmailViewModel] 开始同步邮件: \(folder.name), limit: \(pageSize)")
            let startTime = Date()
            
            // 在后台线程执行网络请求，避免阻塞 UI
            let fetched = try await Task.detached(priority: .userInitiated) { [emailService, account, folder, sinceDate, pageSize] in
                return try await emailService.syncMessages(
                    account: account,
                    folder: folder,
                    since: sinceDate,
                    limit: pageSize,
                    batchSize: 10
                )
            }.value
            
            let elapsed = Date().timeIntervalSince(startTime)
            print("⏱️ [EmailViewModel] 同步完成，耗时: \(String(format: "%.2f", elapsed))秒, 获取: \(fetched.count)封")
            
            if !fetched.isEmpty {
                print("💾 [EmailViewModel] 开始保存 \(fetched.count) 封邮件到Store...")
                let saveStartTime = Date()
                
                // addMessages 内部已经使用 Task.detached 后台保存，这里只是触发
                try await emailStore.addMessages(fetched, folderId: folderId)
                
                let saveElapsed = Date().timeIntervalSince(saveStartTime)
                print("💾 [EmailViewModel] 保存完成，耗时: \(String(format: "%.2f", saveElapsed))秒")
                
                if shouldAffectUI || selectedFolderId == nil {
                    await updateMessagesFromStore()
                }
                
                 if fetched.count < pageSize {
                     hasMoreMessages = false
                 } else if !loadMore {
                     hasMoreMessages = true
                 }
                
                Task.detached(priority: .background) { [weak self] in
                    guard let self else { return }
                    for message in fetched {
                        await self.notificationService.notifyNewEmail(message)
                        
                        if await self.preferences.emailAutoReplyEnabled {
                            await EmailAutoReplyScheduler.shared.processNewMessage(message)
                        }
                    }
                }
            } else if loadMore {
                hasMoreMessages = false
            } else {
                hasMoreMessages = false
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
        if selectedFolderId == nil {
            guard !isLoadingMore && hasMoreMessages else { return }
            currentPage += 1
            Task {
                await updateMessagesFromStore()
            }
            return
        }
        
        guard !isLoadingMore && hasMoreMessages else { return }
        Task {
            await loadMessagesAsync(loadMore: true)
        }
    }
    
    // 选择账号
    func selectAccount(_ account: EmailAccount) {
        selectedAccountId = account.id
        selectedMessageId = nil
        selectedFolderId = nil
        currentPage = 0
        messages = []
        
        Task {
            let existingFolders = emailStore.getFolders(for: account.id)
            if existingFolders.isEmpty {
                await loadFolders(account: account)
            } else {
                await prefetchDefaultFolderIfNeeded(for: account)
                await updateMessagesFromStore()
            }
        }
    }
    
    /// 选择文件夹（终极零卡顿优化）
    func selectFolder(_ folder: EmailFolder) {
        print("📂 [EmailViewModel] 开始切换文件夹: \(folder.name)")
        let startTime = Date()
        
        // 1. 立即更新选择状态（极快，<1ms）
        let oldFolderId = selectedFolderId
        selectedFolderId = folder.id
        selectedMessageId = nil
        currentPage = 0
        hasMoreMessages = true
        loadedDateRange = nil
        
        // 2. 立即从缓存读取并显示（同步读取，极快）
        let cachedMessages = emailStore.messages[folder.id] ?? []
        if !cachedMessages.isEmpty {
            // 有缓存，立即显示
            messages = Array(cachedMessages.sorted { $0.date > $1.date }.prefix(pageSize))
            isLoading = false
            print("📂 [EmailViewModel] 立即显示缓存: \(messages.count) 封邮件，耗时: \(String(format: "%.3f", Date().timeIntervalSince(startTime) * 1000))ms")
        } else {
            // 无缓存，显示loading
            isLoading = true
            messages = []
            print("📂 [EmailViewModel] 无缓存，显示loading")
        }
        
        // 3. 后台加载数据库缓存（如果内存缓存为空）
        if cachedMessages.isEmpty {
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                
                // 从数据库加载
                await self.emailStore.loadMessages(for: folder.id)
                
                // 更新显示
                await self.updateMessagesFromStore()
                
                await MainActor.run {
                    self.isLoading = false
                    let elapsed = Date().timeIntervalSince(startTime)
                    print("📂 [EmailViewModel] 数据库加载完成，耗时: \(String(format: "%.3f", elapsed * 1000))ms")
                }
            }
        }
        
        // 4. 后台同步最新邮件（低优先级，不影响显示）
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            // 延迟一点，确保UI先更新
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            await self.loadMessagesAsync(loadMore: false)
        }
    }
    
    /// 显示所有邮件（不按文件夹过滤）
    func showAllMessages() {
        selectedFolderId = nil
        selectedMessageId = nil
        currentPage = 0
        hasMoreMessages = true
        Task {
            await updateMessagesFromStore()
        }
    }
    
    private func replaceMessageInList(with updated: EmailMessage) {
        if let index = messages.firstIndex(where: { $0.id == updated.id }) {
            let hasBody = updated.isBodyLoaded || (updated.textBody?.isEmpty == false) || (updated.htmlBody?.isEmpty == false)
            print("🔄 [EmailViewModel] replaceMessageInList: \(updated.subject), hasBody=\(hasBody), htmlBody长度=\(updated.htmlBody?.count ?? 0)")
            messages[index] = updated
        }
    }
    
    /// 选择邮件
    func selectMessage(_ message: EmailMessage) {
        selectedMessageId = message.id
        
        // 切换到其他邮件时，关闭回复窗口
        if showReplyPanel {
            showReplyPanel = false
            replyDraft = nil
        }
        
        // 延迟执行副作用操作，避免在视图更新期间触发状态变更
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 尝试从 emailStore 获取最新的消息（可能包含更新的正文内容）
            var currentMessage = message
            if let folderId = message.folderId,
               let storeMessages = self.emailStore.messages[folderId],
               let updatedMessage = storeMessages.first(where: { $0.id == message.id }) {
                currentMessage = updatedMessage
            }
            
            // 标记为已读
            if !currentMessage.isRead {
                Task {
                    await self.markAsRead(currentMessage)
                }
            }
            
            // 加载正文（如果未加载或没有内容）
            let hasTextBody = currentMessage.textBody?.isEmpty == false
            let hasHtmlBody = currentMessage.htmlBody?.isEmpty == false
            let needsBodyLoad = !currentMessage.isBodyLoaded || (!hasTextBody && !hasHtmlBody)
            
            // 触发AI分析（如果启用任何AI功能，且还没有AI结果）
            let needsAIAnalysis = (self.preferences.emailAISmartTaggingEnabled && currentMessage.aiTags.isEmpty) ||
                                  (self.preferences.emailAISummaryEnabled && currentMessage.aiSummary == nil) ||
                                  (self.preferences.emailAIPriorityDetectionEnabled && currentMessage.aiPriority == nil)
            
            // 如果需要加载正文，先加载正文，然后再进行 AI 分析
            if needsBodyLoad {
                Task {
                    await self.loadMessageBody(currentMessage)
                    
                    // 正文加载完成后，如果需要 AI 分析，再执行
                    if needsAIAnalysis {
                        await self.analyzeMessageWithAI(currentMessage)
                    }
                }
            } else if needsAIAnalysis {
                // 如果不需要加载正文，直接进行 AI 分析
                Task {
                    await self.analyzeMessageWithAI(currentMessage)
                }
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
        guard let account = currentAccount else {
            print("⚠️ [EmailViewModel] loadMessageBody 跳过: account=nil")
            return
        }
        
        // 先检查本地是否有缓存
        let hasTextBody = message.textBody?.isEmpty == false
        let hasHtmlBody = message.htmlBody?.isEmpty == false
        
        if hasTextBody || hasHtmlBody {
            // 检查缓存是否过期（默认7天）
            let cacheExpirationDays = 7
            var shouldUseCache = true
            
            if let cachedAt = message.bodyCachedAt {
                if let expirationDate = Calendar.current.date(byAdding: .day, value: cacheExpirationDays, to: cachedAt) {
                    if expirationDate < Date() {
                        // 缓存已过期
                        shouldUseCache = false
                        print("⏰ [EmailViewModel] 正文缓存已过期（缓存时间: \(cachedAt)，过期时间: \(expirationDate)），重新加载")
                    } else {
                        print("✅ [EmailViewModel] 使用本地正文缓存（缓存时间: \(cachedAt)，剩余有效期: \(String(format: "%.1f", expirationDate.timeIntervalSinceNow / 86400))天）")
                    }
                }
            } else {
                // 没有缓存时间戳，但如果有正文内容，仍然使用（兼容旧数据）
                print("✅ [EmailViewModel] 使用本地正文缓存（无缓存时间戳，兼容旧数据）")
            }
            
            if shouldUseCache {
                // 如果使用了缓存但 isBodyLoaded 为 false，更新标志
                if !message.isBodyLoaded {
                    var updated = message
                    updated.isBodyLoaded = true
                    replaceMessageInList(with: updated)
                    // 后台更新数据库
                    Task(priority: .background) {
                        do {
                            try await self.emailStore.updateMessage(updated)
                            print("✅ [EmailViewModel] 已更新 isBodyLoaded 标志")
                        } catch {
                            print("⚠️ [EmailViewModel] 更新 isBodyLoaded 标志失败: \(error)")
                        }
                    }
                }
                return
            }
        }
        
        // 如果已标记为已加载但没有内容，可能是数据不一致，继续加载
        if message.isBodyLoaded && !hasTextBody && !hasHtmlBody {
            print("⚠️ [EmailViewModel] 邮件标记为已加载但无正文内容，重新加载")
        }
        
        let folderIdentifier = message.folderId ?? selectedFolderId
        guard let folderId = folderIdentifier,
              let folder = folder(for: folderId) else {
            print("⚠️ [EmailViewModel] loadMessageBody 跳过: folderId=\(folderIdentifier?.uuidString ?? "nil"), selectedFolderId=\(selectedFolderId?.uuidString ?? "nil")")
            return
        }
        
        print("📧 [EmailViewModel] 开始加载邮件正文: \(message.subject), folder: \(folder.name), uid: \(message.uid ?? 0)")
        
        do {
            let content = try await emailService.fetchMessageBody(
                account: account,
                folder: folder,
                message: message
            )
            
            print("📧 [EmailViewModel] 邮件正文获取成功: textBody=\(content.textBody?.prefix(100) ?? "nil"), htmlBody=\(content.htmlBody?.prefix(100) ?? "nil")")
            
            var updated = message
            // 如果有 textBody 直接使用，否则暂时使用空字符串（避免在主线程解析大型 HTML）
            updated.textBody = content.textBody ?? ""
            updated.htmlBody = content.htmlBody
            updated.containsRemoteResources = content.containsRemoteResources
            if updated.preview.isEmpty {
                updated.preview = content.previewText
            }
            updated.isBodyLoaded = true
            updated.bodyCachedAt = Date() // 记录缓存时间
            
            // 立即更新UI（使用 htmlBody 渲染，不需要等待 textBody）
            replaceMessageInList(with: updated)
            print("📝 [EmailViewModel] 已更新 ViewModel 邮件列表，邮件: \(updated.subject), folderId: \(updated.folderId?.uuidString ?? "nil")")
            
            // 如果没有 textBody，在后台线程从 HTML 提取纯文本（用于搜索等功能）
            if content.textBody == nil, let htmlBody = content.htmlBody, !htmlBody.isEmpty {
                Task.detached(priority: .background) { [weak self] in
                    guard let self = self else { return }
                    let plainText = htmlBody.strippingHTML()
                    await MainActor.run {
                        // 更新 textBody（用于搜索）
                        if var msg = self.messages.first(where: { $0.id == updated.id }) {
                            msg.textBody = plainText
                            self.replaceMessageInList(with: msg)
                        }
                    }
                }
            }
            
            // 后台保存到数据库和 EmailStore
            Task(priority: .background) {
                do {
                    try await self.emailStore.updateMessage(updated)
                    print("✅ [EmailViewModel] 邮件正文已保存到数据库和 EmailStore，folderId: \(updated.folderId?.uuidString ?? "nil")")
                } catch {
                    print("⚠️ [EmailViewModel] 更新邮件正文缓存失败: \(error)")
                }
            }
        } catch {
            print("❌ [EmailViewModel] 加载正文失败: \(error)")
            errorMessage = "加载正文失败: \(error.localizedDescription)"
        }
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
    
    /// 执行搜索（异步，不阻塞主线程）
    private func performSearch(query: String) {
        // 取消之前的搜索任务
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        let lowercasedQuery = query.lowercased()
        let messagesToSearch = messages // 复制当前消息列表，避免并发问题
        
        // 后台执行搜索
        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // 检查是否被取消
            guard !Task.isCancelled else { return }
            
            let results = messagesToSearch.filter { message in
                message.subject.lowercased().contains(lowercasedQuery) ||
                message.from.email.lowercased().contains(lowercasedQuery) ||
                (message.from.name?.lowercased().contains(lowercasedQuery) ?? false) ||
                message.preview.lowercased().contains(lowercasedQuery)
            }
            
            // 检查是否被取消（搜索过程中）
            guard !Task.isCancelled else { return }
            
            // 更新结果到主线程
            await MainActor.run {
                self.searchResults = results
            }
        }
    }
    
    /// 搜索邮件（兼容旧接口，返回当前搜索结果）
    func searchMessages(query: String) -> [EmailMessage] {
        // 如果查询匹配当前搜索文本，返回缓存结果
        if query == searchText {
            return searchText.isEmpty ? messages : searchResults
        }
        // 否则返回空（应该通过 searchText 属性触发搜索）
        return []
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
            // 重要：从当前列表获取最新的邮件（可能已经加载了正文）
            // 避免用旧的邮件覆盖新的正文数据
            let currentMessage = messages.first(where: { $0.id == message.id }) ?? message
            var updated = currentMessage
            
            print("🤖 [EmailViewModel] AI分析邮件: \(updated.subject), hasBody=\(updated.isBodyLoaded), htmlBody长度=\(updated.htmlBody?.count ?? 0)")
            
            // 生成标签（如果启用）
            if preferences.emailAISmartTaggingEnabled {
                let tags = try await emailAIService.generateSmartTags(for: currentMessage)
                updated.aiTags = tags
            }
            
            // 检测优先级（如果启用）
            if preferences.emailAIPriorityDetectionEnabled {
                let priority = try await emailAIService.detectPriority(for: currentMessage)
                updated.aiPriority = priority
            }
            
            // 生成摘要（如果启用）
            if preferences.emailAISummaryEnabled {
                let summary = try await emailAIService.generateSummary(for: currentMessage)
                updated.aiSummary = summary
            }
            
            print("🤖 [EmailViewModel] AI分析完成，更新邮件: hasBody=\(updated.isBodyLoaded), htmlBody长度=\(updated.htmlBody?.count ?? 0)")
            
            try await emailStore.updateMessage(updated)
            
            // 更新列表中的邮件
            replaceMessageInList(with: updated)
        } catch {
            print("❌ [EmailViewModel] AI分析失败: \(error)")
        }
    }
    
    // MARK: - Reply Methods
    
    /// 初始化回复草稿
    func initReplyDraft(for message: EmailMessage, type: ReplyDraft.ReplyType) {
        var draft = ReplyDraft()
        draft.replyType = type
        
        guard let account = currentAccount else { return }
        
        switch type {
        case .reply:
            // 回复：发给发件人
            draft.to = message.replyTo.isEmpty ? [message.from] : message.replyTo
            draft.subject = message.subject.hasPrefix("Re:") ? message.subject : "Re: \(message.subject)"
            // 引用原邮件
            if let textBody = message.textBody {
                let quotedBody = textBody.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
                draft.body = "\n\n在 \(formatDate(message.date))，\(message.from.displayName) 写道：\n\n\(quotedBody)"
            }
        case .replyAll:
            // 回复全部：发给发件人 + 所有收件人（排除自己）
            var recipients = message.replyTo.isEmpty ? [message.from] : message.replyTo
            recipients.append(contentsOf: message.to.filter { $0.email != account.emailAddress })
            recipients.append(contentsOf: message.cc.filter { $0.email != account.emailAddress })
            draft.to = Array(Set(recipients))
            draft.cc = message.cc.filter { $0.email != account.emailAddress }
            draft.subject = message.subject.hasPrefix("Re:") ? message.subject : "Re: \(message.subject)"
            // 引用原邮件
            if let textBody = message.textBody {
                let quotedBody = textBody.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
                draft.body = "\n\n在 \(formatDate(message.date))，\(message.from.displayName) 写道：\n\n\(quotedBody)"
            }
        case .forward:
            // 转发：主题加 Fw:
            draft.subject = message.subject.hasPrefix("Fw:") ? message.subject : "Fw: \(message.subject)"
            // 转发时包含原邮件内容
            if let textBody = message.textBody {
                draft.body = "\n\n---------- 转发邮件 ----------\n\(textBody)"
            } else if let htmlBody = message.htmlBody {
                draft.htmlBody = "<br><br>---------- 转发邮件 ----------<br>\(htmlBody)"
            }
        }
        
        // 关闭编写面板
        showComposePanel = false
        composeDraft = nil
        
        replyDraft = draft
        showReplyPanel = true
        showCcBcc = false  // 重置 Cc/Bcc 展开状态
    }
    
    /// 初始化编写草稿（新邮件）
    func initComposeDraft() {
        // 关闭回复面板
        showReplyPanel = false
        replyDraft = nil
        
        var draft = ReplyDraft()
        draft.replyType = .reply  // 新邮件也使用 reply 类型，但不会引用原邮件
        composeDraft = draft
        showComposePanel = true
        showCcBcc = false
    }
    
    /// 更新编写字段
    func updateComposeField(to: [EmailContact]? = nil, cc: [EmailContact]? = nil, bcc: [EmailContact]? = nil, subject: String? = nil, body: String? = nil) {
        guard var draft = composeDraft else { return }
        if let to = to { draft.to = to }
        if let cc = cc { draft.cc = cc }
        if let bcc = bcc { draft.bcc = bcc }
        if let subject = subject { draft.subject = subject }
        if let body = body { draft.body = body }
        composeDraft = draft
    }
    
    /// 添加附件到编写草稿
    func addAttachmentToCompose(_ attachment: EmailAttachment) {
        guard var draft = composeDraft else { return }
        draft.attachments.append(attachment)
        composeDraft = draft
    }
    
    /// 从编写草稿中移除附件
    func removeAttachmentFromCompose(_ attachmentId: UUID) {
        guard var draft = composeDraft else { return }
        draft.attachments.removeAll { $0.id == attachmentId }
        composeDraft = draft
    }
    
    /// 发送新邮件
    func sendCompose() async throws {
        guard let draft = composeDraft else {
            throw EmailServiceError.invalidConfiguration("编写草稿不存在")
        }
        
        // 检查必填字段
        guard !draft.to.isEmpty else {
            throw EmailServiceError.invalidConfiguration("请填写收件人")
        }
        
        // 检查是否提到附件但没有添加
        let subjectLower = draft.subject.lowercased()
        let bodyLower = draft.body.lowercased()
        let mentionsAttachment = subjectLower.contains("附件") || subjectLower.contains("attachment") ||
                                 bodyLower.contains("附件") || bodyLower.contains("attachment")
        if mentionsAttachment && draft.attachments.isEmpty {
            throw EmailServiceError.invalidConfiguration("您提到了附件，但还没有添加任何附件。请添加附件后再发送，或修改邮件内容。")
        }
        
        try await sendMessage(
            to: draft.to,
            cc: draft.cc,
            bcc: draft.bcc,
            subject: draft.subject,
            body: draft.body,
            htmlBody: draft.htmlBody,
            attachments: draft.attachments
        )
        
        // 发送成功后清除草稿并关闭面板
        composeDraft = nil
        showComposePanel = false
        showCcBcc = false
    }
    
    /// 格式化日期用于引用
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
    
    /// 更新回复字段
    func updateReplyField(to: [EmailContact]? = nil, cc: [EmailContact]? = nil, bcc: [EmailContact]? = nil, subject: String? = nil, body: String? = nil) {
        guard var draft = replyDraft else { return }
        if let to = to { draft.to = to }
        if let cc = cc { draft.cc = cc }
        if let bcc = bcc { draft.bcc = bcc }
        if let subject = subject { draft.subject = subject }
        if let body = body { draft.body = body }
        replyDraft = draft
    }
    
    /// 添加附件到回复草稿
    func addAttachmentToReply(_ attachment: EmailAttachment) {
        guard var draft = replyDraft else { return }
        draft.attachments.append(attachment)
        replyDraft = draft
    }
    
    /// 从回复草稿中移除附件
    func removeAttachmentFromReply(_ attachmentId: UUID) {
        guard var draft = replyDraft else { return }
        draft.attachments.removeAll { $0.id == attachmentId }
        replyDraft = draft
    }
    
    /// 检查主题中提到附件但实际没有附件
    func checkAttachmentMention() -> Bool {
        guard let draft = replyDraft else { return false }
        let subjectLower = draft.subject.lowercased()
        let bodyLower = draft.body.lowercased()
        let mentionsAttachment = subjectLower.contains("附件") || subjectLower.contains("attachment") ||
                                 bodyLower.contains("附件") || bodyLower.contains("attachment")
        return mentionsAttachment && draft.attachments.isEmpty
    }
    
    /// 发送回复
    func sendReply() async throws {
        guard let draft = replyDraft else {
            throw EmailServiceError.invalidConfiguration("回复草稿不存在")
        }
        
        // 检查是否提到附件但没有添加
        if checkAttachmentMention() {
            throw EmailServiceError.invalidConfiguration("您提到了附件，但还没有添加任何附件。请添加附件后再发送，或修改邮件内容。")
        }
        
        try await sendMessage(
            to: draft.to,
            cc: draft.cc,
            bcc: draft.bcc,
            subject: draft.subject,
            body: draft.body,
            htmlBody: draft.htmlBody,
            attachments: draft.attachments
        )
        
        // 发送成功后清除草稿并关闭面板
        replyDraft = nil
        showReplyPanel = false
        showCcBcc = false
    }
    
    // MARK: - Message Actions
    
    /// 切换星标状态
    func toggleStar(_ message: EmailMessage) async {
        guard let account = currentAccount else { return }
        
        do {
            try await emailService.toggleStar(account: account, message: message)
            
            var updated = message
            updated.isStarred.toggle()
            try await emailStore.updateMessage(updated)
            
            // 更新列表中的邮件
            replaceMessageInList(with: updated)
        } catch {
            errorMessage = "操作失败: \(error.localizedDescription)"
            print("❌ [EmailViewModel] 切换星标失败: \(error)")
        }
    }
    
    /// 删除邮件
    func deleteMessage(_ message: EmailMessage) async {
        guard let account = currentAccount else { return }
        
        do {
            try await emailService.deleteMessage(account: account, message: message)
            
            var updated = message
            updated.isDeleted = true
            try await emailStore.updateMessage(updated)
            
            // 从列表中移除
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages.remove(at: index)
            }
            
            // 如果删除的是当前选中的邮件，清除选择
            if selectedMessageId == message.id {
                selectedMessageId = nil
            }
        } catch {
            errorMessage = "删除失败: \(error.localizedDescription)"
            print("❌ [EmailViewModel] 删除邮件失败: \(error)")
        }
    }
    
    /// 标记为垃圾邮件
    func markAsSpam(_ message: EmailMessage) async {
        guard let account = currentAccount else { return }
        
        do {
            try await emailService.markAsSpam(account: account, message: message)
            
            var updated = message
            updated.isSpam = true
            try await emailStore.updateMessage(updated)
            
            replaceMessageInList(with: updated)
        } catch {
            errorMessage = "操作失败: \(error.localizedDescription)"
            print("❌ [EmailViewModel] 标记垃圾邮件失败: \(error)")
        }
    }
    
    /// 取消垃圾邮件标记
    func restoreFromSpam(_ message: EmailMessage) async {
        guard let account = currentAccount else { return }
        
        do {
            try await emailService.unmarkSpam(account: account, message: message)
            
            var updated = message
            updated.isSpam = false
            try await emailStore.updateMessage(updated)
            
            replaceMessageInList(with: updated)
        } catch {
            errorMessage = "操作失败: \(error.localizedDescription)"
            print("❌ [EmailViewModel] 取消垃圾邮件标记失败: \(error)")
        }
    }
    
    // MARK: - Attachment Methods
    
    /// 下载附件
    func downloadAttachment(_ attachment: EmailAttachment, from message: EmailMessage) async throws -> URL {
        guard let account = currentAccount,
              let folderId = message.folderId,
              let folder = folder(for: folderId) else {
            throw EmailServiceError.invalidConfiguration("无法找到邮件所在文件夹")
        }
        
        // 如果已经有本地路径，直接返回
        if let localPath = attachment.localPath,
           FileManager.default.fileExists(atPath: localPath) {
            return URL(fileURLWithPath: localPath)
        }
        
        // 从服务器下载
        let fileURL = try await emailService.downloadAttachment(
            account: account,
            folder: folder,
            message: message,
            attachment: attachment
        )
        
        // 更新附件的本地路径
        var updatedAttachment = attachment
        updatedAttachment.localPath = fileURL.path
        
        var updatedMessage = message
        if let index = updatedMessage.attachments.firstIndex(where: { $0.id == attachment.id }) {
            updatedMessage.attachments[index] = updatedAttachment
            try await emailStore.updateMessage(updatedMessage)
            replaceMessageInList(with: updatedMessage)
        }
        
        return fileURL
    }
    
    /// 预览附件（打开文件）
    func previewAttachment(_ attachment: EmailAttachment, from message: EmailMessage) async {
        do {
            let fileURL = try await downloadAttachment(attachment, from: message)
            // 使用系统默认应用打开文件
            NSWorkspace.shared.open(fileURL)
        } catch {
            errorMessage = "打开附件失败: \(error.localizedDescription)"
            print("❌ [EmailViewModel] 预览附件失败: \(error)")
        }
    }
    
    // MARK: - Image Display Preferences
    
    /// 更新图片显示偏好
    /// - Parameters:
    ///   - message: 邮件消息
    ///   - show: 是否显示图片
    ///   - remember: 是否记住此选择
    func updateImageDisplayPreference(for message: EmailMessage, show: Bool, remember: Bool) {
        imageDisplayPreferences.setShowImages(show, for: message.from, remember: remember)
        showImages = show
        
        // 如果记住，也更新全局设置（作为默认值）
        if remember {
            preferences.emailShowImages = show
        }
    }
    
}

