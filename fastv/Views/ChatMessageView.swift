//
//  ChatMessageView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI
import AppKit
import AVKit

struct ChatMessageView: View {
    let message: ChatMessage
    let modelName: String?  // 模型名称（用于生成头像）
    var onRegenerate: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil
    @State private var imageData: Data?
    @State private var parsedElements: [MarkdownElement] = []
    @State private var isHovered = false
    @State private var showCopySuccess = false
    
    init(message: ChatMessage, modelName: String? = nil, onRegenerate: (() -> Void)? = nil, onRetry: (() -> Void)? = nil) {
        self.message = message
        self.modelName = modelName
        self.onRegenerate = onRegenerate
        self.onRetry = onRetry
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // AI消息：头像在左侧
            if message.isAIMessage {
                avatarView
            }
            
            VStack(alignment: message.isUserMessage ? .trailing : .leading, spacing: 4) {
                // 显示思考过程（如果有）
                if let thinking = message.thinking, !thinking.isEmpty {
                    thinkingView(thinking: thinking)
                }
                
                // 消息文本内容（Markdown 渲染）
                if !parsedElements.isEmpty {
                    VStack(alignment: message.isUserMessage ? .trailing : .leading, spacing: 12) {
                        ForEach(Array(parsedElements.enumerated()), id: \.offset) { index, element in
                            MarkdownElementView(element: element, isTransparentBackground: false)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(message.isUserMessage ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                    }
                } else if !message.content.isEmpty {
                    // 未解析时显示原始文本
                    messageTextView(text: message.content, originalText: message.content)
                }
                
                // 附件显示
                if message.hasAttachments {
                    ForEach(message.attachments) { attachment in
                        AttachmentView(attachment: attachment)
                    }
                }
                
                // 时间戳和状态
                HStack(spacing: 4) {
                    Text(message.formattedTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    if message.isSending {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else if message.sendError != nil {
                        Button(action: { onRetry?() }) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help(message.sendError ?? "发送失败，点击重试")
                    } else if message.isUserMessage {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // AI 消息底部操作栏（hover 时显示重新生成按钮）
                if message.isAIMessage && isHovered {
                    HStack(spacing: 8) {
                        Button(action: { onRegenerate?() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("重新生成")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // 用户消息：头像在右侧
            if message.isUserMessage {
                Spacer(minLength: 60)
                userAvatarView
            } else {
                Spacer(minLength: 60)
            }
        }
        .background(
            // 使用透明背景扩展 hover 区域，包括整个消息区域
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
        )
        .onHover { hovering in
            // 使用 DispatchQueue 延迟状态更新，避免在视图更新期间修改状态
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
        }
        .task(id: message.id) {
            // 异步解析 Markdown，避免在视图更新期间修改状态
            if message.isAIMessage && parsedElements.isEmpty {
                await parseMarkdownAsync()
            }
        }
        .onChange(of: message.content) { oldValue, newValue in
            // 当消息内容变化时，重新解析 Markdown（延迟执行避免约束循环）
            if message.isAIMessage && oldValue != newValue {
                DispatchQueue.main.async {
                    Task { @MainActor in
                        await parseMarkdownAsync()
                    }
                }
            }
        }
    }
    
    /// 消息文本视图（可选择和复制）
    @ViewBuilder
    private func messageTextView(text: String, originalText: String) -> some View {
        // 文本内容（可选择）
        Text(text)
            .font(.body)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(message.isUserMessage ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            }
            .foregroundStyle(.primary)
    }
    
    /// Markdown 文本视图（支持格式化）
    @ViewBuilder
    private func MarkdownTextView(markdown: String, originalText: String) -> some View {
        // 使用 AttributedString 渲染 Markdown（代码块已经单独提取）
        if !markdown.isEmpty {
            // 尝试解析 Markdown
            if let attributedString = try? AttributedString(markdown: markdown, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)) {
                Text(attributedString)
                    .textSelection(.enabled)
                    .lineSpacing(4) // 添加行间距，让文本更易读
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: message.isUserMessage ? .trailing : .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(message.isUserMessage ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                    }
            } else {
                // 如果解析失败，尝试使用基本选项
                if let attributedString = try? AttributedString(markdown: markdown) {
                    Text(attributedString)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: message.isUserMessage ? .trailing : .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(message.isUserMessage ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                        }
                } else {
                    // 如果都失败，回退到普通文本
                    messageTextView(text: markdown, originalText: originalText)
                }
            }
        }
    }
    
    /// AI头像视图（包含复制按钮）
    @ViewBuilder
    private var avatarView: some View {
        VStack(spacing: 4) {
            // 头像
            avatarImage
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }
            
            // 复制按钮（始终渲染，但控制透明度）
            copyButton(originalText: message.content)
                .opacity(isHovered ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
                .allowsHitTesting(isHovered) // 只在可见时允许点击
        }
        .frame(width: 32, height: 40) // 固定高度避免约束变化
        .onHover { hovering in
            // 在头像区域也保持 hover 状态
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
        }
    }
    
    /// 用户头像视图
    @ViewBuilder
    private var userAvatarView: some View {
        VStack(spacing: 4) {
            // 用户头像
            Image(systemName: "person.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
            
            // 复制按钮（始终渲染，但控制透明度）
            copyButton(originalText: message.content)
                .opacity(isHovered ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
                .allowsHitTesting(isHovered) // 只在可见时允许点击
        }
        .frame(width: 32, height: 40) // 固定高度避免约束变化
        .onHover { hovering in
            // 在头像区域也保持 hover 状态
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
        }
    }
    
    /// 根据模型名生成头像
    @ViewBuilder
    private var avatarImage: some View {
        Group {
            if let modelName = modelName, !modelName.isEmpty {
                // 根据模型名生成卡通头像
                let avatarColor = colorForModel(modelName)
                let avatarIcon = iconForModel(modelName)
                
                ZStack {
                    Circle()
                        .fill(avatarColor)
                    
                    Text(avatarIcon)
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
            } else {
                // 默认AI头像
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
        }
    }
    
    /// 根据模型名获取颜色
    private func colorForModel(_ modelName: String) -> Color {
        let name = modelName.lowercased()
        if name.contains("qwen") {
            if name.contains("3") {
                return Color(red: 0.4, green: 0.6, blue: 1.0)  // 蓝色系
            } else if name.contains("vl") {
                return Color(red: 0.8, green: 0.4, blue: 1.0)  // 紫色系
            } else {
                return Color(red: 0.2, green: 0.7, blue: 0.9)  // 青色系
            }
        } else if name.contains("gpt") {
            return Color(red: 0.3, green: 0.7, blue: 0.5)  // 绿色系
        } else if name.contains("claude") {
            return Color(red: 0.9, green: 0.5, blue: 0.2)  // 橙色系
        } else {
            return Color(red: 0.5, green: 0.5, blue: 0.9)  // 默认紫色
        }
    }
    
    /// 根据模型名获取图标
    private func iconForModel(_ modelName: String) -> String {
        let name = modelName.lowercased()
        if name.contains("qwen") {
            if name.contains("vl") || name.contains("vision") {
                return "👁️"
            } else if name.contains("audio") {
                return "🎵"
            } else {
                return "✨"
            }
        } else if name.contains("gpt") {
            return "🤖"
        } else if name.contains("claude") {
            return "🧠"
        } else {
            return "✨"
        }
    }
    
    /// 复制按钮
    @ViewBuilder
    private func copyButton(originalText: String) -> some View {
        CopyButtonView(
            text: originalText,
            showSuccess: $showCopySuccess
        )
    }
    
    /// 复制文本到剪贴板
    private func copyToClipboard(text: String) {
        // 清除当前选择，避免显示灰色块
        NSPasteboard.general.clearContents()
        
        let pasteboard = NSPasteboard.general
        pasteboard.setString(text, forType: .string)
        
        // 显示复制成功提示
        withAnimation {
            showCopySuccess = true
        }
        
        // 1秒后恢复图标
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation {
                showCopySuccess = false
            }
        }
    }
    
    /// 解析 Markdown 内容（异步版本，避免在视图更新期间修改状态）
    @MainActor
    private func parseMarkdownAsync() async {
        // 使用新的 Markdown 解析器
        parsedElements = parseMarkdown(message.content)
    }
    
    /// 思考过程视图
    @ViewBuilder
    private func thinkingView(thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("思考过程")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            
            Text(thinking)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                }
        }
        .padding(.bottom, 4)
    }
}

struct AttachmentView: View {
    let attachment: ChatAttachment
    @State private var imageData: Data?
    @State private var showImagePreview = false
    
    var body: some View {
        Group {
            switch attachment.type {
            case .image:
                imageAttachmentView
            case .audio:
                audioAttachmentView
            case .video:
                videoAttachmentView
            default:
                EmptyView()
            }
        }
    }
    
    private var imageAttachmentView: some View {
        Group {
            if let base64Data = attachment.base64Data,
               let data = Data(base64Encoded: base64Data),
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 300, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture {
                        showImagePreview = true
                    }
                    .sheet(isPresented: $showImagePreview) {
                        ChatImagePreviewView(image: nsImage)
                    }
            } else if let urlString = attachment.url,
                      let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 300, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .frame(width: 100, height: 100)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        }
    }
    
    private var audioAttachmentView: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
            
            if let fileName = attachment.fileName {
                Text(fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("音频文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let fileSize = attachment.fileSize {
                Text(formatFileSize(fileSize))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        }
    }
    
    private var videoAttachmentView: some View {
        Group {
            if let base64Data = attachment.base64Data,
               let data = Data(base64Encoded: base64Data) {
                // Base64 视频
                VideoPlayerView(data: data)
            } else if let urlString = attachment.url,
                      let url = URL(string: urlString) {
                // URL 视频
                VideoPlayerView(url: url)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "video.fill")
                        .foregroundStyle(.secondary)
                    
                    if let fileName = attachment.fileName {
                        Text(fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("视频文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let fileSize = attachment.fileSize {
                        Text(formatFileSize(fileSize))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                }
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// Markdown 媒体视图
struct MarkdownMediaView: View {
    let media: MarkdownMedia
    @State private var showPreview = false
    
    var body: some View {
        Group {
            switch media.type {
            case .image:
                markdownImageView
            case .video:
                markdownVideoView
            }
        }
    }
    
    private var markdownImageView: some View {
        Group {
            if media.url.hasPrefix("data:image/") {
                // Base64 图片
                if let data = extractBase64Data(from: media.url),
                   let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 400, maxHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onTapGesture {
                            showPreview = true
                        }
                        .sheet(isPresented: $showPreview) {
                            ChatImagePreviewView(image: nsImage)
                        }
                }
            } else if let url = URL(string: media.url) {
                // URL 图片
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 200, height: 200)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 400, maxHeight: 400)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .onTapGesture {
                                showPreview = true
                            }
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                            .frame(width: 100, height: 100)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        }
    }
    
    private var markdownVideoView: some View {
        Group {
            if media.url.hasPrefix("data:video/") {
                // Base64 视频
                if let data = extractBase64Data(from: media.url) {
                    VideoPlayerView(data: data)
                }
            } else if let url = URL(string: media.url) {
                // URL 视频
                VideoPlayerView(url: url)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        }
    }
    
    /// 从 data URL 中提取 Base64 数据
    private func extractBase64Data(from dataUrl: String) -> Data? {
        guard let base64Range = dataUrl.range(of: "base64,") else {
            return nil
        }
        let base64String = String(dataUrl[base64Range.upperBound...])
        return Data(base64Encoded: base64String)
    }
}

/// 视频播放器视图
struct VideoPlayerView: View {
    let url: URL?
    let data: Data?
    @State private var tempURL: URL?
    
    init(url: URL) {
        self.url = url
        self.data = nil
    }
    
    init(data: Data) {
        self.url = nil
        self.data = data
    }
    
    var body: some View {
        Group {
            if let url = url {
                AVPlayerViewRepresentable(url: url)
                    .frame(maxWidth: 400, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if let data = data {
                // 对于 base64 数据，需要先保存为临时文件
                if let tempURL = tempURL {
                    AVPlayerViewRepresentable(url: tempURL)
                        .frame(maxWidth: 400, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    ProgressView()
                        .frame(width: 200, height: 200)
                        .onAppear {
                            // 创建临时文件
                            let tempDir = FileManager.default.temporaryDirectory
                            let tempFile = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
                            try? data.write(to: tempFile)
                            tempURL = tempFile
                        }
                }
            } else {
                Image(systemName: "video.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 100, height: 100)
            }
        }
    }
}

/// AVPlayerView 的 SwiftUI 包装
struct AVPlayerViewRepresentable: NSViewRepresentable {
    let url: URL
    @State private var player: AVPlayer?
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        let player = AVPlayer(url: url)
        playerView.player = player
        self.player = player
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // 更新视图（如果需要）
    }
}

/// 复制按钮视图（使用 NSButton 避免文本选择问题）
struct CopyButtonView: NSViewRepresentable {
    let text: String
    @Binding var showSuccess: Bool
    
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        if let image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil) {
            button.image = image
        }
        button.bezelStyle = .rounded
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.copyAction)
        button.toolTip = "复制消息"
        
        // 设置按钮大小
        button.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
        
        // 阻止文本选择
        button.refusesFirstResponder = true
        
        context.coordinator.button = button
        context.coordinator.text = text
        context.coordinator.showSuccess = $showSuccess
        
        return button
    }
    
    func updateNSView(_ nsView: NSButton, context: Context) {
        // 只在必要时更新，避免触发约束循环
        let oldShowSuccess = context.coordinator.showSuccess?.wrappedValue ?? false
        
        context.coordinator.text = text
        context.coordinator.showSuccess = $showSuccess
        
        // 只在状态真正变化时更新 UI
        if oldShowSuccess != showSuccess {
            if showSuccess {
                if let image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) {
                    nsView.image = image
                    nsView.contentTintColor = .systemGreen
                }
            } else {
                if let image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil) {
                    nsView.image = image
                    nsView.contentTintColor = .secondaryLabelColor
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var button: NSButton?
        var text: String = ""
        var showSuccess: Binding<Bool>?
        
        @objc func copyAction() {
            // 清除当前选择，避免显示灰色块
            NSPasteboard.general.clearContents()
            
            let pasteboard = NSPasteboard.general
            pasteboard.setString(text, forType: .string)
            
            // 显示复制成功提示
            DispatchQueue.main.async {
                self.showSuccess?.wrappedValue = true
                
                // 1秒后恢复图标
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.showSuccess?.wrappedValue = false
                }
            }
        }
    }
}

/// 代码块视图
struct CodeBlockView: View {
    let codeBlock: MarkdownCodeBlock
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 代码块头部（语言标签和复制按钮）
            HStack {
                if let language = codeBlock.language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(Color.secondary.opacity(0.15))
                        }
                }
                
                Spacer()
                
                Button(action: {
                    copyCode()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.caption2)
                        Text(isCopied ? "已复制" : "复制")
                            .font(.caption2)
                    }
                    .foregroundStyle(isCopied ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background {
                Rectangle()
                    .fill(Color.secondary.opacity(0.05))
            }
            
            // 代码内容
            ScrollView(.horizontal, showsIndicators: false) {
                Text(codeBlock.code)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }
        }
        .padding(.bottom, 8)
    }
    
    private func copyCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(codeBlock.code, forType: .string)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }
}

/// Markdown 表格视图
struct MarkdownTableView: View {
    let table: MarkdownTable
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // 表头
                HStack(spacing: 0) {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                        Text(header)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(minWidth: 100, alignment: alignmentForColumn(index))
                            .overlay {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(width: 1)
                                    .offset(x: index == 0 ? 0 : -0.5)
                            }
                    }
                }
                .background(Color.secondary.opacity(0.1))
                .overlay {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                        .offset(y: -0.5)
                }
                
                // 数据行
                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                            Text(cell)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minWidth: 100, alignment: alignmentForColumn(colIndex))
                                .overlay {
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(width: 1)
                                        .offset(x: colIndex == 0 ? 0 : -0.5)
                                }
                        }
                        
                        // 如果行数据不足，用空单元格填充
                        if row.count < table.headers.count {
                            ForEach(row.count..<table.headers.count, id: \.self) { colIndex in
                                Text("")
                                    .font(.system(size: 13))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(minWidth: 100)
                                    .overlay {
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.2))
                                            .frame(width: 1)
                                            .offset(x: -0.5)
                                    }
                            }
                        }
                    }
                    .background(rowIndex % 2 == 0 ? Color.secondary.opacity(0.05) : Color.clear)
                    .overlay {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 1)
                            .offset(y: -0.5)
                    }
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }
        }
        .padding(.bottom, 8)
    }
    
    private func alignmentForColumn(_ index: Int) -> Alignment {
        guard index < table.alignments.count else { return .leading }
        
        switch table.alignments[index] {
        case .left:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        case .none:
            return .leading
        }
    }
}

struct ChatImagePreviewView: View {
    let image: NSImage
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 800, height: 600)
    }
}

#Preview {
    VStack(spacing: 20) {
        ChatMessageView(
            message: ChatMessage(
                sessionId: UUID(),
                role: .assistant,
                content: "这是一条AI回复消息"
            ),
            modelName: "qwen-turbo"
        )
        
        ChatMessageView(
            message: ChatMessage(
                sessionId: UUID(),
                role: .user,
                content: "这是一条用户消息"
            )
        )
    }
    .padding()
}

