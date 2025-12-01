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
    @State private var showAttachmentPicker = false
    @FocusState private var isReplyBodyFocused: Bool
    @State private var replyBodyText: String = ""
    @State private var composeBodyText: String = ""
    @State private var bodyUpdateTask: Task<Void, Never>?
    
    var body: some View {
        HSplitView {
            // 左侧：文件夹列表
            folderListView
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 250)
            
            // 中间：邮件列表
            messageListView
                .frame(minWidth: 300, idealWidth: 400)
            
            // 右侧：邮件详情或编写面板
            if viewModel.showComposePanel {
                composeDetailView()
                    .frame(minWidth: 400, idealWidth: 500)
            } else if let message = viewModel.selectedMessage {
                messageDetailView(message: message)
                    .frame(minWidth: 400, idealWidth: 500)
            } else {
                emptyDetailView
                    .frame(minWidth: 400, idealWidth: 500)
            }
        }
        .navigationTitle("邮箱")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    viewModel.initComposeDraft()
                }) {
                    Label("新邮件", systemImage: "square.and.pencil")
                }
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    showAccountManagement = true
                }) {
                    Label("账号管理", systemImage: "person.crop.circle.badge.plus")
                }
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    if let account = viewModel.currentAccount {
                        Task {
                            await viewModel.syncAccount(account)
                        }
                    }
                }) {
                    Label("同步", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .sheet(isPresented: $showAccountManagement) {
            EmailAccountManagementView()
        }
        .onAppear {
            // 视图出现时，后台加载数据,不阻塞UI
            Task.detached(priority: .userInitiated) {
                await viewModel.loadInitialData()
            }
        }
        .onChange(of: viewModel.selectedAccountId) { _, _ in
            // 账号切换时，后台重新加载数据
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
                
                Picker("账号", selection: accountBinding) {
                    ForEach(viewModel.accounts) { account in
                        Text(account.displayName).tag(Optional(account.id))
                    }
                }
                .pickerStyle(.menu)
                .padding()
            } else {
                // 没有账号时的提示
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("没有邮箱账号")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("添加账号") {
                        showAccountManagement = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            
            Divider()
            
            // 文件夹列表
            if viewModel.selectedAccountId != nil {
                let visibleFolders = viewModel.folders.filter { !$0.isGarbled }
                
                if visibleFolders.isEmpty {
                    // 文件夹列表为空时的提示
                    VStack(spacing: 8) {
                        if viewModel.isLoadingFolders {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("正在加载文件夹...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("没有文件夹")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("刷新") {
                                if let account = viewModel.currentAccount {
                                    Task {
                                        await viewModel.loadFolders(account: account)
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    let folderBinding = Binding<UUID?>(
                        get: { viewModel.selectedFolderId },
                        set: { folderId in
                            // 立即执行，不需要延迟（ViewModel已经优化为零卡顿）
                            if let folderId = folderId,
                               let folder = visibleFolders.first(where: { $0.id == folderId }) {
                                viewModel.selectFolder(folder)
                            } else {
                                viewModel.showAllMessages()
                            }
                        }
                    )
                    
                    List(selection: folderBinding) {
                        Section {
                            // 写邮件按钮
                            Button(action: {
                                viewModel.initComposeDraft()
                            }) {
                                HStack {
                                    Image(systemName: "square.and.pencil")
                                        .foregroundStyle(.blue)
                                        .font(.system(size: 16, weight: .medium))
                                    Text("写邮件")
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            
                            Label("所有邮件", systemImage: "tray.full")
                                .tag(Optional<UUID>.none)
                                .contentShape(Rectangle())
                        }
                        ForEach(visibleFolders) { folder in
                            FolderRow(folder: folder)
                                .tag(folder.id)
                        }
                    }
                    .listStyle(.sidebar)
                }
            } else {
                // 没有选择账号时的提示
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("请选择邮箱账号")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }
    
    // MARK: - Message List
    
    private var messageListView: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索邮件", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 邮件列表
            if viewModel.isLoading && viewModel.messages.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.messages.isEmpty && !viewModel.isLoading {
                emptyMessageListView
            } else {
                ScrollViewReader { proxy in
                    let messageBinding = Binding<UUID?>(
                        get: { viewModel.selectedMessageId },
                        set: { newId in
                            // 延迟设置，避免在视图更新期间触发状态变更
                            DispatchQueue.main.async {
                                if let id = newId,
                                   let message = viewModel.messages.first(where: { $0.id == id }) {
                                    viewModel.selectMessage(message)
                                } else {
                                    viewModel.selectedMessageId = nil
                                }
                            }
                        }
                    )
                    
                    List(selection: messageBinding) {
                        ForEach(viewModel.searchText.isEmpty ? viewModel.messages : viewModel.searchResults) { message in
                            MessageRow(message: message, showAttachments: viewModel.showAttachments)
                                .tag(message.id)
                                .onAppear {
                                    // 滚动到底部时自动加载更多
                                    if message.id == viewModel.messages.last?.id {
                                        DispatchQueue.main.async {
                                            viewModel.loadMoreMessages()
                                        }
                                    }
                                }
                        }
                        
                        // 加载更多指示器
                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("加载更多...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding()
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }
    
    private var emptyMessageListView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("没有邮件")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            if viewModel.selectedFolderId == nil {
                Text("暂无邮件，稍后同步或选择文件夹")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Message Detail
    
    private func messageDetailView(message: EmailMessage) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 编写面板（新邮件）
                    if viewModel.showComposePanel, let draft = viewModel.composeDraft {
                        composePanelView(draft: draft)
                            .id("compose-panel")
                    }
                    
                    // 回复面板
                    if viewModel.showReplyPanel, let draft = viewModel.replyDraft {
                        Divider()
                        replyPanelView(draft: draft, originalMessage: message)
                            .id("reply-panel")
                    }
                    
                    // 邮件头部（带操作按钮）
                    messageHeaderWithActions(message: message)
                    
                    // AI摘要（如果有）- 使用渐变背景和毛玻璃效果
                    if let summary = message.aiSummary, !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .font(.title3)
                                Text("AI 摘要")
                                    .font(.headline)
                                    .fontWeight(.semibold)
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
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.blue.opacity(0.08),
                                                    Color.purple.opacity(0.05)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.blue.opacity(0.3),
                                                            Color.purple.opacity(0.2)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1
                                                )
                                        }
                                }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Divider()
                    
                    // 邮件正文 - 增强卡片质感
                    Group {
                        if let htmlBody = message.htmlBody,
                           let attributed = htmlBody.toAttributedHTML() {
                            Text(attributed)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white)
                        } else if let textBody = message.textBody, !textBody.isEmpty {
                            Text(textBody)
                                .font(.system(size: 16)) // 匹配 HTML 注入的 16px
                                .lineSpacing(6) // 匹配 line-height: 1.5
                                .foregroundStyle(Color(red: 29/255, green: 29/255, blue: 31/255)) // Apple 文字黑 #1d1d1f
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20) // 匹配 CSS 中的 content-wrapper padding
                                .background(Color.white)
                        } else {
                            Text(message.preview)
                                .font(.system(size: 16))
                                .foregroundStyle(Color.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                                .background(Color.white)
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
                    
                    // 外部资源加载提示
                    if message.containsRemoteResources && !viewModel.showImages {
                        remoteResourcesBanner(message: message)
                    }
                    
                    // 附件列表（始终显示，如果有附件）
                    if !message.attachments.isEmpty {
                        Divider()
                        attachmentsView(attachments: message.attachments)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.showReplyPanel) { _, newValue in
                if newValue {
                    // 初始化正文内容
                    if let draft = viewModel.replyDraft {
                        replyBodyText = draft.body
                    }
                    // 延迟一点确保视图已渲染
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo("reply-panel", anchor: .top)
                        }
                        // 设置焦点
                        isReplyBodyFocused = true
                    }
                } else {
                    // 关闭时清空
                    replyBodyText = ""
                    bodyUpdateTask?.cancel()
                }
            }
            .onChange(of: viewModel.replyDraft?.body) { _, newValue in
                // 当草稿从外部更新时（比如切换回复类型），同步到本地状态
                if let newValue = newValue, !newValue.isEmpty {
                    // 只在本地状态为空或等于当前草稿内容时才更新，避免覆盖用户正在输入的内容
                    if replyBodyText.isEmpty || replyBodyText == viewModel.replyDraft?.body {
                        replyBodyText = newValue
                    }
                }
            }
            .onChange(of: viewModel.showComposePanel) { _, newValue in
                if newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo("compose-panel", anchor: .top)
                        }
                        isReplyBodyFocused = true
                    }
                }
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
                        }
                    }) {
                        Label("全部", systemImage: "arrowshape.turn.up.left.2")
                    }
                    .disabled(message.isNoReply)
                    
                    Button(action: {
                        viewModel.initReplyDraft(for: message, type: .forward)
                    }) {
                        Label("转发", systemImage: "arrowshape.turn.up.right")
                    }
                }
                
                Spacer()
                
                // 右侧操作按钮组 - 使用图标按钮，更紧凑
                HStack(spacing: 4) {
                    // 星标按钮
                    Button(action: {
                        Task {
                            await viewModel.toggleStar(message)
                        }
                    }) {
                        Image(systemName: message.isStarred ? "star.fill" : "star")
                            .foregroundStyle(message.isStarred ? .yellow : .secondary)
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
                                .foregroundStyle(.orange)
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
                        Task {
                            await viewModel.deleteMessage(message)
                        }
                    }) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
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
        HStack {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
            Text("此邮件包含外部图片或资源")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: {
                viewModel.showImages = true
            }) {
                Text("加载外部资源")
                    .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
    
    private func replyPanelView(draft: ReplyDraft, originalMessage: EmailMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 回复类型切换
            Picker("", selection: Binding(
                get: { draft.replyType },
                set: { newType in
                    if let message = viewModel.selectedMessage {
                        // 先同步当前输入的内容
                        viewModel.updateReplyField(body: replyBodyText)
                        viewModel.initReplyDraft(for: message, type: newType)
                        // 更新本地状态以匹配新的草稿
                        if let newDraft = viewModel.replyDraft {
                            replyBodyText = newDraft.body
                        }
                    }
                }
            )) {
                Text("回复").tag(ReplyDraft.ReplyType.reply)
                Text("回复全部").tag(ReplyDraft.ReplyType.replyAll)
                Text("转发").tag(ReplyDraft.ReplyType.forward)
            }
            .pickerStyle(.segmented)
            
            // To 字段
            VStack(alignment: .leading, spacing: 4) {
                Text("收件人")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("收件人", text: Binding(
                    get: { draft.to.map { $0.displayName }.joined(separator: ", ") },
                    set: { text in
                        let contacts = parseEmailAddresses(text)
                        viewModel.updateReplyField(to: contacts)
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
            
            // Cc/Bcc 折叠区域
            if viewModel.showCcBcc {
                VStack(alignment: .leading, spacing: 4) {
                    Text("抄送")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("抄送", text: Binding(
                        get: { draft.cc.map { $0.displayName }.joined(separator: ", ") },
                        set: { text in
                            let contacts = parseEmailAddresses(text)
                            viewModel.updateReplyField(cc: contacts)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    
                    Text("密送")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("密送", text: Binding(
                        get: { draft.bcc.map { $0.displayName }.joined(separator: ", ") },
                        set: { text in
                            let contacts = parseEmailAddresses(text)
                            viewModel.updateReplyField(bcc: contacts)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            } else {
                Button(action: {
                    viewModel.showCcBcc = true
                }) {
                    Text("添加抄送/密送")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            
            // 主题
            VStack(alignment: .leading, spacing: 4) {
                Text("主题")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("主题", text: Binding(
                    get: { draft.subject },
                    set: { newValue in
                        // 使用防抖更新主题
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms 防抖
                            viewModel.updateReplyField(subject: newValue)
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
            
            // 正文编辑区
            TextEditor(text: $replyBodyText)
            .frame(minHeight: 150)
            .padding(4)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .focused($isReplyBodyFocused)
            .onChange(of: replyBodyText) { _, newValue in
                // 取消之前的更新任务
                bodyUpdateTask?.cancel()
                // 使用防抖，延迟更新 ViewModel（避免每次输入都触发视图更新）
                bodyUpdateTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms 防抖
                    if !Task.isCancelled {
                        await MainActor.run {
                            viewModel.updateReplyField(body: newValue)
                        }
                    }
                }
            }
            .onAppear {
                // 初始化时同步内容（仅在首次显示时）
                if replyBodyText.isEmpty {
                    replyBodyText = draft.body
                }
            }
            
            // 附件列表
            if !draft.attachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("附件 (\(draft.attachments.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(draft.attachments) { attachment in
                        HStack {
                            Image(systemName: attachmentIcon(for: attachment.mimeType))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            
                            Text(attachment.filename)
                                .font(.caption)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Button(action: {
                                viewModel.removeAttachmentFromReply(attachment.id)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // 添加附件按钮
            Button(action: {
                showAttachmentPicker = true
            }) {
                Label("添加附件", systemImage: "paperclip")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .fileImporter(
                isPresented: $showAttachmentPicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    for url in urls {
                        // 需要访问权限
                        _ = url.startAccessingSecurityScopedResource()
                        defer { url.stopAccessingSecurityScopedResource() }
                        
                        let filename = url.lastPathComponent
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                        let mimeType = detectMIMEType(for: url)
                        
                        let attachment = EmailAttachment(
                            filename: filename,
                            mimeType: mimeType,
                            size: fileSize,
                            localPath: url.path
                        )
                        
                        if viewModel.showComposePanel {
                            viewModel.addAttachmentToCompose(attachment)
                        } else {
                            viewModel.addAttachmentToReply(attachment)
                        }
                    }
                case .failure(let error):
                    viewModel.errorMessage = "选择文件失败: \(error.localizedDescription)"
                }
            }
            
            // 操作按钮
            HStack {
                Spacer()
                Button("取消") {
                    bodyUpdateTask?.cancel()
                    replyBodyText = ""
                    viewModel.replyDraft = nil
                    viewModel.showReplyPanel = false
                }
                .buttonStyle(.bordered)
                
                Button("发送") {
                    // 发送前立即同步正文内容
                    viewModel.updateReplyField(body: replyBodyText)
                    Task {
                        do {
                            try await viewModel.sendReply()
                            // 发送成功后清空本地状态
                            replyBodyText = ""
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("选择一封邮件查看详情")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Compose View
    
    private func composeDetailView() -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let draft = viewModel.composeDraft {
                        composePanelView(draft: draft)
                            .id("compose-panel")
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.showComposePanel) { _, newValue in
                if newValue {
                    // 初始化正文内容
                    if let draft = viewModel.composeDraft {
                        composeBodyText = draft.body
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo("compose-panel", anchor: .top)
                        }
                        isReplyBodyFocused = true
                    }
                } else {
                    // 关闭时清空
                    composeBodyText = ""
                    bodyUpdateTask?.cancel()
                }
            }
        }
    }
    
    private func composePanelView(draft: ReplyDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack {
                Text("新邮件")
                    .font(.headline)
                Spacer()
                Button(action: {
                    bodyUpdateTask?.cancel()
                    composeBodyText = ""
                    viewModel.composeDraft = nil
                    viewModel.showComposePanel = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // To 字段
            VStack(alignment: .leading, spacing: 4) {
                Text("收件人")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("收件人", text: Binding(
                    get: { draft.to.map { $0.displayName }.joined(separator: ", ") },
                    set: { text in
                        let contacts = parseEmailAddresses(text)
                        viewModel.updateComposeField(to: contacts)
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
            
            // Cc/Bcc 折叠区域
            if viewModel.showCcBcc {
                VStack(alignment: .leading, spacing: 4) {
                    Text("抄送")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("抄送", text: Binding(
                        get: { draft.cc.map { $0.displayName }.joined(separator: ", ") },
                        set: { text in
                            let contacts = parseEmailAddresses(text)
                            viewModel.updateComposeField(cc: contacts)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    
                    Text("密送")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("密送", text: Binding(
                        get: { draft.bcc.map { $0.displayName }.joined(separator: ", ") },
                        set: { text in
                            let contacts = parseEmailAddresses(text)
                            viewModel.updateComposeField(bcc: contacts)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            } else {
                Button(action: {
                    viewModel.showCcBcc = true
                }) {
                    Text("添加抄送/密送")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            
            // 主题
            VStack(alignment: .leading, spacing: 4) {
                Text("主题")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("主题", text: Binding(
                    get: { draft.subject },
                    set: { viewModel.updateComposeField(subject: $0) }
                ))
                .textFieldStyle(.roundedBorder)
            }
            
            // 正文编辑区
            TextEditor(text: $composeBodyText)
            .frame(minHeight: 200)
            .padding(4)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .focused($isReplyBodyFocused)
            .onChange(of: composeBodyText) { _, newValue in
                // 取消之前的更新任务
                bodyUpdateTask?.cancel()
                // 使用防抖，延迟更新 ViewModel（避免每次输入都触发视图更新）
                bodyUpdateTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms 防抖
                    if !Task.isCancelled {
                        await MainActor.run {
                            viewModel.updateComposeField(body: newValue)
                        }
                    }
                }
            }
            .onAppear {
                // 初始化时同步内容（仅在首次显示时）
                if composeBodyText.isEmpty {
                    composeBodyText = draft.body
                }
            }
            
            // 附件列表
            if !draft.attachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("附件 (\(draft.attachments.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(draft.attachments) { attachment in
                        HStack {
                            Image(systemName: attachmentIcon(for: attachment.mimeType))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            
                            Text(attachment.filename)
                                .font(.caption)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Button(action: {
                                viewModel.removeAttachmentFromCompose(attachment.id)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // 添加附件按钮
            Button(action: {
                showAttachmentPicker = true
            }) {
                Label("添加附件", systemImage: "paperclip")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .fileImporter(
                isPresented: $showAttachmentPicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    for url in urls {
                        _ = url.startAccessingSecurityScopedResource()
                        defer { url.stopAccessingSecurityScopedResource() }
                        
                        let filename = url.lastPathComponent
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                        let mimeType = detectMIMEType(for: url)
                        
                        let attachment = EmailAttachment(
                            filename: filename,
                            mimeType: mimeType,
                            size: fileSize,
                            localPath: url.path
                        )
                        
                        if viewModel.showComposePanel {
                            viewModel.addAttachmentToCompose(attachment)
                        } else {
                            viewModel.addAttachmentToReply(attachment)
                        }
                    }
                case .failure(let error):
                    viewModel.errorMessage = "选择文件失败: \(error.localizedDescription)"
                }
            }
            
            // 操作按钮
            HStack {
                Spacer()
                Button("取消") {
                    bodyUpdateTask?.cancel()
                    composeBodyText = ""
                    viewModel.composeDraft = nil
                    viewModel.showComposePanel = false
                }
                .buttonStyle(.bordered)
                
                Button("发送") {
                    // 发送前立即同步正文内容
                    viewModel.updateComposeField(body: composeBodyText)
                    Task {
                        do {
                            try await viewModel.sendCompose()
                            // 发送成功后清空本地状态
                            composeBodyText = ""
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Folder Row

struct FolderRow: View {
    let folder: EmailFolder
    
    var body: some View {
        HStack {
            Image(systemName: folder.type.icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Text(folder.displayTitle)
            
            Spacer()
            
            if folder.unreadCount > 0 {
                Text("\(folder.unreadCount)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: EmailMessage
    let showAttachments: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
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
                
                Text(message.subject)
                    .font(.subheadline)
                    .fontWeight(message.isRead ? .regular : .medium)
                    .lineLimit(2)
                    .foregroundStyle(message.isRead ? .secondary : .primary)
                    .padding(.top, 2)
                
                if !message.preview.isEmpty {
                    Text(message.preview)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
                
                if showAttachments && message.hasAttachments {
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text("\(message.attachments.count) 个附件")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(message.isRead ? Color.clear : Color.blue.opacity(0.03))
        .contentShape(Rectangle())
    }
}

#Preview {
    EmailView()
}

// MARK: - Helpers

/// 智能格式化邮件日期
private func formatMessageDate(_ date: Date) -> String {
    let calendar = Calendar.current
    let now = Date()
    
    // 今天 - 显示时间
    if calendar.isDateInToday(date) {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // 昨天
    if calendar.isDateInYesterday(date) {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "昨天 " + formatter.string(from: date)
    }
    
    // 本周内 - 显示星期
    if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
       date > weekAgo {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: date)
    }
    
    // 今年内 - 显示月日
    if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
    
    // 更早 - 显示年月日
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy/MM/dd"
    return formatter.string(from: date)
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

