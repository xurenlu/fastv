//
//  DataOtherSettingsTab.swift
//  fastv
//
//  Created by rocky on 2025/11/29.
//

import SwiftUI

/// Tab 4: 数据与其他
/// 包含：历史记录管理、权限测试、支持与推荐
struct DataOtherSettingsTab: View {
    @ObservedObject var preferences = UserPreferences.shared
    @State private var showAbout = false
    
    var body: some View {
        Form {
            // 历史记录管理
            Section {
                HistoryRecordManagementView()
            } header: {
                Text("历史记录")
            } footer: {
                Text("管理语音输入历史记录")
            }
            
            // 关于
            Section {
                Button(action: {
                    showAbout = true
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
                Link(destination: URL(string: "https://83d.me/products/typecho")!) {
                    HStack {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundStyle(.blue)
                        Text("官方支持页")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                // 推荐应用
                VStack(alignment: .leading, spacing: 12) {
                    Text("推荐应用")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    // 妙墨 Markdown 笔记软件
                    Link(destination: URL(string: "https://apps.apple.com/cn/app/%E5%A6%99%E5%A2%A8/id6751117141")!) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("妙墨")
                                    .font(.body)
                                Text("Markdown 笔记软件")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // 时间帐单
                    Link(destination: URL(string: "https://apps.apple.com/cn/app/%E6%97%B6%E9%97%B4%E5%B8%90%E5%8D%95/id6752824838?mt=12")!) {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("时间帐单")
                                    .font(.body)
                                Text("个人时间记录工具")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("支持与推荐")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
    }
}

#Preview {
    DataOtherSettingsTab()
}

