//
//  AITodoQuadrantView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI
import UniformTypeIdentifiers

/// 四象限视图
struct AITodoQuadrantView: View {
    @ObservedObject var viewModel: AITodoViewModel
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // 顶部：重要的
                HStack(spacing: 0) {
                    // 第一象限：重要且紧急（右上）
                    QuadrantCell(
                        title: NSLocalizedString("todo.quadrant.important.urgent", comment: "重要且紧急"),
                        subtitle: NSLocalizedString("todo.quadrant.important.urgent.desc", comment: "立即执行"),
                        icon: "exclamationmark.triangle.fill",
                        color: .red,
                        backgroundColor: Color(red: 1.0, green: 0.95, blue: 0.96), // 淡粉红色
                        todos: viewModel.importantUrgentTodos,
                        viewModel: viewModel,
                        targetPriority: .importantUrgent
                    )
                    .frame(width: geometry.size.width / 2, height: geometry.size.height / 2)
                    
                    Divider()
                    
                    // 第二象限：重要但不紧急（左上）
                    QuadrantCell(
                        title: NSLocalizedString("todo.quadrant.important.not.urgent", comment: "重要但不紧急"),
                        subtitle: NSLocalizedString("todo.quadrant.important.not.urgent.desc", comment: "计划安排"),
                        icon: "star.fill",
                        color: .orange,
                        backgroundColor: Color(red: 1.0, green: 0.97, blue: 0.94), // 淡桃色
                        todos: viewModel.importantNotUrgentTodos,
                        viewModel: viewModel,
                        targetPriority: .importantNotUrgent
                    )
                    .frame(width: geometry.size.width / 2, height: geometry.size.height / 2)
                }
                
                Divider()
                
                // 底部：不重要的
                HStack(spacing: 0) {
                    // 第三象限：不重要但紧急（右下）
                    QuadrantCell(
                        title: NSLocalizedString("todo.quadrant.not.important.urgent", comment: "不重要但紧急"),
                        subtitle: NSLocalizedString("todo.quadrant.not.important.urgent.desc", comment: "委托他人"),
                        icon: "clock.fill",
                        color: .yellow,
                        backgroundColor: Color(red: 1.0, green: 0.99, blue: 0.96), // 淡米色
                        todos: viewModel.notImportantUrgentTodos,
                        viewModel: viewModel,
                        targetPriority: .notImportantUrgent
                    )
                    .frame(width: geometry.size.width / 2, height: geometry.size.height / 2)
                    
                    Divider()
                    
                    // 第四象限：不重要且不紧急（左下）
                    QuadrantCell(
                        title: NSLocalizedString("todo.quadrant.not.important.not.urgent", comment: "不重要且不紧急"),
                        subtitle: NSLocalizedString("todo.quadrant.not.important.not.urgent.desc", comment: "尽量少做"),
                        icon: "circle.fill",
                        color: .gray,
                        backgroundColor: Color(red: 0.97, green: 0.98, blue: 0.99), // 淡蓝灰色
                        todos: viewModel.notImportantNotUrgentTodos,
                        viewModel: viewModel,
                        targetPriority: .notImportantNotUrgent
                    )
                    .frame(width: geometry.size.width / 2, height: geometry.size.height / 2)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

/// 象限单元格
struct QuadrantCell: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let backgroundColor: Color
    let todos: [AITodoItem]
    @ObservedObject var viewModel: AITodoViewModel
    let targetPriority: AITodoPriority
    
    @State private var isDragOver = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题区域
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(color)
                    
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Text("\(todos.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            Capsule()
                                .fill(color.opacity(0.15))
                        }
                }
                
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.05))
            
            Divider()
            
            // Todo 列表
            if todos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.3))
                    
                    Text(NSLocalizedString("todo.quadrant.empty", comment: "暂无任务"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(todos) { todo in
                            QuadrantTodoRow(todo: todo, viewModel: viewModel, accentColor: color, targetPriority: targetPriority)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(Color.clear)
            }
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if isDragOver {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(color, lineWidth: 2)
                    .background(color.opacity(0.1))
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isDragOver)
        .onDrop(of: [UTType.text], isTargeted: $isDragOver) { providers in
            Task {
                await handleDropAsync(providers: providers)
            }
            return true
        }
    }
    
    @MainActor
    private func handleDropAsync(providers: [NSItemProvider]) async {
        guard let provider = providers.first else {
            print("❌ [QuadrantCell] 没有提供者")
            return
        }
        
        print("📥 [QuadrantCell] 接收到拖拽，目标优先级: \(targetPriority.displayName)")
        
        // 捕获 viewModel 和 targetPriority（避免捕获 self，因为 struct 不能使用 weak）
        let viewModel = self.viewModel
        let targetPriority = self.targetPriority
        
        // 首先尝试使用 loadObject 加载 NSString（更直接的方式）
        if provider.canLoadObject(ofClass: NSString.self) {
            do {
                let nsString = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSString, Error>) in
                    provider.loadObject(ofClass: NSString.self) { object, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let string = object as? NSString {
                            continuation.resume(returning: string)
                        } else {
                            continuation.resume(throwing: NSError(domain: "QuadrantCell", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法加载字符串对象"]))
                        }
                    }
                }
                
                let todoIdString = nsString as String
                print("📦 [QuadrantCell] 通过 loadObject 接收到字符串: \(todoIdString)")
                
                guard let todoId = UUID(uuidString: todoIdString) else {
                    print("❌ [QuadrantCell] 无法解析拖拽的 todo ID: \(todoIdString)")
                    return
                }
                
                await processTodoUpdate(todoId: todoId, viewModel: viewModel, targetPriority: targetPriority)
                return
                
            } catch {
                print("⚠️ [QuadrantCell] loadObject 失败，尝试 loadItem: \(error.localizedDescription)")
            }
        }
        
        // 如果 loadObject 失败，回退到 loadItem
        do {
            // 使用 withCheckedContinuation 将回调转换为 async/await
            let item = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSSecureCoding, Error>) in
                provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let item = item {
                        continuation.resume(returning: item)
                    } else {
                        continuation.resume(throwing: NSError(domain: "QuadrantCell", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法加载拖拽数据"]))
                    }
                }
            }
            
            print("📦 [QuadrantCell] 接收到拖拽数据，类型: \(type(of: item))")
            
            // 尝试多种方式解析数据
            var todoIdString: String?
            
            // 优先处理字符串类型（NSString 或 String）
            if let nsString = item as? NSString {
                todoIdString = nsString as String
                print("📦 [QuadrantCell] 数据格式: NSString, 内容: \(todoIdString ?? "nil")")
            } else if let string = item as? String {
                todoIdString = string
                print("📦 [QuadrantCell] 数据格式: String, 内容: \(string)")
            } else if let data = item as? Data {
                todoIdString = String(data: data, encoding: .utf8)
                print("📦 [QuadrantCell] 数据格式: Data, 内容: \(todoIdString ?? "nil")")
            } else if let url = item as? URL {
                // SwiftUI 可能将数据保存为文件，需要从文件中读取
                print("📦 [QuadrantCell] 数据格式: URL, 路径: \(url.absoluteString)")
                
                // 尝试从文件中读取内容
                if url.isFileURL {
                    do {
                        let fileContent = try String(contentsOf: url, encoding: .utf8)
                        todoIdString = fileContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        print("📦 [QuadrantCell] 从文件读取内容: \(todoIdString ?? "nil")")
                    } catch {
                        print("❌ [QuadrantCell] 读取文件失败: \(error.localizedDescription)")
                        // 如果读取失败，尝试使用 URL 的最后一个路径组件
                        let lastComponent = url.lastPathComponent
                        if UUID(uuidString: lastComponent) != nil {
                            todoIdString = lastComponent
                            print("📦 [QuadrantCell] 使用路径组件: \(lastComponent)")
                        }
                    }
                } else {
                    // 如果不是文件 URL，尝试从 URL 字符串中提取
                    todoIdString = url.absoluteString
                }
            }
            
            guard let idString = todoIdString,
                  let todoId = UUID(uuidString: idString) else {
                print("❌ [QuadrantCell] 无法解析拖拽的 todo ID")
                print("   原始数据: \(String(describing: item))")
                print("   解析到的字符串: \(todoIdString ?? "nil")")
                return
            }
            
            await processTodoUpdate(todoId: todoId, viewModel: viewModel, targetPriority: targetPriority)
            
        } catch {
            print("❌ [QuadrantCell] 加载拖拽数据失败: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func processTodoUpdate(todoId: UUID, viewModel: AITodoViewModel, targetPriority: AITodoPriority) async {
        print("🔍 [QuadrantCell] 解析到的 todo ID: \(todoId)")
        
        // 查找对应的 todo
        guard let todo = viewModel.activeTodos.first(where: { $0.id == todoId }) else {
            print("❌ [QuadrantCell] 未找到 ID 为 \(todoId) 的 todo")
            print("📋 [QuadrantCell] 当前活跃 todos 数量: \(viewModel.activeTodos.count)")
            print("📋 [QuadrantCell] 当前活跃 todos IDs: \(viewModel.activeTodos.map { $0.id.uuidString })")
            return
        }
        
        print("✅ [QuadrantCell] 找到 todo: '\(todo.title)'，当前优先级: \(todo.priority.displayName)")
        
        // 如果优先级已经相同，不需要更新
        guard todo.priority != targetPriority else {
            print("ℹ️ [QuadrantCell] Todo 优先级已经是 \(targetPriority.displayName)，无需更新")
            return
        }
        
        // 更新优先级
        print("🔄 [QuadrantCell] 更新 todo '\(todo.title)' 的优先级: \(todo.priority.displayName) -> \(targetPriority.displayName)")
        viewModel.updateTodoPriority(todo, priority: targetPriority)
        
        // 验证更新是否成功
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        if let updatedTodo = viewModel.activeTodos.first(where: { $0.id == todoId }) {
            print("✅ [QuadrantCell] 更新后的优先级: \(updatedTodo.priority.displayName)")
        } else {
            print("⚠️ [QuadrantCell] 更新后未找到 todo")
        }
    }
}

/// 象限中的 Todo 行（简化版）
struct QuadrantTodoRow: View {
    let todo: AITodoItem
    @ObservedObject var viewModel: AITodoViewModel
    let accentColor: Color
    let targetPriority: AITodoPriority
    @State private var isHovered = false
    @State private var showDueDatePicker = false
    @State private var isDragging = false
    @State private var dragResetTask: Task<Void, Never>?
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 完成状态复选框
            Button(action: {
                viewModel.toggleTodoCompletion(todo)
            }) {
                Image(systemName: todo.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(todo.status == .completed ? .green : .secondary)
            }
            .buttonStyle(.plain)
            
            // 内容
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .font(.system(size: 12))
                    .strikethrough(todo.status == .completed)
                    .foregroundStyle(todo.status == .completed ? .secondary : .primary)
                    .lineLimit(2)
                
                if let description = todo.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                // 截止时间
                if let dueDate = todo.dueDate {
                    Button(action: {
                        showDueDatePicker.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                            Text(formatDate(dueDate))
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(todo.isOverdue ? .red : .secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(todo.isOverdue ? Color.red.opacity(0.1) : Color.secondary.opacity(0.08))
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showDueDatePicker) {
                        DueDatePickerView(selectedDate: dueDate) { newDate in
                            viewModel.updateTodoDueDate(todo, dueDate: newDate)
                            showDueDatePicker = false
                        }
                    }
                }
            }
            
            Spacer()
            
            // 操作按钮
            HStack(spacing: 4) {
                Button(action: {
                    viewModel.archiveTodo(todo)
                }) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("archive", comment: "归档"))
                .opacity(isHovered ? 1.0 : 0.0)
                .allowsHitTesting(isHovered)
                
                Button(action: {
                    viewModel.deleteTodo(todo)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("delete", comment: "删除"))
                .opacity(isHovered ? 1.0 : 0.0)
                .allowsHitTesting(isHovered)
            }
            .frame(width: 36)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isHovered ? accentColor.opacity(0.08) : Color.clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(accentColor.opacity(isHovered ? 0.2 : 0), lineWidth: 1)
                }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .opacity(isDragging ? 0.5 : 1.0)
        .scaleEffect(isDragging ? 0.95 : 1.0)
        .onDrag {
            // 取消之前的重置任务
            dragResetTask?.cancel()
            
            withAnimation(.easeInOut(duration: 0.2)) {
                isDragging = true
            }
            
            // 设置一个延迟重置任务（如果拖拽被取消，3秒后自动重置）
            dragResetTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDragging = false
                        }
                    }
                }
            }
            
            let todoIdString = todo.id.uuidString
            print("🔄 [QuadrantTodoRow] 开始拖拽 todo: '\(todo.title)' (ID: \(todoIdString))")
            
            // 使用 NSItemProvider 直接传递字符串
            // 这样可以避免 SwiftUI 将其保存为文件
            let itemProvider = NSItemProvider(object: todoIdString as NSString)
            return itemProvider
        }
        .onChange(of: todo.priority) { oldPriority, newPriority in
            // 当优先级改变时，重置拖拽状态
            if oldPriority != newPriority {
                dragResetTask?.cancel()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDragging = false
                }
            }
        }
        .onDisappear {
            // 视图消失时取消重置任务
            dragResetTask?.cancel()
            isDragging = false
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        
        // 时间格式化器（用于显示具体时间）
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        let timeString = timeFormatter.string(from: date)
        
        // 日期格式化器（用于显示日期）
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        
        if calendar.isDateInToday(date) {
            // 今天：显示"今天 几点几分"
            return String(format: NSLocalizedString("today.at.time", comment: "今天 %@"), timeString)
        } else if calendar.isDateInTomorrow(date) {
            // 明天：显示"明天 几点几分"
            return String(format: NSLocalizedString("tomorrow.at.time", comment: "明天 %@"), timeString)
        } else {
            // 其他日期：显示日期和时间
            dateFormatter.timeStyle = .short
            return dateFormatter.string(from: date)
        }
    }
}

#Preview {
    AITodoQuadrantView(viewModel: AITodoViewModel())
        .frame(width: 800, height: 600)
}

