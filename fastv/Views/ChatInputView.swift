//
//  ChatInputView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI
import AppKit

struct ChatInputView: View {
    @ObservedObject var viewModel: AIChatViewModel
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 错误提示 - Apple 风格
            if let errorMessage = viewModel.errorMessage {
                errorBanner(message: errorMessage)
            }

            // 待发送的图片预览
            if !viewModel.pendingAttachments.isEmpty {
                imagePreviewSection
            }

            // 输入区域 - Apple 风格
            HStack(alignment: .bottom, spacing: 12) {
                ChatTextEditor(text: $viewModel.inputText, onSend: {
                    if !viewModel.isSending {
                        Task { await viewModel.sendTextMessage() }
                    }
                })
                .font(.body)
                .frame(minHeight: 56, maxHeight: 180)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isInputFocused ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.12), lineWidth: isInputFocused ? 1.5 : 1)
                        }
                }
                .focused($isInputFocused)

                // 操作按钮组
                VStack(spacing: 8) {
                    Button(action: { viewModel.selectAndUploadFile() }) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(viewModel.supportsAttachment() ? .secondary : .tertiary)
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.supportsAttachment() ? NSLocalizedString("chat.upload.image", comment: "") : NSLocalizedString("chat.voice.not.supported", comment: ""))
                    .disabled(viewModel.isSending || !viewModel.supportsAttachment())

                    Button(action: {
                        if viewModel.isRecording {
                            Task { await viewModel.stopVoiceRecording() }
                        } else {
                            viewModel.startVoiceRecording()
                        }
                    }) {
                        Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(viewModel.isRecording ? .red : (viewModel.supportsVoice() ? .blue : .secondary))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.supportsVoice() ? (viewModel.isRecording ? NSLocalizedString("chat.stop.recording", comment: "") : NSLocalizedString("chat.voice.input", comment: "")) : NSLocalizedString("chat.voice.not.supported", comment: ""))
                    .disabled(viewModel.isSending || !viewModel.supportsVoice())

                    Button(action: {
                        Task { await viewModel.sendTextMessage() }
                    }) {
                        if viewModel.isSending {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 36, height: 36)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(canSend ? Color.blue : Color(NSColor.tertiaryLabelColor))
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .help(NSLocalizedString("chat.send", comment: ""))
                }
            }
        }
    }

    private var canSend: Bool {
        !viewModel.isSending && (!viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.pendingAttachments.isEmpty)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.red)
                .symbolRenderingMode(.hierarchical)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.1))
        }
        .padding(.bottom, 8)
    }

    private var imagePreviewSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.pendingAttachments) { attachment in
                    if attachment.type == .image,
                       let base64Data = attachment.base64Data,
                       let data = Data(base64Encoded: base64Data),
                       let nsImage = NSImage(data: data) {
                        ZStack(alignment: .topTrailing) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            Button(action: { viewModel.removePendingAttachment(attachment) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 4, y: -4)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 64)
        .padding(.bottom, 8)
    }
}

/// 自定义 TextEditor，支持 Command+Enter 发送
struct ChatTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onSend: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: ChatTextEditor
        weak var textView: NSTextView?

        init(_ parent: ChatTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let event = NSApp.currentEvent
                if let event = event {
                    if event.modifierFlags.contains(.control) {
                        return false
                    } else {
                        parent.onSend()
                        return true
                    }
                }
                parent.onSend()
                return true
            }
            return false
        }
    }
}

#Preview {
    ChatInputView(viewModel: AIChatViewModel())
}
