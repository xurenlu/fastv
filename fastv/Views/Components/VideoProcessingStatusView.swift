//
//  VideoProcessingStatusView.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI

/// 视频处理 UI 状态（用于状态视图组件）
enum VideoProcessingUIState: Equatable {
    case idle
    case preparing
    case processing(progress: Double, status: String)
    case completed(message: String, outputURL: URL?)
    case failed(message: String)
    case cancelled
    
    var isActive: Bool {
        switch self {
        case .preparing, .processing:
            return true
        default:
            return false
        }
    }
}

/// 统一的处理状态视图组件
struct VideoProcessingStatusView: View {
    let state: VideoProcessingUIState
    let onCancel: (() -> Void)?
    let onShowInFinder: ((URL) -> Void)?
    let onRetry: (() -> Void)?
    
    init(
        state: VideoProcessingUIState,
        onCancel: (() -> Void)? = nil,
        onShowInFinder: ((URL) -> Void)? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.state = state
        self.onCancel = onCancel
        self.onShowInFinder = onShowInFinder
        self.onRetry = onRetry
    }
    
    var body: some View {
        VStack(spacing: 12) {
            switch state {
            case .idle:
                EmptyView()
                
            case .preparing:
                preparingView
                
            case .processing(let progress, let status):
                processingView(progress: progress, status: status)
                
            case .completed(let message, let outputURL):
                completedView(message: message, outputURL: outputURL)
                
            case .failed(let message):
                failedView(message: message)
                
            case .cancelled:
                cancelledView
            }
        }
        .animation(.easeInOut(duration: VideoToolsConstants.progressAnimationDuration), value: state)
    }
    
    // MARK: - 子视图
    
    private var preparingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("准备中...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    private func processingView(progress: Double, status: String) -> some View {
        VStack(spacing: 8) {
            // 进度条
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            
            HStack {
                // 状态文本
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                // 百分比
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            
            // 取消按钮
            if let cancel = onCancel {
                Button(action: cancel) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                        Text("取消")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func completedView(message: String, outputURL: URL?) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            
            if let url = outputURL, let showInFinder = onShowInFinder {
                Button(action: { showInFinder(url) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("在访达中显示")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func failedView(message: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            
            if let retry = onRetry {
                Button(action: retry) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("重试")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var cancelledView: some View {
        HStack(spacing: 8) {
            Image(systemName: "stop.circle.fill")
                .foregroundColor(.orange)
                .font(.title2)
            
            Text("操作已取消")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

/// 简化版进度视图 - 仅显示进度条和状态
struct SimpleProgressView: View {
    let progress: Double
    let status: String
    let isProcessing: Bool
    let onCancel: (() -> Void)?
    
    init(progress: Double, status: String, isProcessing: Bool, onCancel: (() -> Void)? = nil) {
        self.progress = progress
        self.status = status
        self.isProcessing = isProcessing
        self.onCancel = onCancel
    }
    
    var body: some View {
        if isProcessing || !status.isEmpty {
            VStack(spacing: 8) {
                if isProcessing {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
                
                HStack {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if isProcessing {
                        if let cancel = onCancel {
                            Button("取消", action: cancel)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        VideoProcessingStatusView(
            state: .preparing,
            onCancel: { print("取消") }
        )
        
        VideoProcessingStatusView(
            state: .processing(progress: 0.65, status: "处理中: 65% | 速度: 1.2x | 剩余: 00:45"),
            onCancel: { print("取消") }
        )
        
        VideoProcessingStatusView(
            state: .completed(message: "处理完成！", outputURL: URL(fileURLWithPath: "/tmp/test.mp4")),
            onShowInFinder: { url in print("打开: \(url)") }
        )
        
        VideoProcessingStatusView(
            state: .failed(message: "处理失败: 文件不存在"),
            onRetry: { print("重试") }
        )
        
        VideoProcessingStatusView(state: .cancelled)
        
        Divider()
        
        SimpleProgressView(
            progress: 0.45,
            status: "正在压缩视频...",
            isProcessing: true,
            onCancel: { print("取消") }
        )
    }
    .padding()
    .frame(width: 400, height: 600)
}
