//
//  VideoToolErrorAlert.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI

/// 视频工具错误信息
struct VideoToolError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let underlyingError: Error?
    let canRetry: Bool
    
    init(title: String = "操作失败", message: String, underlyingError: Error? = nil, canRetry: Bool = true) {
        self.title = title
        self.message = message
        self.underlyingError = underlyingError
        self.canRetry = canRetry
    }
    
    init(error: Error, canRetry: Bool = true) {
        self.title = "操作失败"
        self.message = error.localizedDescription
        self.underlyingError = error
        self.canRetry = canRetry
    }
    
    /// 超时错误
    static func timeout(operation: String) -> VideoToolError {
        VideoToolError(
            title: "操作超时",
            message: "\(operation)超时，请检查视频文件是否过大或系统资源是否充足。",
            canRetry: true
        )
    }
    
    /// FFmpeg 未找到错误
    static var ffmpegNotFound: VideoToolError {
        VideoToolError(
            title: "FFmpeg 未安装",
            message: "请先安装 FFmpeg。可以使用 Homebrew 安装：brew install ffmpeg",
            canRetry: false
        )
    }
    
    /// 无视频选择错误
    static var noVideoSelected: VideoToolError {
        VideoToolError(
            title: "未选择视频",
            message: "请先选择一个视频文件",
            canRetry: false
        )
    }
}

/// 统一的错误提示视图
struct VideoToolErrorAlert: View {
    let error: VideoToolError
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void
    
    init(error: VideoToolError, onRetry: (() -> Void)? = nil, onDismiss: @escaping () -> Void) {
        self.error = error
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // 错误图标
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            // 错误标题
            Text(error.title)
                .font(.headline)
                .foregroundColor(.primary)
            
            // 错误消息
            Text(error.message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // 详细错误（可展开）
            if let underlyingError = error.underlyingError {
                DisclosureGroup("查看详情") {
                    ScrollView {
                        Text(underlyingError.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
                    .padding(.top, 4)
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            // 操作按钮
            HStack(spacing: 12) {
                // 复制错误信息按钮
                Button(action: copyErrorToClipboard) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                // 重试按钮
                if error.canRetry, let retry = onRetry {
                    Button(action: retry) {
                        Label("重试", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
                
                // 关闭按钮
                Button("关闭", action: onDismiss)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
        .frame(minWidth: 300, maxWidth: 400)
    }
    
    private func copyErrorToClipboard() {
        var errorText = "\(error.title)\n\(error.message)"
        if let underlyingError = error.underlyingError {
            errorText += "\n\n详情:\n\(underlyingError.localizedDescription)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(errorText, forType: .string)
    }
}

/// 错误提示 View Modifier
struct VideoToolErrorAlertModifier: ViewModifier {
    @Binding var error: VideoToolError?
    let onRetry: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .alert(item: $error) { error in
                if error.canRetry, let retry = onRetry {
                    Alert(
                        title: Text(error.title),
                        message: Text(error.message),
                        primaryButton: .default(Text("重试"), action: retry),
                        secondaryButton: .cancel(Text("关闭"))
                    )
                } else {
                    Alert(
                        title: Text(error.title),
                        message: Text(error.message),
                        dismissButton: .default(Text("确定"))
                    )
                }
            }
    }
}

extension View {
    /// 添加视频工具错误提示
    func videoToolErrorAlert(_ error: Binding<VideoToolError?>, onRetry: (() -> Void)? = nil) -> some View {
        modifier(VideoToolErrorAlertModifier(error: error, onRetry: onRetry))
    }
}

#Preview {
    VStack {
        VideoToolErrorAlert(
            error: .timeout(operation: "视频压缩"),
            onRetry: { print("重试") },
            onDismiss: { print("关闭") }
        )
    }
    .padding()
    .frame(width: 500, height: 400)
}
