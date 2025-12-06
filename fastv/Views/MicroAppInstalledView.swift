//
//  MicroAppInstalledView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI

/// 已安装 Micro-App 列表视图
struct MicroAppInstalledView: View {
    @StateObject private var manager = MicroAppManager.shared
    @State private var searchText = ""
    
    var filteredApps: [InstalledMicroApp] {
        var apps: [InstalledMicroApp]
        
        if searchText.isEmpty {
            apps = manager.installedApps
        } else {
            apps = manager.installedApps.filter { app in
                app.name.localizedCaseInsensitiveContains(searchText) ||
                app.version.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // 按照最后使用时间排序，最近使用的排在最前面
        return apps.sorted { app1, app2 in
            let time1 = manager.getLastUsedTime(for: app1.id) ?? app1.installedAt
            let time2 = manager.getLastUsedTime(for: app2.id) ?? app2.installedAt
            return time1 > time2 // 降序排列，最新的在前
        }
    }
    
    var body: some View {
        Group {
            if manager.installedApps.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "app.badge")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("还没有安装任何应用")
                        .font(.headline)
                    Text("前往「市场」页面安装应用")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // 搜索栏
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索应用", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    
                    // 应用列表
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)
                        ], spacing: 16) {
                            ForEach(filteredApps) { app in
                                InstalledAppCard(app: app)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
    }
}

/// 已安装应用卡片
struct InstalledAppCard: View {
    let app: InstalledMicroApp
    @StateObject private var manager = MicroAppManager.shared
    @State private var manifest: MicroAppManifest?
    @State private var isLoadingManifest = false
    @State private var showUninstallAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 图标和标题
            HStack(spacing: 12) {
                // 应用图标
                if let iconPath = app.iconPath,
                   let image = NSImage(contentsOfFile: iconPath) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .cornerRadius(8)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, height: 48)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.headline)
                    Text("版本 \(app.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            // 状态标签
            HStack(spacing: 8) {
                if manager.isRunning(id: app.id) {
                    Label("运行中", systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                }
                
                if manager.isPinned(id: app.id) {
                    Label("已固定", systemImage: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            // 权限标签
            if let manifest = manifest, !manifest.permissions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(manifest.permissions, id: \.self) { permission in
                        Text(permissionLabel(permission))
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
            
            // 操作按钮
            HStack(spacing: 8) {
                // 运行/停止按钮
                if manager.isRunning(id: app.id) {
                    Button(action: {
                        manager.closeApp(id: app.id)
                    }) {
                        HStack {
                            Image(systemName: "stop.circle.fill")
                            Text("停止")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: {
                        manager.launchApp(id: app.id)
                        // 发送通知，让 ContentView 切换到该 microAPP
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NavigateToMicroApp"),
                            object: nil,
                            userInfo: ["appId": app.id]
                        )
                    }) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("运行")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                // 卸载按钮
                Button(action: {
                    showUninstallAlert = true
                }) {
                    Image(systemName: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .onAppear {
            loadManifest()
        }
        .alert("确认卸载", isPresented: $showUninstallAlert) {
            Button("取消", role: .cancel) {
                showUninstallAlert = false
            }
            Button("卸载", role: .destructive) {
                Task {
                    do {
                        try await manager.uninstallApp(id: app.id)
                    } catch {
                        print("❌ [InstalledAppCard] 卸载失败: \(error.localizedDescription)")
                    }
                }
            }
        } message: {
            Text("确定要卸载「\(app.name)」吗？")
        }
    }
    
    private func loadManifest() {
        guard !isLoadingManifest else { return }
        isLoadingManifest = true
        
        Task {
            do {
                let loadedManifest = try manager.getManifest(for: app.id)
                await MainActor.run {
                    manifest = loadedManifest
                    isLoadingManifest = false
                }
            } catch {
                await MainActor.run {
                    isLoadingManifest = false
                }
                print("⚠️ [InstalledAppCard] 加载 manifest 失败: \(error.localizedDescription)")
            }
        }
    }
    
    private func permissionLabel(_ permission: String) -> String {
        switch permission {
        case "vision": return "视觉识别"
        case "chat": return "AI对话"
        case "asr": return "语音识别"
        case "tts": return "语音合成"
        case "file": return "文件访问"
        default: return permission
        }
    }
}

