//
//  VideoColorAdjustmentView.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoColorAdjustmentView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @State private var adjustment = ColorAdjustment()
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
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("亮度")
                                Spacer()
                                Text(String(format: "%.2f", adjustment.brightness))
                                    .monospacedDigit()
                            }
                            Slider(value: $adjustment.brightness, in: -1.0...1.0, step: 0.1)
                            
                            HStack {
                                Text("对比度")
                                Spacer()
                                Text(String(format: "%.2f", adjustment.contrast))
                                    .monospacedDigit()
                            }
                            Slider(value: $adjustment.contrast, in: 0.0...3.0, step: 0.1)
                            
                            HStack {
                                Text("饱和度")
                                Spacer()
                                Text(String(format: "%.2f", adjustment.saturation))
                                    .monospacedDigit()
                            }
                            Slider(value: $adjustment.saturation, in: 0.0...3.0, step: 0.1)
                            
                            HStack {
                                Text("色温")
                                Spacer()
                                Text(adjustment.temperature != nil ? "\(Int(adjustment.temperature!))K" : "自动")
                                    .monospacedDigit()
                            }
                            HStack {
                                Slider(value: Binding(
                                    get: { adjustment.temperature ?? 6500 },
                                    set: { adjustment.temperature = $0 }
                                ), in: 3000...10000, step: 100)
                                Button("重置") {
                                    adjustment.temperature = nil
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    } header: {
                        Text("颜色调整")
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
                    startAdjustment()
                }) {
                    Label("应用调整", systemImage: "paintpalette.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.videoURL == nil || isProcessing)
            }
            .padding()
        }
        .navigationTitle("颜色调整")
    }
    
    private func startAdjustment() {
        guard let inputURL = viewModel.videoURL else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.movie, .mpeg4Movie]
        savePanel.nameFieldStringValue = inputURL.deletingPathExtension().lastPathComponent + "_adjusted"
        
        if savePanel.runModal() == .OK, let outputURL = savePanel.url {
            isProcessing = true
            progress = 0.0
            status = "准备处理..."
            
            Task {
                do {
                    try await VideoColorAdjuster.adjust(
                        inputURL: inputURL,
                        outputURL: outputURL,
                        adjustment: adjustment,
                        progressHandler: { prog, stat in
                            Task { @MainActor in
                                progress = prog
                                status = stat
                            }
                        }
                    )
                    
                    await MainActor.run {
                        isProcessing = false
                        status = "处理完成！"
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        status = "处理失败: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
