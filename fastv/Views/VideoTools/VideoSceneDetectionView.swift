//
//  VideoSceneDetectionView.swift
//  fastv
//
//  Created by rocky on 2025/12/25.
//

import SwiftUI
import UniformTypeIdentifiers

/// 场景变更检测视图
struct VideoSceneDetectionView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @State private var isProcessing = false
    @State private var progress: Double = 0
    @State private var statusMessage = ""
    @State private var sceneChanges: [SceneChange] = []
    @State private var threshold: Double = 0.3
    @State private var minSceneDuration: Double = 1.0
    @State private var outputURL: URL?
    @State private var showVideoSelector = false
    @State private var currentTask: Task<Void, Never>?
    
    struct SceneChange: Identifiable {
        let id = UUID()
        let time: TimeInterval
        let frame: Int
        let score: Double
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
                
                // 检测选项
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("检测灵敏度")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.2f", threshold))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            
                            Slider(value: $threshold, in: 0.1...0.9, step: 0.05)
                            
                            HStack {
                                Text("低（检测更多）")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("高（检测更少）")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("最小场景时长")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f 秒", minSceneDuration))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            
                            Slider(value: $minSceneDuration, in: 0.5...5.0, step: 0.5)
                        }
                        
                        Text("调整检测灵敏度和最小场景时长以获得最佳效果")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("检测选项")
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
                
                // 检测结果
                if !sceneChanges.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("检测结果")
                                .font(.headline)
                            Spacer()
                            Text("\(sceneChanges.count) 个场景变更点")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
                            LazyVStack(spacing: 8) {
                                ForEach(sceneChanges) { change in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(formatTime(change.time))
                                                .font(.system(.body, design: .monospaced))
                                                .fontWeight(.medium)
                                            Text("帧 #\(change.frame)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        HStack(spacing: 4) {
                                            Text("相似度:")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(String(format: "%.2f", change.score))
                                                .font(.caption)
                                                .monospacedDigit()
                                                .foregroundStyle(change.score < 0.3 ? .red : change.score < 0.5 ? .orange : .green)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(6)
                                }
                            }
                        }
                        .frame(height: 300)
                    }
                }
                
                // 处理按钮
                HStack(spacing: 12) {
                    Button(action: {
                        currentTask = Task {
                            await detectSceneChanges()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "scissors")
                            }
                            Text(isProcessing ? "检测中..." : "开始检测")
                        }
                        .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isProcessing)
                    
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
        .navigationTitle("场景变更检测")
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
        sceneChanges = []
        outputURL = nil
        progress = 0
        statusMessage = ""
    }
    
    private func detectSceneChanges() async {
        guard let videoURL = viewModel.videoURL else { return }
        
        await MainActor.run {
            isProcessing = true
            progress = 0
            statusMessage = "正在分析视频..."
        }
        
        do {
            let outputDir = viewModel.outputDirectory ?? videoURL.deletingLastPathComponent()
            let videoName = videoURL.deletingPathExtension().lastPathComponent
            
            // 使用 SceneChangeDetector 检测场景变更
            let changes = try await SceneChangeDetector.detectSceneChanges(
                from: videoURL,
                threshold: threshold,
                extractThumbnails: false,
                progressHandler: { prog, status in
                    Task { @MainActor in
                        progress = prog
                        statusMessage = status
                    }
                }
            )
            
            // 转换为 SceneChange 对象
            let sceneChangeList = changes.enumerated().map { index, change in
                SceneChange(
                    time: change.timestamp,
                    frame: change.frameNumber,
                    score: change.changeIntensity
                )
            }
            
            await MainActor.run {
                sceneChanges = sceneChangeList
                statusMessage = "检测完成！"
                progress = 1.0
            }
            
            // 保存结果到文件
            let resultFilename = "\(videoName)_scene_changes.txt"
            let resultURL = outputDir.appendingPathComponent(resultFilename)
            
            var resultText = "视频场景变更检测结果\n"
            resultText += "视频: \(videoURL.lastPathComponent)\n"
            resultText += "检测时间: \(Date())\n"
            resultText += "检测灵敏度: \(String(format: "%.2f", threshold))\n"
            resultText += "最小场景时长: \(String(format: "%.1f", minSceneDuration)) 秒\n"
            resultText += "检测到 \(sceneChangeList.count) 个场景变更点\n\n"
            resultText += "时间\t\t帧号\t相似度\n"
            resultText += String(repeating: "-", count: 50) + "\n"
            
            for change in sceneChangeList {
                resultText += "\(formatTime(change.time))\t\(change.frame)\t\(String(format: "%.2f", change.score))\n"
            }
            
            try resultText.write(to: resultURL, atomically: true, encoding: .utf8)
            
            await MainActor.run {
                outputURL = resultURL
            }
            
            // 在 Finder 中显示
            NSWorkspace.shared.selectFile(resultURL.path, inFileViewerRootedAtPath: outputDir.path)
            
        } catch {
            await MainActor.run {
                statusMessage = "检测失败: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isProcessing = false
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
        } else {
            return String(format: "%02d:%02d.%03d", minutes, secs, millis)
        }
    }
}

#Preview {
    VideoSceneDetectionView(viewModel: VideoProcessorViewModel())
}

