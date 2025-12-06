//
//  MicroAppMarketView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI
import UniformTypeIdentifiers

/// Micro-App 市场视图
struct MicroAppMarketView: View {
    @StateObject private var manager = MicroAppManager.shared
    @State private var searchText = ""
    @State private var showInstallDialog = false
    @State private var showURLDialog = false
    @State private var urlString = ""
    @State private var isInstalling = false
    @State private var errorMessage: String?
    
    // 示例应用列表（后续可以从远程服务器加载）
    private let sampleApps: [SampleApp] = [
        SampleApp(
            id: "com.example.plant-care",
            name: "植物养护助手",
            description: "识别植物并提供养护建议",
            icon: "🌱",
            permissions: ["vision", "chat"]
        )
    ]
    
    var filteredApps: [SampleApp] {
        if searchText.isEmpty {
            return sampleApps
        }
        return sampleApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.description.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
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
                        AppCard(app: app, isInstalled: manager.installedApps.contains { $0.id == app.id })
                    }
                }
                .padding(16)
            }
            
            // 底部操作栏
            HStack(spacing: 16) {
                Button(action: { showInstallDialog = true }) {
                    Label("安装本地包", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                
                Button(action: { showURLDialog = true }) {
                    Label("输入URL安装", systemImage: "link")
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            .padding(16)
        }
        .sheet(isPresented: $showInstallDialog) {
            InstallLocalPackageView()
        }
        .sheet(isPresented: $showURLDialog) {
            InstallURLPackageView()
        }
        .alert("错误", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }
}

/// 应用卡片
struct AppCard: View {
    let app: SampleApp
    let isInstalled: Bool
    @StateObject private var manager = MicroAppManager.shared
    @State private var isInstalling = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 图标和标题
            HStack(spacing: 12) {
                Text(app.icon)
                    .font(.system(size: 48))
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.headline)
                    Text(app.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            
            // 权限标签
            if !app.permissions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(app.permissions, id: \.self) { permission in
                        Text(permissionLabel(permission))
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
            
            // 安装按钮
            Button(action: installApp) {
                HStack {
                    if isInstalling {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: isInstalled ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                    }
                    Text(isInstalled ? "已安装" : "安装")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isInstalling || isInstalled)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func installApp() {
        isInstalling = true
        Task {
            // 这里应该从实际的应用源下载，暂时使用占位逻辑
            // 实际实现中，sampleApps 应该包含下载 URL
            isInstalling = false
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

/// 示例应用模型
struct SampleApp: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let permissions: [String]
}

/// 安装本地包视图
struct InstallLocalPackageView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var manager = MicroAppManager.shared
    @State private var isInstalling = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("安装本地应用包")
                .font(.headline)
            
            Text("选择一个 .zip 格式的应用包文件")
                .font(.body)
                .foregroundStyle(.secondary)
            
            Button(action: selectFile) {
                Label("选择文件", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isInstalling)
            
            if isInstalling {
                ProgressView("安装中...")
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(40)
        .frame(width: 400)
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                installApp(from: url)
            }
        }
    }
    
    private func installApp(from url: URL) {
        isInstalling = true
        errorMessage = nil
        
        Task {
            do {
                _ = try await manager.installApp(from: url)
                await MainActor.run {
                    isInstalling = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isInstalling = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

/// 安装 URL 包视图
struct InstallURLPackageView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var manager = MicroAppManager.shared
    @State private var urlString = ""
    @State private var isInstalling = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("从 URL 安装应用")
                .font(.headline)
            
            TextField("输入应用包 URL", text: $urlString)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Button("取消", role: .cancel) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("安装") {
                    installApp()
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlString.isEmpty || isInstalling)
            }
            
            if isInstalling {
                ProgressView("安装中...")
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(40)
        .frame(width: 500)
    }
    
    private func installApp() {
        guard !urlString.isEmpty else { return }
        
        isInstalling = true
        errorMessage = nil
        
        Task {
            do {
                _ = try await manager.installApp(from: urlString)
                await MainActor.run {
                    isInstalling = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isInstalling = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

