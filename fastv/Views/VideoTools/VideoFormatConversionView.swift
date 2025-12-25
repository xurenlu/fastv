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
                
                Button(action: {
                    startConversion()
                }) {
                    Label("开始转换", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.videoURL == nil || isProcessing)
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
        case .avi:
            savePanel.allowedContentTypes = []
        case .mkv:
            savePanel.allowedContentTypes = []
        case .webm:
            savePanel.allowedContentTypes = []
        }
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        savePanel.nameFieldStringValue = "\(baseName)_converted.\(selectedFormat.rawValue)"
        
        if savePanel.runModal() == .OK, let outputURL = savePanel.url {
            isProcessing = true
            progress = 0.0
            status = "准备转换..."
            
            Task {
                do {
                    try await VideoConverter.convert(
                        inputURL: inputURL,
                        outputURL: outputURL,
                        format: selectedFormat,
                        codec: selectedCodec,
                        progressHandler: { prog, stat in
                            Task { @MainActor in
                                progress = prog
                                status = stat
                            }
                        }
                    )
                    
                    await MainActor.run {
                        isProcessing = false
                        status = "转换完成！"
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        status = "转换失败: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
