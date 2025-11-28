//
//  ContentView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import UniformTypeIdentifiers

/// 侧边栏选项
enum SidebarItem: String, Identifiable, CaseIterable {
    case voiceInput = "语音输入"
    case meetingRecord = "会议记录"
    case videoProcessing = "视频处理"
    case videoSceneAnalysis = "视频场景分析"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .voiceInput:
            return "mic.fill"
        case .meetingRecord:
            return "calendar.badge.clock"
        case .videoProcessing:
            return "video.fill"
        case .videoSceneAnalysis:
            return "waveform.path"
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = VideoProcessorViewModel()
    @State private var showSettings = false
    @State private var showWelcome = false
    @State private var selectedSidebarItem: SidebarItem = .voiceInput
    @ObservedObject private var preferences = UserPreferences.shared
    
    var body: some View {
        // 检查是否完成引导流程
        if !preferences.hasCompletedOnboarding {
            OnboardingView()
        } else {
            NavigationSplitView {
                // 左侧侧边栏
                List(selection: $selectedSidebarItem) {
                    ForEach(SidebarItem.allCases) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .tag(item)
                    }
                }
                .navigationTitle("功能")
                .frame(minWidth: 180)
            } detail: {
                // 右侧内容区域
                Group {
                    switch selectedSidebarItem {
                    case .voiceInput:
                        VoiceInputView()
                            .toolbar {
                                ToolbarItem(placement: .automatic) {
                                    Button(action: { showWelcome = true }) {
                                        Label(NSLocalizedString("help", comment: ""), systemImage: "questionmark.circle")
                                    }
                                    .help(NSLocalizedString("help", comment: ""))
                                }
                                
                                ToolbarItem(placement: .automatic) {
                                    Button(action: { showSettings = true }) {
                                        Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
                                    }
                                    .help(NSLocalizedString("settings", comment: ""))
                                }
                            }
                    case .meetingRecord:
                        MeetingRecordView()
                            .toolbar {
                                ToolbarItem(placement: .automatic) {
                                    Button(action: { showWelcome = true }) {
                                        Label(NSLocalizedString("help", comment: ""), systemImage: "questionmark.circle")
                                    }
                                    .help(NSLocalizedString("help", comment: ""))
                                }
                                
                                ToolbarItem(placement: .automatic) {
                                    Button(action: { showSettings = true }) {
                                        Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
                                    }
                                    .help(NSLocalizedString("settings", comment: ""))
                                }
                            }
                    case .videoProcessing:
                        VideoProcessingView(viewModel: viewModel)
                            .toolbar {
                                ToolbarItem(placement: .primaryAction) {
                                    Button(action: selectVideoFiles) {
                                        Label("选择文件", systemImage: "folder")
                                    }
                                    .keyboardShortcut("o", modifiers: [.command])
                                    .help("选择视频文件")
                                }
                                
                                ToolbarItem(placement: .automatic) {
                                    Button(action: { showWelcome = true }) {
                                        Label(NSLocalizedString("help", comment: ""), systemImage: "questionmark.circle")
                                    }
                                    .help(NSLocalizedString("help", comment: ""))
                                }
                                
                                ToolbarItem(placement: .automatic) {
                                    Button(action: { showSettings = true }) {
                                        Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
                                    }
                                    .help(NSLocalizedString("settings", comment: ""))
                                }
                            }
                    case .videoSceneAnalysis:
                        VideoSceneAnalysisView()
                            .toolbar {
                                ToolbarItem(placement: .automatic) {
                                    Button(action: { showWelcome = true }) {
                                        Label(NSLocalizedString("help", comment: ""), systemImage: "questionmark.circle")
                                    }
                                    .help(NSLocalizedString("help", comment: ""))
                                }
                                
                                ToolbarItem(placement: .automatic) {
                                    Button(action: { showSettings = true }) {
                                        Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
                                    }
                                    .help(NSLocalizedString("settings", comment: ""))
                                }
                            }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                }
                .sheet(isPresented: $showWelcome) {
                    WelcomeView()
                        .frame(width: 600, height: 650)
                }
                .alert("错误", isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )) {
                    Button("确定", role: .cancel) {
                        viewModel.errorMessage = nil
                    }
                } message: {
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                    }
                }
            }
            .frame(minWidth: 720, minHeight: 520)
            .onAppear {
                // 延迟显示欢迎窗口，确保界面已加载完成
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // 检查是否首次启动
                    if !UserPreferences.shared.hasShownWelcome {
                        showWelcome = true
                    }
                }
            }
        }
    }
    
    private func selectVideoFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .avi]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "选择视频文件"
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            if !urls.isEmpty {
                viewModel.loadVideos(urls)
            }
        }
    }
}

#Preview {
    ContentView()
}

// MARK: - 视频信息卡片
struct VideoInfoCard: View {
    let videoInfo: VideoInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("视频信息", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Text("时长")
                        .foregroundStyle(.secondary)
                    Text(videoInfo.durationString)
                }
                GridRow {
                    Text("分辨率")
                        .foregroundStyle(.secondary)
                    Text(videoInfo.resolutionString)
                }
                GridRow {
                    Text("帧率")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f fps", videoInfo.frameRate))
                }
                GridRow {
                    Text("文件大小")
                        .foregroundStyle(.secondary)
                    Text(videoInfo.fileSizeString)
                }
                
                if !videoInfo.audioTracks.isEmpty {
                    Divider()
                        .gridCellColumns(2)
                        .padding(.vertical, 4)
                    
                    ForEach(Array(videoInfo.audioTracks.enumerated()), id: \.offset) { index, track in
                        GridRow {
                            Text("音频轨道 \(index + 1)")
                                .foregroundStyle(.secondary)
                            Text("\(track.sampleRateString) · \(track.channelsString)")
                        }
                    }
                }
            }
            .font(.body)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}

// MARK: - 处理进度视图
struct ProcessingProgressView: View {
    let progress: Double
    let status: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(status)
                    .font(.body)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            
            ProgressView(value: progress)
                .progressViewStyle(.linear)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}

// MARK: - 结果卡片
struct ResultCard: View {
    let firstFrameImage: NSImage?
    let lastFrameImage: NSImage?
    let audioURL: URL?
    let transcriptURL: URL?
    let outputDirectory: URL?
    @State private var transcriptText: String = ""
    @State private var showFullTranscript = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("处理完成", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            
            if firstFrameImage != nil || lastFrameImage != nil {
                HStack(spacing: 16) {
                    if let firstFrameImage = firstFrameImage {
                        FrameThumbnail(image: firstFrameImage, title: "第一帧")
                    }
                    if let lastFrameImage = lastFrameImage {
                        FrameThumbnail(image: lastFrameImage, title: "最后一帧")
                    }
                }
            }
            
            if let audioURL = audioURL {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                        .imageScale(.medium)
                    Text(audioURL.lastPathComponent)
                        .font(.body)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                }
            }
            
            if let transcriptURL = transcriptURL {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(.secondary)
                            .imageScale(.medium)
                        Text("文本稿")
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            if let text = try? String(contentsOf: transcriptURL, encoding: .utf8) {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(text, forType: .string)
                            }
                        }) {
                            Label("复制", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    if !transcriptText.isEmpty {
                        ScrollView {
                            Text(transcriptText)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: showFullTranscript ? 200 : 100)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.quaternary.opacity(0.5))
                        }
                        
                        if transcriptText.count > 200 {
                            Button(action: {
                                showFullTranscript.toggle()
                            }) {
                                Text(showFullTranscript ? "收起" : "展开")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        Text("加载中...")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(.quaternary.opacity(0.5))
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                }
                .onAppear {
                    loadTranscript()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        }
    }
    
    private func loadTranscript() {
        guard let transcriptURL = transcriptURL else { return }
        Task {
            if let text = try? String(contentsOf: transcriptURL, encoding: .utf8) {
                await MainActor.run {
                    transcriptText = text
                }
            }
        }
    }
}

struct FrameThumbnail: View {
    let image: NSImage
    let title: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 200, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
