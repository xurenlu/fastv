//
//  TextCorrectionService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// 快速文本纠错服务
/// 专为 ASR 错误设计，速度极快（毫秒级）
/// 注意：纠错规则已迁移到 CommonMistakeManager，此服务仅保留清理逻辑
@MainActor
class TextCorrectionService {
    static let shared = TextCorrectionService()
    
    private init() {}
    
    // MARK: - 文本纠错
    
    /// 快速纠正文本中的错别字
    /// - Parameter text: 原始文本
    /// - Returns: 纠正后的文本
    func correctText(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        
        // 使用 CommonMistakeManager 进行纠错（包含所有内置规则和用户自定义规则）
        var correctedText = CommonMistakeManager.shared.applyCorrections(to: text)
        
        // 清理多余的空格和标点
        correctedText = cleanText(correctedText)
        
        return correctedText
    }
    
    /// 清理文本：去除多余空格、标点等
    private func cleanText(_ text: String) -> String {
        var cleaned = text
        
        // 去除多余的空格（优化：限制循环次数，避免无限循环）
        var maxSpaceIterations = 10
        while cleaned.contains("  ") && maxSpaceIterations > 0 {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ", options: [], range: nil)
            maxSpaceIterations -= 1
        }
        
        // 去除开头和结尾的空格
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        
        // 去除重复的标点符号（保留一个）- 优化：限制循环次数
        let punctuationPatterns = [
            ("。。", "。"),
            ("，，", "，"),
            ("？？", "？"),
            ("！！", "！"),
            ("：：", "："),
            ("；；", "；"),
        ]
        
        for (pattern, replacement) in punctuationPatterns {
            var maxIterations = 10 // 限制最大迭代次数
            while cleaned.contains(pattern) && maxIterations > 0 {
                cleaned = cleaned.replacingOccurrences(of: pattern, with: replacement)
                maxIterations -= 1
            }
        }
        
        return cleaned
    }
    
    /// 快速纠正文本（异步版本，用于性能测试）
    /// - Parameter text: 原始文本
    /// - Returns: 纠正后的文本
    func correctTextAsync(_ text: String) async -> String {
        // 在实际应用中，这个方法可以用于批量处理
        // 当前实现是同步的，但保持异步接口以便未来扩展
        return correctText(text)
    }
    
    // MARK: - 性能测试
    
    /// 测试纠错性能
    /// - Parameter text: 测试文本
    /// - Returns: (纠正后的文本, 耗时毫秒)
    func testCorrection(_ text: String) -> (correctedText: String, durationMs: Double) {
        let startTime = Date()
        let corrected = correctText(text)
        let duration = Date().timeIntervalSince(startTime) * 1000 // 转换为毫秒
        
        return (corrected, duration)
    }
}
