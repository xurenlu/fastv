//
//  VideoToolsSettingsTab.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI
import AppKit
import Combine

/// Tab: 视频处理设置
struct VideoToolsSettingsTab: View {
    @ObservedObject var preferences = UserPreferences.shared
    @StateObject private var modelDownloader = VideoModelDownloader.shared
    @State private var ffmpegCheckResult: (available: Bool, version: String?, path: String?)?
    @State private var showFFmpegPathPicker = false
    @State private var showModelPathPicker: VideoModelInfo?
    @State private var isCheckingFFmpeg = false
    
    var body: some View {
        Form {
            // FFmpeg 配置
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: ffmpegCheckResult?.available == true ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(ffmpegCheckResult?.available == true ? .green : .orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FFmpeg 状态")
                                .font(.body)
                            
                            if let result = ffmpegCheckResult {
                                if result.available {
                                    if let version = result.version {
                                        Text("已安装 (\(version))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("已安装")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("未找到")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("检查中...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            checkFFmpeg()
                        }) {
                            HStack {
                                if isCheckingFFmpeg {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("重新检测")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isCheckingFFmpeg)
                    }
                    
                    if let result = ffmpegCheckResult, result.available, let path = result.path {
                        HStack {
                            Text("路径:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                        }
                    }
                    
                    // FFmpeg 路径设置
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FFmpeg 路径（可选）")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            TextField("留空则自动检测", text: Binding(
                                get: { preferences.ffmpegPath },
                                set: { newValue in
                                    preferences.ffmpegPath = newValue
                                    checkFFmpeg()
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            
                            Button("选择...") {
                                showFFmpegPathPicker = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.leading, 20)
                    
                    if ffmpegCheckResult?.available != true {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("请先安装 FFmpeg：brew install ffmpeg")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("FFmpeg 配置")
            } footer: {
                Text("FFmpeg 用于视频格式转换、压缩、滤镜处理等功能。如果未安装，请先通过 Homebrew 安装：brew install ffmpeg")
            }
            
            // Hugging Face Token 配置
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Hugging Face Token（可选）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    SecureField("输入您的 Hugging Face Token", text: $preferences.huggingFaceToken)
                        .textFieldStyle(.roundedBorder)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text("用于下载需要认证的模型。获取 Token：https://huggingface.co/settings/tokens")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if !preferences.huggingFaceToken.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("Token 已设置（\(String(preferences.huggingFaceToken.prefix(8)))...）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("模型下载认证")
            } footer: {
                Text("某些模型需要 Hugging Face Token 才能下载。如果下载公开模型，可以不设置 Token。")
            }
            
            // AI 模型管理
            Section {
                ForEach(VideoModelDownloader.availableModels, id: \.id) { model in
                    ModelItemView(
                        model: model,
                        downloader: modelDownloader,
                        onSelectPath: {
                            showModelPathPicker = model
                        }
                    )
                }
            } header: {
                Text("AI 模型")
            } footer: {
                Text("视频处理 AI 模型用于智能功能，如物体检测、人脸识别等。模型将从 Hugging Face 下载。")
            }
            
            // 默认输出设置
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    // 默认编码器
                    VStack(alignment: .leading, spacing: 8) {
                        Text("默认视频编码器")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Picker("", selection: $preferences.videoToolsDefaultCodec) {
                            Text("H.264 (libx264)").tag("libx264")
                            Text("H.265/HEVC (libx265)").tag("libx265")
                            Text("VP9").tag("libvpx-vp9")
                            Text("AV1").tag("libaom-av1")
                        }
                        .pickerStyle(.menu)
                    }
                    
                    // 默认 CRF 值
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("默认压缩质量 (CRF)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Text("\(preferences.videoToolsDefaultCRF)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        
                        Slider(value: Binding(
                            get: { Double(preferences.videoToolsDefaultCRF) },
                            set: { preferences.videoToolsDefaultCRF = Int($0) }
                        ), in: 18...28, step: 1)
                        
                        HStack {
                            Text("高质量（文件较大）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("低质量（文件较小）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // 默认输出目录
                    VStack(alignment: .leading, spacing: 8) {
                        Text("默认输出目录（可选）")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            TextField("留空则使用视频文件同目录", text: $preferences.videoToolsOutputDirectory)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("选择...") {
                                selectOutputDirectory()
                            }
                            .buttonStyle(.bordered)
                            
                            if !preferences.videoToolsOutputDirectory.isEmpty {
                                Button("清除") {
                                    preferences.videoToolsOutputDirectory = ""
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            } header: {
                Text("默认输出设置")
            } footer: {
                Text("CRF 值越小，质量越高但文件越大。推荐值：18-23（高质量），24-28（中等质量）。")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            checkFFmpeg()
        }
        .onChange(of: showFFmpegPathPicker) { oldValue, newValue in
            if newValue {
                selectFFmpegPath()
            }
        }
        .onChange(of: showModelPathPicker) { oldValue, newValue in
            if let model = newValue {
                selectModelPath(for: model)
            }
        }
    }
    
    private func checkFFmpeg() {
        isCheckingFFmpeg = true
        Task {
            let result = FFmpegService.checkFFmpegAvailable()
            await MainActor.run {
                ffmpegCheckResult = result
                isCheckingFFmpeg = false
            }
        }
    }
    
    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = "选择输出目录"
        panel.prompt = "选择"
        
        if panel.runModal() == .OK, let url = panel.url {
            preferences.videoToolsOutputDirectory = url.path
        }
    }
    
    private func selectFFmpegPath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = []
        panel.title = "选择 FFmpeg 可执行文件"
        panel.prompt = "选择"
        
        // 设置默认路径
        if let ffmpegPath = FFmpegService.getFFmpegPath() {
            panel.directoryURL = URL(fileURLWithPath: (ffmpegPath as NSString).deletingLastPathComponent)
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            preferences.ffmpegPath = url.path
            checkFFmpeg()
        }
        showFFmpegPathPicker = false
    }
    
    private func selectModelPath(for model: VideoModelInfo) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = []
        panel.title = "选择 \(model.name) 模型文件"
        panel.prompt = "选择"
        
        // 设置默认路径
        if let modelPath = VideoModelDownloader.shared.getModelPath(model) {
            panel.directoryURL = modelPath.deletingLastPathComponent()
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            switch model.modelType {
            case .yolo:
                preferences.videoYoloModelPath = url.path
            case .faceDetection:
                preferences.videoFaceModelPath = url.path
            }
        }
        showModelPathPicker = nil
    }
}

/// 模型项视图
struct ModelItemView: View {
    let model: VideoModelInfo
    @ObservedObject var downloader: VideoModelDownloader
    @ObservedObject var preferences = UserPreferences.shared
    let onSelectPath: () -> Void
    
    @State private var isDownloading = false
    @State private var showDownloadProgress = false
    
    var modelPath: String {
        switch model.modelType {
        case .yolo:
            return preferences.videoYoloModelPath
        case .faceDetection:
            return preferences.videoFaceModelPath
        }
    }
    
    var modelExists: Bool {
        if !modelPath.isEmpty {
            return FileManager.default.fileExists(atPath: modelPath)
        }
        return downloader.checkModelExists(model)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: modelExists ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(modelExists ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.body)
                    
                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if modelExists {
                    Button("已下载") {
                        // 显示路径信息
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(true)
                } else {
                    Button(action: {
                        downloadModel()
                    }) {
                        HStack {
                            if downloader.isDownloading && downloader.currentModel?.id == model.id {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                            }
                            Text("下载")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(downloader.isDownloading)
                }
                
                Button("选择路径...") {
                    onSelectPath()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // 显示下载进度
            if downloader.isDownloading && downloader.currentModel?.id == model.id {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: downloader.downloadProgress)
                    
                    HStack {
                        Text(downloader.downloadStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if !downloader.downloadSpeed.isEmpty {
                            Text(downloader.downloadSpeed)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.leading, 24)
            }
            
            // 显示模型路径
            if modelExists, !modelPath.isEmpty {
                HStack {
                    Text("路径:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(modelPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func downloadModel() {
        Task {
            do {
                try await downloader.downloadModel(model) { progress, status, speed in
                    // 进度已通过 @Published 属性更新
                }
            } catch {
                // 错误已通过 @Published error 属性处理
                print("下载失败: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    VideoToolsSettingsTab()
}
