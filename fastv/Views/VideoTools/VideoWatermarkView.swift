//
//  VideoWatermarkView.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct VideoWatermarkView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @State private var watermarkType: WatermarkType = .image
    @State private var watermarkImageURL: URL?
    @State private var watermarkText: String = ""
    @State private var position: WatermarkPosition = .bottomRight
    @State private var fontSize: Int = 24
    @State private var opacity: Double = 1.0
    @State private var isProcessing = false
    @State private var progress: Double = 0.0
    @State private var status: String = ""
    
    // 预览相关状态
    @State private var previewImage: NSImage?
    @State private var videoSize: CGSize?
    @State private var isLoadingPreview = false
    
    // 自定义位置和大小（nil 表示使用预设位置）
    @State private var customWatermarkPosition: CGPoint? = nil
    @State private var customWatermarkSize: CGSize? = nil
    
    enum WatermarkType {
        case image
        case text
        case timestamp
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                previewSection
                
                Form {
                    Section {
                        Picker("水印类型", selection: $watermarkType) {
                            Text("图片水印").tag(WatermarkType.image)
                            Text("文字水印").tag(WatermarkType.text)
                            Text("时间戳").tag(WatermarkType.timestamp)
                        }
                        
                        if watermarkType == .image {
                            HStack {
                                Text("Logo 图片")
                                Spacer()
                                if let url = watermarkImageURL {
                                    Text(url.lastPathComponent)
                                        .foregroundStyle(.secondary)
                                    Button("更改") {
                                        selectImage()
                                    }
                                } else {
                                    Button("选择图片") {
                                        selectImage()
                                    }
                                }
                            }
                        } else if watermarkType == .text {
                            TextField("输入水印文字", text: $watermarkText)
                        }
                        
                        Picker("位置", selection: $position) {
                            ForEach(WatermarkPosition.allCases, id: \.self) { pos in
                                Text(pos.displayName).tag(pos)
                            }
                        }
                        
                        HStack {
                            Text("透明度")
                            Spacer()
                            Text(String(format: "%.0f%%", opacity * 100))
                                .monospacedDigit()
                        }
                        Slider(value: $opacity, in: 0.0...1.0, step: 0.1)
                        
                        if watermarkType == .text {
                            HStack {
                                Text("字体大小")
                                Spacer()
                                TextField("", value: $fontSize, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                            }
                        }
                    } header: {
                        Text("水印设置")
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
                    startWatermark()
                }) {
                    Label("添加水印", systemImage: "text.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.videoURL == nil || isProcessing || (watermarkType == .image && watermarkImageURL == nil) || (watermarkType == .text && watermarkText.isEmpty))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("水印Logo")
        .onAppear {
            loadPreview()
        }
        .onChange(of: viewModel.videoURL) { oldValue, newValue in
            if oldValue != newValue {
                loadPreview()
            }
        }
        .onChange(of: watermarkType) { _, _ in
            // 水印类型改变时，预览会自动更新
        }
        .onChange(of: watermarkImageURL) { _, _ in
            // 水印图片改变时，预览会自动更新
        }
        .onChange(of: watermarkText) { _, _ in
            // 水印文字改变时，预览会自动更新
        }
        .onChange(of: position) { _, _ in
            // 位置改变时，预览会自动更新
        }
        .onChange(of: fontSize) { _, _ in
            // 字体大小改变时，预览会自动更新
        }
        .onChange(of: opacity) { _, _ in
            // 透明度改变时，预览会自动更新
        }
        .onChange(of: position) { oldValue, newValue in
            // 当位置改变时，清除自定义位置，使用新的预设位置
            if oldValue != newValue {
                customWatermarkPosition = nil
            }
        }
    }
    
    // MARK: - Preview Section
    
    @ViewBuilder
    private var previewSection: some View {
        if viewModel.videoURL != nil {
            if let previewImage = previewImage, let videoSize = videoSize {
                watermarkPreviewContent(previewImage: previewImage, videoSize: videoSize)
            } else if isLoadingPreview {
                loadingPreviewView
            } else {
                dropZoneView(message: "拖拽视频文件到这里")
            }
        } else {
            dropZoneView(message: "请先选择视频文件")
        }
    }
    
    @ViewBuilder
    private func watermarkPreviewContent(previewImage: NSImage, videoSize: CGSize) -> some View {
        let previewWatermarkType: WatermarkDraggablePreviewView.WatermarkType = {
            switch watermarkType {
            case .image: return .image
            case .text: return .text
            case .timestamp: return .timestamp
            }
        }()
        
        WatermarkDraggablePreviewView(
            previewImage: previewImage,
            videoSize: videoSize,
            watermarkType: previewWatermarkType,
            watermarkImageURL: watermarkImageURL,
            watermarkText: watermarkText,
            fontSize: fontSize,
            opacity: opacity,
            customPosition: $customWatermarkPosition,
            customSize: $customWatermarkSize,
            position: $position
        )
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
        .onDrop(of: [.fileURL], isTargeted: .constant(false)) { providers in
            handleVideoDrop(providers: providers)
        }
    }
    
    private var loadingPreviewView: some View {
        ProgressView("加载预览...")
            .frame(minHeight: 300, maxHeight: 600)
    }
    
    @ViewBuilder
    private func dropZoneView(message: String) -> some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
                .frame(minHeight: 300, maxHeight: 600)
                .frame(maxWidth: 600) // 限制最大宽度
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(message)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: .constant(false)) { providers in
                    handleVideoDrop(providers: providers)
                }
            Spacer()
        }
    }
    
    // MARK: - Video Drop Handler
    
    // 处理视频拖拽
    private func handleVideoDrop(providers: [NSItemProvider]) -> Bool {
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
    
    // 加载预览（异步，不阻塞 UI）
    private func loadPreview() {
        guard let videoURL = viewModel.videoURL else {
            previewImage = nil
            videoSize = nil
            isLoadingPreview = false
            return
        }
        
        isLoadingPreview = true
        previewImage = nil
        videoSize = nil
        
        // 使用 Task.detached 确保在后台线程执行，不阻塞 UI
        Task.detached(priority: .userInitiated) {
            do {
                // 获取视频尺寸
                let videoInfo = try await VideoInfoService.getVideoInfo(from: videoURL)
                
                // 提取第一帧作为预览
                let image = try await FrameExtractor.extractFirstFrame(from: videoURL)
                
                // 回到主线程更新 UI
                await MainActor.run {
                    videoSize = videoInfo.resolution
                    previewImage = image
                    isLoadingPreview = false
                }
            } catch {
                await MainActor.run {
                    isLoadingPreview = false
                    print("❌ [VideoWatermarkView] 加载预览失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            watermarkImageURL = url
        }
    }
    
    private func startWatermark() {
        guard let inputURL = viewModel.videoURL else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.movie, .mpeg4Movie]
        
        // 获取输入文件的扩展名，如果没有则使用 .mp4
        let inputExtension = inputURL.pathExtension.isEmpty ? "mp4" : inputURL.pathExtension
        savePanel.nameFieldStringValue = inputURL.deletingPathExtension().lastPathComponent + "_watermarked.\(inputExtension)"
        
        if savePanel.runModal() == .OK, var outputURL = savePanel.url {
            // 确保输出文件有扩展名
            if outputURL.pathExtension.isEmpty {
                outputURL = outputURL.appendingPathExtension("mp4")
            }
            isProcessing = true
            progress = 0.0
            status = "准备添加水印..."
            
            Task {
                do {
                    if watermarkType == .image, let imageURL = watermarkImageURL {
                        try await VideoWatermark.addImageWatermark(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            watermarkImageURL: imageURL,
                            position: position,
                            customPosition: customWatermarkPosition,
                            customSize: customWatermarkSize,
                            opacity: opacity,
                            progressHandler: { prog, stat in
                                Task { @MainActor in
                                    progress = prog
                                    status = stat
                                }
                            }
                        )
                    } else if watermarkType == .text {
                        try await VideoWatermark.addTextWatermark(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            text: watermarkText,
                            position: position,
                            fontSize: fontSize,
                            opacity: opacity,
                            progressHandler: { prog, stat in
                                Task { @MainActor in
                                    progress = prog
                                    status = stat
                                }
                            }
                        )
                    } else if watermarkType == .timestamp {
                        try await VideoWatermark.addTimestampWatermark(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            position: position,
                            fontSize: fontSize,
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
                        status = "水印添加完成！"
                        
                        // 在 Finder 中显示文件
                        FileManager.default.revealInFinder(outputURL)
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        status = "添加失败: \(error.localizedDescription)"
                        print("❌ [VideoWatermarkView] 添加水印失败: \(error)")
                    }
                }
            }
        }
    }
}
