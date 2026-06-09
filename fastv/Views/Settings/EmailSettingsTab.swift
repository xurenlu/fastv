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
    @State private var showSignatureManager = false
    @State private var imagePreferences: [String: Bool] = [:]
    @State private var showImagePreferencesManager = false
    
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
            
            // 读回执 + 标已读时机
            Section {
                Toggle("发送读回执", isOn: $preferences.emailReadReceiptEnabled)
                    .help("阅读邮件时发送已读回执（默认关闭以保护隐私）")

                Picker("自动标已读", selection: $preferences.emailMarkAsReadDelaySeconds) {
                    Text("立即").tag(0)
                    Text("1 秒后").tag(1)
                    Text("3 秒后").tag(3)
                    Text("5 秒后").tag(5)
                    Text("10 秒后").tag(10)
                    Text("仅手动").tag(-1)
                }
                .help("选中邮件后多久自动标已读。默认 3 秒，期间换邮件会自动取消，避免键盘上下浏览时误标整个收件箱。")
            } header: {
                Text("读回执 / 标已读")
            } footer: {
                if preferences.emailMarkAsReadDelaySeconds == 0 {
                    Text("⚠️ 立即标已读会让方向键滚动浏览时一路把邮件全标了；服务器上的 \\Seen 标志会同步更新，无法撤销。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if preferences.emailMarkAsReadDelaySeconds == -1 {
                    Text("仅手动模式下，邮件永远不会被自动标已读，需要使用菜单或右键手动标读。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // 隐私设置
            Section {
                Toggle("超级隐私模式", isOn: $preferences.emailSuperPrivacyMode)
                    .help("一旦开启，永远不会加载任何远程内容、不会显示图片、不会发送读回执等")
                
                if preferences.emailSuperPrivacyMode {
                    Text("超级隐私模式已启用：所有远程内容将被阻止，图片不会显示，读回执不会发送")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Button(action: {
                    loadImagePreferences()
                    showImagePreferencesManager = true
                }) {
                    HStack {
                        Image(systemName: "photo.fill")
                            .foregroundStyle(Color.blue)
                        Text("管理图片显示偏好")
                        Spacer()
                        if !imagePreferences.isEmpty {
                            Text("\(imagePreferences.count) 项")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("查看和管理已保存的图片显示偏好设置")
            } header: {
                Text("隐私")
            } footer: {
                Text("超级隐私模式会覆盖所有其他设置，确保最大程度的隐私保护")
            }
            
            // 签名设置
            Section {
                Button(action: {
                    showSignatureManager = true
                }) {
                    HStack {
                        Image(systemName: "signature")
                            .foregroundStyle(Color.blue)
                        Text("管理签名")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("创建和管理邮件签名")
            } header: {
                Text("签名")
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
            
            // 邮件加载策略
            Section {
                Toggle("达到阈值后停止自动加载", isOn: $preferences.emailStopAutoSyncAfterThreshold)
                    .help("每个文件夹加载到指定数量后停止自动同步，滚动到底部时手动加载更多")
                
                if preferences.emailStopAutoSyncAfterThreshold {
                    HStack {
                        Text("初始加载数量")
                        Spacer()
                        Picker("", selection: $preferences.emailInitialLoadThreshold) {
                            Text("20 封").tag(20)
                            Text("30 封").tag(30)
                            Text("50 封").tag(50)
                            Text("100 封").tag(100)
                            Text("200 封").tag(200)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                    }
                    .help("每个文件夹初始自动加载的邮件数量")
                    
                    Text("达到阈值后，滚动到底部可加载更多邮件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("加载策略")
            } footer: {
                Text("启用此选项可减少应用启动时的资源占用，邮件将按需加载")
            }
            
            // 数据管理
            Section {
                CleanupDuplicateMessagesView()
            } header: {
                Text("数据管理")
            } footer: {
                Text("清理重复邮件可以释放存储空间并提高性能。系统会自动保留最完整、最新的邮件版本。")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showSignatureManager) {
            EmailSignatureView()
        }
        .sheet(isPresented: $showImagePreferencesManager) {
            ImagePreferencesManagerView(preferences: $imagePreferences)
        }
        .onAppear {
            loadImagePreferences()
        }
    }
    
    private func loadImagePreferences() {
        imagePreferences = EmailImageDisplayPreferences.shared.getAllPreferences()
    }
}

/// 图片显示偏好管理视图
struct ImagePreferencesManagerView: View {
    @Binding var preferences: [String: Bool]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    private var filteredPreferences: [(key: String, value: Bool)] {
        let sorted = preferences.sorted { $0.key < $1.key }
        if searchText.isEmpty {
            return sorted
        }
        return sorted.filter { $0.key.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if filteredPreferences.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("暂无已保存的偏好设置")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("当您在邮件中选择\"记住此选择\"时，偏好设置会显示在这里")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(filteredPreferences.enumerated()), id: \.element.key) { index, item in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.key)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    
                                    HStack(spacing: 4) {
                                        Image(systemName: item.value ? "photo.fill" : "photo")
                                            .font(.caption)
                                            .foregroundStyle(item.value ? Color.green : .secondary)
                                        Text(item.value ? "显示图片" : "不显示图片")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    removePreference(key: item.key)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundStyle(Color.red)
                                }
                                .buttonStyle(.plain)
                                .help("删除此偏好设置")
                            }
                        }
                    }
                }
            }
            .navigationTitle("图片显示偏好")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if !preferences.isEmpty {
                        Button("清除全部") {
                            clearAllPreferences()
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索邮箱地址或域名")
        }
        .frame(width: 600, height: 500)
    }
    
    private func removePreference(key: String) {
        EmailImageDisplayPreferences.shared.removePreference(for: key)
        preferences.removeValue(forKey: key)
    }
    
    private func clearAllPreferences() {
        EmailImageDisplayPreferences.shared.clearAllPreferences()
        preferences = [:]
    }
}

/// 清理重复邮件视图
struct CleanupDuplicateMessagesView: View {
    @State private var isCleaning = false
    @State private var cleanupResult: CleanupResult?
    @State private var showConfirmation = false
    
    enum CleanupResult {
        case success(Int)
        case failure(String)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trash")
                    .foregroundStyle(Color.orange)
                Text("清理重复邮件")
                    .font(.subheadline)
                Spacer()
            }
            
            if let result = cleanupResult {
                switch result {
                case .success(let count):
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                        Text("清理完成，已删除 \(count) 封重复邮件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .failure(let error):
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.red)
                        Text("清理失败: \(error)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Button(action: {
                showConfirmation = true
            }) {
                HStack {
                    if isCleaning {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isCleaning ? "正在清理..." : "开始清理")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isCleaning)
            .help("扫描并删除数据库中的重复邮件")
        }
        .padding(.vertical, 4)
        .confirmationDialog("确认清理重复邮件", isPresented: $showConfirmation) {
            Button("清理所有账号", role: .destructive) {
                cleanupAllAccounts()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作将扫描数据库并删除重复的邮件。系统会自动保留最完整、最新的版本。")
        }
    }
    
    private func cleanupAllAccounts() {
        isCleaning = true
        cleanupResult = nil
        
        Task {
            do {
                let deletedCount = try await EmailStore.shared.cleanupDuplicateMessages()
                await MainActor.run {
                    isCleaning = false
                    cleanupResult = .success(deletedCount)
                    
                    // 3秒后清除结果提示
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run {
                            cleanupResult = nil
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isCleaning = false
                    cleanupResult = .failure(error.localizedDescription)
                }
            }
        }
    }
}

#Preview {
    EmailSettingsTab()
}

