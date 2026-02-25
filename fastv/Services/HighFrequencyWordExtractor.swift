//
//  HighFrequencyWordExtractor.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import Combine

/// 高频词
struct HighFrequencyWord: Codable, Identifiable {
    let id: UUID
    let word: String
    let frequency: Int
    let lastUpdated: Date
    
    init(word: String, frequency: Int, lastUpdated: Date = Date()) {
        self.id = UUID()
        self.word = word
        self.frequency = frequency
        self.lastUpdated = lastUpdated
    }
}

/// 高频词提取器
@MainActor
class HighFrequencyWordExtractor: ObservableObject {
    static let shared = HighFrequencyWordExtractor()
    
    @Published private(set) var highFrequencyWords: [HighFrequencyWord] = []
    @Published private(set) var isExtracting = false
    @Published private(set) var extractionProgress: String = ""
    
    private let storageKey = "highFrequencyWords"
    private let minFrequency = 3 // 最少出现3次才算高频词
    private let minWordLength = 2 // 最少2个字符
    private let maxWordLength = 20 // 最多20个字符
    
    private init() {
        loadHighFrequencyWords()
    }
    
    /// 从文本中提取单词
    private func extractWords(from text: String) -> [String] {
        // 移除标点符号，保留中英文、数字
        let cleanedText = text
            .replacingOccurrences(of: "[，。！？；：、\"\"''（）【】《》〈〉「」『』〔〕〖〗〘〙〚〛…—–·～]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[!\"#$%&'()*+,\\-./:;<=>?@\\[\\]^_`{|}~]", with: " ", options: .regularExpression)
        
        // 按空格分割
        let words = cleanedText
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        return words
    }
    
    /// 检查是否是有效的词
    private func isValidWord(_ word: String) -> Bool {
        // 不能全是数字
        if word.allSatisfy({ $0.isNumber }) {
            return false
        }
        
        // 不能全是标点符号
        if word.allSatisfy({ !$0.isLetter && !$0.isNumber && !$0.isCJK }) {
            return false
        }
        
        return true
    }
    
    /// 获取高频词列表（用于AI纠错）
    func getWordsForAICorrection() -> [String] {
        // 返回频率最高的前100个词
        return Array(highFrequencyWords.prefix(100).map { $0.word })
    }
    
    /// 获取高频词描述（用于AI提示词）
    func getWordsDescription() -> String {
        guard !highFrequencyWords.isEmpty else {
            return "暂无高频词数据"
        }
        
        let topWords = Array(highFrequencyWords.prefix(50))
        let wordsList = topWords.map { "\($0.word)(\($0.frequency)次)" }.joined(separator: ", ")
        return "用户常用词汇（按频率排序）：\(wordsList)"
    }
    
    /// 清空高频词
    func clear() {
        highFrequencyWords.removeAll()
        saveHighFrequencyWords()
    }
    
    // MARK: - Persistence
    
    private func saveHighFrequencyWords() {
        if let encoded = try? JSONEncoder().encode(highFrequencyWords) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func loadHighFrequencyWords() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            highFrequencyWords = []
            return
        }
        
        if let decoded = try? JSONDecoder().decode([HighFrequencyWord].self, from: data) {
            highFrequencyWords = decoded
        } else {
            highFrequencyWords = []
        }
    }
}

// MARK: - Character Extension

extension Character {
    /// 是否是中文字符
    var isCJK: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.value >= 0x4E00 && scalar.value <= 0x9FFF ||
               scalar.value >= 0x3400 && scalar.value <= 0x4DBF ||
               scalar.value >= 0x20000 && scalar.value <= 0x2A6DF ||
               scalar.value >= 0x2A700 && scalar.value <= 0x2B73F ||
               scalar.value >= 0x2B740 && scalar.value <= 0x2B81F ||
               scalar.value >= 0x2B820 && scalar.value <= 0x2CEAF ||
               scalar.value >= 0xF900 && scalar.value <= 0xFAFF ||
               scalar.value >= 0x2F800 && scalar.value <= 0x2FA1F
    }
}

