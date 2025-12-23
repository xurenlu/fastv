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
    @AppStorage("aiTodoShowCompleted") private var showCompletedPreference = false
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
            
            // 视图模式切换工具栏
            viewModeToolbar
            
            Divider()
            
            // Todo 视图（根据模式显示）
            if store.activeTodos.isEmpty && store.archivedTodos.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
        .navigationTitle(NSLocalizedString("ai.todo", comment: "AI Todo"))
        .onAppear {
            viewModel.showCompletedTodos = showCompletedPreference
            Task {
                await viewModel.checkAndAutoArchive()
            }
        }
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        Group {
            switch viewModel.viewMode {
            case .list:
                todoListView
            case .quadrant:
                AITodoQuadrantView(viewModel: viewModel)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.viewMode)
    }
    
    // MARK: - View Mode Toolbar
    
    private var viewModeToolbar: some View {
        HStack(spacing: 12) {
            // 视图模式说明 - 现代化设计
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text(viewModeDescription)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.blue.opacity(0.1),
                                    Color.blue.opacity(0.05)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                }
            }
            
            Spacer()
            
            // 模式切换按钮
            Picker("", selection: $viewModel.viewMode) {
                ForEach(TodoViewMode.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.viewMode)
            
            Toggle(isOn: Binding(
                get: { viewModel.showCompletedTodos },
                set: { newValue in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.showCompletedTodos = newValue
                        showCompletedPreference = newValue
                    }
                }
            )) {
                Label("显示已完成", systemImage: viewModel.showCompletedTodos ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.leading, 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            ZStack {
                Rectangle()
                    .fill(.regularMaterial)
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.primary.opacity(0.02),
                                Color.clear
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }
    
    private var viewModeDescription: String {
        switch viewModel.viewMode {
        case .list:
            return NSLocalizedString("todo.view.mode.list.desc", comment: "所有待办事项按列表显示")
        case .quadrant:
            return NSLocalizedString("todo.view.mode.quadrant.desc", comment: "按重要性和紧急性分为四个象限")
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
        VStack(alignment: .leading, spacing: 8) {
            // 输入框和按钮 - 紧凑设计
            HStack(alignment: .top, spacing: 10) {
                // 输入框
                TextField(NSLocalizedString("ai.todo.input.placeholder", comment: "输入待办事项或语音说话..."), text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .frame(minHeight: 44, maxHeight: 80)
                    .focused($isInputFocused)
                    .onSubmit {
                        Task {
                            await viewModel.processWithAI()
                        }
                    }
                
                // 按钮组 - 横向排列
                HStack(spacing: 8) {
                    // 语音录制按钮
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if viewModel.isRecording {
                                Task {
                                    await viewModel.stopVoiceRecording()
                                }
                            } else {
                                viewModel.startVoiceRecording()
                            }
                        }
                    }) {
                        Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(
                                viewModel.isRecording ?
                                LinearGradient(
                                    gradient: Gradient(colors: [.red, .red.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                            .shadow(color: (viewModel.isRecording ? Color.red : Color.blue).opacity(0.25), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.isRecording ? NSLocalizedString("stop.recording", comment: "停止录音") : NSLocalizedString("start.recording", comment: "开始录音"))
                    .scaleEffect(viewModel.isRecording ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7).repeatForever(autoreverses: viewModel.isRecording), value: viewModel.isRecording)
                    
                    // AI 解析按钮
                    Button(action: {
                        Task {
                            await viewModel.processWithAI()
                        }
                    }) {
                        if viewModel.isProcessingAI {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 36, height: 36)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue, .purple]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)
                                .shadow(color: Color.blue.opacity(0.25), radius: 3, x: 0, y: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isProcessingAI || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(NSLocalizedString("ai.process", comment: "AI 解析"))
                    .opacity(viewModel.isProcessingAI || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
                }
            }
            
            // 底部操作栏 - 紧凑设计
            HStack(spacing: 8) {
                // 提示信息 - 更紧凑
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange.opacity(0.8))
                    
                    Text(NSLocalizedString("ai.todo.input.hint", comment: "可以直接输入文字，或使用语音输入"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // 同步按钮 - 紧凑样式
                Button(action: {
                    Task {
                        await syncFromReminders()
                    }
                }) {
                    HStack(spacing: 5) {
                        if isSyncing {
                            ProgressView()
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(NSLocalizedString("sync.from.reminders", comment: "从提醒事项同步"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
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
        .padding(.vertical, 12)
        .background {
            ZStack {
                Color(NSColor.controlBackgroundColor)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.3)
            }
        }
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
                let visibleTodos = viewModel.visibleActiveTodos
                if !visibleTodos.isEmpty {
                    Section {
                        ForEach(visibleTodos) { todo in
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
                            Text("\(visibleTodos.count)")
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
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
                .overlay {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    }
                }
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
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

