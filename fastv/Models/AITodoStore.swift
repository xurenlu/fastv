//
//  AITodoStore.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// AI Todo 存储管理器
@MainActor
class AITodoStore: ObservableObject {
    static let shared = AITodoStore()
    
    @Published private(set) var activeTodos: [AITodoItem] = []
    @Published private(set) var archivedTodos: [AITodoItem] = []
    @Published private(set) var groups: [AITodoGroup] = []
    
    private let storageKey = "aiTodoItems"
    private let archiveKey = "aiTodoArchivedItems"
    private let groupsKey = "aiTodoGroups"
    private let autoArchiveDaysThreshold = 14 // 14天未完成自动归档
    private let autoArchiveCompletedDaysThreshold = 7 // 完成7天后归档
    
    private var saveTimer: Timer?
    private let saveDelay: TimeInterval = 1.0 // 延迟1秒保存，避免频繁写入
    
    private init() {
        loadTodos()
        loadGroups()
        initializeDefaultGroupsIfNeeded()
        // 启动时自动归档
        Task {
            await autoArchiveOldTodos()
        }
    }
    
    // MARK: - CRUD Operations
    
    /// 检查是否已存在某个提醒事项（通过 reminderIdentifier）
    func hasReminder(identifier: String) -> Bool {
        return activeTodos.contains { $0.reminderIdentifier == identifier } ||
               archivedTodos.contains { $0.reminderIdentifier == identifier }
    }
    
    /// 添加新的 Todo
    func add(_ todo: AITodoItem) {
        activeTodos.append(todo)
        scheduleSave()
    }
    
    /// 更新 Todo
    func update(_ todo: AITodoItem) {
        if let index = activeTodos.firstIndex(where: { $0.id == todo.id }) {
            activeTodos[index] = todo
            scheduleSave()
        } else if let index = archivedTodos.firstIndex(where: { $0.id == todo.id }) {
            archivedTodos[index] = todo
            scheduleSave()
        }
    }
    
    /// 删除 Todo
    func delete(_ todo: AITodoItem) {
        activeTodos.removeAll { $0.id == todo.id }
        archivedTodos.removeAll { $0.id == todo.id }
        scheduleSave()
    }
    
    /// 批量更新（用于 AI 解析后的批量操作）
    func batchUpdate(_ updates: [AITodoItem]) {
        for update in updates {
            if let index = activeTodos.firstIndex(where: { $0.id == update.id }) {
                activeTodos[index] = update
            } else if let index = archivedTodos.firstIndex(where: { $0.id == update.id }) {
                archivedTodos[index] = update
            }
        }
        scheduleSave()
    }
    
    /// 批量添加
    func batchAdd(_ todos: [AITodoItem]) {
        activeTodos.append(contentsOf: todos)
        scheduleSave()
    }
    
    /// 标记为完成
    func markAsCompleted(_ todo: AITodoItem) {
        if var updated = activeTodos.first(where: { $0.id == todo.id }) {
            updated.markAsCompleted()
            update(updated)
        }
    }
    
    /// 标记为待完成
    func markAsPending(_ todo: AITodoItem) {
        if var updated = activeTodos.first(where: { $0.id == todo.id }) {
            updated.markAsPending()
            update(updated)
        }
    }
    
    /// 归档
    func archive(_ todo: AITodoItem) {
        if var updated = activeTodos.first(where: { $0.id == todo.id }) {
            updated.archive()
            activeTodos.removeAll { $0.id == todo.id }
            archivedTodos.append(updated)
            scheduleSave()
        }
    }
    
    /// 恢复（从归档恢复）
    func restore(_ todo: AITodoItem) {
        if var updated = archivedTodos.first(where: { $0.id == todo.id }) {
            updated.restore()
            archivedTodos.removeAll { $0.id == todo.id }
            activeTodos.append(updated)
            scheduleSave()
        }
    }
    
    // MARK: - Auto Archive
    
    /// 自动归档旧的 Todo
    func autoArchiveOldTodos() async {
        var itemsToArchive: [AITodoItem] = []
        
        // 检查待完成项
        for todo in activeTodos {
            if todo.shouldAutoArchive(daysThreshold: autoArchiveDaysThreshold) {
                itemsToArchive.append(todo)
            }
        }
        
        // 检查已完成项
        for todo in activeTodos {
            if todo.shouldArchiveCompleted(daysThreshold: autoArchiveCompletedDaysThreshold) {
                itemsToArchive.append(todo)
            }
        }
        
        // 执行归档
        for todo in itemsToArchive {
            archive(todo)
        }
        
        if !itemsToArchive.isEmpty {
            print("📦 [AITodoStore] 自动归档了 \(itemsToArchive.count) 个 Todo")
        }
    }
    
    // MARK: - AI Context
    
    /// 获取用于 AI 上下文的活跃 Todo 列表（不包括归档项）
    func activeTodosForAIContext() -> [AITodoItem] {
        return activeTodos.filter { $0.status != .archived }
    }
    
    /// 将活跃 Todo 列表格式化为文本上下文
    func formatTodosAsContext() -> String {
        let todos = activeTodosForAIContext()
        guard !todos.isEmpty else {
            return "当前没有待办事项。"
        }
        
        var context = "当前待办事项列表：\n\n"
        for (index, todo) in todos.enumerated() {
            var itemText = "\(index + 1). [\(todo.priority.displayName)] \(todo.title)"
            
            if let description = todo.description, !description.isEmpty {
                itemText += "\n   描述: \(description)"
            }
            
            if let dueDate = todo.dueDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                itemText += "\n   截止时间: \(formatter.string(from: dueDate))"
            }
            
            itemText += "\n   状态: \(todo.status == .completed ? "已完成" : "待完成")"
            itemText += "\n   ID: \(todo.id.uuidString)"
            
            context += itemText + "\n\n"
        }
        
        return context
    }
    
    // MARK: - Group Management
    
    /// 获取指定优先级的所有分组（按 order 排序）
    func getGroups(for priority: AITodoPriority) -> [AITodoGroup] {
        return groups.filter { $0.priority == priority }.sorted { $0.order < $1.order }
    }
    
    /// 创建新分组
    func createGroup(name: String, priority: AITodoPriority) -> AITodoGroup {
        let existingGroups = getGroups(for: priority)
        let maxOrder = existingGroups.map { $0.order }.max() ?? -1
        let newGroup = AITodoGroup(
            name: name,
            priority: priority,
            order: maxOrder + 1
        )
        groups.append(newGroup)
        scheduleSaveGroups()
        return newGroup
    }
    
    /// 删除分组
    func deleteGroup(_ group: AITodoGroup) {
        // 将该分组下的所有事项移到第一个默认分组
        let defaultGroups = getDefaultGroups(for: group.priority)
        let targetGroupId = defaultGroups.first?.id
        
        for index in activeTodos.indices {
            if activeTodos[index].groupId == group.id {
                activeTodos[index].groupId = targetGroupId
            }
        }
        
        groups.removeAll { $0.id == group.id }
        scheduleSaveGroups()
        scheduleSave()
    }
    
    /// 更新分组
    func updateGroup(_ group: AITodoGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
            scheduleSaveGroups()
        }
    }
    
    /// 获取默认分组（待办、进行中、已完成）
    func getDefaultGroups(for priority: AITodoPriority) -> [AITodoGroup] {
        let existingGroups = getGroups(for: priority)
        if !existingGroups.isEmpty {
            return existingGroups
        }
        
        // 创建默认分组
        let defaultGroups = [
            AITodoGroup(name: "待办", priority: priority, order: 0),
            AITodoGroup(name: "进行中", priority: priority, order: 1),
            AITodoGroup(name: "已完成", priority: priority, order: 2)
        ]
        
        groups.append(contentsOf: defaultGroups)
        scheduleSaveGroups()
        return defaultGroups
    }
    
    /// 初始化默认分组（如果不存在）
    private func initializeDefaultGroupsIfNeeded() {
        for priority in AITodoPriority.allCases {
            let existingGroups = getGroups(for: priority)
            if existingGroups.isEmpty {
                _ = getDefaultGroups(for: priority)
            }
        }
    }
    
    /// 获取指定分组的事项
    func getTodos(for group: AITodoGroup) -> [AITodoItem] {
        return activeTodos.filter { $0.priority == group.priority && $0.groupId == group.id }
    }
    
    /// 将事项移动到指定分组
    func moveTodo(_ todo: AITodoItem, to group: AITodoGroup) {
        guard var updated = activeTodos.first(where: { $0.id == todo.id }) else { return }
        updated.groupId = group.id
        updated.updatedAt = Date()
        update(updated)
    }
    
    // MARK: - Persistence
    
    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.saveTodos()
            }
        }
    }
    
    private func saveTodos() {
        // 保存活跃项
        if let encoded = try? JSONEncoder().encode(activeTodos) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
        
        // 保存归档项
        if let encoded = try? JSONEncoder().encode(archivedTodos) {
            UserDefaults.standard.set(encoded, forKey: archiveKey)
        }
    }
    
    private func loadTodos() {
        // 加载活跃项
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([AITodoItem].self, from: data) {
            activeTodos = decoded
        }
        
        // 加载归档项
        if let data = UserDefaults.standard.data(forKey: archiveKey),
           let decoded = try? JSONDecoder().decode([AITodoItem].self, from: data) {
            archivedTodos = decoded
        }
    }
    
    private func scheduleSaveGroups() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.saveGroups()
            }
        }
    }
    
    private func saveGroups() {
        if let encoded = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(encoded, forKey: groupsKey)
        }
    }
    
    private func loadGroups() {
        if let data = UserDefaults.standard.data(forKey: groupsKey),
           let decoded = try? JSONDecoder().decode([AITodoGroup].self, from: data) {
            groups = decoded
        }
    }
}

