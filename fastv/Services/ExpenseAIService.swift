//
//  ExpenseAIService.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation

/// 记账 AI 解析结果
struct ExpenseParsingResult: Codable {
    var amount: Double?         // 使用 Double 以便 JSON 编码/解码
    var type: String?           // "income", "expense", "transfer"
    var categoryName: String?   // 分类名称（如"餐饮"、"交通"等）
    var note: String?          // 备注
    var date: String?           // ISO8601 格式日期（可选）
    
    /// 转换为 Decimal 金额
    var amountDecimal: Decimal? {
        guard let amount = amount else { return nil }
        return Decimal(amount)
    }
}

/// 记账 AI 服务
@MainActor
class ExpenseAIService {
    static let shared = ExpenseAIService()
    
    private init() {}
    
    /// 解析用户输入（文本）
    /// - Parameters:
    ///   - input: 用户输入的文本
    ///   - categories: 可用分类列表（用于上下文）
    ///   - profile: AI 服务配置
    ///   - model: 模型名称（覆盖 profile 默认模型）
    ///   - timeout: 超时时间（覆盖 profile 默认超时）
    /// - Returns: 解析结果
    func parseUserInput(
        input: String,
        categories: [ExpenseCategory],
        profile: AIServiceProfile,
        model: String? = nil,
        timeout: Double? = nil
    ) async throws -> ExpenseParsingResult {
        let effectiveModel = model ?? profile.defaultModel
        let effectiveTimeout = timeout ?? profile.timeout
        
        return try await parseUserInputLegacy(
            input: input,
            categories: categories,
            endpoint: profile.effectiveEndpoint,
            model: effectiveModel,
            apiToken: profile.apiKey.isEmpty ? nil : profile.apiKey,
            timeout: effectiveTimeout
        )
    }
    
    /// 解析用户输入（旧版兼容方法）
    func parseUserInputLegacy(
        input: String,
        categories: [ExpenseCategory],
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval = 30.0
    ) async throws -> ExpenseParsingResult {
        print("🤖 [ExpenseAIService] 开始解析用户输入，长度: \(input.count)")
        
        // 构建分类上下文
        let categoriesContext = categories.map { category in
            "- \(category.name) (\(category.type.displayName))"
        }.joined(separator: "\n")
        
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = TimeZone.current
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let currentDateISO = isoFormatter.string(from: now)
        
        let localizedFormatter = DateFormatter()
        localizedFormatter.locale = Locale(identifier: "zh_CN")
        localizedFormatter.dateStyle = .full
        localizedFormatter.timeStyle = .medium
        let currentDateLocalized = localizedFormatter.string(from: now)
        
        let systemPrompt = #"""
你是一个智能记账助手。用户会通过语音或文字告诉你他们的收支情况，你需要从中提取关键信息。

【可用分类列表】
\#(categoriesContext)

【当前时间上下文】
- 当前日期时间: \#(currentDateLocalized)
- 当前时间（ISO8601）: \#(currentDateISO)

【你的任务】
从用户输入中提取以下信息：
1. 金额（必需）
2. 类型：income（收入）、expense（支出）、transfer（转账）
3. 分类名称（从可用分类列表中选择最匹配的）
4. 备注（可选，如商家名称、用途等）
5. 日期（可选，如果用户提到具体日期，否则使用当前时间）

【类型判断规则】
- 如果用户说"收到"、"工资"、"奖金"、"赚了"等，类型为 income
- 如果用户说"花了"、"买了"、"支付"、"消费"等，类型为 expense
- 如果用户说"转账"、"转给"、"借出"、"还款"等，类型为 transfer

【分类匹配规则】
- 根据用户描述的关键词匹配最合适的分类
- 例如："午饭"、"吃饭"、"餐厅" → 餐饮
- 例如："打车"、"地铁"、"火车"、"机票" → 交通
- 例如："工资"、"薪水" → 工资（收入）
- 如果无法匹配，使用"其他"分类

【输出格式】
只返回 JSON 对象，格式如下：
{
  "amount": 35.00,
  "type": "expense",
  "categoryName": "餐饮",
  "note": "午饭",
  "date": "2025-01-15T12:00:00+08:00"
}

【重要规则】
1. 只返回 JSON 对象，不要其他任何内容
2. amount 必须是数字，不要包含货币符号
3. type 必须是 "income"、"expense" 或 "transfer" 之一
4. categoryName 必须从可用分类列表中选择
5. 如果用户没有提到日期，date 字段可以为空或使用当前时间
"""#
        
        let userPrompt = """
用户输入：\(input)

请解析这段输入，提取记账信息。
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
                "temperature": 0.2,
                "top_p": 0.9
            ]
        } else {
            requestBody = [
                "model": model,
                "prompt": userPrompt,
                "system": systemPrompt,
                "stream": false,
                "options": [
                    "temperature": 0.2,
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
        
        print("🤖 [ExpenseAIService] 发送请求到 AI...")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExpenseAIError.invalidResponse
        }
        
        print("🤖 [ExpenseAIService] 收到响应，状态码: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [ExpenseAIService] 请求失败（状态码: \(httpResponse.statusCode)）：\(errorMessage)")
            throw ExpenseAIError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [ExpenseAIService] 无法解析响应 JSON")
            throw ExpenseAIError.invalidResponse
        }
        
        let rawResponse: String
        
        if apiType == .openAI {
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                rawResponse = content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                print("❌ [ExpenseAIService] OpenAI 格式响应解析失败")
                throw ExpenseAIError.invalidResponse
            }
        } else {
            guard let responseText = json["response"] as? String else {
                print("❌ [ExpenseAIService] Ollama 格式响应解析失败")
                throw ExpenseAIError.invalidResponse
            }
            rawResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        print("📝 [ExpenseAIService] AI 原始响应: \(rawResponse)")
        
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
              let result = try? JSONDecoder().decode(ExpenseParsingResult.self, from: jsonData) else {
            print("⚠️ [ExpenseAIService] JSON 解析失败")
            throw ExpenseAIError.invalidResponse
        }
        
        print("✅ [ExpenseAIService] 解析成功")
        return result
    }
}

/// 记账 AI 错误
enum ExpenseAIError: LocalizedError {
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

