//
//  MistakeAnalyzer.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation

/// 常错词分析服务
@MainActor
class MistakeAnalyzer {
    static let shared = MistakeAnalyzer()
    
    private init() {}
    
    /// 分析校正记录，提炼常错词
    /// - Parameters:
    ///   - records: 校正记录列表
    ///   - endpoint: AI API 端点
    ///   - model: AI 模型名称
    ///   - apiToken: API Token（可选）
    ///   - timeout: 超时时间
    /// - Returns: 常错词列表
    func analyzeCorrections(
        records: [TextCorrectionRecord],
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval = 30.0
    ) async throws -> [CommonMistake] {
        print("🔍 [MistakeAnalyzer] 开始分析校正记录，数量: \(records.count)")
        
        guard !records.isEmpty else {
            print("⚠️ [MistakeAnalyzer] 校正记录为空")
            return []
        }
        
        // 先进行本地统计分析
        let localMistakes = performLocalAnalysis(records: records)
        print("📊 [MistakeAnalyzer] 本地分析完成，找到 \(localMistakes.count) 个常错词")
        
        // 如果记录数量较少，直接返回本地分析结果
        if records.count < 10 {
            return localMistakes
        }
        
        // 使用AI分析
        do {
            let aiMistakes = try await performAIAnalysis(
                records: records,
                endpoint: endpoint,
                model: model,
                apiToken: apiToken,
                timeout: timeout
            )
            print("🤖 [MistakeAnalyzer] AI分析完成，找到 \(aiMistakes.count) 个常错词")
            
            // 合并AI分析和本地统计结果
            return mergeMistakes(local: localMistakes, ai: aiMistakes)
        } catch {
            print("⚠️ [MistakeAnalyzer] AI分析失败，使用本地分析结果: \(error.localizedDescription)")
            return localMistakes
        }
    }
    
    /// 本地统计分析
    private func performLocalAnalysis(records: [TextCorrectionRecord]) -> [CommonMistake] {
        var mistakeMap: [String: [Int]] = [:] // 错误词 -> [出现次数]
        var correctMap: [String: String] = [:] // 错误词 -> 正确词
        
        for record in records {
            // 使用简单的字符串差异算法找出修改的词
            let differences = findWordDifferences(original: record.originalText, corrected: record.correctedText)
            
            for (wrong, correct) in differences {
                let key = "\(wrong)|\(correct)"
                if mistakeMap[key] == nil {
                    mistakeMap[key] = []
                    correctMap[key] = correct
                }
                mistakeMap[key]?.append(1)
            }
        }
        
        // 转换为 CommonMistake 列表
        var mistakes: [CommonMistake] = []
        for (key, frequencies) in mistakeMap {
            let parts = key.split(separator: "|")
            guard parts.count == 2,
                  let correct = correctMap[key] else { continue }
            
            let wrong = String(parts[0])
            let frequency = frequencies.count
            let confidence = min(1.0, Double(frequency) / 10.0) // 置信度基于出现次数
            
            mistakes.append(CommonMistake(
                wrong: wrong,
                correct: correct,
                frequency: frequency,
                confidence: confidence
            ))
        }
        
        // 按频率排序
        return mistakes.sorted { $0.frequency > $1.frequency }
    }
    
    /// AI分析
    private func performAIAnalysis(
        records: [TextCorrectionRecord],
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval
    ) async throws -> [CommonMistake] {
        // 构建提示词
        let prompt = buildAnalysisPrompt(records: records)
        
        // 构建请求体
        let requestBody: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "system": "你是一个专业的文本分析助手。你的任务是分析语音识别中的常见错误模式。",
            "stream": false,
            "options": [
                "temperature": 0.2,
                "top_p": 0.9
            ]
        ]
        
        // 构建 URL
        guard let url = URL(string: "\(endpoint)/api/generate") else {
            throw MistakeAnalyzerError.invalidEndpoint
        }
        
        // 构建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = apiToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = timeout
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MistakeAnalyzerError.requestFailed
        }
        
        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw MistakeAnalyzerError.invalidResponse
        }
        
        // 解析JSON格式的常错词列表
        return try parseMistakesFromResponse(responseText)
    }
    
    /// 构建分析提示词
    private func buildAnalysisPrompt(records: [TextCorrectionRecord]) -> String {
        var prompt = "分析以下校正记录，找出语音识别中常见的错误模式。\n\n"
        prompt += "校正记录（原始文本 -> 校正后文本）：\n"
        
        // 只取前50条记录，避免提示词过长
        let recordsToAnalyze = Array(records.prefix(50))
        for (index, record) in recordsToAnalyze.enumerated() {
            prompt += "\(index + 1). \"\(record.originalText)\" -> \"\(record.correctedText)\"\n"
        }
        
        prompt += "\n请返回JSON格式的常错词列表，格式如下：\n"
        prompt += "[\n"
        prompt += "  {\"wrong\": \"错误词\", \"correct\": \"正确词\", \"frequency\": 出现次数},\n"
        prompt += "  ...\n"
        prompt += "]\n\n"
        prompt += "只返回JSON数组，不要包含其他文字说明。"
        
        return prompt
    }
    
    /// 从AI响应中解析常错词
    private func parseMistakesFromResponse(_ responseText: String) throws -> [CommonMistake] {
        // 尝试提取JSON部分
        let cleanedText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 查找JSON数组的开始和结束
        guard let startIndex = cleanedText.range(of: "["),
              let endIndex = cleanedText.range(of: "]", options: .backwards) else {
            throw MistakeAnalyzerError.invalidResponse
        }
        
        let jsonString = String(cleanedText[startIndex.lowerBound...endIndex.upperBound])
        
        guard let jsonData = jsonString.data(using: .utf8),
              let jsonArray = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            throw MistakeAnalyzerError.invalidResponse
        }
        
        var mistakes: [CommonMistake] = []
        for item in jsonArray {
            guard let wrong = item["wrong"] as? String,
                  let correct = item["correct"] as? String else {
                continue
            }
            
            let frequency = item["frequency"] as? Int ?? 1
            let confidence = min(1.0, Double(frequency) / 10.0)
            
            mistakes.append(CommonMistake(
                wrong: wrong,
                correct: correct,
                frequency: frequency,
                confidence: confidence
            ))
        }
        
        return mistakes
    }
    
    /// 合并本地和AI分析结果
    private func mergeMistakes(local: [CommonMistake], ai: [CommonMistake]) -> [CommonMistake] {
        var mergedMap: [String: CommonMistake] = [:]
        
        // 添加本地结果
        for mistake in local {
            let key = "\(mistake.wrong)|\(mistake.correct)"
            mergedMap[key] = mistake
        }
        
        // 合并AI结果
        for mistake in ai {
            let key = "\(mistake.wrong)|\(mistake.correct)"
            if let existing = mergedMap[key] {
                // 合并频率和置信度
                var updated = existing
                updated.frequency = max(existing.frequency, mistake.frequency)
                updated.confidence = max(existing.confidence, mistake.confidence)
                mergedMap[key] = updated
            } else {
                mergedMap[key] = mistake
            }
        }
        
        return Array(mergedMap.values).sorted { $0.frequency > $1.frequency }
    }
    
    /// 找出词级别的差异
    private func findWordDifferences(original: String, corrected: String) -> [(wrong: String, correct: String)] {
        let originalWords = original.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let correctedWords = corrected.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        var differences: [(wrong: String, correct: String)] = []
        
        // 简单的逐词比较
        let minCount = min(originalWords.count, correctedWords.count)
        for i in 0..<minCount {
            if originalWords[i] != correctedWords[i] {
                differences.append((wrong: originalWords[i], correct: correctedWords[i]))
            }
        }
        
        return differences
    }
}

enum MistakeAnalyzerError: LocalizedError {
    case invalidEndpoint
    case requestFailed
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "无效的API端点"
        case .requestFailed:
            return "AI分析请求失败"
        case .invalidResponse:
            return "AI返回格式无效"
        }
    }
}

