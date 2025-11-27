//
//  VideoSceneAnalysisView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoSceneAnalysisView: View {
    @StateObject private var viewModel = VideoSceneAnalysisViewModel()
    @State private var seekToTime: TimeInterval?
    @State private var isVideoInfoExpanded = false
    @State private var isAnalysisParamsExpanded = false
    @State private var showOnlineVideoInput = false
    @State private var videoURLString = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // 主内容区域
            Group {
                if viewModel.videoURL == nil {
                    // 未选择视频：显示拖拽区域
                    dropZoneView
                } else {
                    // 已选择视频：显示分析界面
                    analysisView
                }
            }
        }
        .navigationTitle("视频场景分析")
    }
    
    private var dropZoneView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "video.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 6) {
                Text("拖拽视频文件到这里")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text("支持 MP4、MOV、AVI、MKV、FLV 等格式")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Button(action: {
                viewModel.selectVideoFile()
            }) {
                Label("选择视频文件", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: .constant(false)) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private var analysisView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 视频预览
                if let videoURL = viewModel.videoURL {
                    VideoPreviewView(
                        videoURL: videoURL,
                        onVideoDropped: { urls in
                            if let url = urls.first {
                                viewModel.loadVideo(url)
                            }
                        },
                        seekToTime: $seekToTime
                    )
                }
                
                // 视频信息（可折叠，默认收起）
                if let videoInfo = viewModel.videoInfo {
                    DisclosureGroup(isExpanded: $isVideoInfoExpanded) {
                        VideoInfoCard(videoInfo: videoInfo)
                            .padding(.top, 8)
                    } label: {
                        Label("视频信息", systemImage: "info.circle")
                            .font(.headline)
                    }
                }
                
                // 分析参数设置（可折叠，默认收起）
                DisclosureGroup(isExpanded: $isAnalysisParamsExpanded) {
                    Form {
                        Section {
                            // 分析模式选择
                            Picker("分析模式", selection: $viewModel.analysisMode) {
                                ForEach(VideoSceneAnalysisViewModel.AnalysisMode.allCases, id: \.self) { mode in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.rawValue)
                                        Text(mode.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                        } header: {
                            Text("分析模式")
                        } footer: {
                            Text(viewModel.analysisMode.description)
                                .font(.caption)
                        }
                        
                        // 传统方法参数
                        if viewModel.analysisMode == .traditional || viewModel.analysisMode == .hybrid {
                            Section {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("变更阈值")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(String(format: "%.1f%%", viewModel.threshold * 100))
                                            .foregroundStyle(.primary)
                                            .monospacedDigit()
                                    }
                                    
                                    Slider(value: $viewModel.threshold, in: 0.1...0.8, step: 0.05) {
                                        Text("阈值")
                                    } minimumValueLabel: {
                                        Text("10%")
                                            .font(.caption)
                                    } maximumValueLabel: {
                                        Text("80%")
                                            .font(.caption)
                                    }
                                    
                                    Text("阈值越低，检测越敏感，会检测到更多变更点")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Divider()
                                
                                // 分析间隔设置
                                VStack(alignment: .leading, spacing: 12) {
                                    Picker("分析间隔方式", selection: $viewModel.intervalMode) {
                                        ForEach(VideoSceneAnalysisViewModel.AnalysisIntervalMode.allCases, id: \.self) { mode in
                                            Text(mode.rawValue).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    
                                    if viewModel.intervalMode == .timeBased {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text("时间间隔")
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                                Text(String(format: "%.2f秒", viewModel.timeInterval))
                                                    .monospacedDigit()
                                            }
                                            
                                            Slider(value: $viewModel.timeInterval, in: 0.05...1.0, step: 0.05) {
                                                Text("时间间隔")
                                            } minimumValueLabel: {
                                                Text("0.05s")
                                                    .font(.caption)
                                            } maximumValueLabel: {
                                                Text("1.0s")
                                                    .font(.caption)
                                            }
                                            
                                            Text("间隔越小，分析越精细但速度越慢")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } else {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text("跳帧数")
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                                Text("每\(viewModel.frameSkip)帧分析一次")
                                                    .monospacedDigit()
                                            }
                                            
                                            Slider(value: Binding(
                                                get: { Double(viewModel.frameSkip) },
                                                set: { viewModel.frameSkip = Int($0) }
                                            ), in: 1...30, step: 1) {
                                                Text("跳帧数")
                                            } minimumValueLabel: {
                                                Text("1")
                                                    .font(.caption)
                                            } maximumValueLabel: {
                                                Text("30")
                                                    .font(.caption)
                                            }
                                            
                                            Text("数值越大，分析越快但可能遗漏变化")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            } header: {
                                Text("传统方法参数")
                            }
                        }
                        
                        // AI 分析参数
                        if viewModel.analysisMode == .aiPowered || viewModel.analysisMode == .hybrid {
                            Section {
                                TextField("视觉模型", text: $viewModel.visionModel)
                                TextField("文本模型", text: $viewModel.textModel)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("帧分析间隔")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(String(format: "%.1f秒", viewModel.frameInterval))
                                            .monospacedDigit()
                                    }
                                    
                                    Slider(value: $viewModel.frameInterval, in: 1.0...5.0, step: 0.5)
                                    
                                    HStack {
                                        Text("音频分段时长")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(String(format: "%.1f秒", viewModel.audioSegmentDuration))
                                            .monospacedDigit()
                                    }
                                    
                                    Slider(value: $viewModel.audioSegmentDuration, in: 3.0...10.0, step: 0.5)
                                }
                            } header: {
                                Text("AI 分析参数")
                            } footer: {
                                Text("AI 分析需要先在设置中配置 Ollama API 端点")
                                    .font(.caption)
                            }
                        }
                        
                        Section {
                            Toggle("提取关键点截图", isOn: $viewModel.extractThumbnails)
                        }
                    }
                    .formStyle(.grouped)
                    .padding(.top, 8)
                } label: {
                    Label("分析参数", systemImage: "slider.horizontal.3")
                        .font(.headline)
                }
                
                // 操作栏
                HStack(spacing: 12) {
                    // 清除当前视频按钮
                    if viewModel.videoURL != nil {
                        Button(action: {
                            viewModel.clearCurrentVideo()
                        }) {
                            Label("清除", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .help("清除当前视频信息")
                    }
                    
                    // 在线视频下载按钮
                    Button(action: {
                        withAnimation {
                            showOnlineVideoInput.toggle()
                        }
                    }) {
                        Label("下载在线视频", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .help("从抖音、YouTube等网站下载视频")
                    
                    Button(action: {
                        viewModel.selectVideoFile()
                    }) {
                        Label("选择文件", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button(action: {
                        Task {
                            await viewModel.startAnalysis()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if viewModel.isAnalyzing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(viewModel.isAnalyzing ? "分析中..." : "开始分析")
                        }
                        .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isAnalyzing)
                    .keyboardShortcut(.return, modifiers: [])
                    
                    if !viewModel.sceneChangePoints.isEmpty {
                        Button(action: {
                            Task {
                                await viewModel.exportKeyFrames()
                            }
                        }) {
                            Label("导出关键帧", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isAnalyzing)
                        
                        Button(action: {
                            viewModel.reset()
                        }) {
                            Label("重置", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // 在线视频输入框
                if showOnlineVideoInput {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("输入视频URL（支持抖音、YouTube、快手等）", text: $videoURLString)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    if !videoURLString.isEmpty {
                                        Task {
                                            await viewModel.downloadAndLoadVideo(from: videoURLString)
                                            if viewModel.videoInfo != nil {
                                                videoURLString = ""
                                                showOnlineVideoInput = false
                                            }
                                        }
                                    }
                                }
                            
                            Button(action: {
                                Task {
                                    await viewModel.downloadAndLoadVideo(from: videoURLString)
                                    if viewModel.videoInfo != nil {
                                        videoURLString = ""
                                        showOnlineVideoInput = false
                                    }
                                }
                            }) {
                                if viewModel.isAnalyzing && viewModel.analysisStatus.contains("下载") {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("下载")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(videoURLString.isEmpty || viewModel.isAnalyzing)
                            
                            Button(action: {
                                withAnimation {
                                    showOnlineVideoInput = false
                                    videoURLString = ""
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Text("支持抖音、快手、YouTube、B站等主流视频平台")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.05))
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // 分析进度
                if viewModel.isAnalyzing {
                    ProcessingProgressView(
                        progress: viewModel.progress,
                        status: viewModel.analysisStatus
                    )
                }
                
                // 分析完成但未找到场景变化点的提示
                if !viewModel.isAnalyzing && !viewModel.analysisStatus.isEmpty && viewModel.sceneChangePoints.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary.opacity(0.6))
                        
                        Text("分析完成")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Text("未检测到明显的场景变化点")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        if viewModel.analysisMode == .traditional || viewModel.analysisMode == .hybrid {
                            Text("建议：尝试降低变更阈值（当前 \(String(format: "%.0f%%", viewModel.threshold * 100))）以获得更多检测结果")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .padding(.horizontal, 20)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.05))
                    }
                }
                
                // 分析结果：时间轴视图
                if !viewModel.sceneChangePoints.isEmpty, let videoInfo = viewModel.videoInfo {
                    VideoTimelineView(
                        duration: videoInfo.duration,
                        changePoints: viewModel.sceneChangePoints,
                        onSeekToTime: { time in
                            seekToTime = time
                        }
                    )
                }
            }
            .padding(20)
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                urls.append(url)
            }
        }
        
        group.notify(queue: .main) {
            if let url = urls.first {
                viewModel.loadVideo(url)
            }
        }
        
        return true
    }
}

#Preview {
    VideoSceneAnalysisView()
}

