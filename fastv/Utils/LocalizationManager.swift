//
//  LocalizationManager.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import SwiftUI
import Combine

/// 多语言管理器
@MainActor
class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: String {
        didSet {
            UserPreferences.shared.defaultLanguage = currentLanguage
            setLanguage(currentLanguage)
        }
    }
    
    private init() {
        // 从UserPreferences加载语言设置
        currentLanguage = UserPreferences.shared.defaultLanguage
        setLanguage(currentLanguage)
    }
    
    /// 设置当前语言
    private func setLanguage(_ languageCode: String) {
        // 设置应用的语言环境
        UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }
    
    /// 获取本地化字符串
    func localizedString(_ key: String, comment: String = "") -> String {
        return NSLocalizedString(key, comment: comment)
    }
}

/// 支持的语言
enum SupportedLanguage: String, CaseIterable {
    case chinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"
    
    var displayName: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "English"
        case .japanese:
            return "日本語"
        }
    }
    
    var nativeName: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "English"
        case .japanese:
            return "日本語"
        }
    }
}

