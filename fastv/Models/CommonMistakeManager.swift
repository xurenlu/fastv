//
//  CommonMistakeManager.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import Combine

/// 常错词管理器
@MainActor
class CommonMistakeManager: ObservableObject {
    static let shared = CommonMistakeManager()
    
    @Published private(set) var mistakes: [CommonMistake] = []
    @Published var enableAutoCorrection: Bool {
        didSet {
            UserDefaults.standard.set(enableAutoCorrection, forKey: "commonMistakeEnableAutoCorrection")
        }
    }
    
    private let storageKey = "commonMistakes"
    private var correctionCache: [String: String] = [:] // 缓存：错误词 -> 正确词
    private var sortedMistakesCache: [CommonMistake]? // 缓存排序后的常错词
    private var regexCache: [String: NSRegularExpression] = [:] // 缓存正则表达式
    
    private init() {
        enableAutoCorrection = UserDefaults.standard.bool(forKey: "commonMistakeEnableAutoCorrection")
        loadMistakes()
        updateCache()
    }
    
    /// 添加或更新常错词
    func addOrUpdate(wrong: String, correct: String, frequency: Int = 1, confidence: Double = 0.5) {
        // 查找是否已存在
        if let index = mistakes.firstIndex(where: { $0.wrong == wrong && $0.correct == correct }) {
            // 更新现有记录
            var mistake = mistakes[index]
            let newFrequency = mistake.frequency + frequency
            let newConfidence = max(mistake.confidence, confidence)
            mistake.update(frequency: newFrequency, confidence: newConfidence)
            mistakes[index] = mistake
        } else {
            // 添加新记录
            let mistake = CommonMistake(
                wrong: wrong,
                correct: correct,
                frequency: frequency,
                confidence: confidence
            )
            mistakes.append(mistake)
        }
        
        invalidateCaches()
        saveMistakes()
    }
    
    /// 删除常错词
    func remove(_ mistake: CommonMistake) {
        mistakes.removeAll { $0.id == mistake.id }
        invalidateCaches()
        saveMistakes()
    }
    
    /// 删除多个常错词
    func remove(_ mistakes: [CommonMistake]) {
        let ids = Set(mistakes.map { $0.id })
        self.mistakes.removeAll { ids.contains($0.id) }
        invalidateCaches()
        saveMistakes()
    }
    
    /// 更新常错词
    func update(_ mistake: CommonMistake) {
        if let index = mistakes.firstIndex(where: { $0.id == mistake.id }) {
            mistakes[index] = mistake
            invalidateCaches()
            saveMistakes()
        }
    }
    
    /// 应用常错词修正
    func applyCorrections(to text: String) -> String {
        guard enableAutoCorrection, !mistakes.isEmpty, !text.isEmpty else { return text }
        
        var result = text
        
        // 使用缓存的排序结果
        let sortedMistakes = getSortedMistakes()
        
        // 快速检查：如果文本中不包含任何错误词，直接返回（避免不必要的正则操作）
        let textLowercased = text.lowercased()
        let relevantMistakes = sortedMistakes.filter { mistake in
            textLowercased.contains(mistake.wrong.lowercased())
        }
        
        guard !relevantMistakes.isEmpty else { return text }
        
        // 限制处理的常错词数量，避免性能问题（最多处理前50个）
        let mistakesToProcess = Array(relevantMistakes.prefix(50))
        
        for mistake in mistakesToProcess {
            // 只替换完整的词（避免误替换）
            // 使用缓存的正则表达式
            let regex = getOrCreateRegex(for: mistake.wrong)
            let range = NSRange(location: 0, length: result.utf16.count)
            let newResult = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: mistake.correct
            )
            
            // 如果替换成功，更新结果
            if newResult != result {
                result = newResult
            }
        }
        
        return result
    }
    
    /// 获取排序后的常错词（使用缓存）
    private func getSortedMistakes() -> [CommonMistake] {
        if let cached = sortedMistakesCache {
            return cached
        }
        let sorted = mistakes.sorted { $0.confidence > $1.confidence }
        sortedMistakesCache = sorted
        return sorted
    }
    
    /// 获取或创建正则表达式（使用缓存）
    private func getOrCreateRegex(for pattern: String) -> NSRegularExpression {
        if let cached = regexCache[pattern] {
            return cached
        }
        let escapedPattern = "\\b\(NSRegularExpression.escapedPattern(for: pattern))\\b"
        if let regex = try? NSRegularExpression(pattern: escapedPattern, options: []) {
            regexCache[pattern] = regex
            return regex
        }
        // 如果创建失败，返回一个不会匹配任何内容的正则
        return try! NSRegularExpression(pattern: "(?!.*)", options: [])
    }
    
    /// 获取统计信息
    func totalCount() -> Int {
        mistakes.count
    }
    
    /// 获取总修正次数
    func totalCorrections() -> Int {
        mistakes.reduce(0) { $0 + $1.frequency }
    }
    
    /// 更新缓存
    private func updateCache() {
        correctionCache.removeAll()
        for mistake in mistakes {
            correctionCache[mistake.wrong] = mistake.correct
        }
    }
    
    /// 使缓存失效
    private func invalidateCaches() {
        updateCache()
        sortedMistakesCache = nil
        regexCache.removeAll()
    }
    
    // MARK: - Persistence
    
    private func saveMistakes() {
        if let encoded = try? JSONEncoder().encode(mistakes) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func loadMistakes() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            mistakes = []
            return
        }
        
        if let decoded = try? JSONDecoder().decode([CommonMistake].self, from: data) {
            mistakes = decoded
        } else {
            mistakes = []
        }
    }
}

