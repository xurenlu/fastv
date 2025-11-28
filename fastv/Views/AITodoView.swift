//
//  AITodoView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

struct AITodoView: View {
    @StateObject private var viewModel = AITodoViewModel()
    @ObservedObject private var store = AITodoStore.shared
    @State private var showArchived = false
    @FocusState private var isInputFocused: Bool
    @State private var isSyncing = false
    @State private var syncErrorMessage: String?
    @State private var syncSuccessMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // 输入区域
            inputSection
            
            Divider()
            
            // Todo 列表
            if store.activeTodos.isEmpty && store.archivedTodos.isEmpty {
                emptyStateView
            } else {
                todoListView
            }
        }
        .navigationTitle(NSLocalizedString("ai.todo", comment: "AI Todo"))
        .onAppear {
            Task {
                await viewModel.checkAndAutoArchive()
            }
        }
    }
    
    // MARK: - Sync from Reminders
    
    private func syncFromReminders() async {
        isSyncing = true
        syncErrorMessage = nil
        syncSuccessMessage = nil
        
        do {
            // 请求权限
            let granted = try await RemindersSyncService.shared.requestAccess()
            
            if !granted {
                syncErrorMessage = NSLocalizedString("reminders.permission.denied", comment: "需要访问提醒事项的权限")
                isSyncing = false
                return
            }
            
            // 同步数据
            let todos = try await RemindersSyncService.shared.syncFromReminders()
            
            // 添加到 store（避免重复）
            var addedCount = 0
            var skippedCount = 0
            
            for todo in todos {
                // 优先使用 reminderIdentifier 判断是否已存在
                if let reminderId = todo.reminderIdentifier {
                    if store.hasReminder(identifier: reminderId) {
                        skippedCount += 1
                        continue
                    }
                } else {
                    // 如果没有 reminderIdentifier，使用标题和创建时间判断（兼容旧数据）
                    let exists = store.activeTodos.contains { existingTodo in
                        existingTodo.title == todo.title &&
                        abs(existingTodo.createdAt.timeIntervalSince(todo.createdAt)) < 60 // 1分钟内创建的认为是同一个
                    }
                    
                    if exists {
                        skippedCount += 1
                        continue
                    }
                }
                
                store.add(todo)
                addedCount += 1
            }
            
            print("📋 [AITodoView] 同步完成：新增 \(addedCount) 个，跳过 \(skippedCount) 个已存在的")
            
            if addedCount > 0 {
                if skippedCount > 0 {
                    syncSuccessMessage = String(format: NSLocalizedString("sync.success.with.skipped", comment: "成功同步 %d 个待办事项，跳过 %d 个已存在的"), addedCount, skippedCount)
                } else {
                    syncSuccessMessage = String(format: NSLocalizedString("sync.success", comment: "成功同步 %d 个待办事项"), addedCount)
                }
                
                // 3秒后清除消息
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        syncSuccessMessage = nil
                    }
                }
            } else {
                if skippedCount > 0 {
                    syncSuccessMessage = String(format: NSLocalizedString("sync.all.existed", comment: "所有 %d 个待办事项已存在，无需同步"), skippedCount)
                } else {
                    syncSuccessMessage = NSLocalizedString("sync.no.new.items", comment: "没有新的待办事项需要同步")
                }
                
                // 2秒后清除消息
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run {
                        syncSuccessMessage = nil
                    }
                }
            }
            
        } catch {
            syncErrorMessage = error.localizedDescription
            print("❌ [AITodoView] 同步失败: \(error)")
        }
        
        isSyncing = false
    }
    
    // MARK: - Input Section
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 提示信息
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                
                Text(NSLocalizedString("ai.todo.input.hint", comment: "可以直接输入文字，或使用语音输入"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.1))
            }
            
            // 输入框和按钮
            HStack(spacing: 12) {
                TextField(NSLocalizedString("ai.todo.input.placeholder", comment: "输入待办事项或语音说话..."), text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .focused($isInputFocused)
                    .onSubmit {
                        Task {
                            await viewModel.processWithAI()
                        }
                    }
                
                // 语音录制按钮
                Button(action: {
                    if viewModel.isRecording {
                        Task {
                            await viewModel.stopVoiceRecording()
                        }
                    } else {
                        viewModel.startVoiceRecording()
                    }
                }) {
                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.isRecording ? .red : .blue)
                }
                .buttonStyle(.plain)
                .help(viewModel.isRecording ? NSLocalizedString("stop.recording", comment: "停止录音") : NSLocalizedString("start.recording", comment: "开始录音"))
                
                // AI 解析按钮
                Button(action: {
                    Task {
                        await viewModel.processWithAI()
                    }
                }) {
                    if viewModel.isProcessingAI {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isProcessingAI || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(NSLocalizedString("ai.process", comment: "AI 解析"))
            }
            
            // 同步按钮
            HStack {
                Button(action: {
                    Task {
                        await syncFromReminders()
                    }
                }) {
                    HStack {
                        if isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(NSLocalizedString("sync.from.reminders", comment: "从提醒事项同步"))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSyncing)
                .help(NSLocalizedString("sync.from.reminders.help", comment: "从 macOS 提醒事项应用同步待办事项"))
            }
            
            // 消息提示
            if let errorMessage = viewModel.aiErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.red.opacity(0.1))
                }
            }
            
            if let successMessage = viewModel.aiSuccessMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(successMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.green.opacity(0.1))
                }
            }
            
            // 同步消息提示
            if let syncError = syncErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(syncError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.red.opacity(0.1))
                }
            }
            
            if let syncSuccess = syncSuccessMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(syncSuccess)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.green.opacity(0.1))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label {
                Text(NSLocalizedString("ai.todo.empty", comment: "暂无待办事项"))
                    .font(.system(size: 20, weight: .semibold))
            } icon: {
                Image(systemName: "checklist")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        } description: {
            VStack(spacing: 8) {
                Text(NSLocalizedString("ai.todo.empty.description", comment: "可以通过文字或语音添加待办事项"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Todo List
    
    private var todoListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // 活跃的 Todo
                if !store.activeTodos.isEmpty {
                    Section {
                        ForEach(store.activeTodos) { todo in
                            AITodoRow(todo: todo, viewModel: viewModel)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 4)
                        }
                    } header: {
                        HStack {
                            Text(NSLocalizedString("ai.todo.active", comment: "待办事项"))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(store.activeTodos.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                }
                
                // 归档的 Todo（可折叠）
                if !store.archivedTodos.isEmpty {
                    Section {
                        if showArchived {
                            ForEach(store.archivedTodos) { todo in
                                AITodoRow(todo: todo, viewModel: viewModel, isArchived: true)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 4)
                            }
                        }
                    } header: {
                        Button(action: {
                            withAnimation {
                                showArchived.toggle()
                            }
                        }) {
                            HStack {
                                Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(NSLocalizedString("ai.todo.archived", comment: "已归档"))
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(store.archivedTodos.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Todo Row

struct AITodoRow: View {
    let todo: AITodoItem
    @ObservedObject var viewModel: AITodoViewModel
    var isArchived: Bool = false
    @State private var isHovered = false
    @State private var showPriorityPicker = false
    @State private var showDueDatePicker = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 完成状态复选框
            Button(action: {
                viewModel.toggleTodoCompletion(todo)
            }) {
                Image(systemName: todo.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.status == .completed ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(todo.status == .completed ? NSLocalizedString("mark.as.pending", comment: "标记为待完成") : NSLocalizedString("mark.as.completed", comment: "标记为已完成"))
            
            // 内容
            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title)
                    .font(.body)
                    .strikethrough(todo.status == .completed)
                    .foregroundStyle(todo.status == .completed ? .secondary : .primary)
                
                if let description = todo.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // 优先级和截止时间
                HStack(spacing: 12) {
                    // 优先级标签
                    Button(action: {
                        showPriorityPicker.toggle()
                    }) {
                        Label(todo.priority.displayName, systemImage: priorityIcon)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(priorityColor.opacity(0.2))
                            }
                            .foregroundStyle(priorityColor)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showPriorityPicker) {
                        PriorityPickerView(selectedPriority: todo.priority) { newPriority in
                            viewModel.updateTodoPriority(todo, priority: newPriority)
                            showPriorityPicker = false
                        }
                    }
                    
                    // 截止时间
                    if let dueDate = todo.dueDate {
                        Button(action: {
                            showDueDatePicker.toggle()
                        }) {
                            Label(formatDate(dueDate), systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(todo.isOverdue ? .red : .secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showDueDatePicker) {
                            DueDatePickerView(selectedDate: dueDate) { newDate in
                                viewModel.updateTodoDueDate(todo, dueDate: newDate)
                                showDueDatePicker = false
                            }
                        }
                    } else {
                        Button(action: {
                            showDueDatePicker.toggle()
                        }) {
                            Label(NSLocalizedString("add.due.date", comment: "添加截止时间"), systemImage: "calendar.badge.plus")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showDueDatePicker) {
                            DueDatePickerView(selectedDate: nil) { newDate in
                                viewModel.updateTodoDueDate(todo, dueDate: newDate)
                                showDueDatePicker = false
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            // 操作按钮
            if !isArchived {
                HStack(spacing: 6) {
                    Button(action: {
                        viewModel.archiveTodo(todo)
                    }) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(NSLocalizedString("archive", comment: "归档"))
                    .opacity(isHovered ? 1.0 : 0.0)
                    .allowsHitTesting(isHovered)
                    
                    Button(action: {
                        viewModel.deleteTodo(todo)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(NSLocalizedString("delete", comment: "删除"))
                    .opacity(isHovered ? 1.0 : 0.0)
                    .allowsHitTesting(isHovered)
                }
                .frame(width: 52)
            } else {
                Button(action: {
                    viewModel.restoreTodo(todo)
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("restore", comment: "恢复"))
                .opacity(isHovered ? 1.0 : 0.0)
                .allowsHitTesting(isHovered)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private var priorityIcon: String {
        switch todo.priority {
        case .importantUrgent:
            return "exclamationmark.triangle.fill"
        case .importantNotUrgent:
            return "star.fill"
        case .notImportantUrgent:
            return "clock.fill"
        case .notImportantNotUrgent:
            return "circle.fill"
        }
    }
    
    private var priorityColor: Color {
        switch todo.priority {
        case .importantUrgent:
            return .red
        case .importantNotUrgent:
            return .orange
        case .notImportantUrgent:
            return .yellow
        case .notImportantNotUrgent:
            return .gray
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Priority Picker

struct PriorityPickerView: View {
    @Binding var selectedPriority: AITodoPriority
    let onSelect: (AITodoPriority) -> Void
    
    init(selectedPriority: AITodoPriority, onSelect: @escaping (AITodoPriority) -> Void) {
        self._selectedPriority = Binding.constant(selectedPriority)
        self.onSelect = onSelect
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(AITodoPriority.allCases, id: \.self) { priority in
                Button(action: {
                    onSelect(priority)
                }) {
                    HStack {
                        Text(priority.displayName)
                        Spacer()
                        if selectedPriority == priority {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 200)
    }
}

// MARK: - Due Date Picker

struct DueDatePickerView: View {
    @Binding var selectedDate: Date?
    let onSelect: (Date?) -> Void
    @State private var date: Date
    @State private var hasTime: Bool = false
    
    init(selectedDate: Date?, onSelect: @escaping (Date?) -> Void) {
        self._selectedDate = Binding.constant(selectedDate)
        self.onSelect = onSelect
        self._date = State(initialValue: selectedDate ?? Date())
        self._hasTime = State(initialValue: selectedDate != nil)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker(NSLocalizedString("due.date", comment: "截止时间"), selection: $date, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
            
            Toggle(NSLocalizedString("include.time", comment: "包含时间"), isOn: $hasTime)
            
            HStack {
                Button(NSLocalizedString("clear", comment: "清空")) {
                    onSelect(nil)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(NSLocalizedString("ok", comment: "确定")) {
                    onSelect(hasTime ? date : Calendar.current.startOfDay(for: date))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}

#Preview {
    AITodoView()
}

