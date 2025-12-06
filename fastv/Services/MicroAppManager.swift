//
//  MicroAppManager.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import AppKit
import Combine

/// Micro-App 管理器
@MainActor
class MicroAppManager: ObservableObject {
    static let shared = MicroAppManager()
    
    @Published var installedApps: [InstalledMicroApp] = []
    @Published var runningApps: Set<String> = []
    @Published var pinnedApps: Set<String> = []
    @Published var lastUsedApps: [String: Date] = [:]
    
    private let appsDirectory: URL
    private let registryFile: URL
    private let pinnedAppsFile: URL
    private let lastUsedAppsFile: URL
    
    private init() {
        // 使用 row1 作为应用标识
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appsDirectory = appSupport.appendingPathComponent("row1/MicroApps", isDirectory: true)
        registryFile = appSupport.appendingPathComponent("row1/installed.json")
        pinnedAppsFile = appSupport.appendingPathComponent("row1/pinned.json")
        lastUsedAppsFile = appSupport.appendingPathComponent("row1/lastUsed.json")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: appsDirectory, withIntermediateDirectories: true)
        
        // 加载已安装应用列表
        loadInstalledApps()
        
        // 加载固定的应用列表
        loadPinnedApps()
        
        // 加载最后使用时间
        loadLastUsedApps()
    }
    
    /// 加载已安装应用列表
    private func loadInstalledApps() {
        guard FileManager.default.fileExists(atPath: registryFile.path),
              let data = try? Data(contentsOf: registryFile),
              let apps = try? JSONDecoder().decode([InstalledMicroApp].self, from: data) else {
            installedApps = []
            return
        }
        installedApps = apps
    }
    
    /// 保存已安装应用列表
    private func saveInstalledApps() {
        guard let data = try? JSONEncoder().encode(installedApps) else { return }
        try? data.write(to: registryFile)
    }
    
    /// 加载固定的应用列表
    private func loadPinnedApps() {
        guard FileManager.default.fileExists(atPath: pinnedAppsFile.path),
              let data = try? Data(contentsOf: pinnedAppsFile),
              let pinnedIds = try? JSONDecoder().decode([String].self, from: data) else {
            pinnedApps = []
            return
        }
        pinnedApps = Set(pinnedIds)
    }
    
    /// 保存固定的应用列表
    private func savePinnedApps() {
        let pinnedIds = Array(pinnedApps)
        guard let data = try? JSONEncoder().encode(pinnedIds) else { return }
        try? data.write(to: pinnedAppsFile)
    }
    
    /// 加载最后使用时间
    private func loadLastUsedApps() {
        guard FileManager.default.fileExists(atPath: lastUsedAppsFile.path),
              let data = try? Data(contentsOf: lastUsedAppsFile) else {
            lastUsedApps = [:]
            return
        }
        
        // 使用时间戳格式解码
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        
        if let lastUsed = try? decoder.decode([String: Date].self, from: data) {
            lastUsedApps = lastUsed
        } else {
            lastUsedApps = [:]
        }
    }
    
    /// 保存最后使用时间
    private func saveLastUsedApps() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        
        guard let data = try? encoder.encode(lastUsedApps) else { return }
        try? data.write(to: lastUsedAppsFile)
    }
    
    /// 安装应用（从本地 zip 文件）
    func installApp(from zipURL: URL) async throws -> InstalledMicroApp {
        // 读取 zip 文件
        guard let zipData = try? Data(contentsOf: zipURL) else {
            throw MicroAppError.invalidZip
        }
        
        return try await installApp(from: zipData)
    }
    
    /// 安装应用（从 zip 数据）
    func installApp(from zipData: Data) async throws -> InstalledMicroApp {
        // 创建临时目录
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // 解压 zip
        let zipURL = tempDir.appendingPathComponent("app.zip")
        try zipData.write(to: zipURL)
        
        let unzipDir = tempDir.appendingPathComponent("unzipped")
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
        
        // 使用系统命令解压（macOS 自带 unzip）
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipURL.path, "-d", unzipDir.path]
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw MicroAppError.invalidZip
        }
        
        // 读取 manifest.json
        let manifestURL = unzipDir.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(MicroAppManifest.self, from: manifestData),
              manifest.validate() else {
            throw MicroAppError.invalidManifest
        }
        
        // 检查是否已安装
        if installedApps.contains(where: { $0.id == manifest.id }) {
            // 卸载旧版本
            try await uninstallApp(id: manifest.id)
        }
        
        // 复制到应用目录
        let appDir = appsDirectory.appendingPathComponent(manifest.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: appDir.path) {
            try FileManager.default.removeItem(at: appDir)
        }
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        // 复制所有文件
        let contents = try FileManager.default.contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil)
        for item in contents {
            let dest = appDir.appendingPathComponent(item.lastPathComponent)
            try FileManager.default.copyItem(at: item, to: dest)
        }
        
        // 创建已安装应用记录
        let iconPath = manifest.icon != nil ? appDir.appendingPathComponent(manifest.icon!).path : nil
        let installedApp = InstalledMicroApp(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            iconPath: iconPath,
            installPath: appDir.path,
            installedAt: Date()
        )
        
        installedApps.append(installedApp)
        saveInstalledApps()
        
        return installedApp
    }
    
    /// 从 URL 安装应用
    func installApp(from urlString: String) async throws -> InstalledMicroApp {
        guard let url = URL(string: urlString) else {
            throw MicroAppError.invalidZip
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return try await installApp(from: data)
    }
    
    /// 卸载应用
    func uninstallApp(id: String) async throws {
        guard let app = installedApps.first(where: { $0.id == id }) else {
            throw MicroAppError.appNotFound
        }
        
        let appDir = URL(fileURLWithPath: app.installPath)
        if FileManager.default.fileExists(atPath: appDir.path) {
            try FileManager.default.removeItem(at: appDir)
        }
        
        installedApps.removeAll { $0.id == id }
        runningApps.remove(id)
        pinnedApps.remove(id)
        saveInstalledApps()
        savePinnedApps()
    }
    
    /// 获取应用 manifest
    func getManifest(for appId: String) throws -> MicroAppManifest {
        guard let app = installedApps.first(where: { $0.id == appId }) else {
            throw MicroAppError.appNotFound
        }
        
        let manifestURL = URL(fileURLWithPath: app.installPath).appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(MicroAppManifest.self, from: data) else {
            throw MicroAppError.invalidManifest
        }
        
        return manifest
    }
    
    /// 获取应用入口 URL
    func getEntryURL(for appId: String) throws -> URL {
        let manifest = try getManifest(for: appId)
        guard let app = installedApps.first(where: { $0.id == appId }) else {
            throw MicroAppError.appNotFound
        }
        
        let appDir = URL(fileURLWithPath: app.installPath)
        let entryURL = appDir.appendingPathComponent(manifest.entry)
        
        guard FileManager.default.fileExists(atPath: entryURL.path) else {
            throw MicroAppError.invalidManifest
        }
        
        return entryURL
    }
    
    /// 启动应用（运行）
    func launchApp(id: String) {
        guard installedApps.contains(where: { $0.id == id }) else {
            print("⚠️ [MicroAppManager] 应用不存在: \(id)")
            return
        }
        runningApps.insert(id)
        updateLastUsedTime(for: id)
        print("✅ [MicroAppManager] 启动应用: \(id)")
    }
    
    /// 更新应用的最后使用时间
    func updateLastUsedTime(for id: String) {
        lastUsedApps[id] = Date()
        saveLastUsedApps()
    }
    
    /// 获取应用的最后使用时间
    func getLastUsedTime(for id: String) -> Date? {
        return lastUsedApps[id]
    }
    
    /// 关闭应用
    func closeApp(id: String) {
        runningApps.remove(id)
        print("🛑 [MicroAppManager] 关闭应用: \(id)")
    }
    
    /// 固定应用到侧边栏
    func pinApp(id: String) {
        guard installedApps.contains(where: { $0.id == id }) else {
            print("⚠️ [MicroAppManager] 应用不存在: \(id)")
            return
        }
        pinnedApps.insert(id)
        savePinnedApps()
        print("📌 [MicroAppManager] 固定应用: \(id)")
    }
    
    /// 取消固定应用
    func unpinApp(id: String) {
        pinnedApps.remove(id)
        savePinnedApps()
        print("📌 [MicroAppManager] 取消固定应用: \(id)")
    }
    
    /// 检查应用是否正在运行
    func isRunning(id: String) -> Bool {
        return runningApps.contains(id)
    }
    
    /// 检查应用是否已固定
    func isPinned(id: String) -> Bool {
        return pinnedApps.contains(id)
    }
    
    /// 检查应用是否应该在侧边栏显示（运行中或已固定）
    func shouldShowInSidebar(id: String) -> Bool {
        return runningApps.contains(id) || pinnedApps.contains(id)
    }
}

