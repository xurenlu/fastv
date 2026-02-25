//
//  AICorrectionDetectionService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// AI 错误检测服务
/// 使用专门的模型来检测语音识别中的错误
@MainActor
class AICorrectionDetectionService {
    static let shared = AICorrectionDetectionService()
    
    private init() {}
    
    /// 检测语音识别文本中的错误
    /// - Parameters:
    ///   - text: 原始识别文本
    ///   - endpoint: API 端点地址
    ///   - model: 用于错误检测的模型名称（应该使用更强的推理模型）
    ///   - apiToken: API Token（可选）
    ///   - timeout: 超时时间（秒）
    ///   - highFrequencyWords: 用户高频词列表（用于上下文）
    /// - Returns: 错误检测结果
    func detectErrors(
        text: String,
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval = 10.0,
        highFrequencyWords: [String] = []
    ) async throws -> CorrectionDetectionResult {
        print("🔍 [AICorrectionDetectionService] 开始检测错误，文本长度: \(text.count)")
        print("🔍 [AICorrectionDetectionService] 使用模型: \(model)")
        
        // 构建系统提示词
        var systemPrompt = """
你是一个专业的语音识别错误检测助手。你的任务是分析语音识别结果，找出可能的识别错误。

任务要求：
1. 仔细分析文本的上下文和语义
2. 识别出不符合上下文或语义的词语
3. 推断正确的词语应该是什么
4. 只检测明显的错误，不要过度纠正

输出格式（JSON）：
{
  "errors": [
    {
      "wrong": "识别错误的词",
      "correct": "正确的词",
      "context": "错误词所在的上下文（前后各10-20字）",
      "confidence": 0.8
    }
  ],
  "corrected_text": "修正后的完整文本"
}

注意：
- confidence 范围是 0.0-1.0，表示你对这个修正的置信度
- 如果没有发现错误，返回空的 errors 数组
- corrected_text 是应用所有修正后的完整文本
- 只返回 JSON，不要其他内容
"""
        
        // 如果有高频词，添加到提示词中
        if !highFrequencyWords.isEmpty {
            let wordsList = highFrequencyWords.prefix(50).joined(separator: ", ")
            systemPrompt += "\n\n用户常用词汇（可能有助于判断）：\(wordsList)"
        }
        
        // 构建用户提示词
        let userPrompt = """
请分析以下语音识别文本，检测可能的识别错误：

文本：
\(text)

请仔细分析上下文，找出不符合语义或上下文的词语，并推断正确的词语。
"""
        
        // 构建请求体
        let requestBody: [String: Any] = [
            "model": model,
            "prompt": userPrompt,
            "system": systemPrompt,
            "stream": false,
            "options": [
                "temperature": 0.2,  // 较低温度以获得更确定的检测结果
                "top_p": 0.9
            ]
        ]
        
        // 构建 URL
        guard let url = URL(string: "\(endpoint)/api/generate") else {
            throw OllamaError.invalidEndpoint
        }
        
        // 构建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 如果有 API Token，添加到请求头
        if let token = apiToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // 设置请求体
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // 设置超时时间（错误检测需要更多时间）
        request.timeoutInterval = timeout
        
        print("🔍 [AICorrectionDetectionService] 发送错误检测请求（超时: \(timeout)秒）...")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        
        print("🔍 [AICorrectionDetectionService] 收到响应，状态码: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [AICorrectionDetectionService] 请求失败: \(errorMessage)")
            throw OllamaError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            print("❌ [AICorrectionDetectionService] 无法解析响应")
            throw OllamaError.invalidResponse
        }
        
        let rawResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 尝试解析 JSON（可能包含在代码块中）
        var jsonString = rawResponse
        
        // 移除可能的 markdown 代码块标记
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 解析 JSON
        guard let jsonData = jsonString.data(using: .utf8),
              let parsedJson = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("⚠️ [AICorrectionDetectionService] JSON 解析失败，尝试降级处理")
            // 降级：返回空结果
            return CorrectionDetectionResult(
                originalText: text,
                correctedText: text,
                detectionModel: model
            )
        }
        
        // 提取错误列表
        var detectionItems: [CorrectionDetectionItem] = []
        if let errors = parsedJson["errors"] as? [[String: Any]] {
            for error in errors {
                if let wrong = error["wrong"] as? String,
                   let correct = error["correct"] as? String,
                   let context = error["context"] as? String {
                    let confidence = (error["confidence"] as? Double) ?? 0.5
                    let item = CorrectionDetectionItem(
                        wrongText: wrong,
                        correctText: correct,
                        context: context,
                        confidence: confidence
                    )
                    detectionItems.append(item)
                }
            }
        }
        
        // 提取修正后的文本
        let correctedText = (parsedJson["corrected_text"] as? String) ?? text
        
        print("✅ [AICorrectionDetectionService] 检测完成，发现 \(detectionItems.count) 个可能的错误")
        
        return CorrectionDetectionResult(
            items: detectionItems,
            originalText: text,
            correctedText: correctedText,
            detectionModel: model
        )
    }
}

