//
//  VideoExtractFramesView.swift
//  fastv
//
//  Created by rocky on 2025/12/25.
//

import SwiftUI
import AVFoundation

/// 提取首尾帧视图
struct VideoExtractFramesView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @State private var isProcessing = false
    @State private var progress: Double = 0
    @State private var statusMessage = ""
    @State private var firstFrameImage: NSImage?
    @State private var lastFrameImage: NSImage?
    @State private var extractFirst = true
    @State private var extractLast = true
    @State private var imageFormat: ImageFormat = .png
    @State private var imageQuality: Double = 90
    @State private var showVideoSelector = false
    @State private var currentTask: Task<Void, Never>?
    
    enum ImageFormat: String, CaseIterable, Identifiable {
        case png = "PNG"
        case jpg = "JPG"
        case tiff = "TIFF"
        
        var id: String { rawValue }
        
        var fileExtension: String {
            switch self {
            case .png: return "png"
            case .jpg: return "jpg"
            case .tiff: return "tiff"
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 视频预览
                if let videoURL = viewModel.videoURL {
                    VideoPreviewView(
                        videoURL: videoURL,
                        onVideoDropped: { urls in
                            if let url = urls.first {
                                viewModel.loadVideo(url)
                                resetState()
                            }
                        },
                        seekToTime: .constant(nil)
                    )
                }
                
                // 视频信息
                if let videoInfo = viewModel.videoInfo {
                    VideoInfoCard(videoInfo: videoInfo)
                }
                
                // 提取选项
                Form {
                    Section {
                        Toggle("提取第一帧", isOn: $extractFirst)
                        Toggle("提取最后一帧", isOn: $extractLast)
                        
                        Divider()
                        
                        HStack {
                            Text("图片格式")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $imageFormat) {
                                ForEach(ImageFormat.allCases) { format in
                                    Text(format.rawValue).tag(format)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }
                        
                        if imageFormat == .jpg {
                            HStack {
                                Text("图片质量")
                                    .foregroundStyle(.secondary)
                                Slider(value: $imageQuality, in: 10...100, step: 10)
                                Text("\(Int(imageQuality))%")
                                    .frame(width: 40)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("提取选项")
                    }
                    
                    Section {
                        HStack {
                            Label("保存位置", systemImage: "folder")
                            Spacer()
                            if let outputDirectory = viewModel.outputDirectory {
                                Text(outputDirectory.lastPathComponent)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("默认（视频文件同目录）")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                viewModel.selectOutputDirectory()
                            }) {
                                Label("选择位置", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            
                            if viewModel.preferences.useCustomOutputDirectory {
                                Button(action: {
                                    viewModel.resetToDefaultOutputDirectory()
                                }) {
                                    Label("使用默认", systemImage: "arrow.counterclockwise")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    } header: {
                        Text("保存位置")
                    }
                }
                .formStyle(.grouped)
                
                // 预览区域
                if firstFrameImage != nil || lastFrameImage != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("提取结果")
                            .font(.headline)
                        
                        HStack(spacing: 20) {
                            if let firstFrame = firstFrameImage {
                                VStack(spacing: 8) {
                                    Image(nsImage: firstFrame)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: 300, maxHeight: 200)
                                        .cornerRadius(8)
                                    Text("第一帧")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            if let lastFrame = lastFrameImage {
                                VStack(spacing: 8) {
                                    Image(nsImage: lastFrame)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: 300, maxHeight: 200)
                                        .cornerRadius(8)
                                    Text("最后一帧")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
                
                // 处理按钮
                HStack(spacing: 12) {
                    Button(action: {
                        currentTask = Task {
                            await extractFrames()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "photo")
                            }
                            Text(isProcessing ? "提取中..." : "开始提取")
                        }
                        .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isProcessing || (!extractFirst && !extractLast))
                    
                    if isProcessing {
                        Button(action: cancelTask) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle")
                                Text("取消")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.red)
                    }
                }
                
                // 进度和状态
                if isProcessing {
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("提取首尾帧")
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
        .onDisappear {
            cancelTask()
        }
    }
    
    private func cancelTask() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        statusMessage = "操作已取消"
    }
    
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
    
    private func resetState() {
        firstFrameImage = nil
        lastFrameImage = nil
        progress = 0
        statusMessage = ""
    }
    
    private func extractFrames() async {
        guard let videoURL = viewModel.videoURL else { return }
        
        // 确保状态更新在主线程
        await MainActor.run {
            isProcessing = true
            progress = 0
            statusMessage = "正在加载视频..."
        }
        
        do {
            let outputDir = viewModel.outputDirectory ?? videoURL.deletingLastPathComponent()
            let videoName = videoURL.deletingPathExtension().lastPathComponent
            
            var extractedCount = 0
            let totalCount = (extractFirst ? 1 : 0) + (extractLast ? 1 : 0)
            
            // 在后台线程执行帧提取，避免阻塞主线程
            let result = try await Task.detached(priority: .userInitiated) {
                let asset = AVAsset(url: videoURL)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                imageGenerator.requestedTimeToleranceAfter = .zero
                imageGenerator.requestedTimeToleranceBefore = .zero
                
                let duration = try await asset.load(.duration)
                
                var firstImage: NSImage?
                var lastImage: NSImage?
                
                // 提取第一帧
                if extractFirst {
                    await MainActor.run {
                        statusMessage = "正在提取第一帧..."
                    }
                    let time = CMTime(seconds: 0, preferredTimescale: 600)
                    let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                    firstImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                }
                
                // 提取最后一帧
                if extractLast {
                    await MainActor.run {
                        statusMessage = "正在提取最后一帧..."
                    }
                    let lastTime = CMTime(seconds: max(0, duration.seconds - 0.1), preferredTimescale: 600)
                    let cgImage = try imageGenerator.copyCGImage(at: lastTime, actualTime: nil)
                    lastImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                }
                
                return (firstImage, lastImage)
            }.value
            
            // 更新 UI 状态
            await MainActor.run {
                firstFrameImage = result.0
                lastFrameImage = result.1
            }
            
            // 保存图片
            if let firstImage = result.0 {
                let filename = "\(videoName)_first_frame.\(imageFormat.fileExtension)"
                let outputURL = outputDir.appendingPathComponent(filename)
                try saveImage(firstImage, to: outputURL)
                extractedCount += 1
                await MainActor.run {
                    progress = Double(extractedCount) / Double(totalCount)
                }
            }
            
            if let lastImage = result.1 {
                let filename = "\(videoName)_last_frame.\(imageFormat.fileExtension)"
                let outputURL = outputDir.appendingPathComponent(filename)
                try saveImage(lastImage, to: outputURL)
                extractedCount += 1
                await MainActor.run {
                    progress = Double(extractedCount) / Double(totalCount)
                }
            }
            
            await MainActor.run {
                statusMessage = "提取完成！"
            }
            
            // 在 Finder 中显示
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: outputDir.path)
            
        } catch {
            await MainActor.run {
                statusMessage = "提取失败: \(error.localizedDescription)"
                print("❌ [VideoExtractFramesView] 提取失败: \(error)")
            }
        }
        
        // 确保状态更新在主线程
        await MainActor.run {
            isProcessing = false
        }
    }
    
    private func saveImage(_ image: NSImage, to url: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            throw NSError(domain: "VideoExtractFrames", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法转换图片格式"])
        }
        
        let imageData: Data?
        switch imageFormat {
        case .png:
            imageData = bitmapImage.representation(using: .png, properties: [:])
        case .jpg:
            let quality = imageQuality / 100.0
            imageData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: quality])
        case .tiff:
            imageData = bitmapImage.representation(using: .tiff, properties: [:])
        }
        
        guard let data = imageData else {
            throw NSError(domain: "VideoExtractFrames", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法生成图片数据"])
        }
        
        try data.write(to: url)
    }
}

#Preview {
    VideoExtractFramesView(viewModel: VideoProcessorViewModel())
}

