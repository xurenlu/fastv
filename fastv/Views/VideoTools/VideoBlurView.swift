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
                            .onChange(of: videoRegion) { _, newRegion in
                                blurRegion = newRegion.toBlurRegion()
                            }
                            .onAppear {
                                videoRegion = VideoRegion(blurRegion)
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
                                if previewImage == nil && videoSize == nil {
                                    ProgressView()
                                        .controlSize(.large)
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
                    .onChange(of: viewModel.videoURL) { _, _ in
                        loadPreviewImage()
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
                            Text("在预览图上拖动鼠标框选区域")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
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
    }
    
    private func loadPreviewImage() {
        guard let videoURL = viewModel.videoURL else {
            previewImage = nil
            videoSize = nil
            return
        }
        
        Task {
            do {
                // 获取视频信息（包含尺寸）
                let videoInfo = try await VideoInfoService.getVideoInfo(from: videoURL)
                // 提取第一帧作为预览
                let image = try await FrameExtractor.extractFirstFrame(from: videoURL)
                
                await MainActor.run {
                    videoSize = videoInfo.resolution
                    previewImage = image
                    // 初始化默认区域为视频中心区域
                    if blurRegion.width <= 0 || blurRegion.height <= 0 {
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
                        videoRegion = VideoRegion(blurRegion)
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
