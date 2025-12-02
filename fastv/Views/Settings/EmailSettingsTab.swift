//
//  EmailSettingsTab.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

/// 邮箱设置标签页
struct EmailSettingsTab: View {
    @ObservedObject var preferences = UserPreferences.shared
    
    var body: some View {
        Form {
            // 通知设置
            Section {
                Toggle("启用新邮件通知", isOn: $preferences.emailNotificationsEnabled)
                    .help("收到新邮件时显示系统通知")
            } header: {
                Text("通知")
            }
            
            // 显示设置
            Section {
                Toggle("显示附件", isOn: $preferences.emailShowAttachments)
                    .help("在邮件列表中显示附件信息")
                
                Toggle("显示图片", isOn: $preferences.emailShowImages)
                    .help("在邮件正文中显示图片（默认关闭以保护隐私）")
            } header: {
                Text("显示")
            }
            
            // 自动回复设置
            Section {
                Toggle("启用自动回复", isOn: $preferences.emailAutoReplyEnabled)
                    .help("收到新邮件时自动发送回复（排除no-reply地址）")
                
                if preferences.emailAutoReplyEnabled {
                    TextEditor(text: $preferences.emailAutoReplyTemplate)
                        .frame(height: 100)
                        .help("自动回复模板")
                }
            } header: {
                Text("自动回复")
            }
            
            // 读回执设置
            Section {
                Toggle("发送读回执", isOn: $preferences.emailReadReceiptEnabled)
                    .help("阅读邮件时发送已读回执（默认关闭以保护隐私）")
            } header: {
                Text("读回执")
            }
            
            // AI功能设置
            Section {
                Toggle("智能标签", isOn: $preferences.emailAISmartTaggingEnabled)
                    .help("使用AI自动为邮件生成标签")
                
                Toggle("AI摘要", isOn: $preferences.emailAISummaryEnabled)
                    .help("使用AI生成邮件摘要")
                
                Toggle("优先级检测", isOn: $preferences.emailAIPriorityDetectionEnabled)
                    .help("使用AI自动检测邮件优先级")
            } header: {
                Text("AI功能")
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    EmailSettingsTab()
}

