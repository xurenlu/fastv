//
//  EmailView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 邮箱主视图
struct EmailView: View {
    @StateObject private var viewModel = EmailViewModel()
    @State private var showAccountManagement = false
    @State private var showComposeWindow = false
    @State private var composeWindowType: EmailComposeWindowView.ComposeType?
    @State private var showMessageHeaders = false
    @State private var showDeleteConfirmation = false
    @State private var deleteOnServer = false // 删除选项：是否在服务器上删除
    @State private var messageToDelete: EmailMessage? // 单个删除的邮件
    
    var body: some View {
        HSplitView {
            // 左侧：文件夹列表
            folderListView
                .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)
                .frame(maxHeight: .infinity, alignment: .top)
            
            // 中间：邮件列表
            messageListView
                .frame(width: 250) // 强制固定宽度，防止自动变宽
                .frame(maxHeight: .infinity, alignment: .top)
            
            // 右侧：邮件详情（正文列）- 限制最大宽度，避免影响主菜单
            if let message = viewModel.selectedMessage {
                messageDetailView(message: message)
                    .frame(minWidth: 300, idealWidth: 400, maxWidth: 550)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                // 未选中邮件时的提示 - Apple 风格
                ContentUnavailableView {
                    Label {
                        Text(NSLocalizedString("email.select.message.hint", comment: ""))
                            .font(.title3.weight(.medium))
                    } icon: {
                        Image(systemName: "envelope.open")
                            .font(.system(size: 56))
                            .foregroundStyle(.tertiary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .frame(minWidth: 300, idealWidth: 400, maxWidth: 550)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("邮箱")
        .sheet(isPresented: $showDeleteConfirmation) {
            DeleteConfirmationView(
                isPresented: $showDeleteConfirmation,
                deleteOnServer: $deleteOnServer,
                messageCount: messageToDelete != nil ? 1 : viewModel.selectedMessageIds.count,
                onConfirm: {
                    if let message = messageToDelete {
                        // 单个删除
                        Task {
                            await viewModel.deleteMessage(message, deleteOnServer: deleteOnServer)
                            messageToDelete = nil
                        }
                    } else {
                        // 批量删除
                        Task {
                            await viewModel.deleteSelectedMessages(deleteOnServer: deleteOnServer)
                        }
                    }
                }
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    viewModel.initComposeDraft()
                    composeWindowType = .new
                    showComposeWindow = true
                }) {
                    Label(NSLocalizedString("email.new.message", comment: ""), systemImage: "square.and.pencil")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button(action: { showAccountManagement = true }) {
                    Label(NSLocalizedString("email.account.management", comment: ""), systemImage: "person.crop.circle.badge.plus")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    if let account = viewModel.currentAccount {
                        Task { await viewModel.syncAccount(account) }
                    }
                }) {
                    Label(NSLocalizedString("email.sync", comment: ""), systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .sheet(isPresented: $showAccountManagement) {
            EmailAccountManagementView()
        }
        .sheet(isPresented: $showComposeWindow) {
            if let composeType = composeWindowType {
                EmailComposeWindowView(viewModel: viewModel, composeType: composeType)
            }
        }
        .sheet(isPresented: $showMessageHeaders) {
            if let message = viewModel.selectedMessage {
                MessageHeadersView(message: message, viewModel: viewModel)
            }
        }
        .onAppear {
            // 如果没有选中文件夹，默认选中"所有邮件"
            if viewModel.selectedFolderId == nil {
                viewModel.showAllMessages()
            }
            // 延迟 50ms 再加载数据，让视图先完成首次渲染，避免切换时主线程被阻塞导致无响应
            Task.detached(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 50_000_000)
                await viewModel.loadInitialData()
            }
        }
        .onChange(of: viewModel.selectedAccountId) { _, _ in
            // 账号切换时，自动选中"所有邮件"
            viewModel.showAllMessages()
            // 后台重新加载数据
            Task.detached(priority: .userInitiated) {
                if let account = await viewModel.currentAccount {
                    await viewModel.loadFolders(account: account)
                }
            }
        }
    }
    
    // MARK: - Folder List
    
    private var folderListView: some View {
        VStack(spacing: 0) {
            // 账号选择器
            if !viewModel.accounts.isEmpty {
                let accountBinding = Binding<UUID?>(
                    get: { viewModel.selectedAccountId ?? viewModel.accounts.first?.id },
                    set: { id in
                        guard let id = id,
                              let account = viewModel.accounts.first(where: { $0.id == id }) else { return }
                        viewModel.selectAccount(account)
                    }
                )
                
                Picker(NSLocalizedString("email.account", comment: ""), selection: accountBinding) {
                    ForEach(viewModel.accounts) { account in
                        Text(account.displayName).tag(Optional(account.id))
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            } else {
                // 没有账号时的提示 - Apple 风格
                ContentUnavailableView {
                    Label {
                        Text(NSLocalizedString("email.no.account", comment: ""))
                            .font(.subheadline.weight(.medium))
                    } icon: {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                            .symbolRenderingMode(.hierarchical)
                    }
                } actions: {
                    Button(NSLocalizedString("email.add.account", comment: "")) {
                        showAccountManagement = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            
            Divider()
            
            // 文件夹列表（填充剩余空间，避免选中邮件时出现大块空白）
            if viewModel.selectedAccountId != nil {
                folderListContent
                    .frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label {
                        Text(NSLocalizedString("email.select.account", comment: ""))
                            .font(.subheadline.weight(.medium))
                    } icon: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    @ViewBuilder
    private var folderListContent: some View {
        let allFolders = viewModel.folders.filter { !$0.isGarbled }
        
        // 分离非空和空文件夹
        let nonEmptyFolders = allFolders.filter { folder in
            let messageCount = EmailStore.shared.getMessageCount(for: folder.id)
            return messageCount > 0
        }
        
        let emptyFolders = allFolders.filter { folder in
            let messageCount = EmailStore.shared.getMessageCount(for: folder.id)
            return messageCount == 0
        }
        
        if nonEmptyFolders.isEmpty && emptyFolders.isEmpty {
            if viewModel.isLoadingFolders {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text(NSLocalizedString("email.loading.folders", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label {
                        Text(NSLocalizedString("email.no.folders", comment: ""))
                            .font(.subheadline.weight(.medium))
                    } icon: {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                            .symbolRenderingMode(.hierarchical)
                    }
                } actions: {
                    Button(NSLocalizedString("email.refresh", comment: "")) {
                        if let account = viewModel.currentAccount {
                            Task { await viewModel.loadFolders(account: account) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        } else {
            let folderBinding = Binding<UUID?>(
                get: { viewModel.selectedFolderId },
                set: { folderId in
                    // 立即执行，不需要延迟（ViewModel已经优化为零卡顿）
                    if let folderId = folderId,
                       let folder = allFolders.first(where: { $0.id == folderId }) {
                        viewModel.selectFolder(folder)
                    } else {
                        viewModel.showAllMessages()
                    }
                }
            )
            
            List(selection: folderBinding) {
                // 写邮件按钮
                Button(action: {
                    viewModel.initComposeDraft()
                    composeWindowType = .new
                    showComposeWindow = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 22)
                        Text(NSLocalizedString("email.write", comment: ""))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // "所有邮件" 选项 - 默认选中
                HStack(spacing: 10) {
                    Image(systemName: viewModel.selectedFolderId == nil ? "tray.fill" : "tray")
                        .font(.system(size: 15, weight: viewModel.selectedFolderId == nil ? .semibold : .medium))
                        .foregroundStyle(viewModel.selectedFolderId == nil ? Color.accentColor : .secondary)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 22)
                    Text(NSLocalizedString("email.all.messages", comment: ""))
                        .font(.system(size: 14, weight: viewModel.selectedFolderId == nil ? .semibold : .regular))
                        .foregroundStyle(viewModel.selectedFolderId == nil ? .primary : .secondary)
                    Spacer()
                    // 显示该账号的所有邮件总数（使用 ViewModel 异步缓存，避免在 View body 中同步查库阻塞主线程）
                    if viewModel.totalMessageCountForAccount > 0 {
                        Text("\(viewModel.totalMessageCountForAccount)")
                            .font(.caption)
                            .foregroundStyle(viewModel.selectedFolderId == nil ? .secondary : .tertiary)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.showAllMessages()
                }
                .tag(nil as UUID?)
                .listRowBackground(
                    viewModel.selectedFolderId == nil ? 
                        Color.accentColor.opacity(0.15) : Color.clear
                )
                
                // 非空文件夹列表
                if !nonEmptyFolders.isEmpty {
                    Section(header:
                        Text(NSLocalizedString("email.folders", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(nil)
                            .padding(.top, 8)
                    ) {
                        ForEach(nonEmptyFolders) { folder in
                            FolderRow(folder: folder, viewModel: viewModel)
                                .tag(folder.id)
                        }
                    }
                }
                
                // 空文件夹折叠区域
                if !emptyFolders.isEmpty {
                    Section(header: 
                        Text("")
                            .font(.caption)
                            .padding(.top, 4)
                    ) {
                        DisclosureGroup(
                            isExpanded: $viewModel.showEmptyFolders
                        ) {
                            ForEach(emptyFolders) { folder in
                                FolderRow(folder: folder, viewModel: viewModel, isEmpty: true)
                                    .tag(folder.id)
                                    .padding(.leading, 8)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .symbolRenderingMode(.hierarchical)
                                    .frame(width: 20)
                                Text(NSLocalizedString("email.empty.folders", comment: ""))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text("(\(emptyFolders.count))")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                        .accentColor(.secondary)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    // MARK: - Message List
    
    private var messageListView: some View {
        VStack(spacing: 0) {
            // 搜索栏和多选模式切换
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .symbolRenderingMode(.hierarchical)
                    TextField(NSLocalizedString("email.search", comment: ""), text: $viewModel.searchText)
                        .textFieldStyle(.plain)

                    Button(action: { viewModel.toggleMultiSelectMode() }) {
                        Image(systemName: viewModel.isMultiSelectMode ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.body)
                            .foregroundStyle(viewModel.isMultiSelectMode ? Color.accentColor : .secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.isMultiSelectMode ? NSLocalizedString("email.exit.multi.select", comment: "") : NSLocalizedString("email.multi.select", comment: ""))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // 过滤和排序工具栏
                HStack(spacing: 8) {
                    Menu {
                        ForEach(EmailViewModel.EmailFilterMode.allCases, id: \.rawValue) { mode in
                            Button(action: { viewModel.filterMode = mode }) {
                                HStack {
                                    Text(mode.displayName)
                                    if viewModel.filterMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 12))
                            Text(viewModel.filterMode.displayName)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    
                    Menu {
                        ForEach(EmailViewModel.EmailSortMode.allCases, id: \.rawValue) { mode in
                            Button(action: { viewModel.sortMode = mode }) {
                                HStack {
                                    Text(mode.displayName)
                                    if viewModel.sortMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .font(.system(size: 12))
                            Text(viewModel.sortMode.displayName)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                // 批量操作工具栏（多选模式下显示）
                if viewModel.isMultiSelectMode {
                    Divider()
                    HStack(spacing: 12) {
                        Button(action: { viewModel.toggleSelectAll() }) {
                            HStack(spacing: 6) {
                                Image(systemName: viewModel.selectedMessageIds.count == (viewModel.searchText.isEmpty ? viewModel.messages.count : viewModel.searchResults.count) ? "checkmark.circle.fill" : "circle")
                                    .font(.subheadline)
                                Text(viewModel.selectedMessageIds.count == (viewModel.searchText.isEmpty ? viewModel.messages.count : viewModel.searchResults.count) ? NSLocalizedString("email.deselect.all", comment: "") : NSLocalizedString("email.select.all", comment: ""))
                                    .font(.subheadline)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if !viewModel.selectedMessageIds.isEmpty {
                            Text(String(format: NSLocalizedString("email.selected.count", comment: ""), viewModel.selectedMessageIds.count))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(action: { Task { await viewModel.archiveSelectedMessages() } }) {
                            HStack(spacing: 6) {
                                Image(systemName: "archivebox")
                                    .font(.subheadline)
                                    .symbolRenderingMode(.hierarchical)
                                Text(NSLocalizedString("email.archive", comment: ""))
                                    .font(.subheadline)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.selectedMessageIds.isEmpty)

                        Button(action: {
                            messageToDelete = nil
                            showDeleteConfirmation = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.subheadline)
                                    .symbolRenderingMode(.hierarchical)
                                Text(NSLocalizedString("email.delete", comment: ""))
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.selectedMessageIds.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                }
            }
            
            Divider()
            
            // 邮件列表视图
            if viewModel.isLoading && viewModel.messages.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.messages.isEmpty && !viewModel.isLoading {
                emptyMessageListView
            } else {
                ScrollViewReader { _ in
                    // 在外部计算 displayedMessages，避免布局时重新计算
                    let displayedMessages = viewModel.searchText.isEmpty ? viewModel.messages : viewModel.searchResults
                    
                    // 使用 ScrollView 替代 List，避免 macOS List 顶部裁剪和切 app 后高度错乱问题
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // 顶部留白，防止首行被裁剪或遮挡
                            Color.clear.frame(height: 8)
                            
                            ForEach(displayedMessages, id: \.id) { message in
                                MessageRow(
                                    message: message,
                                    showAttachments: viewModel.showAttachments,
                                    isMultiSelectMode: viewModel.isMultiSelectMode,
                                    isSelected: viewModel.selectedMessageIds.contains(message.id),
                                    onToggleSelection: {
                                        viewModel.toggleMessageSelection(message.id)
                                    }
                                )
                                .tag(message.id)
                                .contentShape(Rectangle())
                                .background(viewModel.selectedMessageId == message.id && !viewModel.isMultiSelectMode ? Color.accentColor.opacity(0.12) : Color.clear)
                                .if(!viewModel.isMultiSelectMode) { view in
                                    view.onTapGesture { viewModel.selectMessage(message) }
                                }
                            }
                            
                            // 底部加载区域
                            if viewModel.isLoadingMore {
                                HStack(spacing: 10) {
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(0.85)
                                    Text(NSLocalizedString("email.load.more", comment: ""))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 16)
                            } else if viewModel.hasMoreMessages {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear {
                                        Task { @MainActor in
                                            try? await Task.sleep(nanoseconds: 200_000_000)
                                            if viewModel.hasMoreMessages && !viewModel.isLoadingMore {
                                                viewModel.loadMoreMessages()
                                            }
                                        }
                                    }
                            } else {
                                HStack {
                                    Spacer()
                                    Text(NSLocalizedString("email.no.more.messages", comment: ""))
                                        .font(.subheadline)
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .scrollIndicators(.visible)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    private var emptyMessageListView: some View {
        ContentUnavailableView {
            Label {
                Text(NSLocalizedString("email.no.messages", comment: ""))
                    .font(.title3.weight(.medium))
            } icon: {
                Image(systemName: "envelope")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                    .symbolRenderingMode(.hierarchical)
            }
        } description: {
            if viewModel.selectedFolderId == nil {
                Text(NSLocalizedString("email.no.messages.sync.hint", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Message Detail
    
    private func messageDetailView(message: EmailMessage) -> some View {
        ScrollViewReader { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 邮件头部（带操作按钮）
                    messageHeaderWithActions(message: message)
                    
                    // AI摘要（如果有）- Apple 风格：克制、层次清晰
                    if let summary = message.aiSummary, !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                                    .symbolRenderingMode(.hierarchical)
                                Text(NSLocalizedString("email.ai.summary", comment: ""))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }

                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.06))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1)
                                        }
                                }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Divider()
                    
                    // 外部资源加载提示 - 移到正文最前面
                    if message.containsRemoteResources && 
                       !viewModel.showImages &&
                       EmailImageDisplayPreferences.shared.shouldShowImages(for: message.from) == nil {
                        remoteResourcesBanner(message: message)
                    }
                    
                    // 邮件正文 - 使用 WKWebView 渲染，提供完整的 HTML/CSS 支持
                    Group {
                        if let htmlBody = message.htmlBody, !htmlBody.isEmpty {
                            // 优先使用AI优化后的HTML，如果没有则使用原始HTML
                            let displayHTML = viewModel.getOptimizedHTML(for: message) ?? htmlBody
                            // 只在必要时尝试解码 base64（性能优化：快速检查是否已包含中文字符）
                            let decodedHTML = EmailContentDecoder.tryDecodeBase64TextIfNeeded(displayHTML)
                            EmailBodyWebView(htmlBody: decodedHTML, textBody: message.textBody, showImages: viewModel.showImages)
                        } else if let textBody = message.textBody, !textBody.isEmpty {
                            // 只在必要时尝试解码 base64（性能优化）
                            let decodedText = EmailContentDecoder.tryDecodeBase64TextIfNeeded(textBody)
                            Text(decodedText)
                                .font(.system(size: 16))
                                .lineSpacing(6)
                                .foregroundStyle(Color(red: 29/255, green: 29/255, blue: 31/255))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                        } else {
                            // 预览文本也可能需要解码（性能优化）
                            let decodedPreview = EmailContentDecoder.tryDecodeBase64TextIfNeeded(message.preview)
                            Text(decodedPreview)
                                .font(.system(size: 16))
                                .foregroundStyle(Color.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                    .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                    }

                    
                    if !message.isBodyLoaded &&
                        (message.textBody?.isEmpty ?? true) &&
                        (message.htmlBody?.isEmpty ?? true) {
                        ProgressView("正在加载正文...")
                            .padding(.vertical, 8)
                    }
                    
                    // 附件列表（始终显示，如果有附件）
                    if !message.attachments.isEmpty {
                        Divider()
                        attachmentsView(attachments: message.attachments)
                    }
                }
                .padding()
            }
        }
    }
    
    private func messageHeader(message: EmailMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                // 放大头像，增强视觉焦点
                EmailAvatarView(email: message.from.email, size: 56)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.from.name ?? message.from.email)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    Text(message.from.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(formatMessageDate(message.date))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 2)
                }
                
                Spacer()
            }
            
            Text(message.subject)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func messageHeaderWithActions(message: EmailMessage) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            messageHeader(message: message)
            
            Divider()
            
            // 美化的操作按钮栏 - 使用 ControlGroup 和图标按钮组
            HStack(spacing: 8) {
                // 回复操作组
                ControlGroup {
                    Button(action: {
                        if message.isNoReply {
                            viewModel.errorMessage = "这是一个 no-reply 邮箱，无法回复"
                        } else {
                            viewModel.initReplyDraft(for: message, type: .reply)
                            composeWindowType = .reply(message)
                            showComposeWindow = true
                        }
                    }) {
                        Label("回复", systemImage: "arrowshape.turn.up.left")
                    }
                    .disabled(message.isNoReply)
                    
                    Button(action: {
                        if message.isNoReply {
                            viewModel.errorMessage = "这是一个 no-reply 邮箱，无法回复"
                        } else {
                            viewModel.initReplyDraft(for: message, type: .replyAll)
                            composeWindowType = .replyAll(message)
                            showComposeWindow = true
                        }
                    }) {
                        Label("全部", systemImage: "arrowshape.turn.up.left.2")
                    }
                    .disabled(message.isNoReply)
                    
                    Button(action: {
                        viewModel.initReplyDraft(for: message, type: .forward)
                        composeWindowType = .forward(message)
                        showComposeWindow = true
                    }) {
                        Label("转发", systemImage: "arrowshape.turn.up.right")
                    }
                }
                
                Spacer()
                
                // 中间操作按钮组 - 邮件头查看和保存
                HStack(spacing: 4) {
                    // 邮件头查看按钮
                    Button(action: {
                        showMessageHeaders = true
                    }) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .help("查看邮件头信息")
                    
                    // 保存为 .eml 文件按钮
                    Button(action: {
                        if let message = viewModel.selectedMessage {
                            Task {
                                await viewModel.saveMessageAsEML(message: message)
                            }
                        }
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .help("保存为 .eml 文件")
                }
                
                Spacer()
                
                // 右侧操作按钮组 - 使用图标按钮，更紧凑
                HStack(spacing: 4) {
                    // AI智能排版按钮 - 只对HTML邮件显示
                    if let htmlBody = message.htmlBody, !htmlBody.isEmpty {
                        Button(action: {
                            // 同步调用，不阻塞UI（内部使用Task.detached）
                            viewModel.optimizeHTMLLayout(for: message)
                        }) {
                            if viewModel.isOptimizing(for: message) {
                                // 正在优化中：显示进度指示器
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 32, height: 32)
                            } else {
                                // 根据是否已优化显示不同的图标和颜色
                                Image(systemName: viewModel.isLayoutOptimized(for: message) ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack")
                                    .foregroundStyle(viewModel.isLayoutOptimized(for: message) ? Color.purple : .secondary)
                                    .frame(width: 32, height: 32)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.isLayoutOptimized(for: message) ? "恢复原始排版" : "AI智能排版优化")
                        .disabled(viewModel.isOptimizing(for: message))
                    }
                    
                    // 星标按钮
                    Button(action: {
                        Task {
                            await viewModel.toggleStar(message)
                        }
                    }) {
                        Image(systemName: message.isStarred ? "star.fill" : "star")
                            .foregroundStyle(message.isStarred ? Color.yellow : .secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .help(message.isStarred ? "取消星标" : "添加星标")
                    
                    // 垃圾邮件按钮
                    if message.isSpam {
                        Button(action: {
                            Task {
                                await viewModel.restoreFromSpam(message)
                            }
                        }) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.orange)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .help("不是垃圾邮件")
                    } else {
                        Button(action: {
                            Task {
                                await viewModel.markAsSpam(message)
                            }
                        }) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .help("标记为垃圾邮件")
                    }
                    
                    // 删除按钮
                    Button(action: {
                        messageToDelete = message
                        showDeleteConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.red)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .help("删除邮件")
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func remoteResourcesBanner(message: EmailMessage) -> some View {
        RemoteResourcesBannerView(message: message, viewModel: viewModel)
    }
    
    private func attachmentsView(attachments: [EmailAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("附件 (\(attachments.count))")
                .font(.headline)
            
            ForEach(attachments) { attachment in
                HStack {
                    Image(systemName: attachmentIcon(for: attachment.mimeType))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.subheadline)
                        Text(attachment.sizeString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        if let message = viewModel.selectedMessage {
                            Task {
                                await viewModel.previewAttachment(attachment, from: message)
                            }
                        }
                    }) {
                        Label(attachment.localPath != nil ? "打开" : "下载", systemImage: attachment.localPath != nil ? "eye" : "arrow.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private func attachmentIcon(for mimeType: String) -> String {
        if mimeType.hasPrefix("image/") {
            return "photo.fill"
        } else if mimeType.hasPrefix("video/") {
            return "video.fill"
        } else if mimeType.hasPrefix("audio/") {
            return "music.note"
        } else if mimeType == "application/pdf" {
            return "doc.fill"
        } else {
            return "doc.fill"
        }
    }
}

// MARK: - Remote Resources Banner View

private struct RemoteResourcesBannerView: View {
    let message: EmailMessage
    @ObservedObject var viewModel: EmailViewModel
    @ObservedObject var preferences = UserPreferences.shared
    @State private var rememberChoice = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: preferences.emailSuperPrivacyMode ? "lock.shield.fill" : "photo.fill")
                    .foregroundStyle(preferences.emailSuperPrivacyMode ? Color.orange : Color.blue)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(preferences.emailSuperPrivacyMode ? "超级隐私模式已启用" : "此邮件包含外部图片")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    Text(preferences.emailSuperPrivacyMode ? "所有远程内容已被阻止，图片不会显示" : "为了保护您的隐私，图片默认不显示")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !preferences.emailSuperPrivacyMode {
                    Button(action: {
                        viewModel.updateImageDisplayPreference(
                            for: message,
                            show: true,
                            remember: rememberChoice
                        )
                    }) {
                        Text("显示图片")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            if !preferences.emailSuperPrivacyMode {
                Toggle(isOn: $rememberChoice) {
                    Text("记住此选择（按发件人邮箱和域名）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(preferences.emailSuperPrivacyMode ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2), lineWidth: 1)
                }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Folder Row

struct FolderRow: View {
    let folder: EmailFolder
    let viewModel: EmailViewModel
    var isEmpty: Bool = false
    @State private var isHovered = false
    
    // 获取实际的邮件数量
    private var actualMessageCount: Int {
        EmailStore.shared.getMessageCount(for: folder.id)
    }
    
    // 判断是否选中
    private var isSelected: Bool {
        viewModel.selectedFolderId == folder.id
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: folder.type.icon)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .imageScale(.medium)
                .foregroundStyle(isEmpty ? Color.secondary.opacity(0.5) : (isSelected ? Color.accentColor : Color.secondary))
                .frame(width: 20)
            
            Text(folder.displayTitle)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular, design: .default))
                .foregroundStyle(isEmpty ? .tertiary : (isSelected ? .primary : .primary))
            
            Spacer()
            
            // 显示邮件数量和未读数量
            HStack(spacing: 6) {
                // 总邮件数（如果有邮件）
                if actualMessageCount > 0 {
                    Text("\(actualMessageCount)")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .secondary : .tertiary)
                }
                
                // 未读数量（如果有未读邮件）
                if folder.unreadCount > 0 {
                    Text("\(folder.unreadCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                
                // 删除按钮（仅对空文件夹显示，且仅在悬停时显示）
                if isEmpty && isHovered {
                    Button(action: {
                        Task {
                            await viewModel.deleteFolder(folder)
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(Color.red)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("删除空文件夹")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .listRowBackground(
            isSelected ? Color.accentColor.opacity(0.15) : Color.clear
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: EmailMessage
    let showAttachments: Bool
    let isMultiSelectMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // 多选模式下的复选框
            if isMultiSelectMode {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.blue : .secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .frame(width: 24)
            }
            
            EmailAvatarView(email: message.from.email, size: 36)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(message.from.name ?? message.from.email)
                        .font(message.isRead ? .subheadline : .headline)
                        .fontWeight(message.isRead ? .regular : .semibold)
                        .foregroundStyle(message.isRead ? .secondary : .primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(formatMessageDate(message.date))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // 回复标记图标
                    if message.hasBeenReplied {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(message.subject)
                        .font(.subheadline)
                        .fontWeight(message.isRead ? .regular : .medium)
                        .lineLimit(2)
                        .foregroundStyle(message.isRead ? .secondary : .primary)
                }
                .padding(.top, 2)
                
                // 优先显示 AI 摘要，否则显示预览
                if let aiSummary = message.aiSummary, !aiSummary.isEmpty {
                    Text(aiSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                } else if !message.preview.isEmpty {
                    Text(message.preview)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
                
                if showAttachments && message.hasAttachments {
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(Color.blue)
                        Text("\(message.attachments.count) 个附件")
                            .font(.caption2)
                            .foregroundStyle(Color.blue)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(message.isRead ? Color.clear : Color.blue.opacity(0.03))
        .contentShape(Rectangle())
        // 仅在多选模式下添加点击手势，避免阻止 List 的选择功能
        .if(isMultiSelectMode) { view in
            view.onTapGesture {
                onToggleSelection()
            }
        }
    }
}

// MARK: - View Extension for Conditional Modifier
private extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    EmailView()
}

// MARK: - Helpers

// MARK: - Date Formatter Cache

/// 缓存的日期格式化器（避免每次滚动都创建新实例）
private struct DateFormatterCache {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
    
    static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return formatter
    }()
    
    static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter
    }()
    
    static let yearMonthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()
}

/// 智能格式化邮件日期（使用缓存的格式化器）
func formatMessageDate(_ date: Date) -> String {
    let calendar = Calendar.current
    let now = Date()
    
    // 今天 - 显示时间
    if calendar.isDateInToday(date) {
        return DateFormatterCache.timeFormatter.string(from: date)
    }
    
    // 昨天
    if calendar.isDateInYesterday(date) {
        return "昨天 " + DateFormatterCache.timeFormatter.string(from: date)
    }
    
    // 本周内 - 显示星期
    if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
       date > weekAgo {
        return DateFormatterCache.weekdayFormatter.string(from: date)
    }
    
    // 今年内 - 显示月日
    if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
        return DateFormatterCache.monthDayFormatter.string(from: date)
    }
    
    // 更早 - 显示年月日
    return DateFormatterCache.yearMonthDayFormatter.string(from: date)
}

// MARK: - Helper Functions

/// 检测文件的 MIME 类型
private func detectMIMEType(for url: URL) -> String {
    if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
       let mimeType = UTType(uti)?.preferredMIMEType {
        return mimeType
    }
    
    // 根据扩展名推断
    let ext = url.pathExtension.lowercased()
    switch ext {
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "gif": return "image/gif"
    case "pdf": return "application/pdf"
    case "doc": return "application/msword"
    case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    case "xls": return "application/vnd.ms-excel"
    case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    case "zip": return "application/zip"
    case "txt": return "text/plain"
    default: return "application/octet-stream"
    }
}

/// 解析邮箱地址字符串，支持多种格式
private func parseEmailAddresses(_ text: String) -> [EmailContact] {
    guard !text.isEmpty else { return [] }
    
    let addresses = text.components(separatedBy: ",")
    return addresses.compactMap { addressStr in
        let trimmed = addressStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // 验证邮箱格式（简单验证）
        let emailPattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        guard trimmed.range(of: emailPattern, options: .regularExpression) != nil else {
            return nil
        }
        
        return EmailContact(email: trimmed)
    }
}

private extension String {
    func toAttributedHTML() -> AttributedString? {
        // 注入CSS样式来美化邮件显示
        let styledHTML = injectEmailStyles(into: self)
        guard let data = styledHTML.data(using: .utf8) else { return nil }
        
        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return AttributedString(attributed)
        }
        return nil
    }
    
    /// 向HTML中注入CSS样式
    func injectEmailStyles(into html: String) -> String {
        // Apple 设计风格样式 (参考 macOS Mail 和 Safari 阅读模式)
        // 注意：NSAttributedString 的 HTML 解析器较旧，仅支持 CSS2.1 属性，避免使用 clamp/var/calc 等
        let css = """
        <style>
        /* 基础重置 - 模拟一张干净的白纸 */
        body {
            font-family: -apple-system, "PingFang SC", "Helvetica Neue", Helvetica, Arial, sans-serif;
            font-size: 16px;
            line-height: 1.5;
            color: #1d1d1f; /* Apple 经典深灰，比纯黑更护眼 */
            background-color: #ffffff; /* 强制白底，确保与文字对比度 */
            margin: 0;
            padding: 0;
            word-wrap: break-word;
            -webkit-font-smoothing: antialiased;
        }
        
        /* 容器 - 增加统一的呼吸感内边距 */
        .content-wrapper {
            padding: 24px 16px;
            max-width: 100%;
            overflow-x: hidden;
        }
        
        /* 强制继承 - 覆盖垃圾邮件的内联样式 */
        p, div, span, font, td {
            font-family: inherit;
            line-height: inherit;
            color: inherit;
        }
        
        /* 段落优化 - 区分段落间距 */
        p {
            margin-top: 0.8em;
            margin-bottom: 0.8em;
        }
        
        /* 标题优化 - 层次分明 */
        h1, h2, h3, h4, h5, h6 {
            font-family: -apple-system, "PingFang SC", sans-serif;
            font-weight: 600;
            color: #000000;
            margin-top: 1.4em;
            margin-bottom: 0.6em;
            line-height: 1.3;
        }
        h1 { font-size: 24px; letter-spacing: -0.5px; }
        h2 { font-size: 20px; letter-spacing: -0.3px; }
        h3 { font-size: 18px; }
        
        /* 链接 - Apple 标准蓝 */
        a {
            color: #007AFF;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        
        /* 列表 - 增加缩进和间距 */
        ul, ol {
            margin: 12px 0;
            padding-left: 24px;
        }
        li {
            margin-bottom: 6px;
            padding-left: 4px;
        }
        
        /* 引用块 - 现代设计风格 */
        blockquote {
            margin: 16px 0;
            padding-left: 16px;
            border-left: 4px solid #d1d1d6; /* Apple System Gray 4 */
            color: #636366; /* Secondary Label Color */
            font-style: normal; /* 移除老气的斜体 */
        }
        
        /* 图片 - 圆角与自适应 */
        img {
            max-width: 100% !important;
            height: auto !important;
            border-radius: 6px;
            margin: 12px 0;
            display: block;
        }
        
        /* 代码块 - 清晰的等宽字体 */
        pre, code {
            font-family: "SF Mono", Menlo, Monaco, Courier, monospace;
            font-size: 13px;
            background-color: #f5f5f7;
            color: #1d1d1f;
            border-radius: 6px;
        }
        pre {
            padding: 12px;
            border: 1px solid #e5e5e5;
            overflow-x: auto;
            line-height: 1.4;
        }
        
        /* 表格 - 简洁线条 */
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 16px 0;
            font-size: 14px;
        }
        th, td {
            border: 1px solid #e5e5e5;
            padding: 8px 12px;
            text-align: left;
            vertical-align: top;
        }
        th {
            background-color: #f5f5f7;
            font-weight: 600;
        }
        
        /* 分割线 */
        hr {
            border: none;
            border-top: 1px solid #e5e5e5;
            margin: 24px 0;
        }
        </style>
        """
        
        // 预处理 HTML：移除可能干扰样式的 body 标签属性
        var processedHTML = html
        if let bodyRange = processedHTML.range(of: "<body[^>]*>", options: .regularExpression) {
            processedHTML.replaceSubrange(bodyRange, with: "<body>")
        }
        
        // 使用 content-wrapper 包裹内容，确保 padding 生效
        // 检查是否已经包含 body
        if processedHTML.localizedCaseInsensitiveContains("<body>") {
            processedHTML = processedHTML.replacingOccurrences(of: "<body>", with: "<body><div class=\"content-wrapper\">", options: .caseInsensitive)
            processedHTML = processedHTML.replacingOccurrences(of: "</body>", with: "</div></body>", options: .caseInsensitive)
        } else {
            // 如果没有 body 标签，直接包裹
            processedHTML = "<div class=\"content-wrapper\">\(processedHTML)</div>"
        }
        
        // 注入 CSS
        if let headRange = processedHTML.range(of: "<head>", options: .caseInsensitive) {
            processedHTML.insert(contentsOf: css, at: headRange.upperBound)
        } else if let htmlRange = processedHTML.range(of: "<html>", options: .caseInsensitive) {
            processedHTML.insert(contentsOf: "<head>\(css)</head>", at: htmlRange.upperBound)
        } else {
            processedHTML = "<!DOCTYPE html><html><head>\(css)</head><body>\(processedHTML)</body></html>"
        }
        
        return processedHTML
    }
}

// MARK: - Message Headers View

struct MessageHeadersView: View {
    let message: EmailMessage
    @ObservedObject var viewModel: EmailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var rawHeaders: String = ""
    @State private var isLoading = true
    @State private var rawMessageData: Data?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("正在加载邮件头信息...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // 基本信息
                            SectionView(title: "基本信息") {
                                InfoRow(label: "Message-ID", value: message.messageId ?? "无")
                                InfoRow(label: "UID", value: message.uid.map { "\($0)" } ?? "无")
                                InfoRow(label: "Thread-ID", value: message.threadId ?? "无")
                            }
                            
                            // 发件人和收件人
                            SectionView(title: "发件人和收件人") {
                                InfoRow(label: "From", value: message.from.displayName)
                                if !message.to.isEmpty {
                                    InfoRow(label: "To", value: message.to.map { $0.displayName }.joined(separator: ", "))
                                }
                                if !message.cc.isEmpty {
                                    InfoRow(label: "Cc", value: message.cc.map { $0.displayName }.joined(separator: ", "))
                                }
                                if !message.bcc.isEmpty {
                                    InfoRow(label: "Bcc", value: message.bcc.map { $0.displayName }.joined(separator: ", "))
                                }
                                if !message.replyTo.isEmpty {
                                    InfoRow(label: "Reply-To", value: message.replyTo.map { $0.displayName }.joined(separator: ", "))
                                }
                            }
                            
                            // 邮件信息
                            SectionView(title: "邮件信息") {
                                InfoRow(label: "Subject", value: message.subject)
                                InfoRow(label: "Date", value: formatFullDate(message.date))
                                if let receivedDate = message.receivedDate {
                                    InfoRow(label: "Received", value: formatFullDate(receivedDate))
                                }
                            }
                            
                            // 状态信息
                            SectionView(title: "状态信息") {
                                InfoRow(label: "已读", value: message.isRead ? "是" : "否")
                                InfoRow(label: "星标", value: message.isStarred ? "是" : "否")
                                InfoRow(label: "重要", value: message.isImportant ? "是" : "否")
                                InfoRow(label: "垃圾邮件", value: message.isSpam ? "是" : "否")
                                InfoRow(label: "已回复", value: message.hasBeenReplied ? "是" : "否")
                            }
                            
                            // 原始邮件头
                            if !rawHeaders.isEmpty {
                                SectionView(title: "原始邮件头") {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(rawHeaders)
                                            .font(.system(.body, design: .monospaced))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(12)
                                            .background(Color(NSColor.controlBackgroundColor))
                                            .cornerRadius(8)
                                        
                                        // 操作按钮
                                        HStack(spacing: 12) {
                                            Button(action: {
                                                copyHeaders()
                                            }) {
                                                Label("复制邮件头", systemImage: "doc.on.doc")
                                            }
                                            .buttonStyle(.bordered)
                                            
                                            Button(action: {
                                                Task {
                                                    await saveAsEML()
                                                }
                                            }) {
                                                Label("保存为 .eml", systemImage: "square.and.arrow.down")
                                            }
                                            .buttonStyle(.bordered)
                                            
                                            if rawMessageData != nil {
                                                Button(action: {
                                                    copyFullMessage()
                                                }) {
                                                    Label("复制完整邮件", systemImage: "doc.on.clipboard")
                                                }
                                                .buttonStyle(.bordered)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("邮件头信息")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !rawHeaders.isEmpty {
                        Button(action: {
                            copyHeaders()
                        }) {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if rawMessageData != nil {
                        Button(action: {
                            Task {
                                await saveAsEML()
                            }
                        }) {
                            Label("保存", systemImage: "square.and.arrow.down")
                        }
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 500)
        }
        .task {
            await loadHeaders()
        }
    }
    
    private func loadHeaders() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let account = viewModel.currentAccount,
              let folderId = message.folderId else {
            return
        }
        
        // 从 folders 中查找文件夹
        let folder = viewModel.folders.first(where: { $0.id == folderId })
        guard let folder = folder else {
            rawHeaders = "无法找到邮件所在文件夹"
            return
        }
        
        do {
            let rawData = try await EmailService.shared.fetchRawMessage(
                account: account,
                folder: folder,
                message: message
            )
            
            // 保存原始数据用于保存为 .eml
            rawMessageData = rawData
            
            // 解析邮件头（邮件头通常在第一个空行之前）
            if let rawString = String(data: rawData, encoding: .utf8) ??
                              String(data: rawData, encoding: .isoLatin1) {
                let components = rawString.components(separatedBy: "\n\n")
                if let headers = components.first {
                    rawHeaders = headers
                } else {
                    rawHeaders = rawString
                }
            } else {
                rawHeaders = "无法解析原始邮件头（编码问题）"
            }
        } catch {
            rawHeaders = "加载失败: \(error.localizedDescription)"
        }
    }
    
    private func copyHeaders() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(rawHeaders, forType: .string)
    }
    
    private func copyFullMessage() {
        guard let rawData = rawMessageData,
              let rawString = String(data: rawData, encoding: .utf8) ??
                              String(data: rawData, encoding: .isoLatin1) else {
            return
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(rawString, forType: .string)
    }
    
    private func saveAsEML() async {
        guard let rawData = rawMessageData else {
            // 如果没有原始数据，尝试使用 ViewModel 的方法
            await viewModel.saveMessageAsEML(message: message)
            return
        }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.init(filenameExtension: "eml")!]
        savePanel.nameFieldStringValue = sanitizeFilename(message.subject.isEmpty ? "邮件" : message.subject) + ".eml"
        savePanel.title = "保存邮件"
        savePanel.prompt = "保存"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try rawData.write(to: url)
                print("✅ [MessageHeadersView] 邮件已保存为 .eml 文件: \(url.path)")
            } catch {
                print("❌ [MessageHeadersView] 保存失败: \(error)")
            }
        }
    }
    
    private func sanitizeFilename(_ filename: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>")
        return filename.components(separatedBy: invalidChars).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .full
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

struct SectionView<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            
            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label + ":")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Delete Confirmation View

struct DeleteConfirmationView: View {
    @Binding var isPresented: Bool
    @Binding var deleteOnServer: Bool
    let messageCount: Int
    let onConfirm: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            Text("删除邮件")
                .font(.headline)
            
            // 说明文字
            Text(messageCount > 1 ? "确定要删除 \(messageCount) 封邮件吗？" : "确定要删除这封邮件吗？")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // 删除选项
            VStack(alignment: .leading, spacing: 12) {
                Text("删除方式：")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Button(action: {
                    deleteOnServer = false
                }) {
                    HStack {
                        Image(systemName: deleteOnServer ? "circle" : "checkmark.circle.fill")
                            .foregroundStyle(deleteOnServer ? .secondary : Color.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("仅本地删除")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("邮件将从本应用中删除，但服务器上仍保留")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(deleteOnServer ? Color.clear : Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    deleteOnServer = true
                }) {
                    HStack {
                        Image(systemName: deleteOnServer ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(deleteOnServer ? Color.blue : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("服务器删除")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("邮件将从服务器和本应用中删除")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(deleteOnServer ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // 按钮
            HStack(spacing: 12) {
                Button("取消") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("删除") {
                    onConfirm()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
        .frame(width: 450)
    }
}


