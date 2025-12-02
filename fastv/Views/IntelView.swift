//
//  IntelView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI
import AppKit

struct IntelView: View {
    @StateObject private var viewModel = IntelViewModel()
    @FocusState private var isChatInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部：日期选择器（仅在今日的情报标签页显示）
            if viewModel.selectedTab == .today {
                datePickerSection
                Divider()
            }
            
            // 主要内容区域（可调整高度）
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // 上半部分：情报展示区域
                    contentSection
                        .frame(height: viewModel.selectedTab == .today ? 
                               (geometry.size.height - viewModel.chatSectionHeight) : 
                               geometry.size.height)
                    
                    // 可调整的分割线和聊天区域（仅在今日的情报标签页显示）
                    if viewModel.selectedTab == .today {
                        ResizableDivider(
                            height: $viewModel.chatSectionHeight,
                            totalHeight: geometry.size.height,
                            minHeight: 150,
                            maxHeight: geometry.size.height - 200
                        )
                        
                        chatSection
                            .frame(height: viewModel.chatSectionHeight)
                    }
                }
            }
        }
        .navigationTitle("情报")
        .onAppear {
            viewModel.ensureTodayIntelIfNeeded()
        }
    }
    
    // MARK: - Date Picker Section
    
    private var datePickerSection: some View {
        HStack(spacing: 12) {
            DatePicker("日期", selection: $viewModel.selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .onChange(of: viewModel.selectedDate) { _, newDate in
                    viewModel.load(date: newDate)
                }
            
            Button("今天") {
                let today = Date()
                viewModel.load(date: today)
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            if viewModel.isLoadingTodayAutoIntel {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在生成今天的情报...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Content Section
    
    private var contentSection: some View {
        VStack(spacing: 0) {
            // 标签页切换
            Picker("标签", selection: $viewModel.selectedTab) {
                ForEach(IntelTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            // 根据选中的标签页显示不同内容
            if viewModel.selectedTab == .today {
                todayContentSection
            } else {
                historyContentSection
            }
        }
    }
    
    // MARK: - Today Content Section
    
    private var todayContentSection: some View {
        HStack(spacing: 0) {
            // 左侧：情报列表
            intelListSection
                .frame(width: 300)
            
            Divider()
            
            // 右侧：详情区域
            detailSection
                .frame(minWidth: 400)
        }
    }
    
    // MARK: - History Content Section
    
    private var historyContentSection: some View {
        HStack(spacing: 0) {
            // 左侧：日历、词云和列表
            ScrollView {
                VStack(spacing: 16) {
                    // 顶部：三个月日历
                    ThreeMonthCalendarView(viewModel: viewModel)
                        .padding(.top, 16)
                    
                    // 中部：词云
                    WordCloudContainerView(viewModel: viewModel)
                    
                    // 搜索栏和筛选提示
                    HStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("搜索历史情报...", text: $viewModel.historySearchText)
                                .textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(NSColor.controlBackgroundColor))
                        }
                        
                        if let keyword = viewModel.selectedKeyword {
                            HStack(spacing: 8) {
                                Text("筛选: \(keyword)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button(action: {
                                    viewModel.clearKeywordFilter()
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.1))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // 历史情报卡片列表
                    if viewModel.historyEntries.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary.opacity(0.5))
                            Text(viewModel.historySearchText.isEmpty && viewModel.selectedKeyword == nil ? 
                                 "暂无历史情报" : "未找到匹配的历史情报")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
                        ], spacing: 16) {
                            ForEach(viewModel.historyEntries) { entry in
                                HistoryIntelCard(entry: entry, isSelected: viewModel.selectedEntry?.id == entry.id)
                                    .onTapGesture {
                                        viewModel.selectEntry(entry)
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            
            // 右侧：详情区域（如果选中了条目）
            if viewModel.selectedEntry != nil {
                Divider()
                detailSection
                    .frame(width: 400)
            }
        }
    }
    
    // MARK: - Intel List Section
    
    private var intelListSection: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text("情报列表")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.entries.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            // 列表
            if viewModel.entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("暂无情报")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if Calendar.current.isDateInToday(viewModel.selectedDate) {
                        Text("正在自动生成...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.entries) { entry in
                            IntelListRow(
                                entry: entry,
                                isSelected: viewModel.selectedEntry?.id == entry.id
                            )
                            .onTapGesture {
                                viewModel.selectEntry(entry)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Detail Section
    
    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let entry = viewModel.selectedEntry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 日期显示
                        Text(entry.date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        // 概要
                        VStack(alignment: .leading, spacing: 8) {
                            Text("概要")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text(entry.summary)
                                .font(.body)
                        }
                        
                        Divider()
                        
                        // 正文
                        VStack(alignment: .leading, spacing: 8) {
                            Text("正文")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text(entry.body)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        
                        Divider()
                        
                        // 来源标签
                        if !entry.sources.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("来源")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                FlowLayout(spacing: 8) {
                                    ForEach(entry.sources, id: \.self) { source in
                                        Label(source, systemImage: "tag.fill")
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background {
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(Color.accentColor.opacity(0.2))
                                            }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        // 操作按钮
                        HStack(spacing: 12) {
                            Button("删除") {
                                viewModel.deleteEntry(entry)
                            }
                            .buttonStyle(.bordered)
                            .foregroundStyle(.red)
                            
                            Spacer()
                        }
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("请选择一条情报查看详情")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Chat Section
    
    private var chatSection: some View {
        VStack(spacing: 0) {
            // 聊天消息区域
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.chatMessages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: viewModel.chatMessages.count) { _, _ in
                    if let lastMessage = viewModel.chatMessages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // 可调整高度的输入区域分隔条
            ResizableInputDivider(height: $viewModel.inputFieldHeight)
            
            // 输入区域
            HStack(spacing: 12) {
                TextField("输入消息或指令...", text: $viewModel.chatInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...)  // 至少两行，允许更多行
                    .frame(height: viewModel.inputFieldHeight)
                    .focused($isChatInputFocused)
                    .onSubmit {
                        viewModel.sendChat()
                    }
                
                Button(action: {
                    viewModel.sendChat()
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background {
            Color(NSColor.controlBackgroundColor)
        }
    }
}

// MARK: - Resizable Divider

struct ResizableDivider: View {
    @Binding var height: CGFloat
    let totalHeight: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    @State private var isDragging = false
    
    var body: some View {
        ZStack {
            Divider()
            
            Rectangle()
                .fill(Color.clear)
                .frame(height: 8)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                            }
                            
                            let newHeight = height - value.translation.height
                            let clampedHeight = max(minHeight, min(maxHeight, newHeight))
                            height = clampedHeight
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
        }
        .background {
            if isDragging {
                Color.accentColor.opacity(0.1)
            }
        }
    }
}

// MARK: - Resizable Input Divider

struct ResizableInputDivider: View {
    @Binding var height: CGFloat
    @State private var isDragging = false
    private let minHeight: CGFloat = 40  // 最小高度（单行）
    private let maxHeight: CGFloat = 200  // 最大高度
    
    var body: some View {
        ZStack {
            Divider()
            
            Rectangle()
                .fill(Color.clear)
                .frame(height: 8)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                            }
                            
                            // 向上拖拽增加高度，向下拖拽减少高度
                            let newHeight = height - value.translation.height
                            let clampedHeight = max(minHeight, min(maxHeight, newHeight))
                            height = clampedHeight
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
        }
        .background {
            if isDragging {
                Color.accentColor.opacity(0.1)
            }
        }
    }
}

// MARK: - History Intel Card

struct HistoryIntelCard: View {
    let entry: IntelEntry
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 日期
            Text(entry.date, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // 概要
            Text(entry.summary)
                .font(.headline)
                .lineLimit(2)
            
            // 正文预览
            Text(entry.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            
            // 来源标签
            if !entry.sources.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(entry.sources.prefix(3), id: \.self) { source in
                        Text(source)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.2))
                            }
                    }
                    if entry.sources.count > 3 {
                        Text("+\(entry.sources.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: isSelected ? 2 : 1)
        }
    }
}

// MARK: - Intel List Row

struct IntelListRow: View {
    let entry: IntelEntry
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.summary)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
            
            if !entry.sources.isEmpty {
                HStack(spacing: 4) {
                    ForEach(entry.sources.prefix(2), id: \.self) { source in
                        Text(source)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.2))
                            }
                    }
                    if entry.sources.count > 2 {
                        Text("+\(entry.sources.count - 2)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Text(entry.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: IntelChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(message.role == .user ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                    }
                    .foregroundStyle(message.role == .user ? .white : .primary)
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 400, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}
