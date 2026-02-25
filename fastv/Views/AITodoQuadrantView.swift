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
                        color: Color(red: 0.95, green: 0.3, blue: 0.3), // 更柔和的红色
                        backgroundColor: Color(red: 0.99, green: 0.96, blue: 0.97), // 更柔和的淡粉红色
                        todos: viewModel.importantUrgentTodos,
                        viewModel: viewModel,
                        targetPriority: .importantUrgent
                    )
                    .frame(width: geometry.size.width / 2, height: geometry.size.height / 2)
                    
                    // 精致的分隔线
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.clear, Color.secondary.opacity(0.2), Color.clear]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 1)
                    
                    // 第二象限：重要但不紧急（左上）
                    QuadrantCell(
                        title: NSLocalizedString("todo.quadrant.important.not.urgent", comment: "重要但不紧急"),
                        subtitle: NSLocalizedString("todo.quadrant.important.not.urgent.desc", comment: "计划安排"),
                        icon: "star.fill",
                        color: Color(red: 1.0, green: 0.65, blue: 0.2), // 更柔和的橙色
                        backgroundColor: Color(red: 1.0, green: 0.98, blue: 0.96), // 更柔和的淡桃色
                        todos: viewModel.importantNotUrgentTodos,
                        viewModel: viewModel,
                        targetPriority: .importantNotUrgent
                    )
                    .frame(width: geometry.size.width / 2, height: geometry.size.height / 2)
                }
                
                // 精致的分隔线
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.clear, Color.secondary.opacity(0.2), Color.clear]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                
                // 底部：不重要的
                HStack(spacing: 0) {
                    // 第三象限：不重要但紧急（右下）
                    QuadrantCell(
                        title: NSLocalizedString("todo.quadrant.not.important.urgent", comment: "不重要但紧急"),
                        subtitle: NSLocalizedString("todo.quadrant.not.important.urgent.desc", comment: "委托他人"),
                        icon: "clock.fill",
                        color: Color(red: 0.95, green: 0.75, blue: 0.2), // 更柔和的黄色
                        backgroundColor: Color(red: 1.0, green: 0.99, blue: 0.97), // 更柔和的淡米色
                        todos: viewModel.notImportantUrgentTodos,
                        viewModel: viewModel,
                        targetPriority: .notImportantUrgent
                    )
                    .frame(width: geometry.size.width / 2, height: geometry.size.height / 2)
                    
                    // 精致的分隔线
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.clear, Color.secondary.opacity(0.2), Color.clear]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 1)
                    
                    // 第四象限：不重要且不紧急（左下）
                    QuadrantCell(
                        title: NSLocalizedString("todo.quadrant.not.important.not.urgent", comment: "不重要且不紧急"),
                        subtitle: NSLocalizedString("todo.quadrant.not.important.not.urgent.desc", comment: "尽量少做"),
                        icon: "circle.fill",
                        color: Color(red: 0.6, green: 0.6, blue: 0.65), // 更柔和的灰色
                        backgroundColor: Color(red: 0.98, green: 0.98, blue: 0.99), // 更柔和的淡蓝灰色
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
    @State private var showGroupManagement = false
    @State private var showCreateGroupDialog = false
    @State private var newGroupName = ""
    
    var body: some View {
        let groups = viewModel.getGroups(for: targetPriority)
        
        VStack(alignment: .leading, spacing: 0) {
            // 标题区域 - 现代化设计
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    // 图标 - 更大更突出
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [color, color.opacity(0.8)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: color.opacity(0.3), radius: 2, x: 0, y: 1)
                    
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    // 计数徽章 - 更精致
                    Text("\(todos.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(color.opacity(0.15))
                                .overlay {
                                    Capsule()
                                        .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
                                }
                        }
                        .shadow(color: color.opacity(0.1), radius: 2, x: 0, y: 1)
                }
                
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24) // 与图标对齐
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                // 渐变背景
                LinearGradient(
                    gradient: Gradient(colors: [
                        color.opacity(0.08),
                        color.opacity(0.03),
                        Color.clear
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .contextMenu {
                Button(action: {
                    showCreateGroupDialog = true
                }) {
                    Label("新建分组", systemImage: "plus.circle")
                }
                
                Button(action: {
                    showGroupManagement = true
                }) {
                    Label("管理分组", systemImage: "slider.horizontal.3")
                }
                
                Divider()
                
                Button(action: {
                    resetToDefaultGroups()
                }) {
                    Label("重置为默认分组", systemImage: "arrow.counterclockwise")
                }
            }
            
            // 精致的分隔线
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.clear, color.opacity(0.15), Color.clear]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
            
            // 看板式布局
            if groups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [color.opacity(0.4), color.opacity(0.2)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text(NSLocalizedString("todo.quadrant.empty", comment: "暂无任务"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(groups) { group in
                            KanbanColumnView(
                                group: group,
                                viewModel: viewModel,
                                accentColor: color,
                                targetPriority: targetPriority
                            )
                            .frame(width: 240)
                        }
                        
                        // 添加看板按钮 - 紧凑美观设计
                        Button(action: {
                            showCreateGroupDialog = true
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(
                                        LinearGradient(
                                            gradient: Gradient(colors: [color, color.opacity(0.7)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                Text("添加看板")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 200, height: 70)
                            .background {
                                ZStack {
                                    Color(NSColor.controlBackgroundColor)
                                    Rectangle()
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.4)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                color.opacity(0.35),
                                                color.opacity(0.15)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        style: StrokeStyle(lineWidth: 1.2, dash: [5, 3])
                                    )
                            }
                            .shadow(color: color.opacity(0.08), radius: 3, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showCreateGroupDialog)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .background(Color.clear)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: groups.count)
            }
        }
        .background {
            // 毛玻璃效果背景
            ZStack {
                // 基础背景色
                backgroundColor
                
                // 毛玻璃材质层
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            // 精致的边框
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            color.opacity(0.2),
                            color.opacity(0.05),
                            Color.clear
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: color.opacity(0.1), radius: 8, x: 0, y: 2)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .overlay {
            if isDragOver {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color, lineWidth: 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(color.opacity(0.15))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragOver)
        .onDrop(of: [UTType.text], isTargeted: $isDragOver) { providers in
            Task {
                await handleDropAsync(providers: providers)
            }
            return true
        }
        .sheet(isPresented: $showGroupManagement) {
            GroupManagementView(
                priority: targetPriority,
                viewModel: viewModel
            )
        }
        .alert("新建分组", isPresented: $showCreateGroupDialog) {
            TextField("分组名称", text: $newGroupName)
            Button("取消", role: .cancel) {
                newGroupName = ""
            }
            Button("创建") {
                if !newGroupName.isEmpty {
                    _ = viewModel.createGroup(name: newGroupName, priority: targetPriority)
                    newGroupName = ""
                }
            }
        } message: {
            Text("请输入新分组的名称")
        }
    }
    
    private func resetToDefaultGroups() {
        viewModel.resetToDefaultGroups(for: targetPriority)
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

/// 看板列视图
struct KanbanColumnView: View {
    let group: AITodoGroup
    @ObservedObject var viewModel: AITodoViewModel
    let accentColor: Color
    let targetPriority: AITodoPriority
    
    @State private var isDragOver = false
    @State private var isEditing = false
    @State private var editingName = ""
    @State private var showDeleteAlert = false
    @State private var isHovered = false
    @FocusState private var isTextFieldFocused: Bool
    
    var todos: [AITodoItem] {
        viewModel.getTodos(for: group)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 列标题 - 现代化设计
            HStack(spacing: 8) {
                if isEditing && !group.isDefault {
                    TextField("看板名称", text: $editingName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            saveEdit()
                        }
                        .onChange(of: isTextFieldFocused) { oldValue, newValue in
                            // 当失去焦点时，自动保存
                            if oldValue && !newValue && isEditing {
                                // 延迟一下，确保点击事件已经处理完成
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    saveEdit()
                                }
                            }
                        }
                        .onAppear {
                            // 自动聚焦
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isTextFieldFocused = true
                            }
                        }
                } else {
                    HStack(spacing: 4) {
                        Text(group.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        // 编辑提示图标（非默认看板且悬停时显示）
                        if !group.isDefault && isHovered {
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary.opacity(0.6))
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if !group.isDefault {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                startEdit()
                            }
                        }
                    }
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isHovered = hovering
                        }
                    }
                    .help(group.isDefault ? "默认看板名称不可修改" : "双击编辑看板名称")
                }
                
                Spacer()
                
                // 删除按钮（非默认看板）
                if !group.isDefault && !isEditing {
                    Button(action: {
                        showDeleteAlert = true
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("删除看板")
                }
                
                // 计数徽章 - 更精致
                Text("\(todos.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(accentColor.opacity(0.15))
                            .overlay {
                                Capsule()
                                    .strokeBorder(accentColor.opacity(0.3), lineWidth: 0.5)
                            }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                ZStack {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            accentColor.opacity(0.08),
                            accentColor.opacity(0.03),
                            Color.clear
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    // 悬停时的背景高亮（非默认看板）
                    if isHovered && !group.isDefault && !isEditing {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(accentColor.opacity(0.05))
                            .transition(.opacity)
                    }
                }
            }
            
            // 精致的分隔线
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.clear, accentColor.opacity(0.15), Color.clear]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
            
            // 事项列表
            ScrollView {
                LazyVStack(spacing: 6) {
                    if todos.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tray")
                                .font(.system(size: 32))
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            accentColor.opacity(0.4),
                                            accentColor.opacity(0.2)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("暂无事项")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(todos) { todo in
                            KanbanTodoCard(
                                todo: todo,
                                viewModel: viewModel,
                                accentColor: accentColor,
                                targetPriority: targetPriority
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: .infinity)
        }
        .background {
            ZStack {
                Color(NSColor.controlBackgroundColor)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .simultaneousGesture(
            // 点击看板列背景时，如果正在编辑，自动保存
            // 使用 simultaneousGesture 避免与拖拽冲突
            TapGesture()
                .onEnded { _ in
                    if isEditing {
                        saveEdit()
                    }
                }
        )
        .overlay {
            // 精致的边框
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            accentColor.opacity(0.2),
                            accentColor.opacity(0.05),
                            Color.clear
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: accentColor.opacity(0.08), radius: 6, x: 0, y: 2)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .overlay {
            if isDragOver {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 4]))
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accentColor.opacity(0.12))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragOver)
        .onDrop(of: [UTType.text], isTargeted: $isDragOver) { providers in
            Task {
                await handleDropAsync(providers: providers)
            }
            return true
        }
        .alert("删除看板", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                deleteGroup()
            }
        } message: {
            Text("确定要删除看板「\(group.name)」吗？该看板中的事项将移动到默认看板。")
        }
    }
    
    private func startEdit() {
        editingName = group.name
        isEditing = true
        // 延迟一下再聚焦，确保视图已经更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTextFieldFocused = true
        }
    }
    
    private func saveEdit() {
        // 如果名称有变化且不为空，则保存
        if !editingName.isEmpty && editingName != group.name {
            var updated = group
            updated.name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !updated.name.isEmpty {
                viewModel.updateGroup(updated)
            }
        }
        // 关闭编辑模式
        isEditing = false
        isTextFieldFocused = false
        editingName = ""
    }
    
    private func cancelEdit() {
        isEditing = false
        isTextFieldFocused = false
        editingName = ""
    }
    
    private func deleteGroup() {
        viewModel.deleteGroup(group)
    }
    
    @MainActor
    private func handleDropAsync(providers: [NSItemProvider]) async {
        guard let provider = providers.first else { return }
        
        if provider.canLoadObject(ofClass: NSString.self) {
            do {
                let nsString = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSString, Error>) in
                    provider.loadObject(ofClass: NSString.self) { object, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let string = object as? NSString {
                            continuation.resume(returning: string)
                        } else {
                            continuation.resume(throwing: NSError(domain: "DropError", code: -1))
                        }
                    }
                }
                
                let todoIdString = nsString as String
                guard let todoId = UUID(uuidString: todoIdString) else {
                    print("❌ [KanbanColumnView] 无效的 UUID: \(todoIdString)")
                    return
                }
                
                guard let todo = viewModel.activeTodos.first(where: { $0.id == todoId }) else {
                    print("❌ [KanbanColumnView] 未找到 ID 为 \(todoId) 的事项")
                    return
                }
                
                print("📥 [KanbanColumnView] 接收到拖拽事项: '\(todo.title)'")
                print("   当前优先级: \(todo.priority.displayName), 目标优先级: \(group.priority.displayName)")
                print("   当前分组ID: \(todo.groupId?.uuidString ?? "nil"), 目标分组: \(group.name) (ID: \(group.id.uuidString))")
                
                // 如果优先级不同，需要先更新优先级
                if todo.priority != group.priority {
                    print("🔄 [KanbanColumnView] 优先级不同，更新优先级: \(todo.priority.displayName) -> \(group.priority.displayName)")
                    viewModel.updateTodoPriority(todo, priority: group.priority)
                }
                
                // 重新获取最新的 todo（因为优先级可能已更新）
                guard let updatedTodo = viewModel.activeTodos.first(where: { $0.id == todoId }) else {
                    print("❌ [KanbanColumnView] 更新优先级后未找到事项")
                    return
                }
                
                // 移动到目标分组
                viewModel.moveTodo(updatedTodo, to: group)
                print("✅ [KanbanColumnView] 已将事项移动到分组: \(group.name)")
                
                // 验证移动是否成功
                if let finalTodo = viewModel.activeTodos.first(where: { $0.id == todoId }) {
                    print("   ✅ 验证：优先级=\(finalTodo.priority.displayName), 分组ID=\(finalTodo.groupId?.uuidString ?? "nil")")
                }
            } catch {
                print("❌ [KanbanColumnView] 拖拽处理失败: \(error)")
            }
        }
    }
}

/// 看板事项卡片
struct KanbanTodoCard: View {
    let todo: AITodoItem
    @ObservedObject var viewModel: AITodoViewModel
    let accentColor: Color
    let targetPriority: AITodoPriority
    
    @State private var isDragging = false
    @State private var dragResetTask: Task<Void, Never>?
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 完成状态复选框 - 更精致
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.toggleTodoCompletion(todo)
                }
            }) {
                Image(systemName: todo.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        todo.status == .completed ?
                        LinearGradient(
                            gradient: Gradient(colors: [.green, .green.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            gradient: Gradient(colors: [.secondary, .secondary.opacity(0.7)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .buttonStyle(.plain)
            .help(todo.status == .completed ? NSLocalizedString("mark.as.pending", comment: "标记为待完成") : NSLocalizedString("mark.as.completed", comment: "标记为已完成"))
            
            // 内容
            VStack(alignment: .leading, spacing: 8) {
                // 标题
                Text(todo.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(todo.status == .completed ? .secondary : .primary)
                    .strikethrough(todo.status == .completed)
                    .lineLimit(2)
                
                // 描述
                if let description = todo.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                // 截止时间 - 更精致的样式
                if let dueDate = todo.dueDate {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .medium))
                        Text(formatDate(dueDate))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(todo.isOverdue ? .red : accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(
                                todo.isOverdue ?
                                Color.red.opacity(0.12) :
                                accentColor.opacity(0.12)
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        todo.isOverdue ?
                                        Color.red.opacity(0.3) :
                                        accentColor.opacity(0.3),
                                        lineWidth: 0.5
                                    )
                            }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color(NSColor.textBackgroundColor)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.3)
                
                // 悬停时的背景渐变
                if isHovered {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            accentColor.opacity(0.08),
                            accentColor.opacity(0.03)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isHovered ?
                    LinearGradient(
                        gradient: Gradient(colors: [
                            accentColor.opacity(0.3),
                            accentColor.opacity(0.1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ) :
                    LinearGradient(
                        gradient: Gradient(colors: [Color.clear]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isHovered ? 1.5 : 0
                )
        }
        .shadow(color: isHovered ? accentColor.opacity(0.15) : .black.opacity(0.06), radius: isHovered ? 6 : 3, x: 0, y: isHovered ? 3 : 1)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onDrag {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isDragging = true
            }
            
            dragResetTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled {
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isDragging = false
                        }
                    }
                }
            }
            
            return NSItemProvider(object: todo.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], isTargeted: .constant(false)) { _ in
            dragResetTask?.cancel()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isDragging = false
            }
            return false
        }
        .opacity(isDragging ? 0.5 : 1.0)
        .scaleEffect(isDragging ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        
        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            let timeString = formatter.string(from: date)
            return String(format: NSLocalizedString("today.at.time", comment: "今天 %@"), timeString)
        } else if calendar.isDateInTomorrow(date) {
            formatter.timeStyle = .short
            let timeString = formatter.string(from: date)
            return String(format: NSLocalizedString("tomorrow.at.time", comment: "明天 %@"), timeString)
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}

/// 分组管理视图
struct GroupManagementView: View {
    let priority: AITodoPriority
    @ObservedObject var viewModel: AITodoViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var groups: [AITodoGroup] = []
    @State private var showCreateDialog = false
    @State private var newGroupName = ""
    @State private var editingGroup: AITodoGroup?
    @State private var editingName = ""
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    HStack {
                        if editingGroup?.id == group.id {
                            TextField("分组名称", text: $editingName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    saveEdit()
                                }
                        } else {
                            Text(group.name)
                                .font(.body)
                        }
                        
                        Spacer()
                        
                        Text("\(viewModel.getTodos(for: group).count) 项")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive, action: {
                            viewModel.deleteGroup(group)
                            loadGroups()
                        }) {
                            Label("删除", systemImage: "trash")
                        }
                        
                        Button(action: {
                            editingGroup = group
                            editingName = group.name
                        }) {
                            Label("编辑", systemImage: "pencil")
                        }
                    }
                }
            }
            .navigationTitle("管理分组")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成", action: { dismiss() })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        showCreateDialog = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                loadGroups()
            }
            .alert("新建分组", isPresented: $showCreateDialog) {
                TextField("分组名称", text: $newGroupName)
                Button("取消", role: .cancel) {
                    newGroupName = ""
                }
                Button("创建") {
                    if !newGroupName.isEmpty {
                        _ = viewModel.createGroup(name: newGroupName, priority: priority)
                        newGroupName = ""
                        loadGroups()
                    }
                }
            } message: {
                Text("请输入新分组的名称")
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private func loadGroups() {
        groups = viewModel.getGroups(for: priority)
    }
    
    private func saveEdit() {
        if let group = editingGroup, !editingName.isEmpty {
            var updated = group
            updated.name = editingName
            viewModel.updateGroup(updated)
            editingGroup = nil
            editingName = ""
            loadGroups()
        }
    }
}

#Preview {
    AITodoQuadrantView(viewModel: AITodoViewModel())
        .frame(width: 800, height: 600)
}

