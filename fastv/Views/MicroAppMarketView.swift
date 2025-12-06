//
//  MicroAppMarketView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation

/// 安装结果 Toast 提示
struct InstallResultToast: View {
    let successCount: Int
    let failCount: Int
    let isVisible: Bool
    
    var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                if failCount == 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if successCount == 0 {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    if successCount > 0 && failCount > 0 {
                        Text("安装完成")
                            .font(.headline)
                        Text("成功 \(successCount) 个，失败 \(failCount) 个")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if successCount > 0 {
                        Text("安装成功")
                            .font(.headline)
                        Text("已安装 \(successCount) 个应用")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("安装失败")
                            .font(.headline)
                        Text("全部 \(failCount) 个应用安装失败")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// Micro-App 市场视图
struct MicroAppMarketView: View {
    @StateObject private var manager = MicroAppManager.shared
    @State private var searchText = ""
    @State private var showURLDialog = false
    @State private var urlString = ""
    @State private var isInstalling = false
    @State private var errorMessage: String?
    
    // Toast 提示状态
    @State private var showInstallToast = false
    @State private var installSuccessCount = 0
    @State private var installFailCount = 0
    
    // 示例应用列表（后续可以从远程服务器加载）
    private var sampleApps: [SampleApp] {
        // 获取项目根目录的 examples 文件夹路径
        let examplesPath = getExamplesPath()
        return [
            SampleApp(
                id: "com.example.plant-care",
                name: "植物养护助手",
                description: "识别植物并提供养护建议",
                icon: "🌱",
                permissions: ["vision", "chat"],
                localPath: examplesPath
            )
        ]
    }
    
    /// 获取 examples 目录路径
    private func getExamplesPath() -> String? {
        // 尝试多种路径
        var possiblePaths: [String] = []
        
        // 开发环境：项目根目录
        possiblePaths.append((FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("examples/plant-care.microapp.zip"))
        
        // Bundle 资源路径
        if let resourcePath = Bundle.main.resourcePath {
            possiblePaths.append((resourcePath as NSString).appendingPathComponent("examples/plant-care.microapp.zip"))
        }
        
        // 绝对路径（如果知道项目位置）
        possiblePaths.append("/Users/rocky/Sites/fastv/examples/plant-care.microapp.zip")
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
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
        ZStack(alignment: .top) {
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
                    Button(action: selectLocalPackages) {
                        Label("安装本地包", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isInstalling)
                    
                    Button(action: { showURLDialog = true }) {
                        Label("输入URL安装", systemImage: "link")
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    if isInstalling {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("安装中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            
            // Toast 提示层
            InstallResultToast(
                successCount: installSuccessCount,
                failCount: installFailCount,
                isVisible: showInstallToast
            )
            .padding(.top, 60)
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
    
    /// 直接打开文件选择对话框安装本地包（支持多选）
    private func selectLocalPackages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择 .zip 格式的 MicroApp 应用包（可多选）"
        panel.prompt = "安装"
        
        panel.begin { response in
            if response == .OK {
                let urls = panel.urls
                if !urls.isEmpty {
                    installLocalPackages(from: urls)
                }
            }
        }
    }
    
    /// 批量安装本地包
    private func installLocalPackages(from urls: [URL]) {
        isInstalling = true
        errorMessage = nil
        
        Task {
            var successCount = 0
            var failCount = 0
            
            for url in urls {
                do {
                    _ = try await manager.installApp(from: url)
                    successCount += 1
                    print("✅ [MicroAppMarket] 安装成功: \(url.lastPathComponent)")
                } catch {
                    failCount += 1
                    print("❌ [MicroAppMarket] 安装失败: \(url.lastPathComponent) - \(error.localizedDescription)")
                }
            }
            
            await MainActor.run {
                isInstalling = false
                
                // 显示 Toast 提示
                installSuccessCount = successCount
                installFailCount = failCount
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showInstallToast = true
                }
                
                // 3秒后自动隐藏
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showInstallToast = false
                    }
                }
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
        guard !isInstalling && !isInstalled else { return }
        
        isInstalling = true
        
        Task { @MainActor in
            do {
                if let localPath = app.localPath, !localPath.isEmpty, FileManager.default.fileExists(atPath: localPath) {
                    // 从本地路径安装
                    let fileURL = URL(fileURLWithPath: localPath)
                    _ = try await manager.installApp(from: fileURL)
                    print("✅ [AppCard] 安装成功: \(app.name)")
                } else if let downloadURL = app.downloadURL, !downloadURL.isEmpty {
                    // 从 URL 下载安装
                    _ = try await manager.installApp(from: downloadURL)
                    print("✅ [AppCard] 从 URL 安装成功: \(app.name)")
                } else {
                    // 尝试查找文件
                    let possiblePaths = [
                        (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("examples/plant-care.microapp.zip"),
                        Bundle.main.resourcePath?.appending("/examples/plant-care.microapp.zip") ?? "",
                        "/Users/rocky/Sites/fastv/examples/plant-care.microapp.zip"
                    ]
                    
                    var found = false
                    for path in possiblePaths {
                        if FileManager.default.fileExists(atPath: path) {
                            let fileURL = URL(fileURLWithPath: path)
                            _ = try await manager.installApp(from: fileURL)
                            print("✅ [AppCard] 从路径安装成功: \(path)")
                            found = true
                            break
                        }
                    }
                    
                    if !found {
                        throw NSError(domain: "MicroAppMarket", code: -1, userInfo: [NSLocalizedDescriptionKey: "找不到应用包文件，请使用「安装本地包」手动选择文件"])
                    }
                }
                
                // 安装成功
                isInstalling = false
            } catch {
                isInstalling = false
                print("❌ [AppCard] 安装失败: \(error.localizedDescription)")
                // 显示错误提示
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "安装失败"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "确定")
                    alert.runModal()
                }
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

/// 示例应用模型
struct SampleApp: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let permissions: [String]
    let localPath: String? // 本地文件路径（用于示例应用）
    let downloadURL: String? // 下载 URL（用于远程应用）
    
    init(id: String, name: String, description: String, icon: String, permissions: [String], localPath: String? = nil, downloadURL: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.permissions = permissions
        self.localPath = localPath
        self.downloadURL = downloadURL
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

