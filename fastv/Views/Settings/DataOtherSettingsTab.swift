//
//  DataOtherSettingsTab.swift
//  fastv
//
//  Created by rocky on 2025/11/29.
//

import SwiftUI

/// Tab 4: 数据与其他
/// 包含：内存监控、历史记录管理、权限测试、支持与推荐
struct DataOtherSettingsTab: View {
    @ObservedObject var preferences = UserPreferences.shared
    @State private var showMemoryMonitor = false

    var body: some View {
        Form {
            // 内存监控
            Section {
                Button(action: {
                    showMemoryMonitor = true
                }) {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                            .foregroundStyle(.blue)
                        Text(NSLocalizedString("memory.monitor", comment: ""))
                        Spacer()
                        Text(MemoryMonitor.shared.getMemoryUsageString())
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text(NSLocalizedString("performance.monitor", comment: ""))
            }

            // 关于
            Section {
                Button(action: {
                    AboutWindowOpener.open()
                }) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text(NSLocalizedString("about", comment: ""))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text(NSLocalizedString("about", comment: ""))
            }
            
            // 支持与推荐
            Section {
                // 官方支持页
                Link(destination: URL(string: "https://83d.me/products/qecho")!) {
                    HStack {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundStyle(.blue)
                        Text(NSLocalizedString("support.official.page", comment: ""))
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // 推荐应用（与关于窗口共用同一网格）
                VStack(alignment: .leading, spacing: 10) {
                    Text(NSLocalizedString("about.other_apps", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    RecommendedAppsGrid()
                }
            } header: {
                Text(NSLocalizedString("support.and.recommend", comment: ""))
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showMemoryMonitor) {
            MonitorChartView()
                .frame(minWidth: 600, minHeight: 500)
        }
    }
}

#Preview {
    DataOtherSettingsTab()
}
