//
//  VideoTransformView.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoTransformView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @State private var transformType: TransformType = .crop
    @State private var cropRegion: CropRegion = CropRegion(x: 0, y: 0, width: 100, height: 100)
    @State private var videoRegion: VideoRegion = VideoRegion(x: 0, y: 0, width: 100, height: 100)
    @State private var rotationAngle: RotationAngle = .rotate90
    @State private var isProcessing = false
    @State private var progress: Double = 0.0
    @State private var status: String = ""
    @State private var previewImage: NSImage?
    @State private var videoSize: CGSize?
    @State private var showVideoSelector = false
    
    enum TransformType {
        case crop
        case scale
        case rotate
        case flipHorizontal
        case flipVertical
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let videoURL = viewModel.videoURL {
                    // 预览区域（裁剪时显示区域选择器）
                    if transformType == .crop, let previewImage = previewImage, let videoSize = videoSize {
                        VideoRegionSelector(
                            previewImage: previewImage,
                            videoSize: videoSize,
                            selectedRegion: $videoRegion,
                            enabled: true
                        )
                        .onChange(of: videoRegion) { _, newRegion in
                            cropRegion = newRegion.toCropRegion()
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
                        .onAppear {
                            videoRegion = VideoRegion(cropRegion)
                            loadPreviewImage()
                        }
                        .onChange(of: viewModel.videoURL) { _, _ in
                            loadPreviewImage()
                        }
                        .onChange(of: cropRegion) { _, newRegion in
                            videoRegion = VideoRegion(newRegion)
                        }
                    } else {
                        // 非裁剪模式或加载中，显示普通预览
                        VideoPreviewView(
                            videoURL: videoURL,
                            onVideoDropped: { urls in
                                if let url = urls.first {
                                    viewModel.loadVideo(url)
                                }
                            },
                            seekToTime: .constant(nil)
                        )
                    }
                }
                
                Form {
                    Section {
                        Picker("变换类型", selection: $transformType) {
                            Text("裁剪").tag(TransformType.crop)
                            Text("缩放").tag(TransformType.scale)
                            Text("旋转").tag(TransformType.rotate)
                            Text("水平翻转").tag(TransformType.flipHorizontal)
                            Text("垂直翻转").tag(TransformType.flipVertical)
                        }
                        
                        if transformType == .crop {
                            // 区域信息显示（只读，用于查看当前选中的区域）
                            VStack(alignment: .leading, spacing: 8) {
                                Text("在预览图上拖动鼠标框选裁剪区域")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("X: \(cropRegion.x)")
                                        Text("Y: \(cropRegion.y)")
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("宽度: \(cropRegion.width)")
                                        Text("高度: \(cropRegion.height)")
                                    }
                                }
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                            }
                        } else if transformType == .rotate {
                            Picker("旋转角度", selection: $rotationAngle) {
                                ForEach(RotationAngle.allCases, id: \.self) { angle in
                                    Text(angle.displayName).tag(angle)
                                }
                            }
                        }
                    } header: {
                        Text("变换设置")
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
                    startTransform()
                }) {
                    Label("应用变换", systemImage: "crop.rotate")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.videoURL == nil || isProcessing)
            }
            .padding()
        }
        .navigationTitle("裁剪旋转")
        .onAppear {
            if transformType == .crop {
                loadPreviewImage()
            }
        }
        .onChange(of: transformType) { _, newType in
            if newType == .crop {
                loadPreviewImage()
            }
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
                // 重置裁剪区域和预览
                cropRegion = CropRegion(x: 0, y: 0, width: 100, height: 100)
                videoRegion = VideoRegion(x: 0, y: 0, width: 100, height: 100)
                previewImage = nil
                videoSize = nil
                isProcessing = false
                progress = 0.0
                status = ""
            }
        case .failure(let error):
            print("选择视频失败: \(error.localizedDescription)")
        }
    }
    
    private func loadPreviewImage() {
        guard let videoURL = viewModel.videoURL else {
            previewImage = nil
            videoSize = nil
            return
        }
        
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
                    // 初始化默认区域为视频中心区域
                    if cropRegion.width <= 0 || cropRegion.height <= 0 {
                        let centerX = Int(videoInfo.resolution.width) / 2
                        let centerY = Int(videoInfo.resolution.height) / 2
                        let defaultSize = min(Int(videoInfo.resolution.width), Int(videoInfo.resolution.height)) / 2
                        let newRegion = CropRegion(
                            x: centerX - defaultSize / 2,
                            y: centerY - defaultSize / 2,
                            width: defaultSize,
                            height: defaultSize
                        )
                        cropRegion = newRegion
                        videoRegion = VideoRegion(newRegion)
                    } else {
                        videoRegion = VideoRegion(cropRegion)
                    }
                }
            } catch {
                await MainActor.run {
                    previewImage = nil
                    videoSize = nil
                }
            }
        }
    }
    
    private func startTransform() {
        guard let inputURL = viewModel.videoURL else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.movie, .mpeg4Movie]
        savePanel.nameFieldStringValue = inputURL.deletingPathExtension().lastPathComponent + "_transformed"
        
        if savePanel.runModal() == .OK, let outputURL = savePanel.url {
            isProcessing = true
            progress = 0.0
            status = "准备处理..."
            
            Task {
                do {
                    switch transformType {
                    case .crop:
                        try await VideoTransform.crop(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            cropRegion: cropRegion,
                            progressHandler: { prog, stat in
                                Task { @MainActor in
                                    progress = prog
                                    status = stat
                                }
                            }
                        )
                    case .rotate:
                        try await VideoTransform.rotate(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            angle: rotationAngle,
                            progressHandler: { prog, stat in
                                Task { @MainActor in
                                    progress = prog
                                    status = stat
                                }
                            }
                        )
                    case .flipHorizontal:
                        try await VideoTransform.flipHorizontal(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            progressHandler: { prog, stat in
                                Task { @MainActor in
                                    progress = prog
                                    status = stat
                                }
                            }
                        )
                    case .flipVertical:
                        try await VideoTransform.flipVertical(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            progressHandler: { prog, stat in
                                Task { @MainActor in
                                    progress = prog
                                    status = stat
                                }
                            }
                        )
                    case .scale:
                        // 简化：使用默认缩放
                        try await VideoTransform.scale(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            width: 1920,
                            height: 1080,
                            keepAspectRatio: true,
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
