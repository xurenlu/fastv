//
//  VideoBlurView.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoBlurView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @State private var blurType: BlurType = .gaussianBlur
    @State private var blurRegion: BlurRegion = BlurRegion(x: 0, y: 0, width: 100, height: 100)
    @State private var videoRegion: VideoRegion = VideoRegion(x: 0, y: 0, width: 100, height: 100)
    @State private var sigma: Double = 20.0
    @State private var intensity: Int = 10
    @State private var isProcessing = false
    @State private var progress: Double = 0.0
    @State private var status: String = ""
    @State private var previewImage: NSImage?
    @State private var videoSize: CGSize?
    @State private var isLoadingPreview = false
    @State private var previewError: String?
    @State private var showVideoSelector = false
    
    enum BlurType {
        case mosaic
        case gaussianBlur
        case gradientErase
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let videoURL = viewModel.videoURL {
                    // 预览区域（带区域选择器）
                    Group {
                        if let previewImage = previewImage, let videoSize = videoSize {
                            VideoRegionSelector(
                                previewImage: previewImage,
                                videoSize: videoSize,
                                selectedRegion: $videoRegion,
                                enabled: true
                            )
                            .onChange(of: videoRegion) { oldValue, newValue in
                                if oldValue != newValue {
                                    let newBlurRegion = newValue.toBlurRegion()
                                    // 验证区域是否在视频范围内
                                    if isValidRegion(newBlurRegion, videoSize: videoSize) {
                                        blurRegion = newBlurRegion
                                    } else {
                                        // 如果区域无效，恢复旧值
                                        videoRegion = oldValue
                                    }
                                }
                            }
                            .frame(minHeight: 300, maxHeight: 600)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                            }
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.black.opacity(0.05))
                            }
                        } else {
                            // 加载中或未加载状态
                            ZStack {
                                Color.black
                                if isLoadingPreview {
                                    VStack(spacing: 12) {
                                        ProgressView()
                                            .controlSize(.large)
                                        Text("正在加载预览...")
                                            .foregroundStyle(.secondary)
                                    }
                                } else if let error = previewError {
                                    VStack(spacing: 12) {
                                        Image(systemName: "exclamationmark.triangle")
                                            .font(.system(size: 32))
                                            .foregroundStyle(.orange)
                                        Text("预览加载失败")
                                            .font(.headline)
                                        Text(error)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Button("重试") {
                                            loadPreviewImage()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                } else {
                                    Text("加载预览中...")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(minHeight: 300, maxHeight: 600)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .onAppear {
                        loadPreviewImage()
                    }
                    .onChange(of: viewModel.videoURL) { oldValue, newValue in
                        if oldValue != newValue {
                            resetState()
                            loadPreviewImage()
                        }
                    }
                    .onChange(of: blurRegion) { oldValue, newValue in
                        if oldValue != newValue {
                            // 只有当 videoRegion 与新的 blurRegion 不一致时才更新
                            let newVideoRegion = VideoRegion(newValue)
                            if videoRegion != newVideoRegion {
                                videoRegion = newVideoRegion
                            }
                        }
                    }
                    .onDrop(of: [.fileURL], isTargeted: .constant(false)) { providers in
                        // 支持拖放视频文件
                        var urls: [URL] = []
                        let group = DispatchGroup()
                        
                        for provider in providers {
                            group.enter()
                            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                                defer { group.leave() }
                                guard let data = item as? Data,
                                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                                    return
                                }
                                urls.append(url)
                            }
                        }
                        
                        group.notify(queue: .main) {
                            if let url = urls.first {
                                viewModel.loadVideo(url)
                            }
                        }
                        
                        return true
                    }
                }
                
                Form {
                    Section {
                        Picker("模糊类型", selection: $blurType) {
                            Text("马赛克").tag(BlurType.mosaic)
                            Text("高斯模糊").tag(BlurType.gaussianBlur)
                            Text("渐变抹除").tag(BlurType.gradientErase)
                        }
                        
                        // 区域信息显示（只读，用于查看当前选中的区域）
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("在预览图上拖动鼠标框选区域")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(action: {
                                    self.resetRegion()
                                }) {
                                    Label("清除选择", systemImage: "xmark.circle")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                            }
                            
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("X: \(blurRegion.x)")
                                    Text("Y: \(blurRegion.y)")
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("宽度: \(blurRegion.width)")
                                    Text("高度: \(blurRegion.height)")
                                }
                            }
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        }
                        
                        if blurType == .mosaic {
                            HStack {
                                Text("马赛克强度")
                                Spacer()
                                TextField("", value: $intensity, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                            }
                        } else {
                            HStack {
                                Text("模糊强度")
                                Spacer()
                                Text(String(format: "%.1f", sigma))
                                    .monospacedDigit()
                            }
                            Slider(value: $sigma, in: 5.0...100.0, step: 5.0)
                        }
                    } header: {
                        Text("模糊设置")
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
                    startBlur()
                }) {
                    Label("应用模糊", systemImage: "eye.slash.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.videoURL == nil || isProcessing)
            }
            .padding()
        }
        .navigationTitle("模糊马赛克")
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
            self.handleVideoSelection(result)
        }
    }
    
    private func loadPreviewImage() {
        guard let videoURL = viewModel.videoURL else {
            previewImage = nil
            videoSize = nil
            isLoadingPreview = false
            previewError = nil
            return
        }
        
        isLoadingPreview = true
        previewError = nil
        
        Task {
            // 在沙盒环境下，需要获取安全作用域资源访问权限
            let hasAccess = videoURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    videoURL.stopAccessingSecurityScopedResource()
                }
            }
            
            do {
                // 获取视频信息（包含尺寸）
                let videoInfo = try await VideoInfoService.getVideoInfo(from: videoURL)
                // 提取第一帧作为预览
                let image = try await FrameExtractor.extractFirstFrame(from: videoURL)
                
                await MainActor.run {
                    videoSize = videoInfo.resolution
                    previewImage = image
                    isLoadingPreview = false
                    previewError = nil
                    
                    // 初始化默认区域为视频中心区域
                    if blurRegion.width <= 0 || blurRegion.height <= 0 || !isValidRegion(blurRegion, videoSize: videoInfo.resolution) {
                        let centerX = Int(videoInfo.resolution.width) / 2
                        let centerY = Int(videoInfo.resolution.height) / 2
                        let defaultSize = min(Int(videoInfo.resolution.width), Int(videoInfo.resolution.height)) / 4
                        let newRegion = BlurRegion(
                            x: centerX - defaultSize / 2,
                            y: centerY - defaultSize / 2,
                            width: defaultSize,
                            height: defaultSize
                        )
                        blurRegion = newRegion
                        videoRegion = VideoRegion(newRegion)
                    } else {
                        // 验证并调整现有区域
                        let validatedRegion = validateAndAdjustRegion(blurRegion, videoSize: videoInfo.resolution)
                        blurRegion = validatedRegion
                        videoRegion = VideoRegion(validatedRegion)
                    }
                }
            } catch {
                await MainActor.run {
                    previewImage = nil
                    videoSize = nil
                    isLoadingPreview = false
                    previewError = "无法加载预览: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// 验证区域是否在视频尺寸范围内
    private func isValidRegion(_ region: BlurRegion, videoSize: CGSize?) -> Bool {
        guard let videoSize = videoSize else { return false }
        return region.x >= 0 &&
               region.y >= 0 &&
               region.width > 0 &&
               region.height > 0 &&
               region.x + region.width <= Int(videoSize.width) &&
               region.y + region.height <= Int(videoSize.height)
    }
    
    /// 验证并调整区域，确保在视频范围内
    private func validateAndAdjustRegion(_ region: BlurRegion, videoSize: CGSize) -> BlurRegion {
        let maxX = Int(videoSize.width)
        let maxY = Int(videoSize.height)
        
        var x = max(0, min(region.x, maxX - 1))
        var y = max(0, min(region.y, maxY - 1))
        var width = max(1, min(region.width, maxX - x))
        var height = max(1, min(region.height, maxY - y))
        
        return BlurRegion(x: x, y: y, width: width, height: height)
    }
    
    /// 重置区域选择
    private func resetRegion() {
        guard let videoSize = videoSize else { return }
        
        let centerX = Int(videoSize.width) / 2
        let centerY = Int(videoSize.height) / 2
        let defaultSize = min(Int(videoSize.width), Int(videoSize.height)) / 4
        
        let newRegion = BlurRegion(
            x: centerX - defaultSize / 2,
            y: centerY - defaultSize / 2,
            width: defaultSize,
            height: defaultSize
        )
        
        blurRegion = newRegion
        videoRegion = VideoRegion(newRegion)
    }
    
    /// 处理视频选择
    private func handleVideoSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                viewModel.loadVideo(url)
                resetState()
            }
        case .failure(let error):
            print("选择视频失败: \(error.localizedDescription)")
        }
    }
    
    /// 重置状态（更换视频时调用）
    private func resetState() {
        blurRegion = BlurRegion(x: 0, y: 0, width: 100, height: 100)
        videoRegion = VideoRegion(x: 0, y: 0, width: 100, height: 100)
        previewImage = nil
        videoSize = nil
        isLoadingPreview = false
        previewError = nil
        isProcessing = false
        progress = 0.0
        status = ""
    }
    
    private func startBlur() {
        guard let inputURL = viewModel.videoURL else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.movie, .mpeg4Movie]
        savePanel.nameFieldStringValue = inputURL.deletingPathExtension().lastPathComponent + "_blurred"
        
        if savePanel.runModal() == .OK, let outputURL = savePanel.url {
            isProcessing = true
            progress = 0.0
            status = "准备处理..."
            
            Task {
                do {
                    switch blurType {
                    case .mosaic:
                        try await VideoBlur.applyMosaic(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            region: blurRegion,
                            intensity: intensity,
                            progressHandler: { prog, stat in
                                Task { @MainActor in
                                    progress = prog
                                    status = stat
                                }
                            }
                        )
                    case .gaussianBlur:
                        try await VideoBlur.applyGaussianBlur(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            region: blurRegion,
                            sigma: sigma,
                            progressHandler: { prog, stat in
                                Task { @MainActor in
                                    progress = prog
                                    status = stat
                                }
                            }
                        )
                    case .gradientErase:
                        try await VideoBlur.applyGradientErase(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            region: blurRegion,
                            centerSigma: sigma,
                            edgeSigma: sigma * 0.2,
                            progressHandler: { prog, stat in
                                Task { @MainActor in
                                    progress = prog
                                    status = stat
                                }
                            }
                        )
                    }
                    
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
}
