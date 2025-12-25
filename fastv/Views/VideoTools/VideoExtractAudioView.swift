//
//  VideoExtractAudioView.swift
//  fastv
//
//  Created by rocky on 2025/12/25.
//

import SwiftUI
import UniformTypeIdentifiers

/// 提取音频视图
struct VideoExtractAudioView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @ObservedObject var preferences = UserPreferences.shared
    @State private var isProcessing = false
    @State private var progress: Double = 0
    @State private var statusMessage = ""
    @State private var outputURL: URL?
    @State private var showVideoSelector = false
    
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
                            Text("该视频包含音频轨道")
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
                            Text("该视频没有音频轨道")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                // 提取选项
                Form {
                    Section {
                        HStack {
                            Text("音频格式")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $preferences.audioFormat) {
                                ForEach(AudioFormat.allCases, id: \.self) { format in
                                    Text(format.displayName).tag(format)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }
                        
                        Text("选择输出的音频文件格式")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                
                // 提取结果
                if let outputURL = outputURL {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("提取结果")
                            .font(.headline)
                        
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("音频已提取")
                                    .font(.subheadline)
                                Text(outputURL.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(action: {
                                NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: outputURL.deletingLastPathComponent().path)
                            }) {
                                Label("在 Finder 中显示", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                
                // 处理按钮
                Button(action: {
                    Task {
                        await extractAudio()
                    }
                }) {
                    HStack(spacing: 8) {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "waveform")
                        }
                        Text(isProcessing ? "提取中..." : "开始提取")
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isProcessing || viewModel.videoInfo?.hasAudio != true)
                
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
        .navigationTitle("提取音频")
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
                resetState()
            }
        case .failure(let error):
            print("选择视频失败: \(error.localizedDescription)")
        }
    }
    
    private func resetState() {
        outputURL = nil
        progress = 0
        statusMessage = ""
    }
    
    private func extractAudio() async {
        guard let videoURL = viewModel.videoURL else { return }
        guard viewModel.videoInfo?.hasAudio == true else { return }
        
        isProcessing = true
        progress = 0
        statusMessage = "正在提取音频..."
        
        do {
            let outputDir = viewModel.outputDirectory ?? videoURL.deletingLastPathComponent()
            let videoName = videoURL.deletingPathExtension().lastPathComponent
            let audioExtension = preferences.audioFormat.fileExtension
            let audioFilename = "\(videoName).\(audioExtension)"
            let audioURL = outputDir.appendingPathComponent(audioFilename)
            
            // 使用 AudioExtractor 提取音频
            try await AudioExtractor.extractAudio(
                from: videoURL,
                to: audioURL,
                format: preferences.audioFormat,
                progressHandler: { prog in
                    Task { @MainActor in
                        progress = prog
                        statusMessage = "正在提取音频... \(Int(prog * 100))%"
                    }
                }
            )
            
            await MainActor.run {
                outputURL = audioURL
                statusMessage = "提取完成！"
                progress = 1.0
            }
            
            // 在 Finder 中显示
            NSWorkspace.shared.selectFile(audioURL.path, inFileViewerRootedAtPath: outputDir.path)
            
        } catch {
            await MainActor.run {
                statusMessage = "提取失败: \(error.localizedDescription)"
            }
        }
        
        isProcessing = false
    }
}

#Preview {
    VideoExtractAudioView(viewModel: VideoProcessorViewModel())
}

