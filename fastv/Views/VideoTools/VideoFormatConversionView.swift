//
//  VideoFormatConversionView.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct VideoFormatConversionView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @State private var selectedFormat: VideoFormat = .mp4
    @State private var selectedCodec: VideoCodec = .h264
    @State private var isProcessing = false
    @State private var progress: Double = 0.0
    @State private var status: String = ""
    @State private var showVideoSelector = false
    @State private var currentTask: Task<Void, Never>?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let videoURL = viewModel.videoURL {
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
                
                Form {
                    Section {
                        Picker("目标格式", selection: $selectedFormat) {
                            ForEach(VideoFormat.allCases, id: \.self) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        
                        Picker("视频编码器", selection: $selectedCodec) {
                            ForEach(VideoCodec.allCases, id: \.self) { codec in
                                Text(codec.displayName).tag(codec)
                            }
                        }
                    } header: {
                        Text("转换设置")
                    }
                    
                    if isProcessing {
                        Section {
                            ProgressView(value: progress)
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } header: {
                            Text("转换进度")
                        }
                    }
                }
                .formStyle(.grouped)
                
                HStack(spacing: 12) {
                    Button(action: {
                        startConversion()
                    }) {
                        Label("开始转换", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.videoURL == nil || isProcessing)
                    
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
            }
            .padding()
        }
        .navigationTitle("格式转换")
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
        status = "操作已取消"
    }
    
    private func handleVideoSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                viewModel.loadVideo(url)
                // 格式和编码器保持用户选择，不重置
                isProcessing = false
                progress = 0.0
                status = ""
            }
        case .failure(let error):
            print("选择视频失败: \(error.localizedDescription)")
        }
    }
    
    private func startConversion() {
        guard let inputURL = viewModel.videoURL else { return }
        
        let savePanel = NSSavePanel()
        // 根据格式设置允许的文件类型
        switch selectedFormat {
        case .mp4:
            savePanel.allowedContentTypes = [.mpeg4Movie]
        case .mov:
            savePanel.allowedContentTypes = [.quickTimeMovie]
        case .avi, .mkv, .webm:
            // 这些格式没有系统定义的 UTType，允许所有视频类型
            savePanel.allowedContentTypes = [.movie]
        }
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        savePanel.nameFieldStringValue = "\(baseName)_converted.\(selectedFormat.rawValue)"
        
        if savePanel.runModal() == .OK, let outputURL = savePanel.url {
            isProcessing = true
            progress = 0.0
            status = "准备转换..."
            
            // 捕获当前参数值
            let currentFormat = selectedFormat
            let currentCodec = selectedCodec
            
            currentTask = Task {
                do {
                    // 在后台线程执行转换
                    try await Task.detached(priority: .userInitiated) {
                        try await VideoConverter.convert(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            format: currentFormat,
                            codec: currentCodec,
                            progressHandler: { prog, stat in
                                Task { @MainActor in
                                    progress = prog
                                    status = stat
                                }
                            }
                        )
                    }.value
                    
                    await MainActor.run {
                        isProcessing = false
                        status = "转换完成！"
                        // 在 Finder 中显示
                        NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: outputURL.deletingLastPathComponent().path)
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        status = "转换失败: \(error.localizedDescription)"
                        print("❌ [VideoFormatConversionView] 转换失败: \(error)")
                    }
                }
            }
        }
    }
}
