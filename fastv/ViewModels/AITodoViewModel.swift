//
//  AITodoViewModel.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// Todo 视图模式
enum TodoViewMode: String, CaseIterable {
    case list = "list"              // 列表模式
    case quadrant = "quadrant"      // 四象限模式
    
    var displayName: String {
        switch self {
        case .list:
            return NSLocalizedString("todo.view.mode.list", comment: "列表模式")
        case .quadrant:
            return NSLocalizedString("todo.view.mode.quadrant", comment: "四象限模式")
        }
    }
    
    var icon: String {
        switch self {
        case .list:
            return "list.bullet"
        case .quadrant:
            return "square.grid.2x2"
        }
    }
}

/// AI Todo ViewModel
@MainActor
class AITodoViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var isRecording: Bool = false
    @Published var isProcessingAI: Bool = false
    @Published var aiErrorMessage: String?
    @Published var aiSuccessMessage: String?
    @Published var viewMode: TodoViewMode = .quadrant
    @Published var showCompletedTodos: Bool = false
    
    private let store = AITodoStore.shared
    private let aiService = AITodoAIService.shared
    private let voiceService = VoiceInputService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // 订阅 store 的变化，确保当 store 更新时，视图能够刷新
        store.$activeTodos
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        store.$archivedTodos
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    var activeTodos: [AITodoItem] {
        store.activeTodos
    }
    
    var visibleActiveTodos: [AITodoItem] {
        store.activeTodos.filter { showCompletedTodos || $0.status != .completed }
    }
    
    var archivedTodos: [AITodoItem] {
        store.archivedTodos
    }
    
    // MARK: - Quadrant Data
    
    /// 获取指定优先级的活跃 Todo
    func activeTodos(forPriority priority: AITodoPriority) -> [AITodoItem] {
        visibleActiveTodos.filter { $0.priority == priority }
    }
    
    /// 重要且紧急
    var importantUrgentTodos: [AITodoItem] {
        activeTodos(forPriority: .importantUrgent)
    }
    
    /// 重要但不紧急
    var importantNotUrgentTodos: [AITodoItem] {
        activeTodos(forPriority: .importantNotUrgent)
    }
    
    /// 不重要但紧急
    var notImportantUrgentTodos: [AITodoItem] {
        activeTodos(forPriority: .notImportantUrgent)
    }
    
    /// 不重要且不紧急
    var notImportantNotUrgentTodos: [AITodoItem] {
        activeTodos(forPriority: .notImportantNotUrgent)
    }
    
    // MARK: - View Mode
    
    func toggleViewMode() {
        viewMode = viewMode == .list ? .quadrant : .list
    }
    
    // MARK: - Basic CRUD
    
    func addTodo(title: String, description: String? = nil, priority: AITodoPriority = .notImportantNotUrgent, dueDate: Date? = nil) {
        // 确保该优先级有默认分组
        let defaultGroups = store.getDefaultGroups(for: priority)
        let defaultGroupId = defaultGroups.first?.id
        
        let todo = AITodoItem(
            title: title,
            description: description,
            priority: priority,
            dueDate: dueDate,
            groupId: defaultGroupId
        )
        store.add(todo)
    }
    
    func deleteTodo(_ todo: AITodoItem) {
        store.delete(todo)
    }
    
    func toggleTodoCompletion(_ todo: AITodoItem) {
        if todo.status == .completed {
            store.markAsPending(todo)
        } else {
            store.markAsCompleted(todo)
        }
    }
    
    func updateTodoPriority(_ todo: AITodoItem, priority: AITodoPriority) {
        print("🔄 [AITodoViewModel] updateTodoPriority 被调用")
        print("   Todo ID: \(todo.id)")
        print("   当前优先级: \(todo.priority.displayName)")
        print("   新优先级: \(priority.displayName)")
        
        var updated = todo
        updated.priority = priority
        updated.updatedAt = Date()
        
        print("   更新后的 todo priority: \(updated.priority.displayName)")
        
        store.update(updated)
        
        // 验证更新是否成功
        if let verifyTodo = store.activeTodos.first(where: { $0.id == todo.id }) {
            print("   ✅ 验证：store 中的优先级已更新为: \(verifyTodo.priority.displayName)")
        } else {
            print("   ⚠️ 警告：更新后在 store 中未找到该 todo")
        }
    }
    
    func updateTodoDueDate(_ todo: AITodoItem, dueDate: Date?) {
        var updated = todo
        updated.dueDate = dueDate
        updated.updatedAt = Date()
        store.update(updated)
    }
    
    func archiveTodo(_ todo: AITodoItem) {
        store.archive(todo)
    }
    
    func restoreTodo(_ todo: AITodoItem) {
        store.restore(todo)
    }
    
    // MARK: - Group Management
    
    /// 获取指定优先级的所有分组（如果不存在则创建默认分组）
    func getGroups(for priority: AITodoPriority) -> [AITodoGroup] {
        var groups = store.getGroups(for: priority)
        if groups.isEmpty {
            groups = store.getDefaultGroups(for: priority)
        }
        return groups
    }
    
    /// 获取指定分组的事项
    func getTodos(for group: AITodoGroup) -> [AITodoItem] {
        let todos = store.getTodos(for: group)
        return todos.filter { showCompletedTodos || $0.status != .completed }
    }
    
    /// 将事项移动到指定分组
    func moveTodo(_ todo: AITodoItem, to group: AITodoGroup) {
        store.moveTodo(todo, to: group)
    }
    
    /// 创建新分组
    func createGroup(name: String, priority: AITodoPriority) -> AITodoGroup {
        return store.createGroup(name: name, priority: priority)
    }
    
    /// 删除分组
    func deleteGroup(_ group: AITodoGroup) {
        store.deleteGroup(group)
    }
    
    /// 更新分组
    func updateGroup(_ group: AITodoGroup) {
        store.updateGroup(group)
    }
    
    /// 重置为默认分组
    func resetToDefaultGroups(for priority: AITodoPriority) {
        let groups = getGroups(for: priority)
        for group in groups {
            deleteGroup(group)
        }
        _ = store.getDefaultGroups(for: priority)
    }
    
    // MARK: - Voice Input
    
    func startVoiceRecording() {
        guard !isRecording else { return }
        
        do {
            try voiceService.startRecording()
            isRecording = true
            aiErrorMessage = nil
            aiSuccessMessage = nil
        } catch {
            aiErrorMessage = error.localizedDescription
            isRecording = false
        }
    }
    
    func stopVoiceRecording() async {
        guard isRecording else { return }
        
        isRecording = false
        
        do {
            guard let recording = try await voiceService.stopRecording() else {
                aiErrorMessage = "录音失败，未获取到音频数据"
                return
            }
            
            // 转文字
            let language = UserPreferences.shared.transcriptLanguage
            let transcribedText = try await SpeechTranscriber.transcribe(recording: recording, language: language)
            
            // 将转录文本填入输入框
            inputText = transcribedText
            
            // 自动触发 AI 解析
            await processWithAI(transcribedText)
            
        } catch {
            aiErrorMessage = "语音转文字失败: \(error.localizedDescription)"
        }
    }
    
    func cancelVoiceRecording() {
        voiceService.cancelRecording()
        isRecording = false
    }
    
    // MARK: - AI Processing
    
    func processWithAI(_ text: String? = nil) async {
        let input = text ?? inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            aiErrorMessage = "请输入内容"
            return
        }
        
        isProcessingAI = true
        aiErrorMessage = nil
        aiSuccessMessage = nil
        
        // 获取用户设置
        let preferences = UserPreferences.shared
        let config = preferences.getConfig(for: .todoParsing)
        
        // 获取 Todo 上下文
        let todosContext = store.formatTodosAsContext()
        
        do {
            // 调用 AI 解析
            let operations = try await aiService.parseUserInput(
                input: input,
                todosContext: todosContext,
                profile: config.profile,
                model: config.model,
                timeout: config.timeout
            )
            
            // 执行操作
            await executeOperations(operations)
            
            // 清空输入框
            inputText = ""
            
            // 显示成功消息
            if !operations.isEmpty {
                aiSuccessMessage = "成功处理 \(operations.count) 个操作"
                // 3秒后清除消息
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        aiSuccessMessage = nil
                    }
                }
            } else {
                aiErrorMessage = "AI 未能识别出有效的操作，请尝试更明确的表达"
            }
            
        } catch {
            aiErrorMessage = "AI 处理失败: \(error.localizedDescription)"
            print("❌ [AITodoViewModel] AI 处理失败: \(error)")
        }
        
        isProcessingAI = false
    }
    
    private func executeOperations(_ operations: [AITodoOperation]) async {
        for operation in operations {
            switch operation.type {
            case .add:
                if let title = operation.title, !title.isEmpty {
                    var priority: AITodoPriority = .notImportantNotUrgent
                    if let priorityStr = operation.priority {
                        priority = AITodoPriority(rawValue: priorityStr) ?? .notImportantNotUrgent
                    }
                    
                    var dueDate: Date? = nil
                    if let dueDateStr = operation.dueDate {
                        let formatter = ISO8601DateFormatter()
                        dueDate = formatter.date(from: dueDateStr)
                    }
                    
                    addTodo(
                        title: title,
                        description: operation.description,
                        priority: priority,
                        dueDate: dueDate
                    )
                }
                
            case .update:
                if let todoIdStr = operation.todoId,
                   let todoId = UUID(uuidString: todoIdStr),
                   let todo = store.activeTodos.first(where: { $0.id == todoId }) {
                    var updated = todo
                    if let title = operation.title {
                        updated.title = title
                    }
                    if let description = operation.description {
                        updated.description = description
                    }
                    if let priorityStr = operation.priority,
                       let priority = AITodoPriority(rawValue: priorityStr) {
                        updated.priority = priority
                    }
                    if let dueDateStr = operation.dueDate {
                        let formatter = ISO8601DateFormatter()
                        updated.dueDate = formatter.date(from: dueDateStr)
                    }
                    updated.updatedAt = Date()
                    store.update(updated)
                }
                
            case .delete:
                if let todoIdStr = operation.todoId,
                   let todoId = UUID(uuidString: todoIdStr),
                   let todo = store.activeTodos.first(where: { $0.id == todoId }) {
                    deleteTodo(todo)
                }
                
            case .complete:
                if let todoIdStr = operation.todoId,
                   let todoId = UUID(uuidString: todoIdStr),
                   let todo = store.activeTodos.first(where: { $0.id == todoId }) {
                    toggleTodoCompletion(todo)
                }
                
            case .setPriority:
                if let todoIdStr = operation.todoId,
                   let todoId = UUID(uuidString: todoIdStr),
                   let todo = store.activeTodos.first(where: { $0.id == todoId }),
                   let priorityStr = operation.priority,
                   let priority = AITodoPriority(rawValue: priorityStr) {
                    updateTodoPriority(todo, priority: priority)
                }
                
            case .setDueDate:
                if let todoIdStr = operation.todoId,
                   let todoId = UUID(uuidString: todoIdStr),
                   let todo = store.activeTodos.first(where: { $0.id == todoId }),
                   let dueDateStr = operation.dueDate {
                    let formatter = ISO8601DateFormatter()
                    if let dueDate = formatter.date(from: dueDateStr) {
                        updateTodoDueDate(todo, dueDate: dueDate)
                    }
                }
            }
        }
    }
    
    // MARK: - Auto Archive
    
    func checkAndAutoArchive() async {
        await store.autoArchiveOldTodos()
    }
}

