//
//  MicroAppManifest.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation

/// Micro-App Manifest 模型
struct MicroAppManifest: Codable {
    let id: String
    let name: String
    let version: String
    let entry: String
    let icon: String?
    let permissions: [String]
    let minPlatformVersion: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case version
        case entry
        case icon
        case permissions
        case minPlatformVersion
    }
    
    /// 验证 manifest 是否有效
    func validate() -> Bool {
        guard !id.isEmpty,
              !name.isEmpty,
              !version.isEmpty,
              !entry.isEmpty else {
            return false
        }
        return true
    }
    
    /// 检查是否包含指定权限
    func hasPermission(_ permission: String) -> Bool {
        return permissions.contains(permission)
    }
}

/// 已安装的 Micro-App 信息
struct InstalledMicroApp: Codable, Identifiable {
    let id: String
    let name: String
    let version: String
    let iconPath: String?
    let installPath: String
    let installedAt: Date
}

/// Micro-App 错误
enum MicroAppError: LocalizedError {
    case invalidManifest
    case invalidZip
    case installationFailed(String)
    case uninstallationFailed(String)
    case appNotFound
    case permissionDenied(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidManifest:
            return "无效的应用清单文件"
        case .invalidZip:
            return "无效的应用包文件"
        case .installationFailed(let reason):
            return "安装失败: \(reason)"
        case .uninstallationFailed(let reason):
            return "卸载失败: \(reason)"
        case .appNotFound:
            return "应用未找到"
        case .permissionDenied(let permission):
            return "权限被拒绝: \(permission)"
        }
    }
}

