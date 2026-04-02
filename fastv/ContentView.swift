//
//  ContentView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

/// 侧边栏选项（当前产品仅保留语音输入与邮箱）
enum SidebarItem: Identifiable, Hashable {
    case voiceInput
    case email

    var id: String {
        switch self {
        case .voiceInput: return "语音输入"
        case .email: return "邮箱"
        }
    }

    var displayName: String {
        switch self {
        case .voiceInput: return "语音输入"
        case .email: return "邮箱"
        }
    }

    var icon: String {
        switch self {
        case .voiceInput: return "mic.fill"
        case .email: return "envelope.fill"
        }
    }

    static var builtInItems: [SidebarItem] {
        [.voiceInput, .email]
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
            // 使用 HSplitView 替代 NavigationSplitView，彻底规避：1) 自动折叠 2) 状态恢复 3) macOS 26 的 layout bug
            HSplitView {
                // 左侧主菜单：固定宽度，永不折叠
                mainSidebar
                    .frame(width: 160)
                    .frame(maxHeight: .infinity)
                
                // 右侧内容区域
                detailContent
                    .frame(minWidth: 500)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    
    // MARK: - 左侧主菜单（固定，永不折叠）
    private var mainSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("功能")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            VStack(spacing: 2) {
                ForEach(SidebarItem.builtInItems) { item in
                    Button {
                        selectedSidebarItem = item
                    } label: {
                        SidebarItemRow(item: item, isSelected: selectedSidebarItem == item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)  // 避免默认获得焦点时出现焦点环（像边框）
                }
            }
            .padding(.horizontal, 8)
            
            Spacer(minLength: 0)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 1)
        }
    }
    
    // MARK: - 右侧内容区
    @ViewBuilder
    private var detailContent: some View {
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
            // 选中：左侧竖条 + 极淡背景，避免整块圆角矩形像「边框」
            ZStack(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                }
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.leading, 4)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
