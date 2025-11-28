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
        VStack(spacing: 8) {
            // 错误提示
            if let errorMessage = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.red.opacity(0.1))
                }
            }
            
            // 输入区域
            HStack(spacing: 8) {
                // 文本输入框 - 使用 TextEditor 提供更大的输入区域
                ChatTextEditor(text: $viewModel.inputText, onSend: {
                    if !viewModel.isSending {
                        Task {
                            await viewModel.sendTextMessage()
                        }
                    }
                })
                .font(.body)
                .frame(minHeight: 60, maxHeight: 200)
                .padding(4)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(NSColor.textBackgroundColor))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        }
                }
                .focused($isInputFocused)
                
                // 文件上传按钮
                Button(action: {
                    viewModel.selectAndUploadFile()
                }) {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("上传文件")
                .disabled(viewModel.isSending)
                
                // 语音录制按钮
                Button(action: {
                    if viewModel.isRecording {
                        Task {
                            await viewModel.stopVoiceRecording()
                        }
                    } else {
                        viewModel.startVoiceRecording()
                    }
                }) {
                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title3)
                        .foregroundStyle(viewModel.isRecording ? .red : .blue)
                }
                .buttonStyle(.plain)
                .help(viewModel.isRecording ? "停止录音" : "语音输入")
                .disabled(viewModel.isSending)
                
                // 发送按钮
                Button(action: {
                    Task {
                        await viewModel.sendTextMessage()
                    }
                }) {
                    if viewModel.isSending {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSending || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("发送")
            }
        }
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
        
        // 设置委托以处理文本变化
        textView.delegate = context.coordinator
        
        // 设置快捷键处理
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
            // 处理 Enter 和 Ctrl+Enter
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let event = NSApp.currentEvent
                if let event = event {
                    // Ctrl+Enter: 插入换行符（允许默认行为）
                    if event.modifierFlags.contains(.control) {
                        return false  // 允许默认行为，插入换行符
                    }
                    // Enter（无修饰键）: 发送消息
                    else {
                        parent.onSend()
                        return true  // 阻止默认行为，不插入换行符
                    }
                }
                // 如果没有事件信息，默认发送消息
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

