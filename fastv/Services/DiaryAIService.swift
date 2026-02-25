//
//  DiaryAIService.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation

/// 日记 AI 分析结果
struct DiaryAnalysisResult: Codable {
    var title: String?
    var summary: String?        // 摘要（50字以内）
    var mood: String?           // 心情标签：happy, calm, sad, anxious, excited, tired
    var moodAnalysis: String?   // 情绪分析文本
}

/// 日记 AI 服务
@MainActor
class DiaryAIService {
    static let shared = DiaryAIService()
    
    private init() {}
    
    /// 分析日记内容（提取标题、生成摘要、分析情绪）
    /// - Parameters:
    ///   - content: 日记内容
    ///   - profile: AI 服务配置
    ///   - model: 模型名称（覆盖 profile 默认模型）
    ///   - timeout: 超时时间（覆盖 profile 默认超时）
    /// - Returns: 分析结果
    func analyzeDiary(
        content: String,
        profile: AIServiceProfile,
        model: String? = nil,
        timeout: Double? = nil
    ) async throws -> DiaryAnalysisResult {
        let effectiveModel = model ?? profile.defaultModel
        let effectiveTimeout = timeout ?? profile.timeout
        
        return try await analyzeDiaryLegacy(
            content: content,
            endpoint: profile.effectiveEndpoint,
            model: effectiveModel,
            apiToken: profile.apiKey.isEmpty ? nil : profile.apiKey,
            timeout: effectiveTimeout
        )
    }
    
    /// 分析日记内容（旧版兼容方法）
    func analyzeDiaryLegacy(
        content: String,
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval = 30.0
    ) async throws -> DiaryAnalysisResult {
        print("🤖 [DiaryAIService] 开始分析日记内容，长度: \(content.count)")
        
        let systemPrompt = #"""
你是一个智能日记助手。用户会输入日记内容，你需要：

1. 提取或生成一个简洁的标题（10字以内）
2. 生成一个50字以内的摘要
3. 分析用户的心情，从以下选项中选择一个：happy（开心）、calm（平静）、sad（难过）、anxious（焦虑）、excited（兴奋）、tired（疲惫）
4. 提供一段简短的情绪分析（30字以内）

【输出格式】
只返回 JSON 对象，格式如下：
{
  "title": "日记标题",
  "summary": "摘要内容（50字以内）",
  "mood": "happy",
  "moodAnalysis": "情绪分析文本（30字以内）"
}

【重要规则】
1. 只返回 JSON 对象，不要其他任何内容
2. 如果内容为空或无法分析，返回空字符串或 null
3. 心情标签必须严格从以下选项中选择：happy, calm, sad, anxious, excited, tired
"""#
        
        let userPrompt = """
日记内容：
\(content)

请分析这段日记内容，提取标题、生成摘要、分析情绪。
"""
        
        // 检测 API 类型
        let apiType = AITodoAIService.detectAPIType(endpoint: endpoint)
        
        // 构建 URL
        let url = try AITodoAIService.buildAPIURL(endpoint: endpoint)
        
        // 构建请求体
        let requestBody: [String: Any]
        
        if apiType == .openAI {
            requestBody = [
                "model": model,
                "messages": [
                    [
                        "role": "system",
                        "content": systemPrompt
                    ],
                    [
                        "role": "user",
                        "content": userPrompt
                    ]
                ],
                "temperature": 0.3,
                "top_p": 0.9
            ]
        } else {
            requestBody = [
                "model": model,
                "prompt": userPrompt,
                "system": systemPrompt,
                "stream": false,
                "options": [
                    "temperature": 0.3,
                    "top_p": 0.9
                ]
            ]
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
        
        print("🤖 [DiaryAIService] 发送请求到 AI...")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiaryAIError.invalidResponse
        }
        
        print("🤖 [DiaryAIService] 收到响应，状态码: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [DiaryAIService] 请求失败（状态码: \(httpResponse.statusCode)）：\(errorMessage)")
            throw DiaryAIError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [DiaryAIService] 无法解析响应 JSON")
            throw DiaryAIError.invalidResponse
        }
        
        let rawResponse: String
        
        if apiType == .openAI {
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                rawResponse = content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                print("❌ [DiaryAIService] OpenAI 格式响应解析失败")
                throw DiaryAIError.invalidResponse
            }
        } else {
            guard let responseText = json["response"] as? String else {
                print("❌ [DiaryAIService] Ollama 格式响应解析失败")
                throw DiaryAIError.invalidResponse
            }
            rawResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        print("📝 [DiaryAIService] AI 原始响应: \(rawResponse)")
        
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
        
        // 尝试解析 JSON
        guard let jsonData = jsonString.data(using: .utf8),
              let result = try? JSONDecoder().decode(DiaryAnalysisResult.self, from: jsonData) else {
            print("⚠️ [DiaryAIService] JSON 解析失败")
            throw DiaryAIError.invalidResponse
        }
        
        print("✅ [DiaryAIService] 分析成功")
        return result
    }
}

/// 日记 AI 错误
enum DiaryAIError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case requestFailed(Int, String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "无效的 API 端点地址"
        case .invalidResponse:
            return "无效的响应格式"
        case .requestFailed(let code, let message):
            return "请求失败 (状态码: \(code)): \(message)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}

