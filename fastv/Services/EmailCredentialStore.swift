//
//  EmailCredentialStore.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Security

/// 邮箱凭据存储服务（使用Keychain）
class EmailCredentialStore {
    static let shared = EmailCredentialStore()
    
    private let service = "com.fastv.email"
    
    private init() {}
    
    /// 保存密码
    func savePassword(accountId: UUID, password: String) throws {
        let accountIdString = accountId.uuidString
        let passwordData = password.data(using: .utf8)!
        
        // 删除旧密码（如果存在）
        deletePassword(accountId: accountId)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountIdString,
            kSecValueData as String: passwordData
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw EmailCredentialError.saveFailed(status)
        }
    }
    
    /// 获取密码
    func getPassword(accountId: UUID) throws -> String? {
        let accountIdString = accountId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountIdString,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw EmailCredentialError.readFailed(status)
        }
        
        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw EmailCredentialError.invalidData
        }
        
        return password
    }
    
    /// 删除密码
    func deletePassword(accountId: UUID) {
        let accountIdString = accountId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountIdString
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    /// 更新密码
    func updatePassword(accountId: UUID, password: String) throws {
        try savePassword(accountId: accountId, password: password)
    }
}

enum EmailCredentialError: Error {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case invalidData
    
    var localizedDescription: String {
        switch self {
        case .saveFailed(let status):
            return "保存密码失败: \(status)"
        case .readFailed(let status):
            return "读取密码失败: \(status)"
        case .invalidData:
            return "无效的密码数据"
        }
    }
}

