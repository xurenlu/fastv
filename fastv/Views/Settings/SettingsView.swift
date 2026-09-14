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
    @State private var selectedTab: SettingsTab = .typing

    private enum Layout {
        static let sidebarWidth: CGFloat = 196
        static let sidebarHorizontalPadding: CGFloat = 14
        static let sidebarTopPadding: CGFloat = 12
    }

    /// 设置分组：输入法·打字（默认）/ 语音输入 / AI 与模型 / 数据与其他 / 帮助
    enum SettingsTab: String, CaseIterable, Identifiable {
        case typing
        case appearance
        case voice
        case aiModel
        case history
        case data
        case help

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .typing: return "experience.nav.input"
            case .appearance: return "experience.nav.appearance"
            case .history: return "experience.nav.history"
            case .voice: return "settings.tab.voice"
            case .aiModel: return "experience.nav.ai"
            case .data: return "experience.nav.privacy"
            case .help: return "settings.tab.help"
            }
        }

        var icon: String {
            switch self {
            case .typing: return "keyboard.fill"
            case .appearance: return "paintpalette"
            case .history: return "waveform.path"
            case .voice: return "mic.fill"
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
                    .frame(width: Layout.sidebarWidth, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                Divider()

                // 右侧内容区
                tabContent
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(NSLocalizedString("settings.title", comment: ""))
            .frame(
                minWidth: MainWindowLayout.minimumSize.width,
                idealWidth: 960,
                minHeight: MainWindowLayout.minimumSize.height,
                idealHeight: 720
            )
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
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                .font(.caption).foregroundStyle(.secondary).padding()
        }
        .padding(.horizontal, Layout.sidebarHorizontalPadding)
        .padding(.top, Layout.sidebarTopPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .typing:
            TypingTab().id("typing")
        case .appearance:
            Form { CandidateAppearanceView() }.formStyle(.grouped)
        case .history:
            HistoryEvaluationSettingsView()
        case .voice:
            VoiceInputTab(showsSubtabs: false).id("voice")
        case .aiModel:
            AITextProcessingView().id("aiModel")
        case .data:
            PrivacyStorageSettingsView().id("data")
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
