//
//  VideoCompressionView.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoCompressionView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @State private var selectedResolution: VideoResolution = .fhd1080p
    @State private var targetFrameRate: Int? = nil
    @State private var useCRF = true
    @State private var crfValue: Int = 23
    @State private var bitrate: String = ""
    @State private var isProcessing = false
    @State private var progress: Double = 0.0
    @State private var status: String = ""
    
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
                        Picker("目标分辨率", selection: $selectedResolution) {
                            ForEach(VideoResolution.allCases, id: \.self) { resolution in
                                Text(resolution.displayName).tag(resolution)
                            }
                        }
                        
                        HStack {
                            Text("目标帧率")
                            Spacer()
                            TextField("保持原帧率", value: $targetFrameRate, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Text("fps")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("分辨率与帧率")
                    }
                    
                    Section {
                        Toggle("使用 CRF（推荐）", isOn: $useCRF)
                        
                        if useCRF {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("CRF 值")
                                    Spacer()
                                    Text("\(crfValue)")
                                        .monospacedDigit()
                                }
                                Slider(value: Binding(
                                    get: { Double(crfValue) },
                                    set: { crfValue = Int($0) }
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
                        } else {
                            TextField("目标比特率（如：5M）", text: $bitrate)
                                .textFieldStyle(.roundedBorder)
                        }
                    } header: {
                        Text("压缩设置")
                    }
                    
                    if isProcessing {
                        Section {
                            ProgressView(value: progress)
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } header: {
                            Text("压缩进度")
                        }
                    }
                }
                .formStyle(.grouped)
                
                Button(action: {
                    startCompression()
                }) {
                    Label("开始压缩", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.videoURL == nil || isProcessing)
            }
            .padding()
        }
        .navigationTitle("压缩调整")
    }
    
    private func startCompression() {
        guard let inputURL = viewModel.videoURL else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.movie, .mpeg4Movie]
        savePanel.nameFieldStringValue = inputURL.deletingPathExtension().lastPathComponent + "_compressed"
        
        if savePanel.runModal() == .OK, let outputURL = savePanel.url {
            isProcessing = true
            progress = 0.0
            status = "准备压缩..."
            
            Task {
                do {
                    try await VideoCompressor.compress(
                        inputURL: inputURL,
                        outputURL: outputURL,
                        resolution: selectedResolution,
                        frameRate: targetFrameRate,
                        bitrate: bitrate.isEmpty ? nil : bitrate,
                        crf: useCRF ? crfValue : nil,
                        progressHandler: { prog, stat in
                            Task { @MainActor in
                                progress = prog
                                status = stat
                            }
                        }
                    )
                    
                    await MainActor.run {
                        isProcessing = false
                        status = "压缩完成！"
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        status = "压缩失败: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
