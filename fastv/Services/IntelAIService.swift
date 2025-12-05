//
//  IntelAIService.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation

/// 情报聊天结果
struct IntelChatResult {
    var displayReply: String              // 展示给用户的自然语言回复
    var replacementEntriesJSON: String?    // 当 AI 决定修改当天情报时，返回 JSON 字符串；否则为 nil
}

/// 情报 AI 服务
@MainActor
class IntelAIService {
    static let shared = IntelAIService()
    
    private init() {}
    
    /// 自动生成当天情报
    /// - Parameters:
    ///   - date: 日期
    ///   - profile: AI 服务配置
    ///   - model: 模型名称（覆盖 profile 默认模型）
    ///   - timeout: 超时时间（覆盖 profile 默认超时）
    /// - Returns: 生成的情报条目列表
    func generateTodayIntelSummary(
        date: Date,
        profile: AIServiceProfile,
        model: String? = nil,
        timeout: Double? = nil
    ) async throws -> [IntelEntry] {
        let effectiveModel = model ?? profile.defaultModel
        let effectiveTimeout = timeout ?? profile.timeout
        
        return try await generateTodayIntelSummaryLegacy(
            date: date,
            endpoint: profile.effectiveEndpoint,
            model: effectiveModel,
            apiToken: profile.apiKey.isEmpty ? nil : profile.apiKey,
            timeout: effectiveTimeout
        )
    }
    
    /// 自动生成当天情报（旧版兼容方法）
    func generateTodayIntelSummaryLegacy(
        date: Date,
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval = 30.0
    ) async throws -> [IntelEntry] {
        print("🤖 [IntelAIService] 开始生成当天情报，日期: \(date)")
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .none
        let dateString = dateFormatter.string(from: date)
        
        let systemPrompt = #"""
你是一个智能情报助手，专门收集对财务和投资有重大影响的情报。

【你的任务】
根据当前日期，生成5-10条当天可能发生的重要事件情报。每条情报应包含：
1. 概要（summary）：精简描述，20-50字
2. 正文（body）：**必须提供**完整详细描述，150-400字，包含事件背景、具体细节、影响分析等
3. 来源（sources）：**必须提供**具体的信息来源数组，格式为["媒体名称/网站名称"]，例如["Bloomberg", "Reuters", "CNBC", "新华社", "财新网", "华尔街日报", "金融时报"]等。优先提供权威财经媒体名称，如果可能请提供网址

【重点关注领域】
1. **主要经济大国的重要事件**：
   - 美国：货币政策、经济数据、重大政策变化、重要企业动态
   - 中国：经济政策、市场动态、重要企业新闻、政策调整
   - 欧盟：经济政策、重要成员国动态、贸易政策
   - 日本：货币政策、经济数据、重要企业动态
   - 英国：经济政策、脱欧相关、市场动态
   - 其他主要经济体：德国、法国、印度、韩国等的重要经济事件

2. **轰炸性新闻**：
   - 重大突发事件（自然灾害、政治危机、战争冲突等）
   - 重大政策变化（央行政策、贸易政策、税收政策等）
   - 重大企业事件（破产、并购、重大事故等）
   - 重大科技突破（可能影响市场的新技术）

3. **对财务有重大影响的事件**：
   - 股票市场：重大波动、重要企业财报、市场情绪变化
   - 期货市场：大宗商品价格变动、供需关系变化
   - 虚拟货币：监管政策、重大技术更新、市场波动
   - 外汇市场：汇率重大变动、央行干预
   - 债券市场：利率变化、信用评级调整
   - 房地产市场：重大政策变化、市场数据

【排除标准】
以下类型的事件**不要**包含：
- 对经济、股票、期货、虚拟货币等没有影响的小事
- 纯粹的娱乐新闻、体育新闻（除非对市场有重大影响）
- 地方性小事件（除非可能引发连锁反应）
- 个人生活琐事

【输出格式】
只返回 JSON 对象，格式如下：
{
  "intel_entries": [
    {
      "summary": "情报概要（20-50字）",
      "body": "完整正文（150-400字，必须包含事件背景、具体细节和影响分析）",
      "sources": ["Bloomberg", "Reuters", "https://www.bloomberg.com/news/..."]
    }
  ]
}

注意：sources 必须是具体的媒体名称或网站URL，例如：
- "Bloomberg"、"Reuters"、"CNBC"、"Financial Times"
- "新华社"、"财新网"、"第一财经"、"华尔街日报中文网"
- 或者提供具体的新闻网址（如果可用）

【重要规则】
1. 只返回 JSON 对象，不要其他任何内容
2. 情报应该基于当前日期可能发生的事件，重点关注对财务和投资有影响的事件
3. **每条情报必须包含详细的正文（body），至少150字，不能为空或过于简短**
4. **每条情报必须提供具体的媒体来源名称（sources），如"Bloomberg"、"Reuters"、"新华社"等，不要使用泛泛的标签如"新闻"、"财经"**
5. 优先选择对股票、期货、虚拟货币、外汇等金融市场有直接影响的事件
6. 如果无法生成有效情报，返回空数组
7. 确保情报覆盖主要经济大国，不要只关注单一国家
8. 正文应包含：事件背景、具体细节、可能的影响分析
"""#
        
        let userPrompt = """
当前日期：\(dateString)

请生成今天的情报汇总，重点关注：
1. 主要经济大国（美国、中国、欧盟、日本、英国等）的重要事件
2. 轰炸性新闻和重大突发事件
3. 对财务、股票、期货、虚拟货币等有重大影响的事件

请生成5-10条重要事件情报，排除对经济没有影响的小事。
"""
        
        // 输出完整的提示词到日志
        let promptSeparator = String(repeating: "=", count: 80)
        print(promptSeparator)
        print("📋 [IntelAIService] ========== 自动生成情报 - 完整提示词 ==========")
        print("📋 [IntelAIService] System Prompt:")
        print(systemPrompt)
        print("📋 [IntelAIService] User Prompt:")
        print(userPrompt)
        print(promptSeparator)
        
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
                "temperature": 0.7,
                "top_p": 0.9
            ]
        } else {
            requestBody = [
                "model": model,
                "prompt": userPrompt,
                "system": systemPrompt,
                "stream": false,
                "options": [
                    "temperature": 0.7,
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
        
        print("🤖 [IntelAIService] 发送请求到 AI...")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IntelAIError.invalidResponse
        }
        
        print("🤖 [IntelAIService] 收到响应，状态码: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [IntelAIService] 请求失败（状态码: \(httpResponse.statusCode)）：\(errorMessage)")
            throw IntelAIError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [IntelAIService] 无法解析响应 JSON")
            throw IntelAIError.invalidResponse
        }
        
        let rawResponse: String
        
        if apiType == .openAI {
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                rawResponse = content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                print("❌ [IntelAIService] OpenAI 格式响应解析失败")
                throw IntelAIError.invalidResponse
            }
        } else {
            guard let responseText = json["response"] as? String else {
                print("❌ [IntelAIService] Ollama 格式响应解析失败")
                throw IntelAIError.invalidResponse
            }
            rawResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        print("📝 [IntelAIService] AI 原始响应: \(rawResponse)")
        
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
              let parsedJson = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let entriesArray = parsedJson["intel_entries"] as? [[String: Any]] else {
            print("⚠️ [IntelAIService] JSON 解析失败")
            throw IntelAIError.invalidResponse
        }
        
        // 转换为 IntelEntry 数组
        var result: [IntelEntry] = []
        for entryDict in entriesArray {
            guard let summary = entryDict["summary"] as? String,
                  let body = entryDict["body"] as? String else {
                continue
            }
            let sources = entryDict["sources"] as? [String] ?? []
            
            let entry = IntelEntry(
                summary: summary,
                body: body,
                sources: sources,
                date: date
            )
            result.append(entry)
        }
        
        print("✅ [IntelAIService] 生成成功，共 \(result.count) 条情报")
        return result
    }
    
    /// 聊天与情报修改指令
    /// - Parameters:
    ///   - date: 日期
    ///   - message: 用户消息
    ///   - todayEntrySummaries: 今天的情报概要列表（只包含 summary）
    ///   - profile: AI 服务配置
    ///   - model: 模型名称（覆盖 profile 默认模型）
    ///   - timeout: 超时时间（覆盖 profile 默认超时）
    /// - Returns: 聊天结果
    func chatAboutIntel(
        date: Date,
        message: String,
        todayEntrySummaries: [String],
        profile: AIServiceProfile,
        model: String? = nil,
        timeout: Double? = nil
    ) async throws -> IntelChatResult {
        let effectiveModel = model ?? profile.defaultModel
        let effectiveTimeout = timeout ?? profile.timeout
        
        return try await chatAboutIntelLegacy(
            date: date,
            message: message,
            todayEntrySummaries: todayEntrySummaries,
            endpoint: profile.effectiveEndpoint,
            model: effectiveModel,
            apiToken: profile.apiKey.isEmpty ? nil : profile.apiKey,
            timeout: effectiveTimeout
        )
    }
    
    /// 聊天与情报修改指令（旧版兼容方法）
    func chatAboutIntelLegacy(
        date: Date,
        message: String,
        todayEntrySummaries: [String],
        endpoint: String,
        model: String,
        apiToken: String?,
        timeout: TimeInterval = 30.0
    ) async throws -> IntelChatResult {
        print("🤖 [IntelAIService] 开始聊天，消息长度: \(message.count)")
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .none
        let dateString = dateFormatter.string(from: date)
        
        // 构建今天情报列表的文本表示
        let summariesText: String
        if todayEntrySummaries.isEmpty {
            summariesText = "今天还没有任何情报。"
        } else {
            summariesText = todayEntrySummaries.enumerated().map { index, summary in
                "\(index + 1). \(summary)"
            }.joined(separator: "\n")
        }
        
        let systemPrompt = #"""
你是一个智能情报助手。用户会与你讨论当天的情报，或者要求你修改今天的情报列表。

【当前日期】
\#(dateString)

【今天的情报列表（仅概要）】
\#(summariesText)

【你的任务】
你需要根据用户的意图，执行以下两种操作之一：

1. **普通对话模式**：如果用户只是询问、讨论、解释或咨询情报相关内容，请用自然语言回复，不要返回任何 JSON。

2. **修改情报模式**：如果用户要求修改、更新、重新生成、替换今天的情报，或者要求你根据某些信息生成新的情报列表，你必须：
   - 只返回一个 JSON 对象，格式如下：
   {
     "intel_entries": [
       {
         "summary": "情报概要（20-50字）",
         "body": "完整正文（150-400字，必须包含事件背景、具体细节和影响分析）",
         "sources": ["Bloomberg", "Reuters", "新华社", "财新网"]
       }
     ]
   }
   - **body 字段必须详细，至少150字，包含完整的事件描述和分析**
   - **sources 字段必须是具体的媒体名称（如"Bloomberg"、"Reuters"、"新华社"）或网址，不能是泛泛的标签**
   - 不要添加任何其他文字说明
   - 不要添加 markdown 代码块标记
   - 直接返回纯 JSON 对象

【判断用户意图的关键词】
以下情况应进入"修改情报模式"：
- 用户说"修改"、"更新"、"重新生成"、"替换"、"生成新的"、"重新整理"、"根据XX生成"
- 用户要求你"生成今天的情报"、"创建情报列表"
- 用户说"按照XX要求修改"、"根据XX更新"

以下情况应进入"普通对话模式"：
- 用户询问"这是什么"、"为什么"、"如何"、"解释一下"
- 用户说"告诉我"、"介绍一下"、"分析一下"
- 用户只是讨论或评论现有情报

【输出格式规则】
- **普通对话**：只返回自然语言文本，不要包含任何 JSON 或代码块
- **修改情报**：只返回纯 JSON 对象，格式必须严格符合上述要求，不要添加任何 markdown 标记或说明文字

【重要规则】
1. 当用户要求修改情报时，你必须返回 JSON，且只返回 JSON
2. JSON 中的 intel_entries 数组将完全替换今天的所有情报
3. 如果只是讨论或解释，只返回自然语言文本
4. 返回 JSON 时，确保格式正确，可以被直接解析
5. **每条情报的 body 必须详细（至少150字），包含事件背景、细节和影响分析**
6. **每条情报的 sources 必须是具体媒体名称（如"Bloomberg"、"新华社"）或网址，不能用标签**
"""#
        
        let userPrompt = """
用户消息：\(message)

请仔细分析用户的意图：
- 如果用户要求修改、更新、重新生成或替换今天的情报，请返回 JSON 格式的情报列表
- 如果用户只是询问、讨论或解释，请用自然语言回复

请根据用户的消息，决定是进行对话还是修改今天的情报。
"""
        
        // 输出完整的提示词到日志
        let promptSeparator = String(repeating: "=", count: 80)
        print(promptSeparator)
        print("📋 [IntelAIService] ========== 完整提示词 ==========")
        print("📋 [IntelAIService] System Prompt:")
        print(systemPrompt)
        print("📋 [IntelAIService] User Prompt:")
        print(userPrompt)
        print(promptSeparator)
        
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
                "temperature": 0.7,
                "top_p": 0.9
            ]
        } else {
            requestBody = [
                "model": model,
                "prompt": userPrompt,
                "system": systemPrompt,
                "stream": false,
                "options": [
                    "temperature": 0.7,
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
        
        print("🤖 [IntelAIService] 发送聊天请求到 AI...")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IntelAIError.invalidResponse
        }
        
        print("🤖 [IntelAIService] 收到响应，状态码: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [IntelAIService] 请求失败（状态码: \(httpResponse.statusCode)）：\(errorMessage)")
            throw IntelAIError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [IntelAIService] 无法解析响应 JSON")
            throw IntelAIError.invalidResponse
        }
        
        let rawResponse: String
        
        if apiType == .openAI {
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                rawResponse = content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                print("❌ [IntelAIService] OpenAI 格式响应解析失败")
                throw IntelAIError.invalidResponse
            }
        } else {
            guard let responseText = json["response"] as? String else {
                print("❌ [IntelAIService] Ollama 格式响应解析失败")
                throw IntelAIError.invalidResponse
            }
            rawResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let responseSeparator = String(repeating: "=", count: 80)
        print(responseSeparator)
        print("📝 [IntelAIService] ========== AI 原始响应 ==========")
        print("📝 [IntelAIService] 响应长度: \(rawResponse.count) 字符")
        print("📝 [IntelAIService] 响应内容:")
        print(rawResponse)
        print(responseSeparator)
        
        // 尝试解析 JSON（检查是否是修改指令）
        var jsonString: String? = nil
        
        // 方法1: 尝试查找 JSON 代码块
        if rawResponse.contains("```json") {
            let components = rawResponse.components(separatedBy: "```json")
            if components.count > 1 {
                let afterJson = components[1]
                if let endIndex = afterJson.range(of: "```") {
                    jsonString = String(afterJson[..<endIndex.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        // 方法2: 尝试查找普通代码块中的 JSON
        if jsonString == nil && rawResponse.contains("```") {
            let components = rawResponse.components(separatedBy: "```")
            for (index, component) in components.enumerated() {
                if index % 2 == 1 && component.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                    let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.contains("intel_entries") {
                        jsonString = trimmed
                        break
                    }
                }
            }
        }
        
        // 方法3: 尝试直接查找包含 intel_entries 的 JSON 对象
        if jsonString == nil {
            // 查找第一个 { 的位置
            if let firstBraceIndex = rawResponse.firstIndex(of: "{"),
               rawResponse[firstBraceIndex...].contains("\"intel_entries\"") {
                // 从第一个 { 开始，找到匹配的最后一个 }
                var braceCount = 0
                let jsonStart = firstBraceIndex
                var jsonEnd: String.Index? = nil
                
                for index in rawResponse[firstBraceIndex...].indices {
                    let char = rawResponse[index]
                    if char == "{" {
                        braceCount += 1
                    } else if char == "}" {
                        braceCount -= 1
                        if braceCount == 0 {
                            jsonEnd = index
                            break
                        }
                    }
                }
                
                if let jsonEnd = jsonEnd {
                    jsonString = String(rawResponse[jsonStart...jsonEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        // 如果还是没找到，尝试整个响应作为 JSON
        if jsonString == nil {
            let trimmed = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") && trimmed.contains("intel_entries") {
                jsonString = trimmed
            }
        }
        
        // 清理 jsonString
        let finalJsonString = jsonString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        print("🔍 [IntelAIService] 提取的 JSON 字符串:")
        print(finalJsonString)
        print("🔍 [IntelAIService] JSON 字符串长度: \(finalJsonString.count)")
        
        // 尝试解析为 JSON，检查是否包含 intel_entries
        if !finalJsonString.isEmpty,
           let jsonData = finalJsonString.data(using: .utf8),
           let parsedJson = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           parsedJson["intel_entries"] != nil {
            // 这是一个修改指令
            print("✅ [IntelAIService] 检测到修改指令，JSON 解析成功")
            if let entriesArray = parsedJson["intel_entries"] as? [[String: Any]] {
                print("✅ [IntelAIService] 找到 \(entriesArray.count) 条情报条目")
            }
            return IntelChatResult(
                displayReply: "已收到修改指令，正在更新情报列表...",
                replacementEntriesJSON: finalJsonString
            )
        } else {
            // 这是普通对话
            print("✅ [IntelAIService] 普通对话回复（未检测到 JSON 格式）")
            if let jsonString = jsonString, let jsonData = jsonString.data(using: .utf8) {
                if let _ = try? JSONSerialization.jsonObject(with: jsonData) {
                    print("⚠️ [IntelAIService] JSON 解析失败，但数据格式可能是 JSON")
                } else {
                    print("ℹ️ [IntelAIService] 响应不是 JSON 格式，按普通对话处理")
                }
            } else {
                print("ℹ️ [IntelAIService] 响应不是 JSON 格式，按普通对话处理")
            }
            return IntelChatResult(
                displayReply: rawResponse,
                replacementEntriesJSON: nil
            )
        }
    }
}

/// 情报 AI 错误
enum IntelAIError: LocalizedError {
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

