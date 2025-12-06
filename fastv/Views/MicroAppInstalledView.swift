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
    @State private var selectedAppId: String?
    @State private var showUninstallAlert = false
    @State private var appToUninstall: String?
    
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
                List(selection: $selectedAppId) {
                    ForEach(manager.installedApps) { app in
                        InstalledAppRow(app: app)
                            .tag(app.id)
                            .contextMenu {
                                Button(action: { 
                                    appToUninstall = app.id
                                    showUninstallAlert = true
                                }) {
                                    Label("卸载", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .alert("确认卸载", isPresented: $showUninstallAlert) {
            Button("取消", role: .cancel) {
                appToUninstall = nil
            }
            Button("卸载", role: .destructive) {
                if let appId = appToUninstall {
                    uninstallApp(id: appId)
                }
            }
        } message: {
            if let appId = appToUninstall,
               let app = manager.installedApps.first(where: { $0.id == appId }) {
                Text("确定要卸载「\(app.name)」吗？")
            }
        }
    }
    
    private func uninstallApp(id: String) {
        Task {
            do {
                try await manager.uninstallApp(id: id)
            } catch {
                print("❌ [MicroAppInstalledView] 卸载失败: \(error.localizedDescription)")
            }
        }
    }
}

/// 已安装应用行
struct InstalledAppRow: View {
    let app: InstalledMicroApp
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标
            if let iconPath = app.iconPath,
               let image = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            
            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.headline)
                Text("版本 \(app.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

