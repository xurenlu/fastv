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
                    VStack(spacing: 16) {
                        VideoPreviewView(
                            videoURL: videoURL,
                            onVideoDropped: { urls in
                                if let url = urls.first {
                                    viewModel.loadVideo(url)
                                }
                            },
                            seekToTime: $seekToTime
                        )
                        
                        // 实时显示检测到的关键帧缩略图
                        if viewModel.isAnalyzing || !viewModel.sceneChangePoints.isEmpty {
                            KeyFramesGridView(
                                changePoints: viewModel.sceneChangePoints,
                                isAnalyzing: viewModel.isAnalyzing,
                                onSeekToTime: { time in
                                    seekToTime = time
                                }
                            )
                        }
                    }
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
                                // 智能两阶段检测开关
                                Toggle("智能两阶段检测（推荐）", isOn: $viewModel.useSmartTwoStage)
                                
                                if viewModel.useSmartTwoStage {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "sparkles")
                                                .foregroundStyle(.blue)
                                            Text("自动两阶段检测")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                        }
                                        
                                        Text("• 第一阶段：每3.9秒快速扫描，找到候选关键节点")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("• 第二阶段：在每个候选节点前后（前15秒到后10秒）每1.1秒精细检测，精确定位关键帧")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                
                                Divider()
                                
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
                                
                                // 手动间隔设置（仅在关闭智能两阶段检测时显示）
                                if !viewModel.useSmartTwoStage {
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
                                            VStack(alignment: .leading, spacing: 12) {
                                                // 预设值快速选择
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text("快速选择:")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                    
                                                    HStack(spacing: 8) {
                                                    PresetButton(
                                                        title: "0.1秒",
                                                        value: 0.1,
                                                        currentValue: viewModel.timeInterval,
                                                        action: { viewModel.timeInterval = 0.1 }
                                                    )
                                                    
                                                    PresetButton(
                                                        title: "0.5秒",
                                                        value: 0.5,
                                                        currentValue: viewModel.timeInterval,
                                                        action: { viewModel.timeInterval = 0.5 }
                                                    )
                                                    
                                                    PresetButton(
                                                        title: "1秒",
                                                        value: 1.0,
                                                        currentValue: viewModel.timeInterval,
                                                        action: { viewModel.timeInterval = 1.0 }
                                                    )
                                                    
                                                    PresetButton(
                                                        title: "5秒",
                                                        value: 5.0,
                                                        currentValue: viewModel.timeInterval,
                                                        action: { viewModel.timeInterval = 5.0 }
                                                    )
                                                    
                                                    PresetButton(
                                                        title: "10秒",
                                                        value: 10.0,
                                                        currentValue: viewModel.timeInterval,
                                                        action: { viewModel.timeInterval = 10.0 }
                                                    )
                                                    }
                                                }
                                            
                                                VStack(alignment: .leading, spacing: 8) {
                                                HStack {
                                                    Text("时间间隔")
                                                        .foregroundStyle(.secondary)
                                                    Spacer()
                                                    Text(String(format: "%.2f秒", viewModel.timeInterval))
                                                        .monospacedDigit()
                                                }
                                                
                                                Slider(value: $viewModel.timeInterval, in: 0.05...10.0, step: 0.05) {
                                                    Text("时间间隔")
                                                } minimumValueLabel: {
                                                    Text("0.05s")
                                                        .font(.caption)
                                                } maximumValueLabel: {
                                                    Text("10s")
                                                        .font(.caption)
                                                }
                                            }
                                            
                                            Text("间隔越小，分析越精细但速度越慢。建议：快速预览用5-10秒，精细分析用0.1-1秒")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            }
                                        } else {
                                            VStack(alignment: .leading, spacing: 12) {
                                                // 预设值快速选择
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text("快速选择:")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                    
                                                    HStack(spacing: 8) {
                                                    PresetButton(
                                                        title: "10帧",
                                                        value: 10,
                                                        currentValue: Double(viewModel.frameSkip),
                                                        action: { viewModel.frameSkip = 10 }
                                                    )
                                                    
                                                    PresetButton(
                                                        title: "30帧",
                                                        value: 30,
                                                        currentValue: Double(viewModel.frameSkip),
                                                        action: { viewModel.frameSkip = 30 }
                                                    )
                                                    
                                                    PresetButton(
                                                        title: "50帧",
                                                        value: 50,
                                                        currentValue: Double(viewModel.frameSkip),
                                                        action: { viewModel.frameSkip = 50 }
                                                    )
                                                    
                                                    PresetButton(
                                                        title: "100帧",
                                                        value: 100,
                                                        currentValue: Double(viewModel.frameSkip),
                                                        action: { viewModel.frameSkip = 100 }
                                                    )
                                                    
                                                    PresetButton(
                                                        title: "200帧",
                                                        value: 200,
                                                        currentValue: Double(viewModel.frameSkip),
                                                        action: { viewModel.frameSkip = 200 }
                                                    )
                                                    }
                                                }
                                            
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
                                                ), in: 1...200, step: 1) {
                                                    Text("跳帧数")
                                                } minimumValueLabel: {
                                                    Text("1")
                                                        .font(.caption)
                                                } maximumValueLabel: {
                                                    Text("200")
                                                        .font(.caption)
                                                }
                                            }
                                            
                                            Text("数值越大，分析越快但可能遗漏变化。建议：快速预览用100-200帧，精细分析用10-50帧")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            } header: {
                                Text("传统方法参数")
                            } footer: {
                                if viewModel.useSmartTwoStage {
                                    Text("智能两阶段检测会自动优化检测精度和速度，无需手动设置间隔")
                                        .font(.caption)
                                } else {
                                    Text("关闭智能检测后，可手动设置分析间隔")
                                        .font(.caption)
                                }
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

// MARK: - 预设值按钮组件

struct PresetButton: View {
    let title: String
    let value: Double
    let currentValue: Double
    let action: () -> Void
    
    private var isSelected: Bool {
        abs(currentValue - value) < 0.01  // 允许小的浮点数误差
    }
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .buttonBorderShape(.roundedRectangle)
        .foregroundStyle(isSelected ? .white : .primary)
        .background(isSelected ? Color.accentColor : Color.clear)
    }
}

// MARK: - 关键帧网格视图

struct KeyFramesGridView: View {
    let changePoints: [SceneChangePoint]
    let isAnalyzing: Bool
    let onSeekToTime: (TimeInterval) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("检测到的关键帧", systemImage: "photo.on.rectangle")
                    .font(.headline)
                
                Spacer()
                
                if isAnalyzing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("分析中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("共 \(changePoints.count) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if changePoints.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text("暂未检测到关键帧")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(height: 120)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(spacing: 12) {
                        ForEach(changePoints) { point in
                            KeyFrameThumbnailView(
                                point: point,
                                onTap: {
                                    onSeekToTime(point.timestamp)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 140)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        }
    }
}

// MARK: - 关键帧缩略图视图

struct KeyFrameThumbnailView: View {
    let point: SceneChangePoint
    let onTap: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // 缩略图
                Group {
                    if let thumbnailImage = point.thumbnailImage {
                        Image(nsImage: thumbnailImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Color.secondary.opacity(0.2)
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                    }
                }
                .frame(width: 120, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isHovered ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isHovered ? 2 : 1)
                }
                .shadow(color: .black.opacity(isHovered ? 0.2 : 0.1), radius: isHovered ? 4 : 2)
                
                // 时间戳和差异度
                VStack(spacing: 2) {
                    Text(point.timeString)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    Text(String(format: "%.0f%%", point.changeIntensity * 100))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .help("点击跳转到 \(point.timeString)")
    }
}

#Preview {
    VideoSceneAnalysisView()
}

