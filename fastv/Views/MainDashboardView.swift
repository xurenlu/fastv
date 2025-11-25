//
//  MainDashboardView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI
import AVFoundation

/// 主仪表板视图 - 新的主界面
struct MainDashboardView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var meetingDetector = MeetingDetector.shared
    @ObservedObject private var noteManager = NoteManager.shared
    @State private var selectedScene: SceneType = .voiceInput
    @State private var microphoneAuthStatus: AVAuthorizationStatus = .notDetermined
    @State private var showSettings = false
    @State private var showCommonMistakeManagement = false
    @State private var showNoteList = false
    @State private var showMeetingRecordView = false
    
    enum SceneType {
        case voiceInput      // 语音输入
        case meetingRecord   // 会议记录
        case voiceMemo       // 语音备忘录
        case subtitle        // 实时字幕（待实现）
        case aiService       // AI服务
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏
            topNavigationBar
            
            Divider()
            
            // 场景卡片区域
            sceneCardsArea
            
            Divider()
            
            // 快捷功能区
            quickActionsArea
            
            Divider()
            
            // 实时状态栏
            statusBar
        }
        .frame(minWidth: 900, minHeight: 700)
    }
    
    // MARK: - 顶部导航栏
    private var topNavigationBar: some View {
        HStack(spacing: 20) {
            Text("妙打")
                .font(.system(size: 20, weight: .bold))
            
            Spacer()
            
            // 场景切换按钮
            HStack(spacing: 12) {
                sceneButton(.voiceInput, icon: "mic.fill", label: "语音输入")
                sceneButton(.meetingRecord, icon: "video.fill", label: "会议记录")
                sceneButton(.voiceMemo, icon: "note.text", label: "语音备忘录")
            }
            
            Spacer()
            
            // 右侧按钮
            HStack(spacing: 12) {
                Button(action: {
                    showCommonMistakeManagement = true
                }) {
                    Label("常用词", systemImage: "text.badge.checkmark")
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    showSettings = true
                }) {
                    Label("设置", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func sceneButton(_ scene: SceneType, icon: String, label: String) -> some View {
        Button(action: {
            selectedScene = scene
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selectedScene == scene ? Color.accentColor.opacity(0.15) : Color.clear)
            }
            .foregroundStyle(selectedScene == scene ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 场景卡片区域
    private var sceneCardsArea: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                // 语音输入卡片
                VoiceInputSceneCard()
                
                // 会议记录卡片
                MeetingRecordSceneCard()
                
                // 语音备忘录卡片
                VoiceMemoSceneCard()
                
                // 实时字幕卡片（占位）
                SubtitleSceneCard()
                
                // AI服务卡片
                AIServiceSceneCard()
            }
            .padding(20)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showCommonMistakeManagement) {
            CommonMistakeManagementSheet()
        }
        .sheet(isPresented: $showNoteList) {
            NoteListView()
        }
        .sheet(isPresented: $showMeetingRecordView) {
            MeetingRecordView()
        }
        .onAppear {
            checkMicrophoneStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingAppDetected)) { notification in
            // 检测到会议应用时的处理
            if let app = notification.userInfo?["app"] as? MeetingDetector.MeetingApp {
                print("📱 [MainDashboardView] 检测到会议应用: \(app.displayName)")
            }
        }
    }
    
    // MARK: - 快捷功能区
    private var quickActionsArea: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("快捷功能")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            
            HStack(spacing: 20) {
                // 常用词管理
                CommonMistakeQuickView()
                
                // 水词修正
                FillerWordQuickView()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - 实时状态栏
    private var statusBar: some View {
        HStack(spacing: 20) {
            // 麦克风状态
            StatusIndicator(
                icon: "mic.fill",
                label: "麦克风",
                status: microphoneStatus,
                color: microphoneStatus == "已授权" ? .green : .orange
            )
            
            // AI服务状态
            StatusIndicator(
                icon: "sparkles",
                label: "AI服务",
                status: aiServiceStatus,
                color: aiServiceStatus == "已连接" ? .green : .orange
            )
            
            // 会议检测状态
            StatusIndicator(
                icon: "video.fill",
                label: "会议",
                status: meetingDetectionStatus,
                color: meetingDetectionStatus == "未检测到" ? .secondary : .blue
            )
            
            Spacer()
            
            // 版本信息
            Text("\(AppVersionManager.appName) \(AppVersionManager.fullVersion)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - 状态计算属性
    private var microphoneStatus: String {
        switch microphoneAuthStatus {
        case .authorized:
            return "已授权"
        case .denied, .restricted:
            return "未授权"
        case .notDetermined:
            return "未请求"
        @unknown default:
            return "未知"
        }
    }
    
    private var aiServiceStatus: String {
        if preferences.enableAIOptimization {
            return "已连接"
        }
        return "未配置"
    }
    
    private var meetingDetectionStatus: String {
        if let app = meetingDetector.detectedMeetingApp {
            return app.displayName
        }
        return "未检测到"
    }
    
    // MARK: - 辅助方法
    private func checkMicrophoneStatus() {
        microphoneAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
}

// MARK: - 状态指示器组件
struct StatusIndicator: View {
    let icon: String
    let label: String
    let status: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            
            Text(status)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - 场景卡片组件
struct VoiceInputSceneCard: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var history = VoiceInputHistory.shared
    
    var body: some View {
        SceneCardView(
            icon: "mic.fill",
            title: "语音输入",
            description: "快速语音转文字",
            status: "就绪",
            actionText: formatShortcut(),
            action: {
                // 显示快捷键提示
            }
        )
        .overlay(alignment: .topTrailing) {
            if history.todayCount() > 0 {
                Text("\(history.todayCount())")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background {
                        Circle()
                            .fill(.green)
                    }
                    .offset(x: -8, y: 8)
                .help("今日已输入 \(history.todayCount()) 次")
            }
        }
    }
    
    private func formatShortcut() -> String {
        guard preferences.enableVoiceInput else {
            return "未启用"
        }
        let modifiers = preferences.voiceInputShortcutModifiers
        var keys: [String] = []
        if modifiers.contains(.command) { keys.append("⌘") }
        if modifiers.contains(.shift) { keys.append("⇧") }
        if modifiers.contains(.option) { keys.append("⌥") }
        if modifiers.contains(.control) { keys.append("⌃") }
        
        let keyName = keyCodeToString(preferences.voiceInputShortcutKeyCode)
        keys.append(keyName)
        return keys.joined(separator: "+")
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0xFFFF: return "Control"
        case 0x3F: return "FN"
        case 0x31: return "Space"
        default: return "键\(keyCode)"
        }
    }
}

struct MeetingRecordSceneCard: View {
    @ObservedObject private var meetingDetector = MeetingDetector.shared
    @ObservedObject private var recordStorage = MeetingRecordStorage.shared
    @State private var showMeetingRecord = false
    
    var body: some View {
        SceneCardView(
            icon: "video.fill",
            title: "会议记录",
            description: "自动检测会议软件",
            status: meetingDetector.detectedMeetingApp?.displayName ?? "未检测到",
            actionText: meetingDetector.detectedMeetingApp != nil ? "开始记录" : "检测中...",
            action: {
                if meetingDetector.detectedMeetingApp != nil {
                    showMeetingRecord = true
                }
            }
        )
        .sheet(isPresented: $showMeetingRecord) {
            MeetingRecordView()
        }
        .overlay(alignment: .topTrailing) {
            if recordStorage.todayCount() > 0 {
                Text("\(recordStorage.todayCount())")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background {
                        Circle()
                            .fill(.blue)
                    }
                    .offset(x: -8, y: 8)
            }
        }
    }
}

struct VoiceMemoSceneCard: View {
    @ObservedObject private var noteManager = NoteManager.shared
    @State private var showNoteList = false
    
    var body: some View {
        SceneCardView(
            icon: "note.text",
            title: "语音备忘录",
            description: "快速生成笔记",
            status: "就绪",
            actionText: "新建笔记",
            action: {
                showNoteList = true
            }
        )
        .sheet(isPresented: $showNoteList) {
            NoteListView()
        }
        .overlay(alignment: .topTrailing) {
            if noteManager.todayCount() > 0 {
                Text("\(noteManager.todayCount())")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background {
                        Circle()
                            .fill(.red)
                    }
                    .offset(x: -8, y: 8)
            }
        }
    }
}

struct SubtitleSceneCard: View {
    var body: some View {
        SceneCardView(
            icon: "captions.bubble.fill",
            title: "实时字幕",
            description: "视频播放时显示字幕",
            status: "待实现",
            actionText: "待实现",
            action: {},
            isDisabled: true
        )
    }
}

struct AIServiceSceneCard: View {
    @ObservedObject private var preferences = UserPreferences.shared
    
    var body: some View {
        SceneCardView(
            icon: "sparkles",
            title: "AI服务",
            description: "AI优化/总结/翻译",
            status: preferences.enableAIOptimization ? "已连接" : "未配置",
            actionText: preferences.enableAIOptimization ? "正常" : "配置",
            action: {}
        )
    }
}

// MARK: - 通用场景卡片视图
struct SceneCardView: View {
    let icon: String
    let title: String
    let description: String
    let status: String
    let actionText: String
    let action: () -> Void
    var isDisabled: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 图标和标题
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(isDisabled ? .secondary : .accentColor)
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // 操作按钮
            Button(action: action) {
                HStack {
                    Spacer()
                    Text(actionText)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isDisabled ? Color.secondary.opacity(0.2) : Color.accentColor.opacity(0.1))
                }
                .foregroundStyle(isDisabled ? .secondary : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            
            // 状态
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(height: 180)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
                }
        }
    }
    
    private var statusColor: Color {
        switch status {
        case "就绪", "已连接", "正常":
            return .green
        case "未检测到", "未配置", "待实现":
            return .orange
        default:
            return .secondary
        }
    }
}

// MARK: - 快捷功能视图（占位）
struct CommonMistakeQuickView: View {
    @ObservedObject private var mistakeManager = CommonMistakeManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.badge.checkmark")
                    .foregroundStyle(.blue)
                Text("常用词管理")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(mistakeManager.totalCount())")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("常用词")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(mistakeManager.totalCorrections())")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("已修正")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Button("管理") {
                // TODO: 打开常用词管理界面
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        }
    }
}

struct FillerWordQuickView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "water.waves")
                    .foregroundStyle(.cyan)
                Text("水词修正")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Toggle("启用自动修正", isOn: $preferences.enableFastCorrection)
                .toggleStyle(.switch)
            
            Text("自动去除：嗯、啊、那个、这个...")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button("自定义") {
                // TODO: 打开水词设置界面
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        }
    }
}

#Preview {
    MainDashboardView()
        .frame(width: 900, height: 700)
}

