//
//  EmailComposeWindowView.swift
//  fastv
//
//  Created for email compose window
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 支持获取选中文本的 TextEditor
struct SelectableTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSelectionChange: ((String, NSRange?) -> Void)?
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        context.coordinator.textView = textView
        textView.delegate = context.coordinator
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            let wasEditing = textView.window?.firstResponder == textView
            textView.string = text
            // 恢复选中范围（如果之前有选中）
            if selectedRange.location <= text.count {
                let newLocation = min(selectedRange.location, text.count)
                let newLength = min(selectedRange.length, text.count - newLocation)
                textView.setSelectedRange(NSRange(location: newLocation, length: newLength))
            }
            // 恢复焦点
            if wasEditing {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableTextEditor
        var textView: NSTextView?
        
        init(_ parent: SelectableTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            parent.text = textView.string
            updateSelection()
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            updateSelection()
        }
        
        private func updateSelection() {
            guard let textView = textView else { return }
            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0 && selectedRange.location < textView.string.count {
                let nsString = textView.string as NSString
                let safeRange = NSRange(
                    location: selectedRange.location,
                    length: min(selectedRange.length, nsString.length - selectedRange.location)
                )
                let selectedText = nsString.substring(with: safeRange)
                parent.onSelectionChange?(selectedText, safeRange)
            } else {
                parent.onSelectionChange?("", nil)
            }
        }
    }
}

/// 邮件撰写窗口视图（独立弹出窗口，类似 Apple Mail）
struct EmailComposeWindowView: View {
    @ObservedObject var viewModel: EmailViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var toText: String = ""
    @State private var ccText: String = ""
    @State private var bccText: String = ""
    @State private var subjectText: String = ""
    @State private var bodyText: String = ""
    @State private var htmlBodyText: String? = nil
    @State private var showCcBcc: Bool = false
    @State private var showAttachmentPicker: Bool = false
    @FocusState private var focusedField: ComposeField?
    @State private var selectedText: String = ""
    @State private var selectedRange: NSRange? = nil
    @State private var draftId: UUID
    @State private var autoSaveTask: Task<Void, Never>?
    
    enum ComposeField {
        case to, cc, bcc, subject, body
    }
    
    var composeType: ComposeType
    var originalMessage: EmailMessage?
    
    enum ComposeType {
        case new
        case reply(EmailMessage)
        case replyAll(EmailMessage)
        case forward(EmailMessage)
    }
    
    init(viewModel: EmailViewModel, composeType: ComposeType) {
        self.viewModel = viewModel
        self.composeType = composeType
        
        // 生成草稿ID：新邮件使用新UUID，回复/转发使用原邮件ID
        let draftIdValue: UUID
        switch composeType {
        case .new:
            self.originalMessage = nil
            draftIdValue = UUID()
        case .reply(let msg), .replyAll(let msg), .forward(let msg):
            self.originalMessage = msg
            draftIdValue = msg.id // 使用原邮件ID作为草稿ID
        }
        self._draftId = State(initialValue: draftIdValue)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 工具栏
                toolbarView
                
                Divider()
                
                // 表单内容
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 收件人字段
                        composeFieldView(
                            label: "收件人",
                            text: $toText,
                            placeholder: "收件人",
                            field: .to
                        )
                        
                        // Cc/Bcc 字段（可展开）
                        if showCcBcc {
                            composeFieldView(
                                label: "抄送",
                                text: $ccText,
                                placeholder: "抄送",
                                field: .cc
                            )
                            
                            composeFieldView(
                                label: "密送",
                                text: $bccText,
                                placeholder: "密送",
                                field: .bcc
                            )
                        } else {
                            Button(action: {
                                showCcBcc = true
                            }) {
                                Text("添加抄送/密送")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // 主题字段
                        composeFieldView(
                            label: "主题",
                            text: $subjectText,
                            placeholder: "主题",
                            field: .subject
                        )
                        
                        Divider()
                        
                        // 附件列表
                        if !currentAttachments.isEmpty {
                            attachmentsListView
                        }
                        
                        // 正文编辑区
                        SelectableTextEditor(text: $bodyText) { selectedText, selectedRange in
                            self.selectedText = selectedText
                            self.selectedRange = selectedRange
                        }
                        .frame(minHeight: 300)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        // 发送进度条（在正文下方）
                        if isSending {
                            VStack(alignment: .leading, spacing: 8) {
                                ProgressView(value: viewModel.sendProgress, total: 1.0)
                                    .progressViewStyle(.linear)
                                
                                if !viewModel.sendStatusText.isEmpty {
                                    Text(viewModel.sendStatusText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding()
                }
            }
            .frame(minWidth: 600, minHeight: 500)
            .navigationTitle(composeTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        Task {
                            await sendMessage()
                        }
                    }) {
                        Label("发送", systemImage: "paperplane.fill")
                    }
                    .disabled(!canSend || isSending)
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        showAttachmentPicker = true
                    }) {
                        Label("附件", systemImage: "paperclip")
                    }
                }
                
                // AI 美化按钮组
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button(action: {
                            Task {
                                await polishEmailBody(mode: .chineseFormal)
                            }
                        }) {
                            Label("AI 中文润色", systemImage: "wand.and.stars")
                        }
                        .disabled(isPolishing)
                        
                        Button(action: {
                            Task {
                                await polishEmailBody(mode: .englishEmail)
                            }
                        }) {
                            Label("AI 英文邮件", systemImage: "globe")
                        }
                        .disabled(isPolishing)
                        
                        Divider()
                        
                        Button(action: {
                            Task {
                                await polishEmailBody(mode: .translateToChinese)
                            }
                        }) {
                            Label("翻译成中文并美化", systemImage: "character.bubble")
                        }
                        .disabled(isPolishing)
                        
                        Button(action: {
                            Task {
                                await polishEmailBody(mode: .translateToEnglish)
                            }
                        }) {
                            Label("翻译成英文并美化", systemImage: "character.bubble.fill")
                        }
                        .disabled(isPolishing)
                    } label: {
                        if isPolishing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Label("AI 美化", systemImage: "sparkles")
                        }
                    }
                    .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPolishing)
                    .help(selectedText.isEmpty ? "美化全文" : "美化选中文本（\(selectedText.count) 字符）")
                }
            }
        }
        .onAppear {
            initializeComposeFields()
            // 加载草稿（如果有）
            Task {
                await loadDraft()
            }
        }
        .onChange(of: toText) { _, _ in
            autoSaveDraft()
        }
        .onChange(of: ccText) { _, _ in
            autoSaveDraft()
        }
        .onChange(of: bccText) { _, _ in
            autoSaveDraft()
        }
        .onChange(of: subjectText) { _, _ in
            autoSaveDraft()
        }
        .onChange(of: bodyText) { _, _ in
            autoSaveDraft()
        }
        .onChange(of: viewModel.composeDraft?.body) { _, newValue in
            if let newValue = newValue, case .new = composeType {
                bodyText = newValue
            }
        }
        .onChange(of: viewModel.replyDraft?.body) { _, newValue in
            if let newValue = newValue {
                switch composeType {
                case .reply, .replyAll, .forward:
                    bodyText = newValue
                case .new:
                    break
                }
            }
        }
        .onChange(of: viewModel.sendStatusText) { _, newStatus in
            // 当状态文本显示"发送成功！"时，等待提示音播放后关闭窗口
            if newStatus == "发送成功！" {
                // ViewModel 中已经有 0.5 秒延迟并播放提示音，这里再等待 0.3 秒确保提示音播放完成
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    dismiss()
                }
            }
        }
        .onDisappear {
            // 窗口关闭时，如果未发送成功，保存草稿
            if viewModel.sendStatusText != "发送成功！" {
                Task {
                    await saveDraft()
                }
            }
        }
        .fileImporter(
            isPresented: $showAttachmentPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleAttachmentSelection(result)
        }
    }
    
    private var composeTitle: String {
        switch composeType {
        case .new:
            return "新邮件"
        case .reply:
            return "回复"
        case .replyAll:
            return "回复全部"
        case .forward:
            return "转发"
        }
    }
    
    private var currentAttachments: [EmailAttachment] {
        switch composeType {
        case .new:
            return viewModel.composeDraft?.attachments ?? []
        case .reply, .replyAll, .forward:
            return viewModel.replyDraft?.attachments ?? []
        }
    }
    
    private var canSend: Bool {
        !toText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !subjectText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var toolbarView: some View {
        HStack(spacing: 12) {
            // 格式化工具栏（简化版）
            Button(action: {}) {
                Image(systemName: "bold")
            }
            .buttonStyle(.plain)
            
            Button(action: {}) {
                Image(systemName: "italic")
            }
            .buttonStyle(.plain)
            
            Divider()
                .frame(height: 20)
            
            Button(action: {
                showAttachmentPicker = true
            }) {
                Image(systemName: "paperclip")
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func composeFieldView(
        label: String,
        text: Binding<String>,
        placeholder: String,
        field: ComposeField
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: field)
        }
    }
    
    private var attachmentsListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("附件")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            ForEach(currentAttachments) { attachment in
                HStack {
                    Image(systemName: attachmentIcon(for: attachment.mimeType))
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.subheadline)
                        Text(attachment.sizeString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        removeAttachment(attachment.id)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
    
    private func attachmentIcon(for mimeType: String) -> String {
        if mimeType.hasPrefix("image/") {
            return "photo"
        } else if mimeType == "application/pdf" {
            return "doc.fill"
        } else if mimeType.hasPrefix("text/") {
            return "doc.text.fill"
        } else {
            return "doc"
        }
    }
    
    // MARK: - AI Polish Methods
    
    private var isPolishing: Bool {
        switch composeType {
        case .new:
            return viewModel.isPolishingCompose
        case .reply, .replyAll, .forward:
            return viewModel.isPolishingReply
        }
    }
    
    private var isSending: Bool {
        switch composeType {
        case .new:
            return viewModel.isSendingCompose
        case .reply, .replyAll, .forward:
            return viewModel.isSendingReply
        }
    }
    
    private func polishEmailBody(mode: EmailAIService.PolishMode) async {
        // 先同步当前正文到 ViewModel
        syncBodyToViewModel()
        
        let hasSelection = !selectedText.isEmpty && selectedRange != nil
        
        let result: String?
        switch composeType {
        case .new:
            result = await viewModel.aiPolishComposeDraft(
                mode: mode,
                selectedText: hasSelection ? selectedText : nil,
                selectedRange: selectedRange
            )
        case .reply, .replyAll, .forward:
            result = await viewModel.aiPolishReplyDraft(
                mode: mode,
                selectedText: hasSelection ? selectedText : nil,
                selectedRange: selectedRange
            )
        }
        
        // 同步美化后的正文回 UI
        if let result = result {
            bodyText = result
            // 如果有选中文本，美化后应该选中美化后的内容
            // 但为了简化，我们清空选中状态，让用户看到完整结果
            selectedText = ""
            selectedRange = nil
        }
    }
    
    private func syncBodyToViewModel() {
        switch composeType {
        case .new:
            viewModel.updateComposeField(body: bodyText)
        case .reply, .replyAll, .forward:
            viewModel.updateReplyField(body: bodyText)
        }
    }
    
    
    private func initializeComposeFields() {
        switch composeType {
        case .new:
            if let draft = viewModel.composeDraft {
                toText = draft.to.map { $0.email }.joined(separator: ", ")
                ccText = draft.cc.map { $0.email }.joined(separator: ", ")
                bccText = draft.bcc.map { $0.email }.joined(separator: ", ")
                subjectText = draft.subject
                bodyText = draft.body
            }
            
        case .reply(_), .replyAll(_), .forward(_):
            // 使用 viewModel 的草稿（initReplyDraft 已经设置好了）
            if let draft = viewModel.replyDraft {
                toText = draft.to.map { $0.email }.joined(separator: ", ")
                ccText = draft.cc.map { $0.email }.joined(separator: ", ")
                bccText = draft.bcc.map { $0.email }.joined(separator: ", ")
                subjectText = draft.subject
                bodyText = draft.body
            }
        }
    }
    
    private func handleAttachmentSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                addAttachment(from: url)
            }
        case .failure(let error):
            print("❌ [EmailComposeWindow] 选择附件失败: \(error)")
        }
    }
    
    private func addAttachment(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("⚠️ [EmailComposeWindow] 无法访问文件: \(url.path)")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard let data = try? Data(contentsOf: url) else {
            print("⚠️ [EmailComposeWindow] 无法读取文件: \(url.path)")
            return
        }
        
        let filename = url.lastPathComponent
        let mimeType = mimeTypeForFile(at: url)
        
        // 保存到临时目录
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(filename)
        
        do {
            try data.write(to: tempFile)
            
            let attachment = EmailAttachment(
                filename: filename,
                mimeType: mimeType,
                size: Int64(data.count),
                localPath: tempFile.path
            )
            
            switch composeType {
            case .new:
                viewModel.addAttachmentToCompose(attachment)
            case .reply, .replyAll, .forward:
                viewModel.addAttachmentToReply(attachment)
            }
        } catch {
            print("❌ [EmailComposeWindow] 保存附件失败: \(error)")
        }
    }
    
    private func removeAttachment(_ id: UUID) {
        switch composeType {
        case .new:
            viewModel.removeAttachmentFromCompose(id)
        case .reply, .replyAll, .forward:
            viewModel.removeAttachmentFromReply(id)
        }
    }
    
    private func mimeTypeForFile(at url: URL) -> String {
        if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
           let mimeType = UTType(uti)?.preferredMIMEType {
            return mimeType
        }
        
        // 回退到基于扩展名的猜测
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return "application/pdf"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "txt":
            return "text/plain"
        case "doc", "docx":
            return "application/msword"
        case "xls", "xlsx":
            return "application/vnd.ms-excel"
        default:
            return "application/octet-stream"
        }
    }
    
    private func sendMessage() async {
        let toContacts = parseEmailAddresses(toText)
        let ccContacts = parseEmailAddresses(ccText)
        let bccContacts = parseEmailAddresses(bccText)
        
        guard let account = viewModel.currentAccount else {
            print("❌ [EmailComposeWindow] 没有选中账号")
            return
        }
        
        do {
            switch composeType {
            case .new:
                try await viewModel.sendComposeMessage(
                    account: account,
                    to: toContacts,
                    cc: ccContacts,
                    bcc: bccContacts,
                    subject: subjectText,
                    body: bodyText,
                    htmlBody: htmlBodyText
                )
                
            case .reply(let originalMessage):
                try await viewModel.sendReplyMessage(
                    account: account,
                    originalMessage: originalMessage,
                    to: toContacts,
                    cc: ccContacts,
                    bcc: bccContacts,
                    subject: subjectText,
                    body: bodyText,
                    htmlBody: htmlBodyText,
                    replyType: .reply
                )
                
                // 标记原邮件为已回复
                await viewModel.markMessageAsReplied(messageId: originalMessage.id)
                
            case .replyAll(let originalMessage):
                try await viewModel.sendReplyMessage(
                    account: account,
                    originalMessage: originalMessage,
                    to: toContacts,
                    cc: ccContacts,
                    bcc: bccContacts,
                    subject: subjectText,
                    body: bodyText,
                    htmlBody: htmlBodyText,
                    replyType: .replyAll
                )
                
                // 标记原邮件为已回复
                await viewModel.markMessageAsReplied(messageId: originalMessage.id)
                
            case .forward(let originalMessage):
                try await viewModel.sendReplyMessage(
                    account: account,
                    originalMessage: originalMessage,
                    to: toContacts,
                    cc: ccContacts,
                    bcc: bccContacts,
                    subject: subjectText,
                    body: bodyText,
                    htmlBody: htmlBodyText,
                    replyType: .forward
                )
            }
            
            // 发送成功，删除草稿
            await deleteDraft()
            
            // 注意：窗口关闭由 sendProgress 的 onChange 监听器处理
            // 这里不再直接调用 dismiss()，让进度条完成后再关闭
        } catch {
            print("❌ [EmailComposeWindow] 发送失败: \(error)")
            viewModel.errorMessage = error.localizedDescription
            // 发送失败时，重置发送状态，允许用户重试
            // 注意：草稿会保留，用户可以继续编辑
            switch composeType {
            case .new:
                viewModel.isSendingCompose = false
            case .reply, .replyAll, .forward:
                viewModel.isSendingReply = false
            }
            viewModel.sendProgress = 0.0
            viewModel.sendStatusText = ""
        }
    }
    
    private func parseEmailAddresses(_ text: String) -> [EmailContact] {
        let addresses = text.components(separatedBy: ",")
        return addresses.compactMap { addressString -> EmailContact? in
            let trimmed = addressString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            
            // 解析 "Name <email@example.com>" 格式
            if let range = trimmed.range(of: "<", options: .backwards),
               let endRange = trimmed.range(of: ">", options: [], range: range.upperBound..<trimmed.endIndex) {
                let email = String(trimmed[range.upperBound..<endRange.lowerBound])
                let name = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                return EmailContact(name: name.isEmpty ? nil : name, email: email)
            }
            
            return EmailContact(email: trimmed)
        }
    }
    
    // MARK: - Draft Management
    
    /// 自动保存草稿（防抖，延迟2秒）
    private func autoSaveDraft() {
        // 取消之前的保存任务
        autoSaveTask?.cancel()
        
        // 创建新的保存任务（延迟2秒）
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒防抖
            
            // 检查是否被取消
            guard !Task.isCancelled else { return }
            
            // 保存草稿
            await saveDraft()
        }
    }
    
    /// 保存草稿
    private func saveDraft() async {
        guard let accountId = viewModel.currentAccount?.id else { return }
        
        // 解析收件人
        let toContacts = parseEmailAddresses(toText)
        let ccContacts = parseEmailAddresses(ccText)
        let bccContacts = parseEmailAddresses(bccText)
        
        // 如果没有收件人和主题，不保存草稿
        guard !toText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
              !subjectText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
              !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        do {
            // 获取附件
            let attachments = currentAttachments
            
            try await EmailStore.shared.saveDraft(
                draftId: draftId,
                accountId: accountId,
                to: toContacts,
                cc: ccContacts,
                bcc: bccContacts,
                subject: subjectText,
                body: bodyText,
                htmlBody: htmlBodyText,
                attachments: attachments,
                originalMessageId: originalMessage?.id
            )
        } catch {
            print("❌ [EmailComposeWindow] 保存草稿失败: \(error)")
        }
    }
    
    /// 加载草稿
    private func loadDraft() async {
        guard let draft = await EmailStore.shared.loadDraft(draftId: draftId) else {
            // 没有草稿，使用默认值
            return
        }
        
        // 加载草稿内容
        toText = draft.to.map { $0.email }.joined(separator: ", ")
        ccText = draft.cc.map { $0.email }.joined(separator: ", ")
        bccText = draft.bcc.map { $0.email }.joined(separator: ", ")
        subjectText = draft.subject
        bodyText = draft.textBody ?? ""
        htmlBodyText = draft.htmlBody
        
        print("✅ [EmailComposeWindow] 草稿已加载: \(draft.subject)")
    }
    
    /// 删除草稿
    private func deleteDraft() async {
        do {
            try await EmailStore.shared.deleteDraft(draftId: draftId)
        } catch {
            print("❌ [EmailComposeWindow] 删除草稿失败: \(error)")
        }
    }
}

