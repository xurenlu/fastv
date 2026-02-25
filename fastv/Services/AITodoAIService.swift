//
//  AITodoAIService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// AI Todo AI 服务
@MainActor
extension AITodoAIService {
    /// API 类型
    enum APIType {
        case ollama
        case openAI
    }
    
    /// 检测 API 类型
    static func detectAPIType(endpoint: String) -> APIType {
        let lowercased = endpoint.lowercased()
        if lowercased.contains("/chat/completions") ||
           lowercased.contains("/v1/chat") ||
           lowercased.contains("openai") ||
           lowercased.contains("anthropic") ||
           lowercased.contains("dashscope") {
            return .openAI
        }
        return .ollama
    }
    
    /// 智能构建 API URL，如果 endpoint 已经包含完整路径则直接使用，否则根据 API 类型拼接
    /// - Parameter endpoint: API 端点地址
    /// - Returns: 完整的 API URL
    static func buildAPIURL(endpoint: String) throws -> URL {
        // 去除末尾的斜杠
        var cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanEndpoint.hasSuffix("/") {
            cleanEndpoint = String(cleanEndpoint.dropLast())
        }
        
        // 检查是否已经包含完整路径
        let lowercased = cleanEndpoint.lowercased()
        if lowercased.contains("/api/generate") ||
           lowercased.contains("/chat/completions") ||
           lowercased.contains("/v1/chat") ||
           lowercased.contains("/completions") {
            // 已经包含完整路径，直接使用
            guard let url = URL(string: cleanEndpoint) else {
                throw AITodoAIError.invalidEndpoint
            }
            return url
        }
        
        // 根据 API 类型拼接路径
        let apiType = detectAPIType(endpoint: cleanEndpoint)
        let lowercasedClean = cleanEndpoint.lowercased()
        let path: String
        if apiType == .openAI {
            if lowercasedClean.contains("dashscope.aliyuncs.com") && lowercasedClean.contains("compatible-mode") {
                path = "/chat/completions"
            } else {
                path = "/v1/chat/completions"
            }
        } else {
            path = "/api/generate"
        }
        guard let url = URL(string: "\(cleanEndpoint)\(path)") else {
            throw AITodoAIError.invalidEndpoint
        }
        return url
    }
}

/// AI Todo 指令解析结果
struct AITodoOperation: Codable {
    enum OperationType: String, Codable {
        case add = "add"
        case update = "update"
        case delete = "delete"
        case complete = "complete"
        case setPriority = "set_priority"
        case setDueDate = "set_due_date"
    }
    
    var type: OperationType
    var todoId: String? // 用于 update/delete/complete/setPriority/setDueDate
    var title: String?
    var description: String?
    var priority: String? // "important_urgent", "important_not_urgent", etc.
    var dueDate: String? // ISO8601 格式
}

/// AI Todo AI 服务
@MainActor
class AITodoAIService {
    static let shared = AITodoAIService()
    
    private init() {}
    
    /// 解析用户输入（使用新的配置系统）
    /// - Parameters:
    ///   - input: 用户输入的文本
    ///   - todosContext: 当前所有活跃 Todo 的上下文文本
    ///   - profile: AI 服务配置
    ///   - model: 模型名称（覆盖 profile 默认模型）
    ///   - timeout: 超时时间（覆盖 profile 默认超时）
    /// - Returns: 操作列表
    func parseUserInput(
        input: String,
        todosContext: String,
        profile: AIServiceProfile,
        model: String? = nil,
        timeout: Double? = nil
    ) async throws -> [AITodoOperation] {
        let effectiveModel = model ?? profile.defaultModel
        let effectiveTimeout = timeout ?? profile.timeout
        
        return try await parseUserInputLegacy(
            input: input,
            todosContext: todosContext,
            endpoint: profile.effectiveEndpoint,
            model: effectiveModel,
            apiToken: profile.apiKey.isEmpty ? nil : profile.apiKey,
            timeout: effectiveTimeout
        )
    }
    
    /// 解析用户输入（文本或语音转文字）并返回操作列表（旧版兼容方法）
    /// - Parameters:
    ///   - input: 用户输入的文本
    ///   - todosContext: 当前所有活跃 Todo 的上下文文本
    ///   - endpoint: API 端点
    ///   - model: 模型名称
    ///   - apiToken: API Token（可选）
    ///   - timeout: 超时时间
    /// - Returns: 操作列表
    func parseUserInputLegacy(
        input: String,
        todosContext: String,
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval = 10.0
    ) async throws -> [AITodoOperation] {
        print("🤖 [AITodoAIService] 开始解析用户输入，长度: \(input.count)")
        
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
        
        let timeZone = TimeZone.current
        let offsetSeconds = timeZone.secondsFromGMT(for: now)
        let offsetHours = offsetSeconds / 3600
        let offsetMinutes = abs(offsetSeconds / 60) % 60
        let offsetString = String(format: "UTC%+02d:%02d", offsetHours, offsetMinutes)
        
        let systemPrompt = #"""
你是一个智能待办事项助手。用户会通过语音或文字告诉你他们想要对待办事项进行的操作。

【当前待办事项列表】
\#(todosContext)

【当前时间上下文】
- 当前时区: \#(timeZone.identifier) (\#(offsetString))
- 当前日期时间: \#(currentDateLocalized)
- 当前时间（ISO8601）: \#(currentDateISO)
- 所有相对时间（例如“今天”“明天”“后天”“下周一”）必须严格以此为基准进行解析。

【你的任务】
根据用户的输入，理解用户的意图，并返回一个 JSON 数组，包含需要执行的操作。

【操作类型】
1. add - 添加新的待办事项
   - 需要: title (必需), description (可选), priority (可选), dueDate (可选)
   
2. update - 更新现有待办事项
   - 需要: todoId (必需), title/description/priority/dueDate (至少一个)
   
3. delete - 删除待办事项
   - 需要: todoId (必需)
   
4. complete - 标记待办事项为已完成
   - 需要: todoId (必需)
   
5. set_priority - 设置待办事项优先级
   - 需要: todoId (必需), priority (必需，值: "important_urgent", "important_not_urgent", "not_important_urgent", "not_important_not_urgent")
   
6. set_due_date - 设置截止时间
   - 需要: todoId (必需), dueDate (必需，ISO8601 格式，如 "2025-01-15T10:00:00Z")

【优先级说明】
- "important_urgent" - 重要且紧急
- "important_not_urgent" - 重要但不紧急
- "not_important_urgent" - 不重要但紧急
- "not_important_not_urgent" - 不重要且不紧急

【时间解析】
用户可能用自然语言描述时间，如：
- "明天"、"后天"、"下周一"
- "1月15日"、"下个月5号"
- "下午3点"、"晚上8点"
你需要将这些转换为 ISO8601 格式的日期时间字符串。

【时间转换规则】
1. 使用当前时间 \#(currentDateLocalized) 作为解析“今天”“明天”等相对时间的基准。不要假设固定日期。
2. 当用户提供“上午/早上”但没有具体时间时，默认 09:00；“下午/傍晚”默认 15:00；“晚上/夜里”默认 20:00；“中午”默认 12:00。
3. 如果只提供日期（如“明天”）没有时间，默认设置为 09:00，并在 JSON 中注明 dueDate。
4. 输出的 dueDate 必须是包含日期与时间的 ISO8601 字符串（例如 2025-01-16T09:00:00+08:00），不得缺少时间部分。
5. 不要随意延长日期。除非用户明确指定，应尽量贴近用户描述（例如“明天上午 9 点”就转换为实际的下一天 09:00）。

【重要规则】
1. 只返回 JSON 数组，不要其他任何内容
2. 如果用户输入不明确，尽量推断用户的意图
3. 如果找不到匹配的待办事项，返回空数组
4. 时间解析要准确，考虑当前日期
5. 优先级判断要准确，根据用户描述的关键词（"重要"、"紧急"等）判断

【输出格式】
只返回 JSON 数组，格式如下：
[
  {
    "type": "add",
    "title": "待办事项标题",
    "description": "描述（可选）",
    "priority": "important_urgent",
    "dueDate": "2025-01-15T10:00:00+08:00"
  }
]
"""#
        let fullPrompt = """
用户输入：\(input)

请根据用户输入，返回需要执行的操作 JSON 数组。
"""
        
        // 检测 API 类型
        let apiType = Self.detectAPIType(endpoint: endpoint)
        
        // 构建 URL - 智能处理路径拼接
        let url = try Self.buildAPIURL(endpoint: endpoint)
        
        // 根据 API 类型构建不同的请求体
        let requestBody: [String: Any]
        
        if apiType == .openAI {
            // OpenAI 兼容格式（使用 messages）
            requestBody = [
                "model": model,
                "messages": [
                    [
                        "role": "system",
                        "content": systemPrompt
                    ],
                    [
                        "role": "user",
                        "content": fullPrompt
                    ]
                ],
                "temperature": 0.2,
                "top_p": 0.9
            ]
        } else {
            // Ollama 格式（使用 prompt 和 system）
            requestBody = [
                "model": model,
                "prompt": fullPrompt,
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
        
        print("🤖 [AITodoAIService] 发送请求到 AI（超时: \(timeout)秒）...")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AITodoAIError.invalidResponse
        }
        
        print("🤖 [AITodoAIService] 收到响应，状态码: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [AITodoAIService] 请求失败（状态码: \(httpResponse.statusCode)）：\(errorMessage)")
            throw AITodoAIError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        // 解析响应 - 根据 API 类型解析不同的响应格式
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [AITodoAIService] 无法解析响应 JSON")
            throw AITodoAIError.invalidResponse
        }
        
        let rawResponse: String
        
        if apiType == .openAI {
            // OpenAI 格式：响应在 choices[0].message.content
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                rawResponse = content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                print("❌ [AITodoAIService] OpenAI 格式响应解析失败")
                throw AITodoAIError.invalidResponse
            }
        } else {
            // Ollama 格式：响应在 response 字段
            guard let responseText = json["response"] as? String else {
                print("❌ [AITodoAIService] Ollama 格式响应解析失败")
                throw AITodoAIError.invalidResponse
            }
            rawResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        print("📝 [AITodoAIService] AI 原始响应: \(rawResponse)")
        
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
              let operations = try? JSONDecoder().decode([AITodoOperation].self, from: jsonData) else {
            print("⚠️ [AITodoAIService] JSON 解析失败，尝试从文本中提取")
            // 降级方案：如果无法解析 JSON，返回空数组
            return []
        }
        
        print("✅ [AITodoAIService] 解析成功，获得 \(operations.count) 个操作")
        return operations
    }
}

/// AI Todo AI 错误
enum AITodoAIError: LocalizedError {
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

