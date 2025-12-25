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
    
    // 智能向导相关状态
    @State private var useSmartWizard = false
    @State private var targetFileSize: Double = 500
    @State private var fileSizeUnit: FileSizeUnit = .mb
    @State private var recommendation: CompressionRecommendation?
    @State private var videoInfo: VideoInfo?
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
                        Toggle("使用智能向导", isOn: $useSmartWizard)
                            .onChange(of: useSmartWizard) { newValue in
                                if newValue {
                                    loadVideoInfoAndCalculate()
                                }
                            }
                    } header: {
                        Text("压缩模式")
                    } footer: {
                        Text("智能向导可根据目标文件大小自动推荐最佳参数")
                    }
                    
                    if useSmartWizard {
                        Section {
                            HStack {
                                TextField("目标文件大小", value: $targetFileSize, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                    .onChange(of: targetFileSize) { _ in
                                        calculateRecommendation()
                                    }
                                
                                Picker("", selection: $fileSizeUnit) {
                                    ForEach(FileSizeUnit.allCases, id: \.self) { unit in
                                        Text(unit.rawValue).tag(unit)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 100)
                                .onChange(of: fileSizeUnit) { _ in
                                    calculateRecommendation()
                                }
                            }
                        } header: {
                            Text("目标文件大小")
                        }
                        
                        if let rec = recommendation {
                            Section {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("推荐分辨率")
                                        Spacer()
                                        Text(rec.recommendedResolution.displayName)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    HStack {
                                        Text("推荐帧率")
                                        Spacer()
                                        if let fps = rec.recommendedFrameRate {
                                            Text("\(fps) fps")
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("保持原帧率")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    HStack {
                                        Text("推荐码率")
                                        Spacer()
                                        Text(rec.bitrateString)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Divider()
                                    
                                    HStack {
                                        Text("预估压缩比")
                                        Spacer()
                                        Text(rec.compressionRatioString)
                                            .foregroundStyle(.blue)
                                    }
                                    
                                    HStack {
                                        Text("画质评级")
                                        Spacer()
                                        HStack(spacing: 4) {
                                            Text(rec.qualityRating.stars)
                                                .foregroundStyle(.orange)
                                            Text("(\(rec.qualityRating.rawValue))")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            } header: {
                                Text("📊 智能推荐参数")
                            }
                            
                            // 应用推荐参数按钮
                            Section {
                                Button(action: {
                                    applyRecommendation(rec)
                                }) {
                                    Label("应用推荐参数", systemImage: "checkmark.circle")
                                }
                            }
                        }
                    }
                    
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
                        Text(useSmartWizard ? "⚙️ 手动调整（可选）" : "分辨率与帧率")
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
                // 压缩参数保持用户选择，但重置智能向导相关状态
                videoInfo = nil
                recommendation = nil
                isProcessing = false
                progress = 0.0
                status = ""
                if useSmartWizard {
                    loadVideoInfoAndCalculate()
                }
            }
        case .failure(let error):
            print("选择视频失败: \(error.localizedDescription)")
        }
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
    
    // MARK: - 智能向导相关方法
    
    private func loadVideoInfoAndCalculate() {
        guard let videoURL = viewModel.videoURL else { return }
        
        Task {
            do {
                let info = try await VideoInfoService.getVideoInfo(from: videoURL)
                await MainActor.run {
                    self.videoInfo = info
                    calculateRecommendation()
                }
            } catch {
                print("获取视频信息失败: \(error)")
            }
        }
    }
    
    private func calculateRecommendation() {
        guard let info = videoInfo else { return }
        
        let targetSizeBytes = Int64(targetFileSize * Double(fileSizeUnit.bytesMultiplier))
        let rec = VideoCompressionCalculator.calculateRecommendation(
            targetFileSize: targetSizeBytes,
            videoInfo: info
        )
        
        recommendation = rec
    }
    
    private func applyRecommendation(_ rec: CompressionRecommendation) {
        selectedResolution = rec.recommendedResolution
        targetFrameRate = rec.recommendedFrameRate
        
        if let crf = rec.recommendedCRF {
            useCRF = true
            crfValue = crf
        } else {
            useCRF = false
            bitrate = rec.bitrateString.replacingOccurrences(of: " Mbps", with: "M")
        }
    }
}
