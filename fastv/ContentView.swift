//
//  ContentView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

/// 侧边栏选项
enum SidebarItem: Identifiable, Hashable {
    case voiceInput
    case aiTodo
    case diary
    case expense
    case health
    case meetingRecord
    case liveTranscription
    case videoProcessing
    case videoSceneAnalysis
    case aiChat
    case email
    case intel
    case market
    case installed
    case microApp(String) // 已安装的 Micro-App ID
    
    var id: String {
        switch self {
        case .voiceInput: return "语音输入"
        case .aiTodo: return "AI Todo"
        case .diary: return "日记"
        case .expense: return "记账"
        case .health: return "健康助理"
        case .meetingRecord: return "会议记录"
        case .liveTranscription: return "直播转录"
        case .videoProcessing: return "视频处理"
        case .videoSceneAnalysis: return "视频场景分析"
        case .aiChat: return "AI Chat"
        case .email: return "邮箱"
        case .intel: return "情报"
        case .market: return "市场"
        case .installed: return "已安装"
        case .microApp(let appId): return "microapp:\(appId)"
        }
    }
    
    var displayName: String {
        switch self {
        case .voiceInput: return "语音输入"
        case .aiTodo: return "AI Todo"
        case .diary: return "日记"
        case .expense: return "记账"
        case .health: return "健康助理"
        case .meetingRecord: return "会议记录"
        case .liveTranscription: return "直播转录"
        case .videoProcessing: return "视频处理"
        case .videoSceneAnalysis: return "视频场景分析"
        case .aiChat: return "AI Chat"
        case .email: return "邮箱"
        case .intel: return "情报"
        case .market: return "市场"
        case .installed: return "已安装"
        case .microApp(let appId):
            if let app = MicroAppManager.shared.installedApps.first(where: { $0.id == appId }) {
                return app.name
            }
            return appId
        }
    }
    
    var icon: String {
        switch self {
        case .voiceInput: return "mic.fill"
        case .meetingRecord: return "calendar.badge.clock"
        case .liveTranscription: return "waveform.circle.fill"
        case .videoProcessing: return "video.fill"
        case .videoSceneAnalysis: return "waveform.path"
        case .aiTodo: return "checklist"
        case .aiChat: return "message.fill"
        case .email: return "envelope.fill"
        case .diary: return "book.fill"
        case .expense: return "dollarsign.circle.fill"
        case .intel: return "doc.text.magnifyingglass"
        case .health: return "heart.fill"
        case .market: return "storefront.fill"
        case .installed: return "app.badge"
        case .microApp: return "app.fill"
        }
    }
    
    static var builtInItems: [SidebarItem] {
        [.voiceInput, .aiTodo, .diary, .expense, .health, .meetingRecord, .liveTranscription, .videoProcessing, .videoSceneAnalysis, .aiChat, .email, .intel, .market, .installed]
    }
}

struct ContentView: View {
    @StateObject private var viewModel = VideoProcessorViewModel()
    @StateObject private var microAppManager = MicroAppManager.shared
    @State private var showSettings = false
    @State private var selectedSidebarItem: SidebarItem = .voiceInput
    @ObservedObject private var preferences = UserPreferences.shared
    
    var sidebarItems: [SidebarItem] {
        var items = SidebarItem.builtInItems
        // 只添加运行中或已固定的 Micro-App
        let microAppItems: [SidebarItem] = microAppManager.installedApps
            .filter { microAppManager.shouldShowInSidebar(id: $0.id) }
            .map { app in SidebarItem.microApp(app.id) }
        items.append(contentsOf: microAppItems)
        return items
    }
    
    var body: some View {
        // 检查是否完成引导流程
        if !preferences.hasCompletedOnboarding {
            OnboardingView()
        } else {
            NavigationSplitView {
                // 左侧侧边栏
                List(selection: $selectedSidebarItem) {
                    ForEach(sidebarItems) { item in
                        SidebarItemRow(item: item, isSelected: selectedSidebarItem == item)
                            .tag(item)
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("功能")
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 250)
                .onChange(of: selectedSidebarItem) { oldValue, newValue in
                    // 如果点击的是 microAPP，更新最后使用时间
                    if case .microApp(let appId) = newValue {
                        if !microAppManager.isRunning(id: appId) {
                            microAppManager.launchApp(id: appId)
                        } else {
                            // 即使已经运行，点击时也更新最后使用时间
                            microAppManager.updateLastUsedTime(for: appId)
                        }
                    }
                }
            } detail: {
                // 右侧内容区域
                Group {
                    switch selectedSidebarItem {
                    case .voiceInput:
                        VoiceInputView()
                            .toolbar {
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
                                    Button(action: { showSettings = true }) {
                                        Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
                                    }
                                    .help(NSLocalizedString("settings", comment: ""))
                                }
                            }
                    case .liveTranscription:
                        LiveTranscriptionView()
                            .toolbar {
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
                                    Button(action: { showSettings = true }) {
                                        Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
                                    }
                                    .help(NSLocalizedString("settings", comment: ""))
                                }
                            }
                    case .aiTodo:
                        AITodoView()
                            .toolbar {
                                ToolbarItem(placement: .automatic) {
                                    Button(action: { showSettings = true }) {
                                        Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
                                    }
                                    .help(NSLocalizedString("settings", comment: ""))
                                }
                            }
                    case .aiChat:
                        AIChatView()
                            .toolbar {
                                ToolbarItem(placement: .automatic) {
                                    Button(action: { showSettings = true }) {
                                        Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
                                    }
                                    .help(NSLocalizedString("settings", comment: ""))
                                }
                            }
                    case .email:
                        EmailView()
                            .toolbar {
                                ToolbarItem(placement: .automatic) {
                                    Button(action: { showSettings = true }) {
                                        Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
                                    }
                                    .help(NSLocalizedString("settings", comment: ""))
                                }
                            }
                    case .diary:
                        DiaryView()
                            .toolbar {
                                ToolbarItem(placement: .automatic) {
                                    Button(action: { showSettings = true }) {
                                        Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
                                    }
                                    .help(NSLocalizedString("settings", comment: ""))
                                }
                            }
                    case .expense:
                        ExpenseView()
                            .toolbar {
                                ToolbarItem(placement: .automatic) {
                                    Button(action: { showSettings = true }) {
                                        Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
                                    }
                                    .help(NSLocalizedString("settings", comment: ""))
                                }
                            }
                    case .intel:
                        IntelView()
                            .toolbar {
                                ToolbarItem(placement: .automatic) {
                                    Button(action: { showSettings = true }) {
                                        Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
                                    }
                                    .help(NSLocalizedString("settings", comment: ""))
                                }
                            }
                    case .health:
                        HealthAssistantView()
                            .toolbar {
                                ToolbarItem(placement: .automatic) {
                                    Button(action: { showSettings = true }) {
                                        Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
                                    }
                                    .help(NSLocalizedString("settings", comment: ""))
                                }
                            }
                    case .market:
                        MicroAppMarketView()
                    case .installed:
                        MicroAppInstalledView()
                    case .microApp(let appId):
                        MicroAppHostView(appId: appId)
                            .id(appId) // 强制视图重建，修复切换问题
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                        .frame(minWidth: 800, idealWidth: 900, maxWidth: 1000, minHeight: 600, idealHeight: 700, maxHeight: 800)
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
            .overlay(alignment: .top) {
                // 全局 Toast 提示
                ToastView()
                    .padding(.top, 60)
            }
            .onChange(of: microAppManager.runningApps) { oldValue, newValue in
                // 如果当前选中的 microAPP 被关闭了，切换到已安装页面
                if case .microApp(let appId) = selectedSidebarItem {
                    if !newValue.contains(appId) {
                        selectedSidebarItem = .installed
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToMicroApp"))) { notification in
                if let appId = notification.userInfo?["appId"] as? String {
                    selectedSidebarItem = .microApp(appId)
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

// MARK: - Sidebar Item Row

struct SidebarItemRow: View {
    let item: SidebarItem
    let isSelected: Bool
    @StateObject private var microAppManager = MicroAppManager.shared
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            // 图标
            Image(systemName: item.icon)
                .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : (isMicroAppRunning ? .primary : .secondary))
                .frame(width: 20, alignment: .center)
                .symbolEffect(.bounce, value: isSelected)
            
            // 文字
            Text(item.displayName)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : (isMicroAppRunning ? .primary : .secondary))
            
            Spacer()
            
            // 关闭按钮（仅对 microAPP 且悬停时显示）
            if case .microApp(let appId) = item, isHovered {
                Button(action: {
                    microAppManager.closeApp(id: appId)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.secondary.opacity(0.08) : Color.clear))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            if case .microApp(let appId) = item {
                if microAppManager.isPinned(id: appId) {
                    Button(action: {
                        microAppManager.unpinApp(id: appId)
                    }) {
                        Label("取消固定", systemImage: "pin.slash")
                    }
                } else {
                    Button(action: {
                        microAppManager.pinApp(id: appId)
                    }) {
                        Label("固定到侧边栏", systemImage: "pin")
                    }
                }
                
                if microAppManager.isRunning(id: appId) {
                    Button(action: {
                        microAppManager.closeApp(id: appId)
                    }) {
                        Label("关闭", systemImage: "xmark.circle")
                    }
                } else {
                    Button(action: {
                        microAppManager.launchApp(id: appId)
                    }) {
                        Label("运行", systemImage: "play.circle")
                    }
                }
            }
        }
    }
    
    private var isMicroAppRunning: Bool {
        if case .microApp(let appId) = item {
            return microAppManager.isRunning(id: appId)
        }
        return true // 非 microAPP 项始终视为"运行中"
    }
}
