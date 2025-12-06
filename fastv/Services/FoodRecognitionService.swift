//
//  FoodRecognitionService.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import AppKit

/// 食物识别错误
enum FoodRecognitionError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case invalidResponse
    case requestFailed(Int, String)
    case networkError(Error)
    case invalidImage
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "缺少 API Key"
        case .invalidEndpoint:
            return "无效的 API 端点地址"
        case .invalidResponse:
            return "无效的响应格式"
        case .requestFailed(let code, let message):
            return "请求失败 (状态码: \(code)): \(message)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidImage:
            return "无效的图片数据"
        }
    }
}

/// 食物识别结果
struct FoodRecognitionResult: Codable {
    var foods: [RecognizedFood]
    var description: String?  // AI生成的描述
}

/// 食物识别服务（使用阿里云 DashScope qwen-vl 引擎）
@MainActor
class FoodRecognitionService {
    static let shared = FoodRecognitionService()
    
    private init() {}
    
    /// 识别食物图片
    /// - Parameters:
    ///   - imageData: 图片数据数组（支持多张）
    ///   - textDescription: 用户文字描述（可选）
    ///   - profile: AI服务配置（必须是DashScope类型）
    ///   - model: 模型名称（默认使用 qwen-vl-plus）
    ///   - timeout: 超时时间
    /// - Returns: 识别结果
    func recognizeFoods(
        imageData: [Data],
        textDescription: String? = nil,
        profile: AIServiceProfile,
        model: String? = nil,
        timeout: TimeInterval = 60.0
    ) async throws -> FoodRecognitionResult {
        guard !imageData.isEmpty else {
            throw FoodRecognitionError.invalidImage
        }
        
        // 确保使用 DashScope API
        guard profile.protocolType == .dashScope || 
              profile.endpoint.lowercased().contains("dashscope") else {
            throw FoodRecognitionError.invalidEndpoint
        }
        
        // 使用指定的模型，或默认使用 qwen-vl-plus
        let visionModel = model ?? "qwen-vl-plus"
        
        return try await recognizeWithDashScope(
            imageData: imageData,
            textDescription: textDescription,
            profile: profile,
            model: visionModel,
            timeout: timeout
        )
    }
    
    /// 使用 DashScope API 识别（qwen-vl 系列）
    private func recognizeWithDashScope(
        imageData: [Data],
        textDescription: String?,
        profile: AIServiceProfile,
        model: String,
        timeout: TimeInterval
    ) async throws -> FoodRecognitionResult {
        guard !profile.apiKey.isEmpty else {
            throw FoodRecognitionError.missingAPIKey
        }
        
        // 使用 DashScope 兼容模式端点
        let baseURL = profile.endpoint.isEmpty ? "https://dashscope.aliyuncs.com/compatible-mode/v1" : profile.endpoint
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw FoodRecognitionError.invalidEndpoint
        }
        
        print("🤖 [FoodRecognitionService] 使用 DashScope qwen-vl 引擎识别食物，模型: \(model)")
        
        // 构建图片内容数组
        var contentArray: [[String: Any]] = []
        
        // 添加所有图片
        for data in imageData {
            let base64Image = data.base64EncodedString()
            let imageUrl = "data:image/jpeg;base64,\(base64Image)"
            contentArray.append(["image": imageUrl])
        }
        
        // 添加文本描述
        var userPrompt = "请识别这些图片中的食物。对于每道菜，请告诉我：\n1. 食物名称\n2. 估算的份量（如：1碗、250ml、1个等）\n3. 估算的卡路里（每100克或每份）\n\n请以JSON格式返回，格式如下：\n{\n  \"foods\": [\n    {\n      \"name\": \"食物名称\",\n      \"estimatedAmount\": \"估算份量\",\n      \"calories\": 估算卡路里\n    }\n  ]\n}"
        
        if let textDescription = textDescription, !textDescription.isEmpty {
            userPrompt = "用户描述：\(textDescription)\n\n" + userPrompt
        }
        
        contentArray.append(["text": userPrompt])
        
        let systemPrompt = """
你是一个专业的食物识别和营养分析助手。你需要：
1. 准确识别图片中的所有食物
2. 估算每道菜的份量（考虑中餐常见份量）
3. 估算每道菜的卡路里（基于常见食物数据库）
4. 如果有多道菜，请分别识别每一道

注意：
- 中国人经常一起吃饭，所以图片中可能有多道菜
- 请识别所有可见的食物
- 估算要尽量准确，可以参考常见中餐的卡路里数据
"""
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": contentArray
                ]
            ],
            "temperature": 0.2,
            "top_p": 0.9
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(profile.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = timeout
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FoodRecognitionError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            throw FoodRecognitionError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw FoodRecognitionError.invalidResponse
        }
        
        let rawResponse = content.trimmingCharacters(in: .whitespacesAndNewlines)
        print("📝 [FoodRecognitionService] AI 原始响应: \(rawResponse)")
        
        // 解析 JSON 响应
        var jsonString = rawResponse
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        }
        if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = jsonString.data(using: .utf8),
              let result = try? JSONDecoder().decode(FoodRecognitionResult.self, from: jsonData) else {
            // 如果 JSON 解析失败，尝试从文本中提取信息
            return parseFoodsFromText(rawResponse)
        }
        
        return result
    }
    
    /// 从文本中解析食物信息（备用方案）
    private func parseFoodsFromText(_ text: String) -> FoodRecognitionResult {
        var foods: [RecognizedFood] = []
        
        // 简单的文本解析逻辑（如果 JSON 解析失败）
        // 这里可以添加更复杂的解析逻辑
        
        return FoodRecognitionResult(foods: foods, description: text)
    }
}

