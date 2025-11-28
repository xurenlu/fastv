//
//  RemindersSyncService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import EventKit

/// 提醒事项同步服务
@MainActor
class RemindersSyncService {
    static let shared = RemindersSyncService()
    
    private let eventStore = EKEventStore()
    private var hasRequestedAccess = false
    
    private init() {}
    
    /// 请求访问提醒事项的权限
    func requestAccess() async throws -> Bool {
        print("📋 [RemindersSyncService] 请求访问提醒事项权限")
        
        let status = EKEventStore.authorizationStatus(for: .reminder)
        
        if hasReminderAccess(status: status) {
            print("✅ [RemindersSyncService] 已授权访问提醒事项")
            return true
        }
        
        switch status {
        case .notDetermined, .restricted:
            print("📋 [RemindersSyncService] 权限未确定，请求权限...")
            if #available(macOS 14.0, *) {
                return try await withCheckedThrowingContinuation { continuation in
                    eventStore.requestFullAccessToReminders { granted, error in
                        if let error = error {
                            print("❌ [RemindersSyncService] 请求权限失败: \(error)")
                            continuation.resume(throwing: RemindersSyncError.syncFailed(error.localizedDescription))
                        } else if granted {
                            print("✅ [RemindersSyncService] 用户授权访问提醒事项（Full Access）")
                            continuation.resume(returning: true)
                        } else {
                            print("❌ [RemindersSyncService] 用户拒绝访问提醒事项（Full Access）")
                            continuation.resume(throwing: RemindersSyncError.permissionDenied)
                        }
                    }
                }
            } else {
                return try await withCheckedThrowingContinuation { continuation in
                    eventStore.requestAccess(to: .reminder) { granted, error in
                        if let error = error {
                            print("❌ [RemindersSyncService] 请求权限失败: \(error)")
                            continuation.resume(throwing: RemindersSyncError.syncFailed(error.localizedDescription))
                        } else if granted {
                            print("✅ [RemindersSyncService] 用户授权访问提醒事项")
                            continuation.resume(returning: true)
                        } else {
                            print("❌ [RemindersSyncService] 用户拒绝访问提醒事项")
                            continuation.resume(throwing: RemindersSyncError.permissionDenied)
                        }
                    }
                }
            }
        case .denied:
            print("❌ [RemindersSyncService] 提醒事项权限被拒绝")
            throw RemindersSyncError.permissionDenied
        default:
            print("❌ [RemindersSyncService] 未知的权限状态: \(status.rawValue)")
            throw RemindersSyncError.unknownError
        }
    }
    
    /// 检查权限状态
    func checkAuthorizationStatus() -> Bool {
        return hasReminderAccess(status: EKEventStore.authorizationStatus(for: .reminder))
    }
    
    private func hasReminderAccess(status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess:
                return true
            case .authorized:
                // 某些系统仍然返回 .authorized
                return true
            default:
                return false
            }
        } else {
            return status == .authorized
        }
    }
    
    /// 从系统提醒事项同步数据
    /// - Returns: 同步的 Todo 项列表
    func syncFromReminders() async throws -> [AITodoItem] {
        print("📋 [RemindersSyncService] 开始从系统提醒事项同步")
        
        // 检查权限
        guard checkAuthorizationStatus() else {
            throw RemindersSyncError.permissionDenied
        }
        
        // 获取所有提醒事项列表
        let calendars = eventStore.calendars(for: .reminder)
        print("📋 [RemindersSyncService] 找到 \(calendars.count) 个提醒事项列表")
        
        // 获取所有未完成的提醒事项
        let predicate = eventStore.predicateForReminders(in: calendars)
        let reminders = try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders)
            }
        }
        
        guard let reminders = reminders else {
            print("⚠️ [RemindersSyncService] 未获取到提醒事项")
            return []
        }
        
        // 过滤出未完成的提醒事项
        let incompleteReminders = reminders.filter { !$0.isCompleted }
        print("📋 [RemindersSyncService] 找到 \(incompleteReminders.count) 个未完成的提醒事项")
        
        // 转换为 AITodoItem
        var todos: [AITodoItem] = []
        
        for reminder in incompleteReminders {
            // 跳过空标题的提醒事项
            guard let title = reminder.title, !title.isEmpty else {
                continue
            }
            
            // 确定优先级
            var priority: AITodoPriority = .notImportantNotUrgent
            
            // 检查优先级（EKReminder 的 priority 是 0-9，0 是最高优先级）
            let hasDueDate = reminder.dueDateComponents != nil
            if reminder.priority == 0 {
                // 高优先级
                priority = hasDueDate ? .importantUrgent : .importantNotUrgent
            } else {
                // 普通优先级
                priority = hasDueDate ? .notImportantUrgent : .notImportantNotUrgent
            }
            
            // 获取截止日期
            var dueDate: Date? = nil
            if let dueDateComponents = reminder.dueDateComponents {
                dueDate = Calendar.current.date(from: dueDateComponents)
            }
            
            // 创建 Todo 项，保存提醒事项的唯一标识符
            let todo = AITodoItem(
                title: title,
                description: reminder.notes,
                priority: priority,
                status: .pending,
                dueDate: dueDate,
                createdAt: reminder.creationDate ?? Date(),
                updatedAt: reminder.lastModifiedDate ?? Date(),
                reminderIdentifier: reminder.calendarItemIdentifier
            )
            
            todos.append(todo)
        }
        
        print("✅ [RemindersSyncService] 成功同步 \(todos.count) 个 Todo 项")
        return todos
    }
    
    /// 获取所有提醒事项列表的名称
    func getReminderListNames() async throws -> [String] {
        guard checkAuthorizationStatus() else {
            throw RemindersSyncError.permissionDenied
        }
        
        let calendars = eventStore.calendars(for: .reminder)
        return calendars.map { $0.title }
    }
}

/// 提醒事项同步错误
enum RemindersSyncError: LocalizedError {
    case permissionDenied
    case unknownError
    case syncFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "需要访问提醒事项的权限。请在系统设置 > 隐私与安全性 > 提醒事项中授权。"
        case .unknownError:
            return "未知错误"
        case .syncFailed(let message):
            return "同步失败: \(message)"
        }
    }
}

