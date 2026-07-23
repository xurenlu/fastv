//
//  SettingsView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//  Refactored to multi-tab structure on 2025/11/29.
//  Refactored to left sidebar tabs (5 groups) on 2026-07-23.
//

import SwiftUI
import AVFoundation
import AppKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .general

    /// 设置分组：常用 / 语音输入 / 输入法·打字 / AI 与模型 / 数据与其他
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general
        case voice
        case typing
        case aiModel
        case data
        case help

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .general: return "settings.tab.general"
            case .voice: return "settings.tab.voice"
            case .typing: return "settings.tab.typing"
            case .aiModel: return "settings.tab.aiModel"
            case .data: return "settings.tab.data"
            case .help: return "settings.tab.help"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .voice: return "mic.fill"
            case .typing: return "keyboard.fill"
            case .aiModel: return "cpu"
            case .data: return "folder.fill"
            case .help: return "questionmark.circle.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // 左侧竖向 tab 栏
                sidebar
                    .frame(width: 176)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                Divider()

                // 右侧内容区
                ScrollView {
                    tabContent
                }
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(NSLocalizedString("settings.title", comment: ""))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("settings.done", comment: "")) {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(minWidth: 720, minHeight: 580)
        }
    }

    // MARK: - 左侧 tab 栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                SidebarItem(
                    title: NSLocalizedString(tab.titleKey, comment: ""),
                    icon: tab.icon,
                    isSelected: selectedTab == tab
                ) {
                    selectedTab = tab
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            GeneralTab().id("general")
        case .voice:
            VoiceInputTab().id("voice")
        case .typing:
            TypingTab().id("typing")
        case .aiModel:
            AIModelSettingsTab().id("aiModel")
        case .data:
            DataOtherSettingsTab().id("data")
        case .help:
            HelpTab().id("help")
        }
    }
}

// MARK: - 侧栏项

private struct SidebarItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

#Preview {
    SettingsView()
}
