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
    case meeting
    case aiTodo
    case aiChat
    case email

    var id: String {
        switch self {
        case .voiceInput: return "语音输入"
        case .meeting: return "会议记录"
        case .aiTodo: return "AI Todo"
        case .aiChat: return "AI Chat"
        case .email: return "邮箱"
        }
    }

    var displayName: String {
        switch self {
        case .voiceInput: return "语音输入"
        case .meeting: return "会议记录"
        case .aiTodo: return "AI Todo"
        case .aiChat: return "AI Chat"
        case .email: return "邮箱"
        }
    }

    var icon: String {
        switch self {
        case .voiceInput: return "mic.fill"
        case .meeting: return "doc.text.fill"
        case .aiTodo: return "checklist"
        case .aiChat: return "message.fill"
        case .email: return "envelope.fill"
        }
    }

    static var builtInItems: [SidebarItem] {
        [.voiceInput, .meeting, .aiTodo, .aiChat, .email]
    }
}

struct ContentView: View {
    @State private var showSettings = false
    @State private var selectedSidebarItem: SidebarItem = .voiceInput
    @ObservedObject private var preferences = UserPreferences.shared
    
    var body: some View {
        Group {
            // 检查是否完成引导流程
            if !preferences.hasCompletedOnboarding {
                OnboardingView()
            } else {
            NavigationSplitView {
                // 左侧侧边栏
                List(selection: $selectedSidebarItem) {
                    ForEach(SidebarItem.builtInItems) { item in
                        SidebarItemRow(item: item, isSelected: selectedSidebarItem == item)
                            .tag(item)
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("功能")
                .frame(minWidth: 140, idealWidth: 160, maxWidth: 180)
            } detail: {
                // 右侧内容区域（.id 确保切换时销毁旧视图，释放内存，避免累积导致无响应）
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
                    case .meeting:
                        MeetingRecordView()
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
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                        .frame(minWidth: 800, idealWidth: 900, maxWidth: 1000, minHeight: 600, idealHeight: 700, maxHeight: 800)
                }
                .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                    showSettings = true
                }
                .id(selectedSidebarItem)
            }
            .frame(minWidth: 720, minHeight: 520)
            }
        }
        .onChange(of: preferences.hasCompletedOnboarding) { _, completed in
            if completed {
                // 用户完成引导后，若已下载模型则预加载
                SpeechModelPreloadManager.shared.startPreloadIfNeeded()
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

#Preview {
    ContentView()
}


// MARK: - Sidebar Item Row

struct SidebarItemRow: View {
    let item: SidebarItem
    let isSelected: Bool
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            // 图标
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 18, alignment: .center)
                .symbolEffect(.bounce, value: isSelected)
            
            // 文字
            Text(item.displayName)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
            
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
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
    }
}
