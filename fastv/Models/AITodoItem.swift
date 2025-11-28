//
//  AITodoItem.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// Todo 优先级（重要性和紧急性的组合）
enum AITodoPriority: String, Codable, CaseIterable {
    case importantUrgent = "important_urgent"      // 重要且紧急
    case importantNotUrgent = "important_not_urgent" // 重要但不紧急
    case notImportantUrgent = "not_important_urgent" // 不重要但紧急
    case notImportantNotUrgent = "not_important_not_urgent" // 不重要且不紧急
    
    var displayName: String {
        switch self {
        case .importantUrgent:
            return NSLocalizedString("todo.priority.important.urgent", comment: "重要且紧急")
        case .importantNotUrgent:
            return NSLocalizedString("todo.priority.important.not.urgent", comment: "重要但不紧急")
        case .notImportantUrgent:
            return NSLocalizedString("todo.priority.not.important.urgent", comment: "不重要但紧急")
        case .notImportantNotUrgent:
            return NSLocalizedString("todo.priority.not.important.not.urgent", comment: "不重要且不紧急")
        }
    }
    
    var isImportant: Bool {
        return self == .importantUrgent || self == .importantNotUrgent
    }
    
    var isUrgent: Bool {
        return self == .importantUrgent || self == .notImportantUrgent
    }
}

/// Todo 状态
enum AITodoStatus: String, Codable {
    case pending = "pending"      // 待完成
    case completed = "completed"  // 已完成
    case archived = "archived"    // 已归档
}

/// AI Todo 项
struct AITodoItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String?
    var priority: AITodoPriority
    var status: AITodoStatus
    var dueDate: Date?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var archivedAt: Date?
    /// 系统提醒事项的唯一标识符（用于避免重复导入）
    var reminderIdentifier: String?
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        priority: AITodoPriority = .notImportantNotUrgent,
        status: AITodoStatus = .pending,
        dueDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        archivedAt: Date? = nil,
        reminderIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.priority = priority
        self.status = status
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.archivedAt = archivedAt
        self.reminderIdentifier = reminderIdentifier
    }
    
    /// 标记为完成
    mutating func markAsCompleted() {
        status = .completed
        completedAt = Date()
        updatedAt = Date()
    }
    
    /// 标记为待完成
    mutating func markAsPending() {
        status = .pending
        completedAt = nil
        updatedAt = Date()
    }
    
    /// 归档
    mutating func archive() {
        status = .archived
        archivedAt = Date()
        updatedAt = Date()
    }
    
    /// 恢复（从归档状态恢复）
    mutating func restore() {
        status = .pending
        archivedAt = nil
        updatedAt = Date()
    }
    
    /// 检查是否过期（超过截止日期且未完成）
    var isOverdue: Bool {
        guard let dueDate = dueDate, status == .pending else {
            return false
        }
        return Date() > dueDate
    }
    
    /// 检查是否应该自动归档（太久未完成）
    func shouldAutoArchive(daysThreshold: Int = 14) -> Bool {
        guard status == .pending else { return false }
        let daysSinceCreation = Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
        return daysSinceCreation >= daysThreshold
    }
    
    /// 检查已完成项是否应该归档（完成太久）
    func shouldArchiveCompleted(daysThreshold: Int = 7) -> Bool {
        guard status == .completed, let completedAt = completedAt else { return false }
        let daysSinceCompletion = Calendar.current.dateComponents([.day], from: completedAt, to: Date()).day ?? 0
        return daysSinceCompletion >= daysThreshold
    }
}

