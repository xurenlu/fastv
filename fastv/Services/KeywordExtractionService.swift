//
//  KeywordExtractionService.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import NaturalLanguage

/// 关键词提取服务
@MainActor
class KeywordExtractionService {
    static let shared = KeywordExtractionService()
    
    private init() {}
    
    /// 从文本中提取关键词和实体
    /// - Parameters:
    ///   - text: 要分析的文本
    ///   - maxKeywords: 最大关键词数量
    /// - Returns: (关键词数组, 实体字典)
    func extractKeywordsAndEntities(from text: String, maxKeywords: Int = 20) -> (keywords: [String], entities: [String: [String]]) {
        var keywords: [String] = []
        var entities: [String: [String]] = [:]
        
        // 合并 summary 和 body
        let fullText = text
        
        // 使用 NaturalLanguage 框架进行命名实体识别
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = fullText
        
        // 提取命名实体
        tagger.enumerateTags(in: fullText.startIndex..<fullText.endIndex, unit: .word, scheme: .nameType) { tag, tokenRange in
            if let tag = tag {
                let entity = String(fullText[tokenRange])
                
                // 分类实体类型
                var category: String = "其他"
                switch tag {
                case .organizationName:
                    category = "公司"
                case .personalName:
                    category = "人名"
                case .placeName:
                    category = "地点"
                default:
                    category = "其他"
                }
                
                if entities[category] == nil {
                    entities[category] = []
                }
                if !entities[category]!.contains(entity) {
                    entities[category]!.append(entity)
                }
                
                // 添加到关键词
                if !keywords.contains(entity) {
                    keywords.append(entity)
                }
            }
            return true
        }
        
        // 使用词性标注提取重要名词和形容词
        tagger.enumerateTags(in: fullText.startIndex..<fullText.endIndex, unit: .word, scheme: .lexicalClass) { tag, tokenRange in
            if let tag = tag {
                let word = String(fullText[tokenRange])
                
                // 只提取名词和形容词，且长度大于1
                if word.count > 1 {
                    switch tag {
                    case .noun, .adjective:
                        if !keywords.contains(word) && !isCommonWord(word) {
                            keywords.append(word)
                        }
                    default:
                        break
                    }
                }
            }
            return true
        }
        
        // 限制关键词数量
        if keywords.count > maxKeywords {
            keywords = Array(keywords.prefix(maxKeywords))
        }
        
        return (keywords, entities)
    }
    
    /// 批量分析多条情报，提取高频关键词
    /// - Parameters:
    ///   - entries: 情报条目数组
    ///   - dateRange: 日期范围（可选）
    /// - Returns: 关键词频率字典
    func analyzeKeywordFrequency(from entries: [IntelEntry], dateRange: (from: Date, to: Date)? = nil) -> [String: Int] {
        var frequency: [String: Int] = [:]
        
        let calendar = Calendar.current
        let filteredEntries: [IntelEntry]
        
        if let range = dateRange {
            filteredEntries = entries.filter { entry in
                let entryDate = calendar.startOfDay(for: entry.date)
                let fromDate = calendar.startOfDay(for: range.from)
                let toDate = calendar.startOfDay(for: range.to)
                return entryDate >= fromDate && entryDate <= toDate
            }
        } else {
            filteredEntries = entries
        }
        
        // 统计所有关键词的频率
        for entry in filteredEntries {
            // 使用已提取的关键词
            for keyword in entry.keywords {
                frequency[keyword, default: 0] += 1
            }
            
            // 如果没有关键词，临时提取
            if entry.keywords.isEmpty {
                let (keywords, _) = extractKeywordsAndEntities(from: "\(entry.summary) \(entry.body)")
                for keyword in keywords {
                    frequency[keyword, default: 0] += 1
                }
            }
        }
        
        return frequency
    }
    
    /// 判断是否为常见词（停用词）
    private func isCommonWord(_ word: String) -> Bool {
        let commonWords: Set<String> = [
            "的", "了", "在", "是", "我", "有", "和", "就", "不", "人", "都", "一", "一个", "上", "也", "很", "到", "说", "要", "去", "你", "会", "着", "没有", "看", "好", "自己", "这",
            "the", "be", "to", "of", "and", "a", "in", "that", "have", "i", "it", "for", "not", "on", "with", "he", "as", "you", "do", "at", "this", "but", "his", "by", "from", "they", "we", "say", "her", "she", "or", "an", "will", "my", "one", "all", "would", "there", "their"
        ]
        return commonWords.contains(word.lowercased())
    }
    
    /// 为情报条目提取并更新关键词（后台执行）
    func extractKeywordsForEntry(_ entry: IntelEntry) async -> IntelEntry {
        return await Task.detached {
            let text = "\(entry.summary) \(entry.body)"
            let (keywords, entities) = await MainActor.run {
                KeywordExtractionService.shared.extractKeywordsAndEntities(from: text)
            }
            
            var updatedEntry = entry
            updatedEntry.keywords = keywords
            updatedEntry.entities = entities
            updatedEntry.updatedAt = Date()
            
            return updatedEntry
        }.value
    }
}

