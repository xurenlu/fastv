//
//  EmailNotificationService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import UserNotifications
import AppKit

/// 邮件通知服务
@MainActor
class EmailNotificationService {
    static let shared = EmailNotificationService()
    
    private let preferences = UserPreferences.shared
    
    private init() {
        requestAuthorizationIfNeeded()
    }
    
    /// 请求通知权限
    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error = error {
                        print("❌ [EmailNotificationService] 请求通知权限失败: \(error)")
                    } else if granted {
                        print("✅ [EmailNotificationService] 通知权限已授予")
                    }
                }
            }
        }
    }
    
    /// 发送新邮件通知
    func notifyNewEmail(_ message: EmailMessage) {
        // 检查是否启用通知
        guard preferences.emailNotificationsEnabled else {
            return
        }
        
        // 检查是否已读（避免重复通知）
        guard !message.isRead else {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = message.from.displayName
        content.body = message.subject.isEmpty ? message.preview : message.subject
        content.sound = .default
        content.userInfo = [
            "messageId": message.id.uuidString,
            "accountId": message.accountId.uuidString,
            "folderId": message.folderId?.uuidString ?? ""
        ]
        
        // 设置分类标识符（用于操作按钮）
        content.categoryIdentifier = "EMAIL_NOTIFICATION"
        
        let request = UNNotificationRequest(
            identifier: message.id.uuidString,
            content: content,
            trigger: nil // 立即发送
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ [EmailNotificationService] 发送通知失败: \(error)")
            }
        }
    }
    
    /// 注册通知分类（用于操作按钮）
    func registerNotificationCategories() {
        let markAsReadAction = UNNotificationAction(
            identifier: "MARK_AS_READ",
            title: "标记为已读",
            options: []
        )
        
        let replyAction = UNNotificationAction(
            identifier: "REPLY",
            title: "回复",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "EMAIL_NOTIFICATION",
            actions: [markAsReadAction, replyAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

