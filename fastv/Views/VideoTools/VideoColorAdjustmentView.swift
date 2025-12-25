//
//  VideoColorAdjustmentView.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoColorAdjustmentView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @State private var adjustment = ColorAdjustment()
    @State private var isProcessing = false
    @State private var progress: Double = 0.0
    @State private var status: String = ""
    
    // 预览相关状态
    @State private var videoInfo: VideoInfo?
    @State private var selectedTime: TimeInterval = 0
    @State private var originalPreviewImage: NSImage?
    @State private var adjustedPreviewImage: NSImage?
    @State private var isGeneratingPreview = false
    @State private var previewUpdateTask: Task<Void, Never>?
    @State private var showVideoSelector = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let videoURL = viewModel.videoURL {
                    VideoPreviewView(
                        videoURL: videoURL,
                        onVideoDropped: { urls in
                            if let url = urls.first {
                                viewModel.loadVideo(url)
                                loadVideoInfo(url)
                            }
                        },
                        seekToTime: .constant(nil)
                    )
                }
                
                // 时间轴选择器
                if let info = videoInfo {
                    VideoTimelineSelector(
                        duration: info.duration,
                        selectedTime: $selectedTime
                    )
                }
                
                // 效果对比预览
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.left.and.right.circle")
                            .foregroundColor(.secondary)
                        Text("效果对比")
                            .font(.headline)
                        
                        Spacer()
                        
                        if isGeneratingPreview {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 20, height: 20)
                            Text("生成预览中...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    ImageComparisonSlider(
                        originalImage: originalPreviewImage,
                        adjustedImage: adjustedPreviewImage
                    )
                    .frame(height: 300)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("亮度")
                                Spacer()
                                Text(String(format: "%.2f", adjustment.brightness))
                                    .monospacedDigit()
                            }
                            Slider(value: $adjustment.brightness, in: -1.0...1.0, step: 0.1)
                            
                            HStack {
                                Text("对比度")
                                Spacer()
                                Text(String(format: "%.2f", adjustment.contrast))
                                    .monospacedDigit()
                            }
                            Slider(value: $adjustment.contrast, in: 0.0...3.0, step: 0.1)
                            
                            HStack {
                                Text("饱和度")
                                Spacer()
                                Text(String(format: "%.2f", adjustment.saturation))
                                    .monospacedDigit()
                            }
                            Slider(value: $adjustment.saturation, in: 0.0...3.0, step: 0.1)
                            
                            HStack {
                                Text("色温")
                                Spacer()
                                Text(adjustment.temperature != nil ? "\(Int(adjustment.temperature!))K" : "自动")
                                    .monospacedDigit()
                            }
                            HStack {
                                Slider(value: Binding(
                                    get: { adjustment.temperature ?? 6500 },
                                    set: { adjustment.temperature = $0 }
                                ), in: 3000...10000, step: 100)
                                Button("重置") {
                                    adjustment.temperature = nil
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    } header: {
                        Text("颜色调整")
                    }
                    
                    if isProcessing {
                        Section {
                            ProgressView(value: progress)
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } header: {
                            Text("处理进度")
                        }
                    }
                }
                .formStyle(.grouped)
                
                Button(action: {
                    startAdjustment()
                }) {
                    Label("应用调整", systemImage: "paintpalette.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.videoURL == nil || isProcessing)
            }
            .padding()
        }
        .navigationTitle("颜色调整")
        .onAppear {
            if let videoURL = viewModel.videoURL {
                loadVideoInfo(videoURL)
            }
        }
        .onDisappear {
            // 取消待处理的预览任务
            previewUpdateTask?.cancel()
            
            // 清理缓存
            if let videoURL = viewModel.videoURL {
                Task {
                    await VideoFrameCache.shared.clearCache(for: videoURL)
                }
            }
        }
        .onChange(of: selectedTime) { _, _ in
            schedulePreviewUpdate()
        }
        .onChange(of: adjustment.brightness) { _, _ in
            schedulePreviewUpdate()
        }
        .onChange(of: adjustment.contrast) { _, _ in
            schedulePreviewUpdate()
        }
        .onChange(of: adjustment.saturation) { _, _ in
            schedulePreviewUpdate()
        }
        .onChange(of: adjustment.temperature) { _, _ in
            schedulePreviewUpdate()
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
    
    // MARK: - 预览相关方法
    
    private func loadVideoInfo(_ videoURL: URL) {
        Task {
            do {
                let info = try await VideoInfoService.getVideoInfo(from: videoURL)
                await MainActor.run {
                    self.videoInfo = info
                    // 默认选择视频中间位置
                    self.selectedTime = info.duration / 2
                    // 生成初始预览
                    generatePreview()
                }
            } catch {
                print("获取视频信息失败: \(error)")
            }
        }
    }
    
    private func schedulePreviewUpdate() {
        // 取消之前的任务
        previewUpdateTask?.cancel()
        
        // 使用防抖机制，延迟 300ms 后更新预览
        previewUpdateTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                generatePreview()
            }
        }
    }
    
    private func generatePreview() {
        guard let videoURL = viewModel.videoURL else { return }
        guard !isGeneratingPreview else { return }
        
        isGeneratingPreview = true
        
        Task {
            do {
                let (original, adjusted) = try await VideoColorAdjuster.extractAndAdjustFrame(
                    from: videoURL,
                    at: selectedTime,
                    adjustment: adjustment
                )
                
                await MainActor.run {
                    self.originalPreviewImage = original
                    self.adjustedPreviewImage = adjusted
                    self.isGeneratingPreview = false
                }
            } catch {
                print("生成预览失败: \(error)")
                await MainActor.run {
                    self.isGeneratingPreview = false
                }
            }
        }
    }
    
    private func startAdjustment() {
        guard let inputURL = viewModel.videoURL else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.movie, .mpeg4Movie]
        savePanel.nameFieldStringValue = inputURL.deletingPathExtension().lastPathComponent + "_adjusted"
        
        if savePanel.runModal() == .OK, let outputURL = savePanel.url {
            isProcessing = true
            progress = 0.0
            status = "准备处理..."
            
            Task {
                do {
                    try await VideoColorAdjuster.adjust(
                        inputURL: inputURL,
                        outputURL: outputURL,
                        adjustment: adjustment,
                        progressHandler: { prog, stat in
                            Task { @MainActor in
                                progress = prog
                                status = stat
                            }
                        }
                    )
                    
                    await MainActor.run {
                        isProcessing = false
                        status = "处理完成！"
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        status = "处理失败: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func handleVideoSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                viewModel.loadVideo(url)
                // 重置颜色调整参数和预览
                adjustment = ColorAdjustment()
                originalPreviewImage = nil
                adjustedPreviewImage = nil
                videoInfo = nil
                selectedTime = 0
                isProcessing = false
                progress = 0.0
                status = ""
                previewUpdateTask?.cancel()
            }
        case .failure(let error):
            print("选择视频失败: \(error.localizedDescription)")
        }
    }
}
