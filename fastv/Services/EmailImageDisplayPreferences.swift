//
//  EmailImageDisplayPreferences.swift
//  fastv
//
//  Created by rocky on 2025/12/01.
//

import Foundation

/// 邮件图片显示偏好管理服务
@MainActor
class EmailImageDisplayPreferences {
    static let shared = EmailImageDisplayPreferences()
    
    private let defaults = UserDefaults.standard
    private let preferencesKey = "emailImageDisplayPreferences"
    
    // 存储结构: [邮箱地址或域名: 是否显示图片]
    private var preferences: [String: Bool] {
        get {
            if let data = defaults.data(forKey: preferencesKey),
               let dict = try? JSONDecoder().decode([String: Bool].self, from: data) {
                return dict
            }
            return [:]
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: preferencesKey)
            }
        }
    }
    
    private init() {}
    
    /// 从邮箱地址提取域名
    /// - Parameter email: 邮箱地址，如 "hello@remotive.com"
    /// - Returns: 域名，如 "remotive.com"，如果无法提取则返回 nil
    func getDomain(from email: String) -> String? {
        guard let atIndex = email.firstIndex(of: "@") else {
            return nil
        }
        let domain = String(email[email.index(after: atIndex)...])
        return domain.isEmpty ? nil : domain.lowercased()
    }
    
    /// 检查是否应该显示图片
    /// - Parameter sender: 发件人信息
    /// - Returns: 如果已记住偏好则返回偏好值，否则返回 nil（需要用户选择）
    func shouldShowImages(for sender: EmailContact) -> Bool? {
        let email = sender.email.lowercased()
        
        // 优先检查发件人邮箱地址
        if let preference = preferences[email] {
            return preference
        }
        
        // 如果没有，检查域名
        if let domain = getDomain(from: email),
           let preference = preferences[domain] {
            return preference
        }
        
        // 没有记住的偏好
        return nil
    }
    
    /// 设置并记住图片显示偏好
    /// - Parameters:
    ///   - show: 是否显示图片
    ///   - sender: 发件人信息
    ///   - remember: 是否记住此选择
    func setShowImages(_ show: Bool, for sender: EmailContact, remember: Bool) {
        let email = sender.email.lowercased()
        
        if remember {
            var updatedPreferences = preferences
            
            // 优先按发件人邮箱地址存储
            updatedPreferences[email] = show
            
            // 如果用户希望按域名记住，也存储域名偏好
            // 但邮箱地址的优先级更高
            if let domain = getDomain(from: email) {
                // 只有当域名没有其他发件人的偏好时，才设置域名偏好
                // 这里简化处理：如果记住，同时设置域名偏好
                // 但查询时会优先使用邮箱地址
                updatedPreferences[domain] = show
            }
            
            preferences = updatedPreferences
        }
    }
    
    /// 清除某个发件人或域名的偏好设置
    /// - Parameter sender: 发件人信息
    func clearPreference(for sender: EmailContact) {
        let email = sender.email.lowercased()
        var updatedPreferences = preferences
        updatedPreferences.removeValue(forKey: email)
        
        if let domain = getDomain(from: email) {
            updatedPreferences.removeValue(forKey: domain)
        }
        
        preferences = updatedPreferences
    }
    
    /// 清除所有偏好设置
    func clearAllPreferences() {
        preferences = [:]
    }
}

