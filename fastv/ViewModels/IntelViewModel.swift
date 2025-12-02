//
//  IntelViewModel.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import Combine

/// 情报聊天消息（简化版，仅用于情报功能的聊天界面）
struct IntelChatMessage: Identifiable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    
    enum ChatRole {
        case user
        case assistant
    }
    
    init(id: UUID = UUID(), role: ChatRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

/// 标签页类型
enum IntelTab: String, CaseIterable {
    case today = "今日的情报"
    case history = "历史情报"
}

/// 情报 ViewModel
@MainActor
class IntelViewModel: ObservableObject {
    @Published var selectedDate: Date = Date()
    @Published var entries: [IntelEntry] = []
    @Published var isLoadingTodayAutoIntel: Bool = false
    @Published var chatInput: String = ""
    @Published var chatMessages: [IntelChatMessage] = []
    @Published var errorMessage: String?
    @Published var selectedEntry: IntelEntry? = nil
    @Published var selectedTab: IntelTab = .today
    @Published var historySearchText: String = ""
    @Published var chatSectionHeight: CGFloat = 200
    @Published var inputFieldHeight: CGFloat = 60  // 默认两行高度（约60像素）
    @Published var selectedKeyword: String? = nil  // 用于词云筛选
    @Published var calendarDisplayMonths: [Date] = []  // 当前显示的三个月
    
    private let store = IntelStore.shared
    private let aiService = IntelAIService.shared
    private let keywordService = KeywordExtractionService.shared
    private var cancellables = Set<AnyCancellable>()
    private var hasCheckedTodayIntel = false
    
    /// 历史情报列表（用于历史回顾标签页）
    var historyEntries: [IntelEntry] {
        let allEntries = store.entries
        let calendar = Calendar.current
        let today = Date()
        
        // 过滤掉今天的情报
        var history = allEntries.filter { entry in
            !calendar.isDate(entry.date, inSameDayAs: today)
        }
        
        // 如果有关键词筛选，先按关键词筛选
        if let keyword = selectedKeyword {
            history = history.filter { entry in
                entry.keywords.contains { $0.lowercased() == keyword.lowercased() } ||
                entry.summary.lowercased().contains(keyword.lowercased()) ||
                entry.body.lowercased().contains(keyword.lowercased())
            }
        }
        
        // 如果搜索文本不为空，进行搜索
        if !historySearchText.isEmpty {
            let searchText = historySearchText.lowercased()
            history = history.filter { entry in
                entry.summary.lowercased().contains(searchText) ||
                entry.body.lowercased().contains(searchText) ||
                entry.sources.contains { $0.lowercased().contains(searchText) } ||
                entry.keywords.contains { $0.lowercased().contains(searchText) }
            }
        }
        
        return history.sorted { $0.date > $1.date }
    }
    
    init() {
        // 订阅 store 的变化
        store.$entries
            .sink { [weak self] _ in
                self?.loadEntriesForSelectedDate()
            }
            .store(in: &cancellables)
        
        // 初始化时加载当前日期的情报
        loadEntriesForSelectedDate()
        
        // 初始化日历显示月份（最近三个月）
        updateCalendarDisplayMonths()
    }
    
    // MARK: - Load Operations
    
    /// 加载指定日期的情报
    func load(date: Date) {
        selectedDate = date
        loadEntriesForSelectedDate()
        hasCheckedTodayIntel = false
    }
    
    /// 加载当前选中日期的情报
    private func loadEntriesForSelectedDate() {
        entries = store.entries(for: selectedDate)
        selectedEntry = entries.first
    }
    
    /// 确保今天的情报已生成（如果需要）
    func ensureTodayIntelIfNeeded() {
        let calendar = Calendar.current
        let today = Date()
        
        // 只在今天且还没有检查过时才自动生成
        guard calendar.isDate(selectedDate, inSameDayAs: today),
              !hasCheckedTodayIntel,
              entries.isEmpty else {
            hasCheckedTodayIntel = true
            return
        }
        
        hasCheckedTodayIntel = true
        
        // 如果今天还没有情报，自动生成
        Task {
            await generateTodayIntel()
        }
    }
    
    /// 生成今天的情报
    private func generateTodayIntel() async {
        isLoadingTodayAutoIntel = true
        errorMessage = nil
        
        // 获取用户设置
        let preferences = UserPreferences.shared
        let config = preferences.getConfig(for: .intelGeneration)
        
        do {
            let generatedEntries = try await aiService.generateTodayIntelSummary(
                date: selectedDate,
                profile: config.profile,
                model: config.model,
                timeout: config.timeout
            )
            
            // 为每条情报提取关键词
            var entriesWithKeywords: [IntelEntry] = []
            for entry in generatedEntries {
                let (keywords, entities) = keywordService.extractKeywordsAndEntities(
                    from: "\(entry.summary) \(entry.body)"
                )
                var updatedEntry = entry
                updatedEntry.keywords = keywords
                updatedEntry.entities = entities
                entriesWithKeywords.append(updatedEntry)
            }
            
            // 保存生成的情报（带关键词）
            store.setEntries(entriesWithKeywords, for: selectedDate)
            
            // 刷新列表
            loadEntriesForSelectedDate()
            
        } catch {
            errorMessage = "生成情报失败: \(error.localizedDescription)"
            print("❌ [IntelViewModel] 生成情报失败: \(error)")
        }
        
        isLoadingTodayAutoIntel = false
    }
    
    // MARK: - Chat Operations
    
    /// 发送聊天消息
    func sendChat() {
        let message = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            errorMessage = "请输入消息"
            return
        }
        
        // 添加用户消息到聊天记录
        let userMessage = IntelChatMessage(role: .user, content: message)
        chatMessages.append(userMessage)
        
        // 清空输入框
        chatInput = ""
        
        // 发送到 AI
        Task {
            await processChatMessage(message)
        }
    }
    
    /// 处理聊天消息
    private func processChatMessage(_ message: String) async {
        errorMessage = nil
        
        // 获取今天的情报概要列表
        let todaySummaries = entries.map { $0.summary }
        
        // 获取用户设置
        let preferences = UserPreferences.shared
        let config = preferences.getConfig(for: .intelGeneration)
        
        do {
            let result = try await aiService.chatAboutIntel(
                date: selectedDate,
                message: message,
                todayEntrySummaries: todaySummaries,
                profile: config.profile,
                model: config.model,
                timeout: config.timeout
            )
            
            // 添加 AI 回复到聊天记录
            let assistantMessage = IntelChatMessage(role: .assistant, content: result.displayReply)
            chatMessages.append(assistantMessage)
            
            // 如果返回了 JSON，解析并更新情报
            if let jsonString = result.replacementEntriesJSON {
                print("🔄 [IntelViewModel] 收到 JSON 替换指令，开始处理...")
                print("🔄 [IntelViewModel] JSON 内容: \(jsonString)")
                await processReplacementJSON(jsonString)
            } else {
                print("ℹ️ [IntelViewModel] AI 返回普通对话，未检测到 JSON 格式")
            }
            
        } catch {
            errorMessage = "聊天失败: \(error.localizedDescription)"
            print("❌ [IntelViewModel] 聊天失败: \(error)")
            
            // 添加错误消息到聊天记录
            let errorMessage = IntelChatMessage(role: .assistant, content: "抱歉，处理失败：\(error.localizedDescription)")
            chatMessages.append(errorMessage)
        }
    }
    
    /// 处理替换情报的 JSON
    private func processReplacementJSON(_ jsonString: String) async {
        print("🔄 [IntelViewModel] 开始解析 JSON...")
        print("🔄 [IntelViewModel] JSON 字符串: \(jsonString)")
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ [IntelViewModel] JSON 字符串无法转换为 Data")
            errorMessage = "解析 JSON 失败：无法转换字符串"
            return
        }
        
        guard let parsedJson = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("❌ [IntelViewModel] JSON 解析失败，无法转换为字典")
            if let error = try? JSONSerialization.jsonObject(with: jsonData) {
                print("❌ [IntelViewModel] 解析结果: \(error)")
            }
            errorMessage = "解析 JSON 失败：格式错误"
            return
        }
        
        print("✅ [IntelViewModel] JSON 解析成功")
        print("✅ [IntelViewModel] 解析后的字典键: \(parsedJson.keys)")
        
        guard let entriesArray = parsedJson["intel_entries"] as? [[String: Any]] else {
            print("❌ [IntelViewModel] 未找到 intel_entries 字段")
            print("❌ [IntelViewModel] 可用字段: \(parsedJson.keys)")
            errorMessage = "解析 JSON 失败：未找到 intel_entries 字段"
            return
        }
        
        print("✅ [IntelViewModel] 找到 \(entriesArray.count) 条情报条目")
        
        // 转换为 IntelEntry 数组
        var newEntries: [IntelEntry] = []
        for (index, entryDict) in entriesArray.enumerated() {
            print("🔄 [IntelViewModel] 处理第 \(index + 1) 条情报...")
            print("🔄 [IntelViewModel] 条目字典: \(entryDict)")
            
            guard let summary = entryDict["summary"] as? String,
                  let body = entryDict["body"] as? String else {
                print("⚠️ [IntelViewModel] 第 \(index + 1) 条情报缺少必要字段")
                continue
            }
            let sources = entryDict["sources"] as? [String] ?? []
            
            print("✅ [IntelViewModel] 第 \(index + 1) 条情报解析成功:")
            print("   - 概要: \(summary)")
            print("   - 正文长度: \(body.count)")
            print("   - 来源: \(sources)")
            
            // 提取关键词
            let (keywords, entities) = keywordService.extractKeywordsAndEntities(
                from: "\(summary) \(body)"
            )
            
            let entry = IntelEntry(
                summary: summary,
                body: body,
                sources: sources,
                keywords: keywords,
                entities: entities,
                date: selectedDate
            )
            newEntries.append(entry)
        }
        
        print("✅ [IntelViewModel] 共解析出 \(newEntries.count) 条有效情报")
        
        // 整体替换今天的情报
        store.setEntries(newEntries, for: selectedDate)
        
        print("✅ [IntelViewModel] 情报已更新到存储")
        
        // 刷新列表
        loadEntriesForSelectedDate()
        
        print("✅ [IntelViewModel] 情报列表已刷新，当前有 \(entries.count) 条情报")
    }
    
    // MARK: - CRUD Operations
    
    func deleteEntry(_ entry: IntelEntry) {
        store.delete(entry)
        if selectedEntry?.id == entry.id {
            selectedEntry = entries.first
        }
    }
    
    func updateEntry(_ entry: IntelEntry, summary: String? = nil, body: String? = nil, sources: [String]? = nil) {
        var updated = entry
        updated.update(summary: summary, body: body, sources: sources)
        store.update(updated)
        if selectedEntry?.id == entry.id {
            selectedEntry = updated
        }
    }
    
    func selectEntry(_ entry: IntelEntry) {
        selectedEntry = entry
    }
    
    // MARK: - History Operations
    
    /// 获取所有历史日期（用于历史回顾）
    var historyDates: [Date] {
        let calendar = Calendar.current
        let today = Date()
        let allEntries = store.entries
        
        // 获取所有不重复的日期（排除今天）
        let dates = Set(allEntries.map { entry in
            calendar.startOfDay(for: entry.date)
        }).filter { date in
            !calendar.isDate(date, inSameDayAs: today)
        }
        
        return Array(dates).sorted(by: >)
    }
    
    /// 获取指定日期的历史情报
    func historyEntries(for date: Date) -> [IntelEntry] {
        return store.entries(for: date)
    }
    
    // MARK: - Calendar Operations
    
    /// 更新日历显示的月份（最近三个月）
    func updateCalendarDisplayMonths() {
        let calendar = Calendar.current
        let today = Date()
        
        // 获取最近三个月的第一天
        var months: [Date] = []
        for i in 0..<3 {
            if let month = calendar.date(byAdding: .month, value: -i, to: today) {
                if let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) {
                    months.append(firstDay)
                }
            }
        }
        
        calendarDisplayMonths = months.reversed()  // 从旧到新排序
    }
    
    /// 切换到下三个月
    func nextThreeMonths() {
        guard let lastMonth = calendarDisplayMonths.last else {
            updateCalendarDisplayMonths()
            return
        }
        
        let calendar = Calendar.current
        var newMonths: [Date] = []
        
        for i in 1...3 {
            if let month = calendar.date(byAdding: .month, value: i, to: lastMonth) {
                if let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) {
                    newMonths.append(firstDay)
                }
            }
        }
        
        if !newMonths.isEmpty {
            calendarDisplayMonths = newMonths
        }
    }
    
    /// 切换到前三个月
    func previousThreeMonths() {
        guard let firstMonth = calendarDisplayMonths.first else {
            updateCalendarDisplayMonths()
            return
        }
        
        let calendar = Calendar.current
        var newMonths: [Date] = []
        
        for i in 1...3 {
            if let month = calendar.date(byAdding: .month, value: -i, to: firstMonth) {
                if let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) {
                    newMonths.append(firstDay)
                }
            }
        }
        
        if !newMonths.isEmpty {
            calendarDisplayMonths = newMonths.reversed()
        }
    }
    
    // MARK: - Keyword Operations
    
    /// 计算指定日期范围的关键词频率
    func keywordFrequency(from startDate: Date, to endDate: Date) -> [String: Int] {
        return keywordService.analyzeKeywordFrequency(from: store.entries, dateRange: (from: startDate, to: endDate))
    }
    
    /// 获取最近三个月的关键词频率（用于词云）
    var recentThreeMonthsKeywordFrequency: [String: Int] {
        guard let firstMonth = calendarDisplayMonths.first,
              let lastMonth = calendarDisplayMonths.last else {
            return [:]
        }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: firstMonth)
        
        // 获取最后一个月最后一天
        var endComponents = calendar.dateComponents([.year, .month], from: lastMonth)
        endComponents.day = calendar.range(of: .day, in: .month, for: lastMonth)?.count ?? 31
        let endDate = calendar.date(from: endComponents) ?? lastMonth
        
        return keywordFrequency(from: startDate, to: endDate)
    }
    
    /// 按关键词筛选情报
    func filterByKeyword(_ keyword: String?) {
        selectedKeyword = keyword
    }
    
    /// 清除关键词筛选
    func clearKeywordFilter() {
        selectedKeyword = nil
    }
    
    /// 检查指定日期是否有情报
    func hasEntries(for date: Date) -> Bool {
        return !store.entries(for: date).isEmpty
    }
}

