//
//  EmailViewModel.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine
import SwiftUI
import AppKit
import UserNotifications
import UniformTypeIdentifiers

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
    
    // 多选模式相关状态
    @Published var isMultiSelectMode = false // 是否处于多选模式
    @Published var selectedMessageIds: Set<UUID> = [] // 选中的邮件ID集合
    
    @Published var isLoading = false // 邮件列表加载
    @Published var isLoadingFolders = false
    @Published var syncProgress: Double = 0.0
    @Published var syncStatus: String = ""
    
    @Published var searchText: String = ""
    @Published var searchResults: [EmailMessage] = [] // 搜索结果缓存
    @Published var showAttachments: Bool = false
    @Published var showImages: Bool = false
    
    @Published var errorMessage: String?
    @Published var isSendingReply = false // 正在发送回复
    @Published var isSendingCompose = false // 正在发送新邮件
    @Published var sendProgress: Double = 0.0 // 发送进度 0.0 - 1.0
    @Published var sendStatusText: String = "" // 发送状态文字
    
    // AI 美化相关状态
    @Published var isPolishingCompose = false // 正在美化新邮件
    @Published var isPolishingReply = false // 正在美化回复
    
    // AI HTML排版优化相关状态
    @Published var optimizingMessageIds: Set<UUID> = [] // 正在优化的邮件ID集合
    @Published var optimizedHTMLCache: [UUID: String] = [:] // 优化后的HTML缓存
    
    // 后台优化任务管理
    private var optimizationTasks: [UUID: Task<Void, Never>] = [:] // 优化任务字典
    
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
    private let threadService = EmailThreadService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // 防抖机制：避免短时间内多次排序
    private var updateMessagesTask: Task<Void, Never>?
    private let updateDebounceInterval: TimeInterval = 0.05 // 50ms防抖
    
    @Published var accounts: [EmailAccount] = []
    @Published var folders: [EmailFolder] = []
    @Published var messages: [EmailMessage] = []
    
    // 空文件夹显示控制
    @Published var showEmptyFolders = false // 默认隐藏空文件夹
    
    // 线程视图相关
    @Published var viewMode: ViewMode = .list
    @Published var threads: [EmailThread] = []
    @Published var selectedThreadId: UUID?
    
    enum ViewMode {
        case list  // 列表视图
        case thread // 线程视图
    }
    
    // 分页加载状态
    @Published var isLoadingMore = false
    @Published var hasMoreMessages = true
    private var currentPage = 0
    private let pageSize = 200 // 每页加载200封邮件（增加数量，避免误判）
    private var loadedDateRange: Date? // 已加载的最早邮件日期
    
    var currentAccount: EmailAccount? {
        guard let accountId = selectedAccountId else { return nil }
        return emailStore.getAccount(id: accountId)
    }
    
    var selectedMessage: EmailMessage? {
        guard let messageId = selectedMessageId else { return nil }
        if let folderId = selectedFolderId,
           let storeMessages = emailStore.messages[folderId],
           let storeMessage = storeMessages.first(where: { $0.id == messageId }) {
            return storeMessage
        }
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
                // 如果超级隐私模式开启，强制不显示图片
                if self.preferences.emailSuperPrivacyMode {
                    self.showImages = false
                    return
                }
                
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
        
        // 监听超级隐私模式变化
        preferences.$emailSuperPrivacyMode
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    // 如果开启超级隐私模式，强制不显示图片
                    self.showImages = false
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
        
        // 启动后台同步任务：持续加载每个文件夹的更多邮件
        startBackgroundSyncTask()
    }
    
    /// 后台同步任务：持续加载每个文件夹的更多邮件
    /// 
    /// 智能加载策略：
    /// - 每个文件夹加载到阈值（默认30封）后停止自动加载
    /// - 用户滚动到底部时触发加载更多
    /// - 可在设置中调整阈值或关闭此策略
    private func startBackgroundSyncTask() {
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            // 等待 App 完全启动后再开始同步
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5秒
            
            while !Task.isCancelled {
                // 每隔一段时间检查并加载更多邮件
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30秒间隔
                
                let accountId = await MainActor.run {
                    self.selectedAccountId
                }
                guard let accountId = accountId else {
                    continue
                }
                
                // 获取用户设置的加载策略
                let (threshold, stopAfterThreshold) = await MainActor.run {
                    (self.preferences.emailInitialLoadThreshold,
                     self.preferences.emailStopAutoSyncAfterThreshold)
                }
                
                let folders = await MainActor.run {
                    self.emailStore.getFolders(for: accountId)
                }
                
                print("🔄 [EmailViewModel] 后台同步：开始检查 \(folders.count) 个文件夹（阈值: \(threshold)，达到后停止: \(stopAfterThreshold)）...")
                
                // 为每个文件夹加载更多邮件
                for folder in folders {
                    // 检查当前内存中的邮件数量
                    let currentMessages = await MainActor.run {
                        self.emailStore.messages[folder.id] ?? []
                    }
                    
                    let currentCount = currentMessages.count
                    
                    // 智能加载策略：如果启用了阈值停止，且已达到阈值，则跳过自动加载
                    if stopAfterThreshold && currentCount >= threshold {
                        print("📊 [EmailViewModel] 后台同步：文件夹 \(folder.name) 已有 \(currentCount) 封邮件，达到阈值 \(threshold)，跳过自动加载")
                        continue
                    }
                    
                    // 如果内存中邮件少于阈值，尝试从数据库加载更多
                    if currentCount < threshold {
                        print("🔄 [EmailViewModel] 后台同步：文件夹 \(folder.name) 当前有 \(currentCount) 封，尝试加载更多...")
                        await self.emailStore.loadMessages(for: folder.id, forceLoadMore: true)
                    }
                    
                    // 再次检查加载后的数量
                    let afterLoadMessages = await MainActor.run {
                        self.emailStore.messages[folder.id] ?? []
                    }
                    let afterLoadCount = afterLoadMessages.count
                    
                    // 如果仍然少于阈值，尝试从服务器同步
                    if afterLoadCount < threshold {
                        let account = await MainActor.run {
                            self.currentAccount
                        }
                        guard let account = account else {
                            continue
                        }
                        
                        print("🔄 [EmailViewModel] 后台同步：文件夹 \(folder.name) 邮件较少（\(afterLoadCount)/\(threshold)），从服务器同步...")
                        
                        // 计算日期范围：从最旧的邮件往前推
                        let existing = await MainActor.run {
                            self.emailStore.messages[folder.id] ?? []
                        }
                        
                        let sinceDate: Date
                        if let earliestMessage = existing.min(by: { $0.date < $1.date }) {
                            sinceDate = Calendar.current.date(byAdding: .day, value: -365, to: earliestMessage.date) ?? Date.distantPast
                        } else {
                            sinceDate = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date.distantPast
                        }
                        
                        // 计算还需要加载多少封
                        let neededCount = threshold - afterLoadCount
                        let loadLimit = min(neededCount + 10, 200) // 多加载一点余量，但不超过200
                        
                        do {
                            let fetched = try await self.emailService.syncMessages(
                                account: account,
                                folder: folder,
                                since: sinceDate,
                                limit: loadLimit,
                                batchSize: 10
                            )
                            
                            if !fetched.isEmpty {
                                try await self.emailStore.addMessages(fetched, folderId: folder.id)
                                print("🔄 [EmailViewModel] 后台同步：文件夹 \(folder.name) 同步了 \(fetched.count) 封新邮件")
                            }
                        } catch {
                            print("❌ [EmailViewModel] 后台同步失败：\(folder.name) - \(error)")
                        }
                    }
                    
                    // 短暂延迟，避免一次性加载太多
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒
                }
                
                print("🔄 [EmailViewModel] 后台同步：本轮完成")
            }
        }
    }
    
    /// 从 EmailStore 更新邮件列表（终极优化，零卡顿）
    /// - Parameter preserveHasMore: 如果为 true，不覆盖 hasMoreMessages 状态（用于加载更多模式）
    private func updateMessagesFromStore(preserveHasMore: Bool = false) async {
        guard let folderId = selectedFolderId else {
            await updateMessagesForAllFolders(preserveHasMore: preserveHasMore)
            return
        }
        
        // 快速读取数据（在主线程，极快）
        let allMessages = emailStore.messages[folderId] ?? []
        let currentPageValue = currentPage
        let pageSizeValue = pageSize
        
        // 统一在后台线程处理去重和排序（无论数据量大小，确保零卡顿）
        print("📊 [EmailViewModel] 开始后台处理邮件，数量: \(allMessages.count)")
        let sortStart = Date()
        
        let processedMessages = await Task.detached(priority: .userInitiated) {
            // 先去重：按 Message-ID 去重，避免同一封邮件在同一文件夹中有多个副本
            var seen = Set<String>()
            var deduplicated: [EmailMessage] = []
            for msg in allMessages {
                // 生成去重键：优先使用 Message-ID，否则使用 (subject, from.email, date) 组合
                let key: String
                if let mid = msg.messageId, !mid.isEmpty {
                    key = mid
                } else {
                    key = "\(msg.subject)|\(msg.from.email)|\(msg.date.timeIntervalSince1970)"
                }
                if seen.insert(key).inserted {
                    deduplicated.append(msg)
                }
            }
            
            // 排序
            let sorted = deduplicated.sorted { $0.date > $1.date }
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
        // 只有在非加载更多模式下才更新 hasMoreMessages
        // 加载更多时由 loadMoreMessagesFromDatabase 来决定是否还有更多
        if !preserveHasMore {
        hasMoreMessages = processedMessages.hasMore
        }
    }
    
    /// 为邮件生成去重键
    /// - Parameter message: 邮件消息
    /// - Returns: 去重键，优先使用 Message-ID，否则使用 (subject, from.email, date) 组合
    private func deduplicationKey(for message: EmailMessage) -> String {
        if let mid = message.messageId, !mid.isEmpty {
            return mid
        }
        return "\(message.subject)|\(message.from.email)|\(message.date.timeIntervalSince1970)"
    }
    
    /// 更新所有文件夹的邮件（完全异步）
    /// - Parameter preserveHasMore: 如果为 true，不覆盖 hasMoreMessages 状态（用于加载更多模式）
    private func updateMessagesForAllFolders(preserveHasMore: Bool = false) async {
        // 快速读取必要数据（注意：这里已经在 MainActor 上下文中）
        let accountId = selectedAccountId
        let currentPageValue = currentPage
        let pageSizeValue = pageSize
        
        guard let accountId = accountId else {
            messages = []
            if !preserveHasMore {
            hasMoreMessages = false
            }
            return
        }
        
        // 读取文件夹和邮件
        let foldersForAccount = emailStore.getFolders(for: accountId)
        let allFolderMessages = emailStore.messages
        
        print("📊 [EmailViewModel] 开始合并所有文件夹的邮件，文件夹数: \(foldersForAccount.count)")
        let mergeStart = Date()
        
        // 在后台线程处理合并和排序
        let processedMessages = await Task.detached(priority: .userInitiated) {
            // 合并所有文件夹的邮件，并去重
            var seen = Set<String>()
            var combined: [EmailMessage] = []
            for folder in foldersForAccount {
                if let folderMsgs = allFolderMessages[folder.id] {
                    for msg in folderMsgs {
                        // 生成去重键：优先使用 Message-ID，否则使用 (subject, from.email, date) 组合
                        let key: String
                        if let mid = msg.messageId, !mid.isEmpty {
                            key = mid
                        } else {
                            key = "\(msg.subject)|\(msg.from.email)|\(msg.date.timeIntervalSince1970)"
                        }
                        if seen.insert(key).inserted {
                            combined.append(msg)
                        }
                    }
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
        // 只有在非加载更多模式下才更新 hasMoreMessages
        // 加载更多时由 loadMoreMessagesFromDatabase 来决定是否还有更多
        if !preserveHasMore {
        hasMoreMessages = processedMessages.hasMore
        }
    }
    
    private func aggregatedMessagesForCurrentAccount() -> [EmailMessage] {
        guard let accountId = selectedAccountId else { return [] }
        let foldersForAccount = emailStore.getFolders(for: accountId)
        // 合并所有文件夹的邮件，并去重
        var seen = Set<String>()
        var combined: [EmailMessage] = []
        for folder in foldersForAccount {
            if let folderMsgs = emailStore.messages[folder.id] {
                for msg in folderMsgs {
                    let key = deduplicationKey(for: msg)
                    if seen.insert(key).inserted {
                        combined.append(msg)
                    }
                }
            }
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
            // 确保存在“本地已发送”文件夹，用于存放本机发出的邮件
            try await emailStore.ensureLocalSentFolder(for: account.id)
            
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
    
    /// 删除文件夹（仅限空文件夹）
    func deleteFolder(_ folder: EmailFolder) async {
        // 检查文件夹是否为空
        let messageCount = emailStore.getMessageCount(for: folder.id)
        guard messageCount == 0 else {
            errorMessage = "无法删除非空文件夹"
            return
        }
        
        do {
            try await emailStore.deleteFolder(folder)
            
            // 如果删除的是当前选中的文件夹，清除选择
            if selectedFolderId == folder.id {
                selectedFolderId = nil
                await updateMessagesFromStore()
            }
            
            print("✅ [EmailViewModel] 文件夹已删除: \(folder.name)")
        } catch {
            errorMessage = "删除文件夹失败: \(error.localizedDescription)"
            print("❌ [EmailViewModel] 删除文件夹失败: \(error)")
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
                // preserveHasMore: true 确保不会覆盖 hasMoreMessages 状态
                await updateMessagesFromStore(preserveHasMore: true)
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
                // 加载更多时，获取当前已加载邮件中最旧的日期，然后往前加载
                let existing = emailStore.messages[folderId] ?? []
                if let earliestMessage = existing.min(by: { $0.date < $1.date }) {
                    // 从最旧的邮件日期往前推，加载更早的邮件
                    sinceDate = Calendar.current.date(byAdding: .day, value: -60, to: earliestMessage.date)
                    print("📥 [EmailViewModel] 加载更多：从 \(earliestMessage.date) 往前加载更早的邮件")
                } else {
                    // 如果没有已加载的邮件，使用当前日期往前推
                    sinceDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())
                }
            } else {
                sinceDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())
            }
            loadedDateRange = sinceDate
            
            // 加载更多时，使用更大的 limit 以确保能加载到足够的邮件
            // 同时不限制日期范围，或者使用更大的日期范围
            let loadLimit = loadMore ? 200 : pageSize
            let actualSinceDate = loadMore ? nil : sinceDate // 加载更多时不限制日期范围
            
            print("📥 [EmailViewModel] 开始同步邮件: \(folder.name), loadMore: \(loadMore), limit: \(loadLimit)")
            let startTime = Date()
            
            // 在后台线程执行网络请求，避免阻塞 UI
            let fetched = try await Task.detached(priority: .userInitiated) { [emailService, account, folder, actualSinceDate, loadLimit] in
                return try await emailService.syncMessages(
                    account: account,
                    folder: folder,
                    since: actualSinceDate,
                    limit: loadLimit,
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
                
                // 更新 hasMoreMessages 状态
                // 对于 loadMore 模式，我们需要更智能的判断：
                // 1. 如果返回的邮件数量 >= loadLimit，说明可能还有更多
                // 2. 如果返回的邮件数量 < loadLimit，需要检查是否真的没有更多了
                //    可以通过检查返回的邮件中是否有比已加载邮件更早的来判断
                if loadMore {
                    // 加载更多模式：检查返回的邮件是否比已加载的最早邮件更早
                    let existing = emailStore.messages[folderId] ?? []
                    if existing.min(by: { $0.date < $1.date }) != nil,
                       fetched.min(by: { $0.date < $1.date }) != nil {
                        // 如果返回的邮件中有比已加载邮件更早的，说明可能还有更多
                        // 如果返回的邮件都比已加载的邮件新，说明可能已经到顶了
                        // 但为了保险起见，如果返回数量 >= loadLimit，仍然认为可能还有更多
                        if fetched.count >= loadLimit {
                            hasMoreMessages = true
                            print("📄 [EmailViewModel] 加载更多：返回 \(fetched.count) 封，可能还有更多")
                        } else {
                            // 返回数量 < loadLimit，且没有更早的邮件，可能没有更多了
                            // 但为了保险，我们仍然保持 hasMoreMessages = true，让用户再试一次
                            hasMoreMessages = true
                            print("📄 [EmailViewModel] 加载更多：返回 \(fetched.count) 封，可能已到底，但保持可加载状态")
                        }
                    } else {
                        // 无法比较，保守处理：如果返回数量 >= loadLimit，认为可能还有更多
                        hasMoreMessages = fetched.count >= loadLimit
                        print("📄 [EmailViewModel] 加载更多：返回 \(fetched.count) 封，hasMoreMessages=\(fetched.count >= loadLimit)")
                    }
                } else {
                    // 首次加载模式：如果返回数量 < pageSize，说明可能没有更多了
                    if fetched.count < pageSize {
                        hasMoreMessages = false
                        print("📄 [EmailViewModel] 首次加载：返回 \(fetched.count) 封，少于 pageSize \(pageSize)，可能没有更多")
                    } else {
                        hasMoreMessages = true
                        print("📄 [EmailViewModel] 首次加载：返回 \(fetched.count) 封，可能还有更多")
                    }
                }
                
                // 建立线程关系（后台执行）
                Task.detached(priority: .background) { [weak self] in
                    guard let self else { return }
                    for message in fetched {
                        // 尝试建立线程关系
                        if let threadId = try? await threadService.buildThreadRelationship(for: message) {
                            // 更新消息的threadId
                            var updated = message
                            updated.threadId = threadId.uuidString
                            try? await emailStore.updateMessage(updated)
                        }
                    }
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
            } else {
                // 没有获取到任何邮件
                if loadMore {
                    // 加载更多时没有获取到邮件，说明没有更多了
                    hasMoreMessages = false
                    print("📄 [EmailViewModel] 加载更多时未获取到邮件，已加载所有邮件")
                } else {
                    // 首次加载时没有邮件，可能真的没有邮件，也可能需要继续尝试
                    // 这里设置为 false，因为如果真的有邮件，后续加载会更新这个状态
                    hasMoreMessages = false
                    print("📄 [EmailViewModel] 首次加载未获取到邮件")
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            print("❌ [EmailViewModel] 加载邮件失败: \(error)")
            // 加载失败时，不改变 hasMoreMessages 状态，允许重试
        }
        
        isLoading = false
        isLoadingMore = false
    }
    
    /// 加载更多邮件（滚动到底部时调用）
    func loadMoreMessages() {
        // 防止重复调用
        guard !isLoadingMore && hasMoreMessages else {
            print("📄 [EmailViewModel] loadMoreMessages 跳过：isLoadingMore=\(isLoadingMore), hasMoreMessages=\(hasMoreMessages)")
            return
        }
        
        if selectedFolderId == nil {
            // "所有邮件"视图：从数据库加载更多
            isLoadingMore = true
            currentPage += 1
            
            Task {
                // 先尝试从内存更新（这会更新显示的邮件列表）
                // preserveHasMore: true 确保不会因为内存中没有更多邮件而把 hasMoreMessages 设为 false
                await updateMessagesFromStore(preserveHasMore: true)
                
                // 尝试从数据库加载更多邮件
                // loadMoreMessagesFromDatabase 会正确设置 hasMoreMessages 状态
                    await loadMoreMessagesFromDatabase()
                
                isLoadingMore = false
            }
            return
        }
        
        // 单个文件夹视图：从服务器加载更多
        isLoadingMore = true
        Task {
            await loadMessagesAsync(loadMore: true)
        }
    }
    
    /// 后台加载所有文件夹的更多邮件（用于应用空闲时预加载）
    func loadMoreMessagesForAllFoldersInBackground() {
        guard let accountId = selectedAccountId,
              currentAccount != nil else { return }
        
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            let foldersForAccount = await MainActor.run {
                self.emailStore.getFolders(for: accountId)
            }
            
            print("🔄 [EmailViewModel] 开始后台加载所有文件夹的更多邮件，文件夹数: \(foldersForAccount.count)")
            
            // 为每个文件夹加载更多邮件（不更新UI，静默加载）
            for folder in foldersForAccount {
                // 检查当前内存中该文件夹的邮件数量
                let existingCount = await MainActor.run {
                    self.emailStore.messages[folder.id]?.count ?? 0
                }
                
                // 如果内存中已经有足够多的邮件（比如500封），跳过
                if existingCount >= 500 {
                    continue
                }
                
                print("📥 [EmailViewModel] 后台加载文件夹 \(folder.name) 的更多邮件...")
                
                // 从服务器加载更多邮件（不更新UI）
                await self.loadMessagesAsync(
                    loadMore: true,
                    folderIdOverride: folder.id,
                    affectsCurrentList: false
                )
                
                // 稍微延迟，避免对服务器造成太大压力
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            }
            
            print("✅ [EmailViewModel] 后台加载所有文件夹的更多邮件完成")
        }
    }
    
    /// 从数据库加载更多邮件（用于"所有邮件"视图）
    private func loadMoreMessagesFromDatabase() async {
        guard let accountId = selectedAccountId else { return }
        
        let foldersForAccount = await MainActor.run {
            emailStore.getFolders(for: accountId)
        }
        
        var totalLoaded = 0
        
        // 从所有文件夹加载更多邮件
        for folder in foldersForAccount {
            let existingMessages = await MainActor.run {
                emailStore.messages[folder.id] ?? []
            }
            
            let beforeCount = existingMessages.count
            
            if existingMessages.isEmpty {
                // 如果内存中没有该文件夹的邮件，从数据库加载
                await emailStore.loadMessages(for: folder.id)
            } else {
                // 如果内存中已有邮件，强制加载更多（追加到现有列表）
                await emailStore.loadMessages(for: folder.id, forceLoadMore: true)
            }
            
            // 检查加载后是否有新增邮件
            let afterMessages = await MainActor.run {
                emailStore.messages[folder.id] ?? []
            }
            let afterCount = afterMessages.count
            let loaded = afterCount - beforeCount
            
            totalLoaded += loaded
        }
        
        // 计算 hasMoreMessages 状态
        // 改进逻辑：只要加载到了邮件，就认为可能还有更多
        // 只有当所有文件夹都没有加载到新邮件时，才认为没有更多了
        let newHasMore: Bool
        if totalLoaded == 0 {
            // 没有加载到任何新邮件，说明数据库中没有更多了
            // 但可能服务器上还有，所以尝试从服务器加载
            newHasMore = true // 保持为 true，让用户可以尝试从服务器加载
            print("📄 [EmailViewModel] 从数据库加载更多邮件完成，无新邮件，但可能服务器上还有，保持 hasMoreMessages = true")
        } else {
            // 加载到了邮件，肯定还有更多（数据库或服务器上）
            newHasMore = true
            print("📄 [EmailViewModel] 从数据库加载更多邮件完成，加载了 \(totalLoaded) 封，可能还有更多")
        }
        
        // 重新更新邮件列表（使用 preserveHasMore 避免覆盖我们刚计算的状态）
        await updateMessagesFromStore(preserveHasMore: true)
        
        // 最后设置 hasMoreMessages
        await MainActor.run {
            hasMoreMessages = newHasMore
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
        selectedFolderId = folder.id
        selectedMessageId = nil
        currentPage = 0
        hasMoreMessages = true
        loadedDateRange = nil
        
        // 2. 立即从缓存读取并显示（同步读取，极快，但需要去重）
        let cachedMessages = emailStore.messages[folder.id] ?? []
        if !cachedMessages.isEmpty {
            // 有缓存，立即显示（需要去重）
            // 使用与 updateMessagesFromStore 相同的去重逻辑
            var seen = Set<String>()
            var deduplicated: [EmailMessage] = []
            for msg in cachedMessages {
                // 生成去重键：优先使用 Message-ID，否则使用 (subject, from.email, date) 组合
                let key: String
                if let mid = msg.messageId, !mid.isEmpty {
                    key = mid
                } else {
                    key = "\(msg.subject)|\(msg.from.email)|\(msg.date.timeIntervalSince1970)"
                }
                if seen.insert(key).inserted {
                    deduplicated.append(msg)
                }
            }
            let sorted = deduplicated.sorted { $0.date > $1.date }
            messages = Array(sorted.prefix(pageSize))
            isLoading = false
            print("📂 [EmailViewModel] 立即显示缓存（已去重）: \(messages.count) 封邮件，原始: \(cachedMessages.count) 封，耗时: \(String(format: "%.3f", Date().timeIntervalSince(startTime) * 1000))ms")
        } else {
            // 无缓存，保留当前数据避免闪动，显示loading状态
            isLoading = true
            // 不立即清空 messages，保留当前数据直到新数据加载完成
            print("📂 [EmailViewModel] 无缓存，保留当前数据，显示loading")
        }
        
        // 3. 后台加载数据库缓存（如果内存缓存为空）
        if cachedMessages.isEmpty {
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                
                // 从数据库加载
                await self.emailStore.loadMessages(for: folder.id)
                
                // 更新显示（会执行去重）
                await self.updateMessagesFromStore()
                
                await MainActor.run {
                    self.isLoading = false
                    let elapsed = Date().timeIntervalSince(startTime)
                    print("📂 [EmailViewModel] 数据库加载完成，耗时: \(String(format: "%.3f", elapsed * 1000))ms")
                }
            }
        } else {
            // 即使有缓存，也异步调用一次 updateMessagesFromStore 确保去重逻辑一致
            // 这样可以处理缓存中可能存在的重复邮件
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                // 延迟一点，确保UI先更新
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05秒
                await self.updateMessagesFromStore()
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
            // 初始显示时，如果内存中的邮件不够一页，仍然设置 hasMoreMessages = true
            // 让用户可以尝试从数据库加载更多邮件
            // 只有 loadMoreMessagesFromDatabase 确认没有更多邮件时才设为 false
            if messages.count >= pageSize {
                // 如果已经显示了足够多的邮件，让 updateMessagesFromStore 的结果决定
            } else {
                // 如果显示的邮件少于一页，保持 hasMoreMessages = true
                // 因为数据库中可能还有更多邮件没有加载到内存
                hasMoreMessages = true
            }
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
    /// 选择线程
    func selectThread(_ threadId: UUID) {
        selectedThreadId = threadId
        selectedMessageId = nil
    }
    
    /// 加载线程列表
    func loadThreads() async {
        guard let accountId = selectedAccountId else {
            threads = []
            return
        }
        
        do {
            threads = try await threadService.getThreads(for: accountId)
        } catch {
            print("❌ [EmailViewModel] 加载线程失败: \(error)")
            errorMessage = "加载线程失败: \(error.localizedDescription)"
        }
    }
    
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
            
            // 只在加载正文后才触发 AI 分析，避免滚动时自动触发数据库写入
            // 这样可以避免在滚动列表时因为选择邮件而触发大量数据库操作
            if needsBodyLoad {
                Task {
                    await self.loadMessageBody(currentMessage)
                    
                    // 正文加载完成后，再检查是否需要 AI 分析（仅在正文已加载时）
                    // 这样可以确保 AI 分析只在用户真正查看邮件时触发
                    let updatedMessage = self.messages.first(where: { $0.id == currentMessage.id }) ?? currentMessage
                    // 如果超级隐私模式开启，不进行 AI 分析
                    let needsAIAnalysis = !self.preferences.emailSuperPrivacyMode &&
                                         ((self.preferences.emailAISmartTaggingEnabled && updatedMessage.aiTags.isEmpty) ||
                                          (self.preferences.emailAISummaryEnabled && updatedMessage.aiSummary == nil) ||
                                          (self.preferences.emailAIPriorityDetectionEnabled && updatedMessage.aiPriority == nil))
                    
                    if needsAIAnalysis && updatedMessage.isBodyLoaded {
                        // 在后台线程执行 AI 分析，不阻塞 UI
                        Task.detached(priority: .background) { [weak self] in
                            guard let self = self else { return }
                            await self.analyzeMessageWithAI(updatedMessage)
                        }
                    }
                }
            }
            // 注意：如果正文已加载，我们也不立即触发 AI 分析
            // 只有在用户明确查看邮件详情时才会触发（通过其他机制，如手动请求）
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
                // 优先从 emailStore 获取文件夹（确保使用正确的数据库ID）
                let folder = emailStore.getFolders(for: account.id).first { $0.id == folderId }
                    ?? folders.first { $0.id == folderId }
                
                guard let validFolder = folder else {
                    print("⚠️ [EmailViewModel] 无法找到文件夹: \(folderId)")
                    isLoading = false
                    return
                }
                
                let messages = try await emailService.syncMessages(
                    account: account,
                    folder: validFolder,
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
        
        let startTime = Date()
        let messageId = message.id.uuidString
        let uid = message.uid ?? 0
        let hasCachedBody = (message.textBody?.isEmpty == false) || (message.htmlBody?.isEmpty == false) || message.isBodyLoaded
        print("⏱ [EmailViewModel] loadMessageBody 开始: subject=\(message.subject), uid=\(uid), id=\(messageId), cached=\(hasCachedBody)")
        
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
                let totalElapsed = Date().timeIntervalSince(startTime) * 1000
                print("⏱ [EmailViewModel] loadMessageBody 缓存命中: \(String(format: "%.1f", totalElapsed))ms, uid=\(uid), id=\(messageId)")
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
            let fetchStart = Date()
            let content = try await emailService.fetchMessageBody(
                account: account,
                folder: folder,
                message: message
            )
            let fetchElapsed = Date().timeIntervalSince(fetchStart) * 1000
            print("⏱ [EmailViewModel] fetchMessageBody 耗时: \(String(format: "%.1f", fetchElapsed))ms, uid=\(uid), id=\(messageId)")
            
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
            
            // 先同步更新 EmailStore 内存，再返回，避免用户切换文件夹再切回时从 Store 读到未含正文的邮件而重复显示「正在加载正文」
            do {
                try await self.emailStore.updateMessage(updated)
                print("✅ [EmailViewModel] 邮件正文已写入 EmailStore，folderId: \(updated.folderId?.uuidString ?? "nil")")
            } catch {
                print("⚠️ [EmailViewModel] 更新邮件正文到 Store 失败: \(error)")
            }
            
            // 如果没有 textBody，在后台线程从 HTML 提取纯文本（用于搜索等功能）
            if content.textBody == nil, let htmlBody = content.htmlBody, !htmlBody.isEmpty {
                Task.detached(priority: .background) { [weak self] in
                    guard let self = self else { return }
                    let plainText = await MainActor.run {
                        htmlBody.strippingHTML()
                    }
                    await MainActor.run {
                        // 更新 textBody（用于搜索）
                        if var msg = self.messages.first(where: { $0.id == updated.id }) {
                            msg.textBody = plainText
                            self.replaceMessageInList(with: msg)
                        }
                    }
                }
            }
            
            let totalElapsed = Date().timeIntervalSince(startTime) * 1000
            print("⏱ [EmailViewModel] loadMessageBody 完成: \(String(format: "%.1f", totalElapsed))ms, uid=\(uid), id=\(messageId)")
        } catch {
            print("❌ [EmailViewModel] 加载正文失败: \(error)")
            errorMessage = "加载正文失败: \(error.localizedDescription)"
        }
    }
    
    /// 标记为已读
    func markAsRead(_ message: EmailMessage) async {
        guard let account = currentAccount else { return }
        
        // 获取邮件所在的文件夹
        let folderId = message.folderId ?? selectedFolderId
        guard let id = folderId,
              let folder = folder(for: id) else {
            print("⚠️ [EmailViewModel] markAsRead: 无法获取邮件所在文件夹")
            return
        }
        
        do {
            try await emailService.markAsRead(account: account, folder: folder, message: message)
            
            // 重要：从 emailStore 获取最新的邮件数据（包含正文缓存）
            // 避免用没有正文的邮件对象覆盖数据库中已缓存的正文
            var updated = message
            if let folderId = message.folderId,
               let storeMessages = emailStore.messages[folderId],
               let latestMessage = storeMessages.first(where: { $0.id == message.id }) {
                updated = latestMessage
                print("✅ [EmailViewModel] markAsRead: 使用 EmailStore 中的最新邮件数据（保留正文缓存）")
            } else {
                print("⚠️ [EmailViewModel] markAsRead: 未找到 EmailStore 中的邮件，使用传入的邮件对象")
            }
            
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
                // 使用返回的文件夹（带有正确的数据库ID）
                let savedFolder = try await emailStore.addFolder(folder)
                
                let messages = try await emailService.syncMessages(
                    account: account,
                    folder: savedFolder,
                    since: nil
                )
                try await emailStore.addMessages(messages, folderId: savedFolder.id)
                
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
    /// 先搜索本地缓存，如果结果不足或用户明确要求，再搜索服务端
    private func performSearch(query: String) {
        // 取消之前的搜索任务
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        let lowercasedQuery = query.lowercased()
        let messagesToSearch = messages // 复制当前消息列表，避免并发问题
        let account = currentAccount
        let selectedFolderIdValue = selectedFolderId
        
        // 后台执行搜索
        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // 检查是否被取消
            guard !Task.isCancelled else { return }
            
            // 先搜索本地缓存
            var localResults = messagesToSearch.filter { message in
                message.subject.lowercased().contains(lowercasedQuery) ||
                message.from.email.lowercased().contains(lowercasedQuery) ||
                (message.from.name?.lowercased().contains(lowercasedQuery) ?? false) ||
                message.preview.lowercased().contains(lowercasedQuery) ||
                (message.textBody?.lowercased().contains(lowercasedQuery) ?? false)
            }
            
            // 检查是否被取消（搜索过程中）
            guard !Task.isCancelled else { return }
            
            // 如果本地结果少于 20 条，或者查询长度 >= 3 个字符，尝试服务端搜索
            let shouldSearchServer = localResults.count < 20 && query.count >= 3
            
            if shouldSearchServer, let account = account {
                // 从服务端搜索
                do {
                    // 在主线程获取文件夹信息
                    let folder: EmailFolder? = await MainActor.run {
                        if let folderId = selectedFolderIdValue {
                            return self.folder(for: folderId)
                        }
                        return nil
                    }
                    
                    if let folder = folder {
                        // 搜索指定文件夹
                        let serverResults = try await emailService.searchMessages(
                            account: account,
                            folder: folder,
                            query: query,
                            limit: 100
                        )
                        
                        // 合并结果，去重
                        var allResults = localResults
                        let localIds = Set(localResults.map { $0.id })
                        for serverMsg in serverResults {
                            if !localIds.contains(serverMsg.id) {
                                allResults.append(serverMsg)
                            }
                        }
                        localResults = allResults
                    } else {
                        // 搜索所有文件夹（"所有邮件"视图）
                        let folders = await MainActor.run {
                            self.emailStore.getFolders(for: account.id)
                        }
                        var allServerResults: [EmailMessage] = []
                        
                        for folder in folders.prefix(10) { // 限制搜索前10个文件夹，避免太慢
                            guard !Task.isCancelled else { break }
                            
                            do {
                                let folderResults = try await emailService.searchMessages(
                                    account: account,
                                    folder: folder,
                                    query: query,
                                    limit: 50
                                )
                                allServerResults.append(contentsOf: folderResults)
                            } catch {
                                print("⚠️ [EmailViewModel] 搜索文件夹 \(folder.name) 失败: \(error)")
                            }
                        }
                        
                        // 合并结果，去重
                        var allResults = localResults
                        let localIds = Set(localResults.map { $0.id })
                        for serverMsg in allServerResults {
                            if !localIds.contains(serverMsg.id) {
                                allResults.append(serverMsg)
                            }
                        }
                        localResults = allResults
                    }
                } catch {
                    print("⚠️ [EmailViewModel] 服务端搜索失败: \(error)，仅使用本地结果")
                }
            }
            
            // 检查是否被取消（搜索过程中）
            guard !Task.isCancelled else { return }
            
            // 按日期排序（最新的在前）
            let sortedResults = localResults.sorted { $0.date > $1.date }
            
            // 更新结果到主线程
            await MainActor.run {
                self.searchResults = sortedResults
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
        
        // 如果超级隐私模式开启，强制不发送读回执
        let shouldSendReadReceipt = preferences.emailSuperPrivacyMode ? false : preferences.emailReadReceiptEnabled
        
        try await emailService.sendMessage(
            account: account,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            body: body,
            htmlBody: htmlBody,
            attachments: attachments,
            readReceipt: shouldSendReadReceipt
        )
    }
    
    /// 使用AI分析邮件
    func analyzeMessageWithAI(_ message: EmailMessage) async {
        // 如果超级隐私模式开启，不发送邮件内容给 AI
        if preferences.emailSuperPrivacyMode {
            print("🔒 [EmailViewModel] 超级隐私模式已启用，跳过 AI 分析")
            return
        }
        
        do {
            // 在主线程一次性获取所有需要的配置和数据，避免多次切换
            let (currentMessage, needsTagging, needsPriority, needsSummary, config, prefs) = await MainActor.run {
                let msg = messages.first(where: { $0.id == message.id }) ?? message
                let tagging = preferences.emailAISmartTaggingEnabled && msg.aiTags.isEmpty
                let priority = preferences.emailAIPriorityDetectionEnabled && msg.aiPriority == nil
                let summary = preferences.emailAISummaryEnabled && msg.aiSummary == nil
                let aiConfig = preferences.getConfig(for: .aiChat)
                return (msg, tagging, priority, summary, aiConfig, preferences)
            }
            
            var updated = currentMessage
            
            print("🤖 [EmailViewModel] AI分析邮件: \(updated.subject), hasBody=\(updated.isBodyLoaded), htmlBody长度=\(updated.htmlBody?.count ?? 0)")
            
            // 在后台线程执行AI请求，传递已获取的配置，避免再次切换到主线程
            // 生成标签（如果启用）
            if needsTagging {
                let tags = try await emailAIService.generateSmartTags(for: currentMessage, config: config, preferences: prefs)
                updated.aiTags = tags
            }
            
            // 检测优先级（如果启用）
            if needsPriority {
                let priority = try await emailAIService.detectPriority(for: currentMessage, config: config, preferences: prefs)
                updated.aiPriority = priority
            }
            
            // 生成摘要（如果启用）
            if needsSummary {
                let summary = try await emailAIService.generateSummary(for: currentMessage, config: config, preferences: prefs)
                updated.aiSummary = summary
            }
            
            print("🤖 [EmailViewModel] AI分析完成，更新邮件: hasBody=\(updated.isBodyLoaded), htmlBody长度=\(updated.htmlBody?.count ?? 0)")
            
            // 保存到数据库（后台线程）
            try await emailStore.updateMessage(updated)
            
            // 在主线程更新UI
            await MainActor.run {
                replaceMessageInList(with: updated)
            }
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
    
    /// 发送新邮件（从撰写窗口调用）
    func sendComposeMessage(
        account: EmailAccount,
        to: [EmailContact],
        cc: [EmailContact] = [],
        bcc: [EmailContact] = [],
        subject: String,
        body: String,
        htmlBody: String? = nil
    ) async throws {
        // 更新草稿
        var draft = composeDraft ?? ReplyDraft()
        draft.to = to
        draft.cc = cc
        draft.bcc = bcc
        draft.subject = subject
        draft.body = body
        draft.htmlBody = htmlBody
        composeDraft = draft
        
        // 发送
        try await sendCompose()
    }
    
    /// 发送回复（从撰写窗口调用）
    func sendReplyMessage(
        account: EmailAccount,
        originalMessage: EmailMessage,
        to: [EmailContact],
        cc: [EmailContact] = [],
        bcc: [EmailContact] = [],
        subject: String,
        body: String,
        htmlBody: String? = nil,
        replyType: ReplyDraft.ReplyType = .reply
    ) async throws {
        // 初始化回复草稿
        initReplyDraft(for: originalMessage, type: replyType)
        
        // 更新草稿
        var draft = replyDraft ?? ReplyDraft()
        draft.to = to
        draft.cc = cc
        draft.bcc = bcc
        draft.subject = subject
        draft.body = body
        draft.htmlBody = htmlBody
        replyDraft = draft
        
        // 发送
        try await sendReply()
    }
    
    /// 标记邮件为已回复
    func markMessageAsReplied(messageId: UUID) async {
        guard let message = messages.first(where: { $0.id == messageId }) else {
            print("⚠️ [EmailViewModel] 未找到要标记的邮件: \(messageId)")
            return
        }
        
        var updated = message
        updated.hasBeenReplied = true
        
        do {
            try await emailStore.updateMessage(updated)
            print("✅ [EmailViewModel] 邮件已标记为已回复: \(message.subject)")
        } catch {
            print("❌ [EmailViewModel] 标记邮件失败: \(error)")
        }
    }
    
    // MARK: - AI Polish
    
    /// 切分回复正文，分离用户撰写部分和引用部分
    private func splitReplyBody(_ body: String) -> (userPart: String, quotedPart: String) {
        // 常见的引用分隔符模式
        let separators = [
            "\n\n--- 原始邮件 ---",
            "\n\n--- 转发邮件 ---",
            "\n\n在 ",
            "\n\n> ",
            "\n\nOn ",
            "\n\nFrom:",
            "\n\n发件人:"
        ]
        
        // 查找第一个匹配的分隔符
        for separator in separators {
            if let range = body.range(of: separator) {
                let userPart = String(body[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let quotedPart = String(body[range.lowerBound...])
                return (userPart, quotedPart)
            }
        }
        
        // 如果没有找到分隔符，检查是否有以 ">" 开头的行（常见引用格式）
        let lines = body.components(separatedBy: .newlines)
        var userLines: [String] = []
        var quotedLines: [String] = []
        var foundQuotedStart = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") || trimmed.hasPrefix("|") {
                foundQuotedStart = true
                quotedLines.append(line)
            } else if foundQuotedStart {
                quotedLines.append(line)
            } else {
                userLines.append(line)
            }
        }
        
        if !quotedLines.isEmpty {
            let userPart = userLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let quotedPart = quotedLines.joined(separator: "\n")
            return (userPart, quotedPart)
        }
        
        // 如果都没有找到，返回整个正文作为用户部分
        return (body, "")
    }
    
    /// AI 美化新邮件草稿（支持选中文本）
    func aiPolishComposeDraft(mode: EmailAIService.PolishMode, selectedText: String? = nil, selectedRange: NSRange? = nil) async -> String? {
        guard var draft = composeDraft else {
            errorMessage = "没有正在编写的邮件"
            return nil
        }
        
        let originalBody = draft.body
        
        // 如果有选中文本，只美化选中部分
        if let selectedText = selectedText, !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let selectedRange = selectedRange else {
                errorMessage = "选中范围无效"
                return nil
            }
            
            isPolishingCompose = true
            errorMessage = nil
            
            do {
                let polishedSelection = try await emailAIService.polishEmailBody(text: selectedText, mode: mode)
                
                // 替换选中部分
                let nsString = originalBody as NSString
                let newBody = nsString.replacingCharacters(in: selectedRange, with: polishedSelection)
                
                draft.body = newBody
                composeDraft = draft
                print("✅ [EmailViewModel] AI 美化选中文本成功")
                isPolishingCompose = false
                return newBody
            } catch {
                errorMessage = "AI 美化失败: \(error.localizedDescription)"
                print("❌ [EmailViewModel] AI 美化选中文本失败: \(error)")
                isPolishingCompose = false
                return nil
            }
        }
        
        // 美化整个正文
        let trimmedBody = originalBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            errorMessage = "正文内容为空，无法美化"
            return nil
        }
        
        isPolishingCompose = true
        errorMessage = nil
        
        do {
            let polishedBody = try await emailAIService.polishEmailBody(text: trimmedBody, mode: mode)
            draft.body = polishedBody
            composeDraft = draft
            print("✅ [EmailViewModel] AI 美化新邮件成功")
            isPolishingCompose = false
            return polishedBody
        } catch {
            errorMessage = "AI 美化失败: \(error.localizedDescription)"
            print("❌ [EmailViewModel] AI 美化新邮件失败: \(error)")
            isPolishingCompose = false
            return nil
        }
    }
    
    /// AI 美化回复草稿（支持选中文本）
    func aiPolishReplyDraft(mode: EmailAIService.PolishMode, selectedText: String? = nil, selectedRange: NSRange? = nil) async -> String? {
        guard var draft = replyDraft else {
            errorMessage = "没有正在回复的邮件"
            return nil
        }
        
        let originalBody = draft.body
        
        // 如果有选中文本，检查选中部分是否在引用区域内
        if let selectedText = selectedText, !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let selectedRange = selectedRange else {
                errorMessage = "选中范围无效"
                return nil
            }
            
            // 检查选中部分是否包含引用内容
            let (userPart, quotedPart) = splitReplyBody(originalBody)
            
            // 如果选中范围与引用部分重叠，不允许美化
            if !quotedPart.isEmpty && selectedRange.location + selectedRange.length > userPart.count {
                errorMessage = "不能美化引用内容，请只选择您撰写的部分"
                return nil
            }
            
            isPolishingReply = true
            errorMessage = nil
            
            do {
                let polishedSelection = try await emailAIService.polishEmailBody(text: selectedText, mode: mode)
                
                // 替换选中部分
                let nsString = originalBody as NSString
                let newBody = nsString.replacingCharacters(in: selectedRange, with: polishedSelection)
                
                draft.body = newBody
                replyDraft = draft
                print("✅ [EmailViewModel] AI 美化回复选中文本成功")
                isPolishingReply = false
                return newBody
            } catch {
                errorMessage = "AI 美化失败: \(error.localizedDescription)"
                print("❌ [EmailViewModel] AI 美化回复选中文本失败: \(error)")
                isPolishingReply = false
                return nil
            }
        }
        
        // 美化整个用户撰写部分
        let (userPart, quotedPart) = splitReplyBody(originalBody)
        
        guard !userPart.isEmpty else {
            errorMessage = "没有可美化的内容（可能只有引用部分）"
            return nil
        }
        
        isPolishingReply = true
        errorMessage = nil
        
        do {
            let polishedUserPart = try await emailAIService.polishEmailBody(text: userPart, mode: mode)
            
            // 拼接美化后的用户部分和原始引用部分
            if quotedPart.isEmpty {
                draft.body = polishedUserPart
            } else {
                // 确保两部分之间有适当的换行
                let separator = originalBody.contains("\n\n") ? "\n\n" : "\n"
                draft.body = polishedUserPart + separator + quotedPart
            }
            
            replyDraft = draft
            print("✅ [EmailViewModel] AI 美化回复成功")
            isPolishingReply = false
            return draft.body
        } catch {
            errorMessage = "AI 美化失败: \(error.localizedDescription)"
            print("❌ [EmailViewModel] AI 美化回复失败: \(error)")
            isPolishingReply = false
            return nil
        }
    }
    
    /// 发送新邮件（发送完成后通知用户）
    /// 注意：LibEtPan 的 SMTP 操作必须在主线程执行，所以这里不能用 Task.detached
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
        
        // 设置发送状态和进度
        isSendingCompose = true
        errorMessage = nil
        sendProgress = 0.0
        sendStatusText = "准备发送..."
        
        // 保存草稿信息
        let draftToSend = draft
        let subject = draft.subject
        let hasAttachments = !draft.attachments.isEmpty
        
        // 让 UI 有机会更新
        await Task.yield()
        
        do {
            // 阶段1: 连接服务器
            sendProgress = 0.1
            sendStatusText = "正在连接邮件服务器..."
            await Task.yield()
            
            // 阶段2: 准备邮件内容
            sendProgress = 0.3
            if hasAttachments {
                sendStatusText = "正在准备附件 (\(draftToSend.attachments.count) 个)..."
            } else {
                sendStatusText = "正在准备邮件内容..."
            }
            await Task.yield()
            
            // 阶段3: 发送邮件
            sendProgress = 0.5
            sendStatusText = "正在发送邮件..."
            
            try await sendMessage(
                to: draftToSend.to,
                cc: draftToSend.cc,
                bcc: draftToSend.bcc,
                subject: draftToSend.subject,
                body: draftToSend.body,
                htmlBody: draftToSend.htmlBody,
                attachments: draftToSend.attachments
            )
            
            // 阶段4: 发送成功
            sendProgress = 1.0
            sendStatusText = "发送成功！"
            await Task.yield()
            
            // 短暂显示成功状态后关闭面板
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            
            // 发送成功后关闭面板
            composeDraft = nil
            showComposePanel = false
            showCcBcc = false
            isSendingCompose = false
            sendProgress = 0.0
            sendStatusText = ""
            
            // 保存到“已发送(本地)”文件夹，便于在客户端查看
            if let account = currentAccount {
                saveSentMessageToLocalFolder(
                    account: account,
                    to: draftToSend.to,
                    cc: draftToSend.cc,
                    bcc: draftToSend.bcc,
                    subject: draftToSend.subject,
                    body: draftToSend.body,
                    htmlBody: draftToSend.htmlBody
                )
            }
            notifyEmailSent(subject: subject, success: true)
        } catch {
            // 发送失败
            sendProgress = 0.0
            sendStatusText = ""
            isSendingCompose = false
            errorMessage = error.localizedDescription
            notifyEmailSent(subject: subject, success: false, error: error.localizedDescription)
            throw error
        }
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
    
    /// 发送回复（发送完成后通知用户）
    /// 注意：LibEtPan 的 SMTP 操作必须在主线程执行，所以这里不能用 Task.detached
    func sendReply() async throws {
        guard let draft = replyDraft else {
            throw EmailServiceError.invalidConfiguration("回复草稿不存在")
        }
        
        // 检查是否提到附件但没有添加
        if checkAttachmentMention() {
            throw EmailServiceError.invalidConfiguration("您提到了附件，但还没有添加任何附件。请添加附件后再发送，或修改邮件内容。")
        }
        
        // 设置发送状态和进度
        isSendingReply = true
        errorMessage = nil
        sendProgress = 0.0
        sendStatusText = "准备发送..."
        
        // 保存草稿信息
        let draftToSend = draft
        let subject = draft.subject
        let hasAttachments = !draft.attachments.isEmpty
        
        // 让 UI 有机会更新
        await Task.yield()
        
        do {
            // 阶段1: 连接服务器
            sendProgress = 0.1
            sendStatusText = "正在连接邮件服务器..."
            await Task.yield()
            
            // 阶段2: 准备邮件内容
            sendProgress = 0.3
            if hasAttachments {
                sendStatusText = "正在准备附件 (\(draftToSend.attachments.count) 个)..."
            } else {
                sendStatusText = "正在准备邮件内容..."
            }
            await Task.yield()
            
            // 阶段3: 发送邮件
            sendProgress = 0.5
            sendStatusText = "正在发送邮件..."
            
            try await sendMessage(
                to: draftToSend.to,
                cc: draftToSend.cc,
                bcc: draftToSend.bcc,
                subject: draftToSend.subject,
                body: draftToSend.body,
                htmlBody: draftToSend.htmlBody,
                attachments: draftToSend.attachments
            )
            
            // 阶段4: 发送成功
            sendProgress = 1.0
            sendStatusText = "发送成功！"
            await Task.yield()
            
            // 短暂显示成功状态后关闭面板
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            
            // 发送成功后关闭面板
            replyDraft = nil
            showReplyPanel = false
            showCcBcc = false
            isSendingReply = false
            sendProgress = 0.0
            sendStatusText = ""
            
            // 保存到“已发送(本地)”文件夹
            if let account = currentAccount {
                saveSentMessageToLocalFolder(
                    account: account,
                    to: draftToSend.to,
                    cc: draftToSend.cc,
                    bcc: draftToSend.bcc,
                    subject: draftToSend.subject,
                    body: draftToSend.body,
                    htmlBody: draftToSend.htmlBody
                )
            }
            notifyEmailSent(subject: subject, success: true)
        } catch {
            // 发送失败
            sendProgress = 0.0
            sendStatusText = ""
            isSendingReply = false
            errorMessage = error.localizedDescription
            notifyEmailSent(subject: subject, success: false, error: error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Message Actions
    
    /// 切换星标状态
    func toggleStar(_ message: EmailMessage) async {
        guard let account = currentAccount else { return }
        
        do {
            try await emailService.toggleStar(account: account, message: message)
            
            // 从 emailStore 获取最新数据（保留正文缓存）
            var updated = message
            if let folderId = message.folderId,
               let storeMessages = emailStore.messages[folderId],
               let latestMessage = storeMessages.first(where: { $0.id == message.id }) {
                updated = latestMessage
            }
            
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
    /// - Parameters:
    ///   - message: 要删除的邮件
    ///   - deleteOnServer: 是否在服务器上删除（true=服务器删除，false=仅本地删除）
    func deleteMessage(_ message: EmailMessage, deleteOnServer: Bool = false) async {
        guard let account = currentAccount else { return }
        
        do {
            // 如果需要在服务器上删除，调用服务器删除接口
            if deleteOnServer {
                try await emailService.deleteMessage(account: account, message: message)
            }
            
            // 从 emailStore 获取最新数据（保留正文缓存）
            var updated = message
            if let folderId = message.folderId,
               let storeMessages = emailStore.messages[folderId],
               let latestMessage = storeMessages.first(where: { $0.id == message.id }) {
                updated = latestMessage
            }
            
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
            
            // 如果是在多选模式下删除，从选中集合中移除
            selectedMessageIds.remove(message.id)
        } catch {
            errorMessage = "删除失败: \(error.localizedDescription)"
            print("❌ [EmailViewModel] 删除邮件失败: \(error)")
        }
    }
    
    /// 批量删除邮件
    /// - Parameter deleteOnServer: 是否在服务器上删除
    func deleteSelectedMessages(deleteOnServer: Bool) async {
        let messagesToDelete = messages.filter { selectedMessageIds.contains($0.id) }
        
        for message in messagesToDelete {
            await deleteMessage(message, deleteOnServer: deleteOnServer)
        }
        
        // 清除多选状态
        selectedMessageIds.removeAll()
        isMultiSelectMode = false
    }
    
    /// 切换多选模式
    func toggleMultiSelectMode() {
        isMultiSelectMode.toggle()
        if !isMultiSelectMode {
            selectedMessageIds.removeAll()
        }
    }
    
    /// 切换单个邮件的选中状态
    func toggleMessageSelection(_ messageId: UUID) {
        if selectedMessageIds.contains(messageId) {
            selectedMessageIds.remove(messageId)
        } else {
            selectedMessageIds.insert(messageId)
        }
    }
    
    /// 全选/取消全选
    func toggleSelectAll() {
        let displayedMessages = searchText.isEmpty ? messages : searchResults
        if selectedMessageIds.count == displayedMessages.count {
            selectedMessageIds.removeAll()
        } else {
            selectedMessageIds = Set(displayedMessages.map { $0.id })
        }
    }
    
    /// 归档单个邮件
    func archiveMessage(_ message: EmailMessage) async {
        guard let account = currentAccount else { return }
        
        // 查找归档文件夹
        let archiveFolder = folders.first { $0.type == .archive }
        guard let archiveFolder = archiveFolder else {
            errorMessage = "找不到归档文件夹"
            return
        }
        
        do {
            try await emailService.moveMessage(account: account, message: message, to: archiveFolder)
            
            // 更新本地状态 - 创建新的邮件实例，因为 folderId 是 let 常量
            let updated = EmailMessage(
                id: message.id,
                accountId: message.accountId,
                folderId: archiveFolder.id,
                uid: message.uid,
                messageId: message.messageId,
                threadId: message.threadId,
                subject: message.subject,
                from: message.from,
                to: message.to,
                cc: message.cc,
                bcc: message.bcc,
                replyTo: message.replyTo,
                textBody: message.textBody,
                htmlBody: message.htmlBody,
                preview: message.preview,
                date: message.date,
                receivedDate: message.receivedDate,
                isRead: message.isRead,
                isStarred: message.isStarred,
                isImportant: message.isImportant,
                isNoReply: message.isNoReply,
                hasAttachments: message.hasAttachments,
                isSpam: message.isSpam,
                isDeleted: message.isDeleted,
                containsRemoteResources: message.containsRemoteResources,
                hasBeenReplied: message.hasBeenReplied,
                isDraft: message.isDraft,
                tags: message.tags,
                aiTags: message.aiTags,
                aiSummary: message.aiSummary,
                aiPriority: message.aiPriority,
                attachments: message.attachments,
                syncedAt: message.syncedAt,
                updatedAt: Date(),
                isBodyLoaded: message.isBodyLoaded,
                bodyCachedAt: message.bodyCachedAt
            )
            try await emailStore.updateMessage(updated)
            
            // 从当前列表中移除
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages.remove(at: index)
            }
            
            // 如果归档的是当前选中的邮件，清除选择
            if selectedMessageId == message.id {
                selectedMessageId = nil
            }
        } catch {
            errorMessage = "归档失败: \(error.localizedDescription)"
            print("❌ [EmailViewModel] 归档邮件失败: \(error)")
        }
    }
    
    /// 归档选中的邮件
    func archiveSelectedMessages() async {
        guard currentAccount != nil else { return }
        
        let messagesToArchive = messages.filter { selectedMessageIds.contains($0.id) }
        
        for message in messagesToArchive {
            await archiveMessage(message)
        }
        
        // 清除多选状态
        selectedMessageIds.removeAll()
        isMultiSelectMode = false
    }
    
    /// 标记为垃圾邮件
    func markAsSpam(_ message: EmailMessage) async {
        guard let account = currentAccount else { return }
        
        do {
            try await emailService.markAsSpam(account: account, message: message)
            
            // 从 emailStore 获取最新数据（保留正文缓存）
            var updated = message
            if let folderId = message.folderId,
               let storeMessages = emailStore.messages[folderId],
               let latestMessage = storeMessages.first(where: { $0.id == message.id }) {
                updated = latestMessage
            }
            
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
            
            // 从 emailStore 获取最新数据（保留正文缓存）
            var updated = message
            if let folderId = message.folderId,
               let storeMessages = emailStore.messages[folderId],
               let latestMessage = storeMessages.first(where: { $0.id == message.id }) {
                updated = latestMessage
            }
            
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
        // 如果超级隐私模式开启，不允许显示图片
        if preferences.emailSuperPrivacyMode {
            showImages = false
            return
        }
        
        imageDisplayPreferences.setShowImages(show, for: message.from, remember: remember)
        showImages = show
        
        // 如果记住，也更新全局设置（作为默认值）
        if remember {
            preferences.emailShowImages = show
        }
    }
    
    // MARK: - 已发送保存到本地
    
    /// 将刚发出的邮件保存到“已发送(本地)”文件夹，便于在客户端查看
    private func saveSentMessageToLocalFolder(
        account: EmailAccount,
        to: [EmailContact],
        cc: [EmailContact],
        bcc: [EmailContact],
        subject: String,
        body: String,
        htmlBody: String?
    ) {
        guard let folder = emailStore.getLocalSentFolder(for: account.id) else { return }
        let from = EmailContact(name: account.displayName.isEmpty ? nil : account.displayName, email: account.emailAddress)
        let preview = body.prefix(200).trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let sentMessage = EmailMessage(
            accountId: account.id,
            folderId: folder.id,
            uid: nil,
            messageId: nil,
            threadId: nil,
            subject: subject.isEmpty ? "(无主题)" : subject,
            from: from,
            to: to,
            cc: cc,
            bcc: bcc,
            replyTo: [],
            textBody: body.isEmpty ? nil : body,
            htmlBody: htmlBody,
            preview: String(preview),
            date: now,
            receivedDate: now,
            isRead: true,
            isStarred: false,
            isImportant: false,
            isNoReply: false,
            hasAttachments: false,
            isSpam: false,
            isDeleted: false,
            containsRemoteResources: false,
            hasBeenReplied: false,
            isDraft: false,
            syncedAt: now,
            updatedAt: now,
            isBodyLoaded: true
        )
        Task {
            try? await emailStore.addMessages([sentMessage], folderId: folder.id)
        }
    }
    
    // MARK: - Send Notification
    
    /// 邮件发送完成后通知用户
    private func notifyEmailSent(subject: String, success: Bool, error: String? = nil) {
        // 播放系统提示音
        if success {
            if let sound = NSSound(named: .init("Mail Sent")) {
                sound.play()
            } else {
                NSSound.beep()
            }
        } else {
            NSSound.beep()
        }
        
        // 发送系统通知
        let content = UNMutableNotificationContent()
        if success {
            content.title = "邮件已发送"
            content.body = subject.isEmpty ? "邮件发送成功" : "「\(subject)」已发送"
            content.sound = .default
        } else {
            content.title = "邮件发送失败"
            content.body = error ?? "发送时遇到问题，请稍后重试"
            content.sound = .defaultCritical
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // 立即显示
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ [EmailViewModel] 发送通知失败: \(error)")
            }
        }
    }
    
    // MARK: - AI HTML Layout Optimization
    
    /// AI智能优化邮件HTML排版（异步，不阻塞UI）
    /// - Parameter message: 要优化的邮件
    func optimizeHTMLLayout(for message: EmailMessage) {
        // 检查是否有HTML内容
        guard let htmlBody = message.htmlBody, !htmlBody.isEmpty else {
            errorMessage = "此邮件没有HTML内容可优化"
            return
        }
        
        // 检查是否已经优化过
        if optimizedHTMLCache[message.id] != nil {
            // 已经优化过，切换回原始版本（立即执行，不影响性能）
            optimizedHTMLCache.removeValue(forKey: message.id)
            print("🔄 [EmailViewModel] 恢复原始排版，邮件ID: \(message.id)")
            return
        }
        
        // 检查是否已经有优化任务在运行
        if optimizingMessageIds.contains(message.id) {
            print("⚠️ [EmailViewModel] 邮件正在优化中，跳过重复请求，邮件ID: \(message.id)")
            return
        }
        
        let messageId = message.id
        let textBody = message.textBody
        
        // 标记为正在优化
        optimizingMessageIds.insert(messageId)
        errorMessage = nil
        
        print("🚀 [EmailViewModel] 开始AI排版优化（后台任务），邮件ID: \(messageId)")
        
        // 创建后台任务，不阻塞UI
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                // 在后台线程执行AI优化（耗时操作）
                let optimizedHTML = try await self?.emailAIService.optimizeHTMLLayout(
                    htmlBody: htmlBody,
                    textBody: textBody,
                    existingStyles: nil
                )
                
                // 回到主线程更新UI状态
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    
                    // 保存优化后的HTML到缓存
                    if let optimizedHTML = optimizedHTML {
                        self.optimizedHTMLCache[messageId] = optimizedHTML
                        print("✅ [EmailViewModel] AI排版优化成功，邮件ID: \(messageId)")
                        print("📊 [EmailViewModel] 原始长度: \(htmlBody.count), 优化后长度: \(optimizedHTML.count)")
                    }
                    
                    // 移除优化中标记
                    self.optimizingMessageIds.remove(messageId)
                    
                    // 清理任务引用
                    self.optimizationTasks.removeValue(forKey: messageId)
                }
            } catch {
                // 回到主线程处理错误
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    
                    // 只在当前邮件还是选中状态时才显示错误
                    if self.selectedMessageId == messageId {
                        self.errorMessage = "AI排版优化失败: \(error.localizedDescription)"
                    }
                    print("❌ [EmailViewModel] AI排版优化失败，邮件ID: \(messageId), 错误: \(error)")
                    
                    // 移除优化中标记
                    self.optimizingMessageIds.remove(messageId)
                    
                    // 清理任务引用
                    self.optimizationTasks.removeValue(forKey: messageId)
                }
            }
        }
        
        // 保存任务引用，以便需要时可以取消
        optimizationTasks[messageId] = task
    }
    
    /// 取消正在进行的优化任务
    /// - Parameter messageId: 邮件ID
    func cancelOptimization(for messageId: UUID) {
        if let task = optimizationTasks[messageId] {
            task.cancel()
            optimizationTasks.removeValue(forKey: messageId)
            optimizingMessageIds.remove(messageId)
            print("🛑 [EmailViewModel] 取消AI排版优化，邮件ID: \(messageId)")
        }
    }
    
    /// 获取优化后的HTML（如果有）
    /// - Parameter message: 邮件
    /// - Returns: 优化后的HTML，如果没有优化过则返回nil
    func getOptimizedHTML(for message: EmailMessage) -> String? {
        return optimizedHTMLCache[message.id]
    }
    
    /// 检查邮件是否已优化排版
    /// - Parameter message: 邮件
    /// - Returns: 是否已优化
    func isLayoutOptimized(for message: EmailMessage) -> Bool {
        return optimizedHTMLCache[message.id] != nil
    }
    
    /// 检查邮件是否正在优化中
    /// - Parameter message: 邮件
    /// - Returns: 是否正在优化
    func isOptimizing(for message: EmailMessage) -> Bool {
        return optimizingMessageIds.contains(message.id)
    }
    
    /// 保存邮件为 .eml 文件
    func saveMessageAsEML(message: EmailMessage) async {
        guard let account = currentAccount else {
            errorMessage = "未选择账号"
            return
        }
        
        guard let folderId = message.folderId,
              let folder = folder(for: folderId) else {
            errorMessage = "无法获取邮件所在文件夹"
            return
        }
        
        do {
            // 尝试获取原始邮件数据
            let rawData = try await emailService.fetchRawMessage(
                account: account,
                folder: folder,
                message: message
            )
            
            // 使用文件保存对话框
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.init(filenameExtension: "eml")!]
            savePanel.nameFieldStringValue = sanitizeFilename(message.subject.isEmpty ? "邮件" : message.subject) + ".eml"
            savePanel.title = "保存邮件"
            savePanel.prompt = "保存"
            
            if savePanel.runModal() == .OK, let url = savePanel.url {
                try rawData.write(to: url)
                print("✅ [EmailViewModel] 邮件已保存为 .eml 文件: \(url.path)")
            }
        } catch {
            print("❌ [EmailViewModel] 保存邮件失败: \(error)")
            errorMessage = "保存失败: \(error.localizedDescription)"
            
            // 如果获取原始数据失败，尝试手动构建 .eml 文件
            await saveMessageAsEMLManual(message: message)
        }
    }
    
    /// 手动构建 .eml 文件（当无法获取原始数据时使用）
    private func saveMessageAsEMLManual(message: EmailMessage) async {
        let emlContent = EmailEMLBuilder.buildEML(from: message)
        
        guard let emlData = emlContent.data(using: .utf8) else {
            errorMessage = "无法构建 .eml 文件内容"
            return
        }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.init(filenameExtension: "eml")!]
        savePanel.nameFieldStringValue = sanitizeFilename(message.subject.isEmpty ? "邮件" : message.subject) + ".eml"
        savePanel.title = "保存邮件"
        savePanel.prompt = "保存"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try emlData.write(to: url)
                print("✅ [EmailViewModel] 邮件已保存为 .eml 文件（手动构建）: \(url.path)")
            } catch {
                errorMessage = "保存失败: \(error.localizedDescription)"
            }
        }
    }
    
    /// 清理文件名，移除不允许的字符
    private func sanitizeFilename(_ filename: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>")
        return filename.components(separatedBy: invalidChars).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
}

