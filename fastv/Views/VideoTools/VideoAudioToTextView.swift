//
//  VideoAudioToTextView.swift
//  fastv
//
//  Created by rocky on 2025/12/25.
//

import SwiftUI
import UniformTypeIdentifiers

/// 音频转文字视图
struct VideoAudioToTextView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @ObservedObject var preferences = UserPreferences.shared
    @State private var isProcessing = false
    @State private var progress: Double = 0
    @State private var statusMessage = ""
    @State private var transcriptText = ""
    @State private var outputURL: URL?
    @State private var showVideoSelector = false
    @State private var currentTask: Task<Void, Never>?
    
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
                    
                    // 音频信息
                    if videoInfo.hasAudio {
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundStyle(.green)
                            Text("该视频包含音频轨道，可以进行转写")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        HStack {
                            Image(systemName: "speaker.slash")
                                .foregroundStyle(.orange)
                            Text("该视频没有音频轨道，无法转写")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                // 转写选项
                Form {
                    Section {
                        HStack {
                            Text("语言")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $preferences.transcriptLanguage) {
                                ForEach(TranscriptLanguage.allCases, id: \.self) { language in
                                    Text(language.displayName).tag(language)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }
                        
                        Text("选择视频音频的语言，自动识别可能不够准确")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("转写选项")
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
                
                // 转写结果
                if !transcriptText.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("转写结果")
                                .font(.headline)
                            Spacer()
                            if let outputURL = outputURL {
                                Button(action: {
                                    NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: outputURL.deletingLastPathComponent().path)
                                }) {
                                    Label("在 Finder 中显示", systemImage: "folder")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        
                        ScrollView {
                            Text(transcriptText)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .frame(height: 200)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        
                        HStack {
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(transcriptText, forType: .string)
                            }) {
                                Label("复制文本", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                // 处理按钮
                HStack(spacing: 12) {
                    Button(action: {
                        currentTask = Task {
                            await transcribeAudio()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "doc.text")
                            }
                            Text(isProcessing ? "转写中..." : "开始转写")
                        }
                        .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isProcessing || viewModel.videoInfo?.hasAudio != true)
                    
                    // 取消按钮
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
        .navigationTitle("音频转文字")
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
        transcriptText = ""
        outputURL = nil
        progress = 0
        statusMessage = ""
    }
    
    private func transcribeAudio() async {
        guard let videoURL = viewModel.videoURL else { return }
        guard viewModel.videoInfo?.hasAudio == true else { return }
        
        // 确保状态更新在主线程
        await MainActor.run {
            isProcessing = true
            progress = 0
            statusMessage = "正在提取音频..."
        }
        
        let tempAudioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        
        defer {
            // 确保清理临时文件
            try? FileManager.default.removeItem(at: tempAudioURL)
        }
        
        do {
            let outputDir = viewModel.outputDirectory ?? videoURL.deletingLastPathComponent()
            let videoName = videoURL.deletingPathExtension().lastPathComponent
            
            // 1. 先提取音频（添加超时保护）
            await MainActor.run {
                progress = 0.1
            }
            
            print("🎵 [VideoAudioToTextView] 开始提取音频...")
            
            // 使用 Task.detached 确保音频提取在后台线程执行，并添加超时
            try await withTimeout(seconds: VideoToolsConstants.audioExtractionTimeout) {
                try await Task.detached(priority: .userInitiated) {
                    try await AudioExtractor.extractAudio(
                        from: videoURL,
                        to: tempAudioURL,
                        format: .wav,
                        progressHandler: { prog in
                            Task { @MainActor in
                                progress = 0.1 + (prog * 0.2)
                                statusMessage = "提取音频: \(Int(prog * 100))%"
                            }
                        }
                    )
                }.value
            }
            
            print("✅ [VideoAudioToTextView] 音频提取完成")
            
            // 2. 转写音频（使用分段处理，在后台线程执行，避免阻塞主线程）
            await MainActor.run {
                progress = 0.3
                statusMessage = "正在转写音频..."
            }
            
            print("🎤 [VideoAudioToTextView] 开始转写音频（分段处理）...")
            
            // 使用 Task.detached 确保推理在后台线程执行，并添加超时
            // 使用新的分段转录方法，支持进度回调
            let transcript = try await withTimeout(seconds: VideoToolsConstants.transcriptionTimeout) {
                try await Task.detached(priority: .userInitiated) {
                    try await SpeechTranscriber.transcribeWithSegmentation(
                        audioURL: tempAudioURL,
                        language: await MainActor.run { preferences.transcriptLanguage },
                        enableCTCDeduplication: await MainActor.run { preferences.enableCTCDeduplication },
                        progressHandler: { segmentProgress, segmentStatus in
                            Task { @MainActor in
                                // 转写进度占 0.3 到 0.85 的区间
                                progress = 0.3 + (segmentProgress * 0.55)
                                statusMessage = segmentStatus
                            }
                        }
                    )
                }.value
            }
            
            print("✅ [VideoAudioToTextView] 音频转写完成，文本长度: \(transcript.count)")
            
            // 3. 应用文本纠错
            await MainActor.run {
                progress = 0.9
                statusMessage = "正在优化文本..."
            }
            
            var finalText = transcript
            
            // 快速纠错（在主线程执行，因为很快）
            let mistakeManager = CommonMistakeManager.shared
            let enableAutoCorrection = await MainActor.run { mistakeManager.enableAutoCorrection }
            if enableAutoCorrection {
                finalText = TextCorrectionService.shared.correctText(finalText)
            }
            
            // AI 优化（如果启用）
            let shouldOptimize = await MainActor.run { self.preferences.enableAIOptimization }
            if shouldOptimize {
                do {
                    let config = await MainActor.run { self.preferences.getConfig(for: .voiceInputOptimization) }
                    let systemPrompt = await MainActor.run { self.preferences.aiSystemPrompt }
                    finalText = try await OllamaService.shared.optimizeTranscript(
                        text: finalText,
                        profile: config.profile,
                        systemPrompt: systemPrompt
                    )
                } catch {
                    print("⚠️ AI 优化失败: \(error.localizedDescription)")
                }
            }
            
            // 4. 保存文本文件
            let textFilename = "\(videoName)_transcript.txt"
            let textURL = outputDir.appendingPathComponent(textFilename)
            try finalText.write(to: textURL, atomically: true, encoding: .utf8)
            
            await MainActor.run {
                transcriptText = finalText
                outputURL = textURL
                statusMessage = "转写完成！"
                progress = 1.0
            }
            
            // 在 Finder 中显示
            NSWorkspace.shared.selectFile(textURL.path, inFileViewerRootedAtPath: outputDir.path)
            
        } catch {
            let errorMessage: String
            if let timeoutError = error as? TimeoutError {
                errorMessage = "操作超时: \(timeoutError.localizedDescription)"
                print("⏱️ [VideoAudioToTextView] 操作超时: \(timeoutError)")
            } else {
                errorMessage = "转写失败: \(error.localizedDescription)"
                print("❌ [VideoAudioToTextView] 转写失败: \(error)")
                if let nsError = error as NSError? {
                    print("   错误域: \(nsError.domain), 错误码: \(nsError.code)")
                    print("   用户信息: \(nsError.userInfo)")
                }
            }
            
            await MainActor.run {
                statusMessage = errorMessage
            }
        }
        
        // 确保状态更新在主线程
        await MainActor.run {
            isProcessing = false
        }
    }
    
    /// 超时错误
    private struct TimeoutError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    
    /// 带超时的异步操作包装器
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // 添加实际操作任务
            group.addTask {
                try await operation()
            }
            
            // 添加超时任务
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError(message: "操作超过 \(Int(seconds)) 秒未完成")
            }
            
            // 等待第一个完成的任务
            let result = try await group.next()!
            // 取消其他任务
            group.cancelAll()
            return result
        }
    }
}

#Preview {
    VideoAudioToTextView(viewModel: VideoProcessorViewModel())
}

