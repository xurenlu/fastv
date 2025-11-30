//
//  LocalWebResourceManager.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// 本地 Web 资源管理器
/// 负责管理打包在应用内的 JS/CSS 资源文件
class LocalWebResourceManager: ObservableObject {
    static let shared = LocalWebResourceManager()
    
    private init() {}
    
    // MARK: - 本地资源路径配置
    
    /// WebLibs 资源目录路径
    private let webLibsPath = "WebLibs"
    
    /// 获取本地资源文件的内容
    func getLocalResourceContent(path: String) -> String? {
        // 支持传入相对路径（例如 "katex/katex.min.js" 或 "prism/components/prism-core.min.js"）
        var normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // 如果传入路径已包含 WebLibs/ 前缀，则去掉，避免双重拼接
        if normalizedPath.hasPrefix("\(webLibsPath)/") {
            normalizedPath = String(normalizedPath.dropFirst(webLibsPath.count + 1))
        }
        let fileName = (normalizedPath as NSString).lastPathComponent
        let subDir = (normalizedPath as NSString).deletingLastPathComponent

        // 构造候选查找策略，兼容：
        // 1) WebLibs 作为文件夹引用（蓝色文件夹，保留层级）
        // 2) WebLibs 作为普通分组（黄色文件夹，资源被扁平复制到 Bundle）
        var candidatePaths: [String?] = []
        // a) WebLibs/子目录
        let inDirWithSub = subDir.isEmpty ? webLibsPath : "\(webLibsPath)/\(subDir)"
        candidatePaths.append(Bundle.main.path(forResource: fileName, ofType: nil, inDirectory: inDirWithSub))
        // b) 仅在 WebLibs 根目录下查找
        candidatePaths.append(Bundle.main.path(forResource: fileName, ofType: nil, inDirectory: webLibsPath))
        // c) 在整个 Bundle 范围内查找（适配被扁平化复制的情况）
        candidatePaths.append(Bundle.main.path(forResource: fileName, ofType: nil))
        // d) 直接用 URL 拼接（仅当 WebLibs 为文件夹引用时有效）
        if let baseURL = Bundle.main.resourceURL {
            let url = baseURL.appendingPathComponent(webLibsPath).appendingPathComponent(normalizedPath)
            if FileManager.default.fileExists(atPath: url.path) {
                candidatePaths.append(url.path)
            }
        }

        // 取第一个有效路径
        if let foundPath = candidatePaths.compactMap({ $0 }).first {
            if let content = try? String(contentsOfFile: foundPath, encoding: .utf8) {
                print("✅ 成功读取本地资源: \(normalizedPath) (大小: \(content.count) 字符)")
                return content
            } else {
                print("❌ 本地资源存在但读取失败(编码/权限): \(normalizedPath) → \(foundPath)")
                return nil
            }
        }

        print("❌ 无法读取本地资源: \(normalizedPath) — 未在 Bundle 中找到匹配文件")
        return nil
    }
    
    /// 检查本地资源是否存在
    func isLocalResourceAvailable(path: String) -> Bool {
        var normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.hasPrefix("\(webLibsPath)/") {
            normalizedPath = String(normalizedPath.dropFirst(webLibsPath.count + 1))
        }
        let fileName = (normalizedPath as NSString).lastPathComponent
        let subDir = (normalizedPath as NSString).deletingLastPathComponent

        let inDirWithSub = subDir.isEmpty ? webLibsPath : "\(webLibsPath)/\(subDir)"
        if Bundle.main.path(forResource: fileName, ofType: nil, inDirectory: inDirWithSub) != nil { return true }
        if Bundle.main.path(forResource: fileName, ofType: nil, inDirectory: webLibsPath) != nil { return true }
        if Bundle.main.path(forResource: fileName, ofType: nil) != nil { return true }
        if let baseURL = Bundle.main.resourceURL {
            let url = baseURL.appendingPathComponent(webLibsPath).appendingPathComponent(normalizedPath)
            if FileManager.default.fileExists(atPath: url.path) { return true }
        }
        return false
    }
    
    // MARK: - KaTeX 本地资源
    
    /// 获取 KaTeX CSS 内容
    func getKaTeXCSS() -> String? {
        return getLocalResourceContent(path: "katex/katex.min.css")
    }
    
    /// 获取 KaTeX JS 内容
    func getKaTeXJS() -> String? {
        return getLocalResourceContent(path: "katex/katex.min.js")
    }
    
    /// 获取 KaTeX Auto-render JS 内容
    func getKaTeXAutoRenderJS() -> String? {
        return getLocalResourceContent(path: "katex/auto-render.min.js")
    }
}

