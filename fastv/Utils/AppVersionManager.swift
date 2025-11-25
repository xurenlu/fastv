//
//  AppVersionManager.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// 应用版本管理器
struct AppVersionManager {
    /// 获取应用版本号（短版本，如 "1.0"）
    static var shortVersion: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return "未知版本"
        }
        return version
    }
    
    /// 获取构建版本号（如 "1"）
    static var buildVersion: String {
        guard let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return "未知构建"
        }
        return build
    }
    
    /// 获取完整版本号（如 "1.0 (1)"）
    static var fullVersion: String {
        return "\(shortVersion) (\(buildVersion))"
    }
    
    /// 获取应用名称
    static var appName: String {
        guard let name = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ??
                         Bundle.main.infoDictionary?["CFBundleName"] as? String else {
            return "妙打"
        }
        return name
    }
    
    /// 获取 Bundle ID
    static var bundleIdentifier: String {
        return Bundle.main.bundleIdentifier ?? "com.wxside.typecho"
    }
}








