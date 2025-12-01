//
//  ExpenseViewModel.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

/// 记账视图模式
enum ExpenseViewMode: String, CaseIterable {
    case list = "list"          // 列表视图
    case chart = "chart"        // 图表视图
    case calendar = "calendar"  // 日历视图
    
    var displayName: String {
        switch self {
        case .list:
            return "列表"
        case .chart:
            return "图表"
        case .calendar:
            return "日历"
        }
    }
    
    var icon: String {
        switch self {
        case .list:
            return "list.bullet"
        case .chart:
            return "chart.bar.fill"
        case .calendar:
            return "calendar"
        }
    }
}

/// 记账 ViewModel
@MainActor
class ExpenseViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var isRecording: Bool = false
    @Published var isProcessingAI: Bool = false
    @Published var aiErrorMessage: String?
    @Published var aiSuccessMessage: String?
    @Published var viewMode: ExpenseViewMode = .list
    @Published var selectedType: ExpenseType? = nil  // 筛选类型
    @Published var selectedDateRange: ClosedRange<Date>? = nil  // 日期范围
    @Published var selectedImages: [(id: UUID, data: Data)] = []  // 选中的图片列表
    @Published var editingItem: ExpenseItem? = nil  // 正在编辑的条目
    
    private let store = ExpenseStore.shared
    private let aiService = ExpenseAIService.shared
    private let visionService = ReceiptVisionService.shared
    private let voiceService = VoiceInputService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // 订阅 store 的变化
        store.$items
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        store.$categories
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    var items: [ExpenseItem] {
        var filtered = store.items
        
        if let selectedType = selectedType {
            filtered = filtered.filter { $0.type == selectedType }
        }
        
        if let dateRange = selectedDateRange {
            filtered = filtered.filter { dateRange.contains($0.date) }
        }
        
        return filtered
    }
    
    var categories: [ExpenseCategory] {
        store.categories
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
        
        // 如果有图片但没有输入文字，提示用户
        if !selectedImages.isEmpty && input.isEmpty {
            aiErrorMessage = "请先输入文字说明或使用语音输入"
            return
        }
        
        // 如果既没有图片也没有文字，提示用户
        if selectedImages.isEmpty && input.isEmpty {
            aiErrorMessage = "请输入内容或上传图片"
            return
        }
        
        isProcessingAI = true
        aiErrorMessage = nil
        aiSuccessMessage = nil
        
        // 获取用户设置
        let preferences = UserPreferences.shared
        let config = preferences.getConfig(for: .expenseParsing)
        
        do {
            var finalAmount: Decimal = 0
            var finalType: ExpenseType = .expense
            var finalCategoryId: UUID?
            var finalNote: String = ""
            var finalDate: Date = Date()
            var finalImageData: Data? = nil
            
            // 如果有图片，先识别图片
            if !selectedImages.isEmpty {
                // 获取阿里云 API Key
                guard let dashScopeProfile = preferences.aiServiceProfiles.first(where: { $0.protocolType == .dashScope }),
                      !dashScopeProfile.apiKey.isEmpty else {
                    aiErrorMessage = "请先在设置中配置阿里云 DashScope API Key"
                    isProcessingAI = false
                    return
                }
                
                // 识别所有图片并累加金额
                var imageAmounts: [Decimal] = []
                var imageNotes: [String] = []
                var imageTypes: [ExpenseType] = []
                var imageCategoryIds: [UUID] = []
                var imageDates: [Date] = []
                
                for (_, imageData) in selectedImages {
                    let recognition = try await visionService.recognizeReceipt(
                        imageData: imageData,
                        apiKey: dashScopeProfile.apiKey,
                        categories: store.categories,
                        userInput: input.isEmpty ? nil : input  // 传递用户输入作为上下文
                    )
                    
                    if let amount = recognition.amountDecimal, amount > 0 {
                        imageAmounts.append(amount)
                        if let note = recognition.note, !note.isEmpty {
                            imageNotes.append(note)
                        }
                        
                        let type = ExpenseType(rawValue: recognition.type ?? "expense") ?? .expense
                        imageTypes.append(type)
                        
                        // 查找分类
                        if let categoryName = recognition.categoryName,
                           let category = store.categories.first(where: { $0.name == categoryName && $0.type == type }) {
                            imageCategoryIds.append(category.id)
                        } else if let otherCategory = store.categories.first(where: { $0.name == "其他" && $0.type == type }) {
                            imageCategoryIds.append(otherCategory.id)
                        }
                        
                        // 解析日期
                        if let dateStr = recognition.date {
                            let formatter = ISO8601DateFormatter()
                            formatter.timeZone = TimeZone.current
                            if let parsedDate = formatter.date(from: dateStr) {
                                imageDates.append(parsedDate)
                            }
                        }
                    }
                }
                
                // 累加所有金额
                finalAmount = imageAmounts.reduce(Decimal(0), +)
                
                // 确定类型（优先使用第一个图片的类型，如果都是同一类型）
                if let firstType = imageTypes.first, imageTypes.allSatisfy({ $0 == firstType }) {
                    finalType = firstType
                } else {
                    finalType = .expense  // 默认支出
                }
                
                // 确定分类（优先使用第一个图片的分类）
                if let firstCategoryId = imageCategoryIds.first {
                    finalCategoryId = firstCategoryId
                }
                
                // 合并备注：图片识别的备注 + 用户输入的文字（提炼后）
                var notes: [String] = []
                if !imageNotes.isEmpty {
                    notes.append(contentsOf: imageNotes)
                }
                if !input.isEmpty {
                    // 提炼用户输入的意思作为备注
                    notes.append(input)
                }
                finalNote = notes.joined(separator: "；")
                
                // 使用第一个图片的日期，如果没有则使用当前日期
                finalDate = imageDates.first ?? Date()
                
                // 合并所有图片数据（用于保存）
                finalImageData = selectedImages.map { $0.data }.reduce(Data(), +)
            }
            
            // 如果没有图片，使用文本解析
            if selectedImages.isEmpty {
                let parsing = try await aiService.parseUserInput(
                    input: input,
                    categories: store.categories,
                    profile: config.profile,
                    model: config.model,
                    timeout: config.timeout
                )
                
                guard let amount = parsing.amountDecimal, amount > 0 else {
                    aiErrorMessage = "未能识别出金额"
                    isProcessingAI = false
                    return
                }
                
                finalAmount = amount
                finalType = ExpenseType(rawValue: parsing.type ?? "expense") ?? .expense
                
                // 查找分类
                if let categoryName = parsing.categoryName,
                   let category = store.categories.first(where: { $0.name == categoryName && $0.type == finalType }) {
                    finalCategoryId = category.id
                } else {
                    if let otherCategory = store.categories.first(where: { $0.name == "其他" && $0.type == finalType }) {
                        finalCategoryId = otherCategory.id
                    } else {
                        if let firstCategory = store.categories.first(where: { $0.type == finalType }) {
                            finalCategoryId = firstCategory.id
                        } else {
                            aiErrorMessage = "未找到匹配的分类"
                            isProcessingAI = false
                            return
                        }
                    }
                }
                
                finalNote = parsing.note ?? input
                
                // 解析日期
                if let dateStr = parsing.date {
                    let formatter = ISO8601DateFormatter()
                    formatter.timeZone = TimeZone.current
                    if let parsedDate = formatter.date(from: dateStr) {
                        finalDate = parsedDate
                    }
                }
            }
            
            // 确保有分类
            if finalCategoryId == nil {
                if let otherCategory = store.categories.first(where: { $0.name == "其他" && $0.type == finalType }) {
                    finalCategoryId = otherCategory.id
                } else if let firstCategory = store.categories.first(where: { $0.type == finalType }) {
                    finalCategoryId = firstCategory.id
                } else {
                    aiErrorMessage = "未找到匹配的分类"
                    isProcessingAI = false
                    return
                }
            }
            
            guard let categoryId = finalCategoryId else {
                aiErrorMessage = "未找到匹配的分类"
                isProcessingAI = false
                return
            }
            
            let item = ExpenseItem(
                amount: finalAmount,
                type: finalType,
                categoryId: categoryId,
                note: finalNote.isEmpty ? nil : finalNote,
                date: finalDate,
                imageData: finalImageData
            )
            
            store.add(item)
            
            // 清空输入框和图片
            inputText = ""
            selectedImages = []
            
            // 显示成功消息
            aiSuccessMessage = "记账已保存：\(finalType.displayName) ¥\(formatAmount(finalAmount))"
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    aiSuccessMessage = nil
                }
            }
            
        } catch {
            aiErrorMessage = "AI 处理失败: \(error.localizedDescription)"
            print("❌ [ExpenseViewModel] AI 处理失败: \(error)")
        }
        
        isProcessingAI = false
    }
    
    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "0.00"
    }
    
    /// 选择图片文件（支持多选）
    func selectReceiptImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true  // 支持多选
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "选择票据图片（可多选）"
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let imageData = try? Data(contentsOf: url) {
                    selectedImages.append((id: UUID(), data: imageData))
                }
            }
        }
    }
    
    /// 删除选中的图片
    func removeSelectedImage(id: UUID) {
        selectedImages.removeAll { $0.id == id }
    }
    
    /// 清空选中的图片
    func clearSelectedImages() {
        selectedImages = []
    }
    
    // MARK: - CRUD Operations
    
    func deleteItem(_ item: ExpenseItem) {
        store.delete(item)
    }
    
    func showEditItem(_ item: ExpenseItem) {
        editingItem = item
    }
    
    func updateItem(_ item: ExpenseItem, amount: Decimal? = nil, type: ExpenseType? = nil, categoryId: UUID? = nil, note: String? = nil, date: Date? = nil) {
        var updated = item
        updated.update(amount: amount, type: type, categoryId: categoryId, note: note, date: date)
        store.update(updated)
        editingItem = nil
    }
    
    func cancelEditItem() {
        editingItem = nil
    }
    
    // MARK: - Statistics
    
    func totalAmount(for type: ExpenseType, from startDate: Date? = nil, to endDate: Date? = nil) -> Decimal {
        return store.totalAmount(for: type, from: startDate, to: endDate)
    }
    
    func amountByCategory(for type: ExpenseType, from startDate: Date? = nil, to endDate: Date? = nil) -> [UUID: Decimal] {
        return store.amountByCategory(for: type, from: startDate, to: endDate)
    }
}


