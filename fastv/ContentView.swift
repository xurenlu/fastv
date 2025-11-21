//
//  ContentView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = VideoProcessorViewModel()
    @State private var showSettings = false
    @State private var showLastVideoBanner = false
    @State private var showWelcome = false
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: 视频处理
            NavigationStack {
                VStack(spacing: 0) {
                    // 上次打开视频横幅提示
                    if showLastVideoBanner, let lastURL = viewModel.getLastVideoURL() {
                        LastVideoBannerView(
                            lastVideoURL: lastURL,
                            onOpen: {
                                viewModel.loadVideo(lastURL)
                                showLastVideoBanner = false
                            },
                            onDismiss: {
                                showLastVideoBanner = false
                            }
                        )
                    }
                    
                    // 主内容区域
                    Group {
                        if viewModel.appState.isEmpty {
                            DropZoneView(viewModel: viewModel)
                        } else if viewModel.appState.isSingleVideo {
                            processingView
                        } else {
                            // 多视频列表视图
                            if let listViewModel = viewModel.videoListViewModel {
                                VideoListView(viewModel: listViewModel)
                            } else {
                                ProgressView("加载中...")
                                    .onAppear {
                                        viewModel.initializeVideoList()
                                    }
                            }
                        }
                    }
                }
                .navigationTitle("视频处理")
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
                            Label("使用说明", systemImage: "questionmark.circle")
                        }
                        .help("查看使用说明")
                    }
                    
                    ToolbarItem(placement: .automatic) {
                        Button(action: { showSettings = true }) {
                            Label("设置", systemImage: "gearshape")
                        }
                        .help("打开设置")
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
            .tabItem {
                Label("视频处理", systemImage: "video.fill")
            }
            .tag(0)
            
            // Tab 2: 语音输入
            NavigationStack {
                VoiceInputView()
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showWelcome = true }) {
                        Label("使用说明", systemImage: "questionmark.circle")
                    }
                    .help("查看使用说明")
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: { showSettings = true }) {
                        Label("设置", systemImage: "gearshape")
                    }
                    .help("打开设置")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showWelcome) {
                WelcomeView()
                    .frame(width: 600, height: 650)
            }
            .tabItem {
                Label("语音输入", systemImage: "mic.fill")
            }
            .tag(1)
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
            
            // 检查是否有上次打开的文件，显示横幅提示
            if viewModel.getLastVideoURL() != nil {
                showLastVideoBanner = true
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
                showLastVideoBanner = false
            }
        }
    }
    
    private var processingView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 视频预览
                if let videoURL = viewModel.videoURL {
                    VideoPreviewView(
                        videoURL: videoURL,
                        onVideoDropped: { urls in
                            viewModel.loadVideos(urls)
                        }
                    )
                }
                
                // 视频信息
                if let videoInfo = viewModel.videoInfo {
                    VideoInfoCard(videoInfo: videoInfo)
                }
                
                // 操作栏
                HStack(spacing: 12) {
                    Button(action: selectVideoFiles) {
                        Label("切换文件", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button(action: {
                        Task {
                            await viewModel.startProcessing()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if viewModel.isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(viewModel.isProcessing ? "处理中..." : "开始处理")
                        }
                        .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isProcessing || !viewModel.hasAnyOptionSelected)
                    .keyboardShortcut(.return, modifiers: [])
                }
                
                // 处理选项
                Form {
                    Section {
                        ProcessingOptionsView(provider: viewModel)
                    } header: {
                        Text("处理选项")
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
                
                // 处理进度
                if viewModel.isProcessing {
                    ProcessingProgressView(
                        progress: viewModel.progress,
                        status: viewModel.processingStatus
                    )
                }
                
                // 结果预览
                if viewModel.processingCompleted {
                    ResultCard(
                        firstFrameImage: viewModel.firstFrameImage,
                        lastFrameImage: viewModel.lastFrameImage,
                        audioURL: viewModel.audioURL,
                        transcriptURL: viewModel.transcriptURL,
                        outputDirectory: viewModel.outputDirectory
                    )
                    
                    // 操作按钮
                    HStack(spacing: 12) {
                        Button(action: {
                            viewModel.reset()
                        }) {
                            Label("处理新文件", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                        
                        if let outputDirectory = viewModel.outputDirectory {
                            Button(action: {
                                FileManager.default.revealInFinder(outputDirectory)
                            }) {
                                Label("打开保存位置", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
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
                        .fill(.quaternary)
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

#Preview {
    ContentView()
}
