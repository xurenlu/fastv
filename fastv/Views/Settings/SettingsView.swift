//
//  SettingsView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//  Refactored to multi-tab structure on 2025/11/29.
//

import SwiftUI
import AVFoundation
import AppKit

struct SettingsView: View {
    @ObservedObject var preferences = UserPreferences.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .quick

    enum SettingsTab: String, CaseIterable, Identifiable {
        case quick = "快速配置"
        case aiModel = "AI与模型"
        case data = "数据与其他"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .quick: return "bolt.fill"
            case .aiModel: return "cpu"
            case .data: return "folder.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 自定义标签栏
                TabBar(selectedTab: $selectedTab)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                Divider()

                // 内容区域 - 使用 @ViewBuilder 和 id 保持视图状态
                ScrollView {
                    tabContent
                }
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
            .frame(minWidth: 640, minHeight: 580)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .quick:
            QuickSettingsTab()
                .id("quick")
        case .aiModel:
            AIModelSettingsTab()
                .id("aiModel")
        case .data:
            DataOtherSettingsTab()
                .id("data")
        }
    }
}

// MARK: - Tab Bar

struct TabBar: View {
    @Binding var selectedTab: SettingsView.SettingsTab
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SettingsView.SettingsTab.allCases) { tab in
                TabBarItem(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    namespace: animation
                ) {
                    // 使用更轻量的动画
                    withAnimation(.linear(duration: 0.15)) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(4)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct TabBarItem: View {
    let tab: SettingsView.SettingsTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(NSColor.selectedContentBackgroundColor))
                        .matchedGeometryEffect(id: "selectedTab", in: namespace)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
}
