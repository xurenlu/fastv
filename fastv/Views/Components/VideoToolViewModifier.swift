//
//  VideoToolViewModifier.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI
import UniformTypeIdentifiers

/// 视频工具通用视图修饰器 - 处理视频选择和工具栏
struct VideoToolViewModifier: ViewModifier {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @Binding var showingFilePicker: Bool
    let onVideoSelected: (() -> Void)?
    let onReset: (() -> Void)?
    
    init(
        viewModel: VideoProcessorViewModel,
        showingFilePicker: Binding<Bool>,
        onVideoSelected: (() -> Void)? = nil,
        onReset: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self._showingFilePicker = showingFilePicker
        self.onVideoSelected = onVideoSelected
        self.onReset = onReset
    }
    
    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: VideoToolHelper.supportedVideoTypes,
                allowsMultipleSelection: false
            ) { result in
                handleVideoSelection(result)
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: { showingFilePicker = true }) {
                        Label("选择视频", systemImage: "folder")
                    }
                    
                    if viewModel.videoURL != nil {
                        Button(action: resetAll) {
                            Label("重置", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
    }
    
    private func handleVideoSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                // 开始安全访问
                let accessing = url.startAccessingSecurityScopedResource()
                
                viewModel.loadVideo(url)
                onVideoSelected?()
                
                // 注意：安全访问需要在使用完成后调用 stopAccessingSecurityScopedResource
                // 但由于视频可能持续使用，这里不立即停止访问
                if !accessing {
                    print("⚠️ [VideoToolViewModifier] 无法访问安全作用域资源")
                }
            }
        case .failure(let error):
            print("❌ [VideoToolViewModifier] 选择视频失败: \(error.localizedDescription)")
        }
    }
    
    private func resetAll() {
        viewModel.reset()
        onReset?()
    }
}

/// 视频工具辅助类
enum VideoToolHelper {
    
    /// 支持的视频文件类型
    static let supportedVideoTypes: [UTType] = [
        .movie,
        .quickTimeMovie,
        .mpeg4Movie,
        .mpeg,
        .avi,
        UTType(filenameExtension: "mkv") ?? .movie,
        UTType(filenameExtension: "webm") ?? .movie,
        UTType(filenameExtension: "flv") ?? .movie,
        UTType(filenameExtension: "wmv") ?? .movie,
        UTType(filenameExtension: "m4v") ?? .movie
    ]
    
    /// 处理视频选择结果
    /// - Parameters:
    ///   - result: 文件选择结果
    ///   - viewModel: 视频处理视图模型
    ///   - onSuccess: 成功回调
    ///   - onError: 错误回调
    static func handleVideoSelection(
        _ result: Result<[URL], Error>,
        viewModel: VideoProcessorViewModel,
        onSuccess: (() -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                let accessing = url.startAccessingSecurityScopedResource()
                viewModel.loadVideo(url)
                onSuccess?()
                
                if !accessing {
                    print("⚠️ [VideoToolHelper] 无法访问安全作用域资源")
                }
            }
        case .failure(let error):
            print("❌ [VideoToolHelper] 选择视频失败: \(error.localizedDescription)")
            onError?(error)
        }
    }
    
    /// 在 Finder 中显示文件
    static func showInFinder(_ url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
    
    /// 打开文件
    static func openFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
    
    /// 格式化文件大小
    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// 格式化时长
    static func formatDuration(_ duration: TimeInterval) -> String {
        guard duration.isFinite && duration >= 0 else { return "--:--" }
        
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    /// 格式化帧率
    static func formatFrameRate(_ fps: Double) -> String {
        if fps == floor(fps) {
            return "\(Int(fps)) fps"
        } else {
            return String(format: "%.2f fps", fps)
        }
    }
    
    /// 格式化分辨率
    static func formatResolution(width: Int, height: Int) -> String {
        return "\(width) × \(height)"
    }
}

/// 可取消任务管理器
actor CancellableTaskManager {
    private var currentTask: Task<Void, Never>?
    private var tempFiles: [URL] = []
    
    /// 设置当前任务
    func setTask(_ task: Task<Void, Never>) {
        currentTask = task
    }
    
    /// 添加临时文件（取消时清理）
    func addTempFile(_ url: URL) {
        tempFiles.append(url)
    }
    
    /// 取消当前任务
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        cleanupTempFiles()
    }
    
    /// 任务完成
    func complete() {
        currentTask = nil
        tempFiles.removeAll()
    }
    
    /// 清理临时文件
    private func cleanupTempFiles() {
        for url in tempFiles {
            try? FileManager.default.removeItem(at: url)
        }
        tempFiles.removeAll()
    }
    
    /// 是否有正在运行的任务
    var isRunning: Bool {
        currentTask != nil && !currentTask!.isCancelled
    }
}

// MARK: - View Extensions

extension View {
    /// 添加视频工具通用功能
    func videoToolSetup(
        viewModel: VideoProcessorViewModel,
        showingFilePicker: Binding<Bool>,
        onVideoSelected: (() -> Void)? = nil,
        onReset: (() -> Void)? = nil
    ) -> some View {
        modifier(VideoToolViewModifier(
            viewModel: viewModel,
            showingFilePicker: showingFilePicker,
            onVideoSelected: onVideoSelected,
            onReset: onReset
        ))
    }
}
