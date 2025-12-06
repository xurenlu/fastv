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
    
    private let appsDirectory: URL
    private let registryFile: URL
    
    private init() {
        // 使用 row1 作为应用标识
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appsDirectory = appSupport.appendingPathComponent("row1/MicroApps", isDirectory: true)
        registryFile = appSupport.appendingPathComponent("row1/installed.json")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: appsDirectory, withIntermediateDirectories: true)
        
        // 加载已安装应用列表
        loadInstalledApps()
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
        saveInstalledApps()
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
}

