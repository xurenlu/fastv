//
//  VideoCartoonView.swift
//  fastv
//
//  Created for Video Cartoonization
//

import SwiftUI
import AVKit

struct VideoCartoonView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @StateObject private var cartoonizer = VideoCartoonizerService.shared
    
    @State private var selectedStyle: CartoonStyle = .shinkai
    @State private var processedPreviewImage: NSImage?
    @State private var originalPreviewImage: NSImage?
    @State private var isProcessingPreview = false
    @State private var errorMessage: String?
    @State private var showVideoSelector = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. 顶部控制区
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("视频卡通化")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("使用 AI 将视频转换为动漫风格。")
                            .foregroundStyle(.secondary)
                        
                        // 风格选择
                        Picker("选择风格", selection: $selectedStyle) {
                            ForEach(CartoonStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                        
                        // 模型状态检查
                        if cartoonizer.isModelAvailable(for: selectedStyle) {
                            Label("模型就绪", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else {
                            HStack {
                                Label("模型未找到", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Button("如何获取模型?") {
                                    showModelHelp()
                                }
                                .buttonStyle(.link)
                            }
                            .font(.caption)
                        }
                        
                        // 操作按钮
                        HStack {
                            Button(action: generatePreview) {
                                if isProcessingPreview {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("生成预览", systemImage: "eye")
                                }
                            }
                            .disabled(viewModel.videoURL == nil || isProcessingPreview || !cartoonizer.isModelAvailable(for: selectedStyle))
                            
                            Button(action: startFullProcessing) {
                                Label("开始转换视频", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.videoURL == nil || cartoonizer.isProcessing || !cartoonizer.isModelAvailable(for: selectedStyle))
                        }
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // 2. 预览区域
                if let videoURL = viewModel.videoURL {
                    HStack(spacing: 20) {
                        // 原图
                        VStack {
                            Text("原视频预览")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            if let image = originalPreviewImage {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 300)
                                    .cornerRadius(8)
                            } else {
                                Rectangle()
                                    .fill(Color.black.opacity(0.1))
                                    .frame(height: 300)
                                    .overlay(Text("无法加载预览").foregroundStyle(.secondary))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        // 箭头
                        Image(systemName: "arrow.right")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        
                        // 效果图
                        VStack {
                            Text("卡通化效果")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            ZStack {
                                if let image = processedPreviewImage {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .cornerRadius(8)
                                } else {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.1))
                                }
                                
                                if isProcessingPreview {
                                    ZStack {
                                        Color.black.opacity(0.3)
                                        ProgressView("AI 处理中...")
                                            .controlSize(.large)
                                            .tint(.white)
                                            .foregroundStyle(.white)
                                    }
                                } else if processedPreviewImage == nil {
                                    Text("点击预览查看效果")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(height: 300)
                            .cornerRadius(8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    // 空状态
                    VStack(spacing: 16) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("请先在左侧选择或拖入视频")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(12)
                }
                
                // 错误提示
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                        Spacer()
                        Button("关闭") { errorMessage = nil }
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .foregroundStyle(.red)
                    .cornerRadius(8)
                }
            }
            .padding()
        }
        .onAppear {
            if viewModel.videoURL != nil {
                loadOriginalPreview()
            }
        }
        .onChange(of: viewModel.videoURL) { _, _ in
            loadOriginalPreview()
            processedPreviewImage = nil
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if viewModel.videoURL != nil {
                    Button(action: { showVideoSelector = true }) {
                        Label("更换视频", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showVideoSelector,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            handleVideoSelection(result)
        }
    }
    
    private func handleVideoSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                viewModel.loadVideo(url)
                // 重置预览图片
                originalPreviewImage = nil
                processedPreviewImage = nil
                errorMessage = nil
            }
        case .failure(let error):
            print("选择视频失败: \(error.localizedDescription)")
        }
    }
    
    private func loadOriginalPreview() {
        guard let url = viewModel.videoURL else { return }
        
        Task {
            // 在沙盒环境下，需要获取安全作用域资源访问权限
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            do {
                let image = try await FrameExtractor.extractFirstFrame(from: url)
                await MainActor.run {
                    self.originalPreviewImage = image
                }
            } catch {
                print("❌ [VideoCartoonView] 预览加载失败: \(error.localizedDescription)")
            }
        }
    }
    
    private func generatePreview() {
        guard let original = originalPreviewImage else { return }
        
        isProcessingPreview = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await cartoonizer.processImage(original, style: selectedStyle)
                await MainActor.run {
                    self.processedPreviewImage = result
                    self.isProcessingPreview = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "处理失败: \(error.localizedDescription)"
                    self.isProcessingPreview = false
                }
            }
        }
    }
    
    private func startFullProcessing() {
        // TODO: 实现完整视频处理流程
        // 这里需要调用 VideoProcessor 或 VideoCartoonizerService 的视频处理方法
        errorMessage = "完整视频处理功能即将上线，目前仅支持单帧预览。"
    }
    
    private func showModelHelp() {
        let alert = NSAlert()
        alert.messageText = "模型文件缺失"
        alert.informativeText = """
请下载对应的 ONNX 模型文件并放入以下目录：
fastv/Resources/Models/Cartoon/

您可以运行项目根目录下的 download_cartoon_models.sh 脚本来尝试自动下载示例模型。
"""
        alert.addButton(withTitle: "我知道了")
        alert.runModal()
    }
}
