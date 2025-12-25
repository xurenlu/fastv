//
//  VideoSubtitleView.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct VideoSubtitleView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @State private var subtitleURL: URL?
    @State private var style = SubtitleStyle()
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
                        HStack {
                            Text("字幕文件")
                            Spacer()
                            if let url = subtitleURL {
                                Text(url.lastPathComponent)
                                    .foregroundStyle(.secondary)
                                Button("更改") {
                                    selectSubtitleFile()
                                }
                            } else {
                                Button("选择字幕文件") {
                                    selectSubtitleFile()
                                }
                            }
                        }
                        
                        HStack {
                            Text("字体大小")
                            Spacer()
                            TextField("", value: $style.fontSize, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        
                        HStack {
                            Text("位置")
                            Spacer()
                            Picker("", selection: $style.alignment) {
                                Text("底部居中").tag(2)
                                Text("底部左对齐").tag(1)
                                Text("底部右对齐").tag(3)
                            }
                        }
                    } header: {
                        Text("字幕设置")
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
                    startSubtitle()
                }) {
                    Label("烧录字幕", systemImage: "text.bubble")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.videoURL == nil || subtitleURL == nil || isProcessing)
            }
            .padding()
        }
        .navigationTitle("字幕处理")
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
                // 字幕文件和样式保持用户选择，不重置
                isProcessing = false
                progress = 0.0
                status = ""
            }
        case .failure(let error):
            print("选择视频失败: \(error.localizedDescription)")
        }
    }
    
    private func selectSubtitleFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            subtitleURL = url
        }
    }
    
    private func startSubtitle() {
        guard let inputURL = viewModel.videoURL,
              let subtitleURL = subtitleURL else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.movie, .mpeg4Movie]
        savePanel.nameFieldStringValue = inputURL.deletingPathExtension().lastPathComponent + "_subtitled"
        
        if savePanel.runModal() == .OK, let outputURL = savePanel.url {
            isProcessing = true
            progress = 0.0
            status = "准备烧录字幕..."
            
            Task {
                do {
                    if subtitleURL.pathExtension.lowercased() == "srt" {
                        try await VideoSubtitle.burnSRTSubtitle(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            subtitleURL: subtitleURL,
                            style: style,
                            progressHandler: { prog, stat in
                                Task { @MainActor in
                                    progress = prog
                                    status = stat
                                }
                            }
                        )
                    } else if subtitleURL.pathExtension.lowercased() == "ass" {
                        try await VideoSubtitle.burnASSSubtitle(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            subtitleURL: subtitleURL,
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
                        status = "字幕烧录完成！"
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        status = "烧录失败: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
