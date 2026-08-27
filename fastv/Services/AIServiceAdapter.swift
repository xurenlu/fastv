//
//  AIServiceAdapter.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation

/// AI 服务适配器 - 统一处理不同协议的请求构建
@MainActor
class AIServiceAdapter {
    static let shared = AIServiceAdapter()
    
    private init() {}
    
    /// 构建 API URL
    func buildAPIURL(for profile: AIServiceProfile, useChatCompletions: Bool? = nil, model: String? = nil) throws -> URL {
        let endpoint = profile.effectiveEndpoint
        var cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanEndpoint.hasSuffix("/") {
            cleanEndpoint = String(cleanEndpoint.dropLast())
        }
        
        // 检查是否已经包含完整路径
        let lowercased = cleanEndpoint.lowercased()
        if lowercased.contains("/api/generate") ||
           lowercased.contains("/chat/completions") ||
           lowercased.contains("/v1/chat") ||
           lowercased.contains("/completions") ||
           lowercased.contains("/v1beta") ||
           lowercased.contains("/models/") ||
           lowercased.contains("/messages") {
            // 已经包含完整路径，直接使用
            guard let url = URL(string: cleanEndpoint) else {
                throw AIServiceError.invalidEndpoint
            }
            return url
        }
        
        // 根据协议类型拼接路径
        let path: String
        switch profile.protocolType {
        case .openAI, .azureOpenAI, .someIM, .openRouter:
            path = "/chat/completions"
        case .dashScope:
            // DashScope 需要根据内容类型选择端点，默认使用文本生成
            // 如果 endpoint 已经包含 /compatible-mode/v1，只添加 /chat/completions
            if cleanEndpoint.contains("/compatible-mode/v1") {
                path = "/chat/completions"
            } else {
                path = "/compatible-mode/v1/chat/completions"
            }
        case .claude:
            path = "/v1/messages"
        case .gemini:
            // Gemini 使用 OpenAI 兼容端点或原生端点
            // 如果 endpoint 包含 /v1beta，使用原生格式，否则使用 OpenAI 兼容格式
            if cleanEndpoint.contains("/v1beta") {
                // 原生格式需要在 URL 中包含模型名
                let effectiveModel = model ?? profile.defaultModel
                path = "/models/\(effectiveModel):generateContent"
            } else {
                path = "/v1/chat/completions"
            }
        case .ollama:
            let shouldUseChat = useChatCompletions ?? false
            path = shouldUseChat ? "/v1/chat/completions" : "/api/generate"
        case .zhipuAI:
            path = "/chat/completions"
        case .miniMaxCN, .miniMaxGlobal:
            path = "/text/chatcompletion_v2"
        case .custom:
            // 自定义协议，尝试检测
            if useChatCompletions == true {
                path = "/v1/chat/completions"
            } else {
                path = "/api/generate"
            }
        }
        
        guard let url = URL(string: "\(cleanEndpoint)\(path)") else {
            throw AIServiceError.invalidEndpoint
        }
        return url
    }
    
    /// 构建请求体
    func buildRequestBody(
        for profile: AIServiceProfile,
        messages: [[String: Any]],
        model: String? = nil,
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        additionalParams: [String: Any]? = nil
    ) -> [String: Any] {
        let effectiveModel = model ?? profile.defaultModel
        
        // 全局 max_tokens 范围验证 [1, 8192]
        var adjustedMaxTokens = maxTokens
        if let maxTokens = maxTokens {
            // 确保 max_tokens 在有效范围内 [1, 8192]
            if maxTokens < 1 {
                adjustedMaxTokens = 1
            } else if maxTokens > 8192 {
                adjustedMaxTokens = 8192
            }
        }
        
        // qwen 系列模型的特殊处理
        let modelLowercased = effectiveModel.lowercased()
        if modelLowercased.contains("qwen") {
            if adjustedMaxTokens == nil {
                // 如果没有指定 maxTokens，为 qwen 模型设置默认值 8192
                adjustedMaxTokens = 8192
            }
        }
        
        let endpoint = profile.effectiveEndpoint.lowercased()
        let usesDashScopeCompatibleMode = endpoint.contains("compatible-mode") || endpoint.contains("/chat/completions")
        
        switch profile.protocolType {
        case .openAI, .azureOpenAI, .someIM, .openRouter, .zhipuAI:
            // OpenAI 兼容格式（智谱 AI 使用 OpenAI 兼容接口）
            var body: [String: Any] = [
                "model": effectiveModel,
                "messages": messages
            ]
            if let temperature = temperature {
                body["temperature"] = temperature
            }
            if let topP = topP {
                body["top_p"] = topP
            }
            if let maxTokens = adjustedMaxTokens {
                body["max_tokens"] = maxTokens
            }
            if let additionalParams = additionalParams {
                body.merge(additionalParams) { (_, new) in new }
            }
            return body
            
        case .miniMaxCN, .miniMaxGlobal:
            // MiniMax OpenAI 兼容格式，使用 max_completion_tokens
            var body: [String: Any] = [
                "model": effectiveModel,
                "messages": messages
            ]
            if let temperature = temperature {
                body["temperature"] = temperature
            }
            if let topP = topP {
                body["top_p"] = topP
            }
            if let maxTokens = adjustedMaxTokens {
                body["max_completion_tokens"] = maxTokens
            }
            if let additionalParams = additionalParams {
                body.merge(additionalParams) { (_, new) in new }
            }
            return body
            
        case .dashScope:
            if usesDashScopeCompatibleMode {
                // DashScope 兼容模式（OpenAI 格式）
                var body: [String: Any] = [
                    "model": effectiveModel,
                    "messages": messages
                ]
                if let temperature = temperature {
                    body["temperature"] = temperature
                }
                if let topP = topP {
                    body["top_p"] = topP
                }
                if let maxTokens = adjustedMaxTokens {
                    body["max_tokens"] = maxTokens
                }
                if let additionalParams = additionalParams {
                    body.merge(additionalParams) { (_, new) in new }
                }
                return body
            } else {
                // DashScope 原生格式
                var body: [String: Any] = [
                    "model": effectiveModel,
                    "input": [
                        "messages": messages
                    ]
                ]
                var parameters: [String: Any] = [:]
                if let temperature = temperature {
                    parameters["temperature"] = temperature
                }
                if let topP = topP {
                    parameters["top_p"] = topP
                }
                if let maxTokens = adjustedMaxTokens {
                    parameters["max_tokens"] = maxTokens
                }
                if let additionalParams = additionalParams {
                    parameters.merge(additionalParams) { (_, new) in new }
                }
                if !parameters.isEmpty {
                    body["parameters"] = parameters
                }
                return body
            }
            
        case .claude:
            // Claude 格式
            var body: [String: Any] = [
                "model": effectiveModel,
                "messages": messages,
                "max_tokens": adjustedMaxTokens ?? 1024
            ]
            if let temperature = temperature {
                body["temperature"] = temperature
            }
            if let topP = topP {
                body["top_p"] = topP
            }
            if let additionalParams = additionalParams {
                body.merge(additionalParams) { (_, new) in new }
            }
            return body
            
        case .gemini:
            // Gemini 格式（支持 OpenAI 兼容和原生格式）
            // 检查 endpoint 是否包含 /v1beta 来判断使用哪种格式
            let isNativeFormat = profile.effectiveEndpoint.contains("/v1beta")
            
            if isNativeFormat {
                // 原生 Gemini API 格式
                var contents: [[String: Any]] = []
                for msg in messages {
                    if let role = msg["role"] as? String {
                        var parts: [[String: Any]] = []
                        if let content = msg["content"] as? String {
                            parts.append(["text": content])
                        } else if let contentArray = msg["content"] as? [[String: Any]] {
                            // 处理多模态内容
                            for item in contentArray {
                                if let text = item["text"] as? String {
                                    parts.append(["text": text])
                                } else if let imageUrl = item["image_url"] as? [String: Any],
                                          let url = imageUrl["url"] as? String {
                                    parts.append(["inline_data": ["mime_type": "image/png", "data": url]])
                                }
                            }
                        }
                        contents.append([
                            "role": role == "user" ? "user" : "model",
                            "parts": parts
                        ])
                    }
                }
                var body: [String: Any] = [
                    "contents": contents
                ]
                if let temperature = temperature {
                    body["temperature"] = temperature
                }
                if let topP = topP {
                    body["topP"] = topP
                }
                if let maxTokens = adjustedMaxTokens {
                    body["maxOutputTokens"] = maxTokens
                }
                if let additionalParams = additionalParams {
                    body.merge(additionalParams) { (_, new) in new }
                }
                return body
            } else {
                // OpenAI 兼容格式
                var body: [String: Any] = [
                    "model": effectiveModel,
                    "messages": messages
                ]
                if let temperature = temperature {
                    body["temperature"] = temperature
                }
                if let topP = topP {
                    body["top_p"] = topP
                }
                if let maxTokens = adjustedMaxTokens {
                    body["max_tokens"] = maxTokens
                }
                if let additionalParams = additionalParams {
                    body.merge(additionalParams) { (_, new) in new }
                }
                return body
            }
            
        case .ollama:
            // Ollama 格式
            let lastUserMessage = messages.last { ($0["role"] as? String) == "user" }
            let prompt = lastUserMessage?["content"] as? String ?? ""
            
            var body: [String: Any] = [
                "model": effectiveModel,
                "prompt": prompt,
                "stream": false,
                // 关掉思考模式，否则 gemma4 这类模型会先吐一大段思考，实测慢一个数量级
                OllamaRequestDefaults.thinkingKey: OllamaRequestDefaults.thinkingEnabled
            ]

            if let systemPrompt = systemPrompt {
                body["system"] = systemPrompt
            }
            
            var options: [String: Any] = [:]
            if let temperature = temperature {
                options["temperature"] = temperature
            }
            if let topP = topP {
                options["top_p"] = topP
            }
            if let maxTokens = adjustedMaxTokens {
                options["num_predict"] = maxTokens
            }
            if !options.isEmpty {
                body["options"] = options
            }
            
            if let additionalParams = additionalParams {
                body.merge(additionalParams) { (_, new) in new }
            }
            
            return body
            
        case .custom:
            // 自定义协议，默认使用 OpenAI 兼容格式
            var body: [String: Any] = [
                "model": effectiveModel,
                "messages": messages
            ]
            if let temperature = temperature {
                body["temperature"] = temperature
            }
            if let topP = topP {
                body["top_p"] = topP
            }
            if let maxTokens = adjustedMaxTokens {
                body["max_tokens"] = maxTokens
            }
            if let additionalParams = additionalParams {
                body.merge(additionalParams) { (_, new) in new }
            }
            return body
        }
    }
    
    /// 构建请求头
    func buildRequestHeaders(for profile: AIServiceProfile) -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json"
        ]
        
        // 添加认证头
        if !profile.apiKey.isEmpty {
            let headerName = profile.protocolType.authHeaderName
            let headerValue = profile.protocolType.formatAuthHeader(apiKey: profile.apiKey)
            headers[headerName] = headerValue
        }
        
        return headers
    }
    
    /// 解析响应
    func parseResponse(
        data: Data,
        for profile: AIServiceProfile
    ) throws -> (content: String, thinking: String?) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.invalidResponse
        }
        
        let responseText: String
        var thinking: String? = nil
        let endpoint = profile.effectiveEndpoint.lowercased()
        let dashScopeUsesCompatibleMode = endpoint.contains("compatible-mode") || endpoint.contains("/chat/completions")
        
        switch profile.protocolType {
        case .openAI, .azureOpenAI, .someIM, .openRouter, .zhipuAI, .miniMaxCN, .miniMaxGlobal:
            // OpenAI 格式（智谱、MiniMax 均兼容）
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                responseText = content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                throw AIServiceError.invalidResponse
            }
            
        case .dashScope:
            if dashScopeUsesCompatibleMode {
                // 兼容模式使用 OpenAI 格式
                if let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any] {
                    if let content = message["content"] as? String {
                        responseText = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if let contentArray = message["content"] as? [[String: Any]] {
                        var textParts: [String] = []
                        for item in contentArray {
                            if let text = item["text"] as? String {
                                textParts.append(text)
                            }
                        }
                        responseText = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        throw AIServiceError.invalidResponse
                    }
                } else {
                    throw AIServiceError.invalidResponse
                }
            } else if let output = json["output"] as? [String: Any] {
                // DashScope 原生格式
                if let text = output["text"] as? String {
                    responseText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let choices = output["choices"] as? [[String: Any]],
                          let firstChoice = choices.first,
                          let message = firstChoice["message"] as? [String: Any] {
                    if let contentArray = message["content"] as? [[String: Any]] {
                        var textParts: [String] = []
                        for item in contentArray {
                            if let text = item["text"] as? String {
                                textParts.append(text)
                            }
                        }
                        responseText = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if let content = message["content"] as? String {
                        responseText = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        throw AIServiceError.invalidResponse
                    }
                    
                    // 提取 thinking（如果有）
                    if let thinkingContent = message["thinking"] as? String {
                        thinking = thinkingContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } else {
                    throw AIServiceError.invalidResponse
                }
            } else {
                throw AIServiceError.invalidResponse
            }
            
        case .claude:
            // Claude 格式
            if let content = json["content"] as? [[String: Any]],
               let firstContent = content.first,
               let text = firstContent["text"] as? String {
                responseText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                throw AIServiceError.invalidResponse
            }
            
        case .gemini:
            // Gemini 格式（支持 OpenAI 兼容和原生格式）
            let isNativeFormat = profile.effectiveEndpoint.contains("/v1beta")
            
            if isNativeFormat {
                // 原生 Gemini API 格式
                if let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let text = firstPart["text"] as? String {
                    responseText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    throw AIServiceError.invalidResponse
                }
            } else {
                // OpenAI 兼容格式
                if let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    responseText = content.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    throw AIServiceError.invalidResponse
                }
            }
            
        case .ollama:
            // Ollama 格式
            guard let responseTextValue = json["response"] as? String else {
                throw AIServiceError.invalidResponse
            }
            responseText = responseTextValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
        case .custom:
            // 自定义协议，尝试 OpenAI 格式
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                responseText = content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let response = json["response"] as? String {
                responseText = response.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                throw AIServiceError.invalidResponse
            }
        }
        
        return (content: responseText, thinking: thinking)
    }
}

/// AI 服务错误
enum AIServiceError: LocalizedError {
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

// MARK: - 流式支持

extension AIServiceAdapter {
    /// 给请求体加上对应协议的「开启流式」标志
    func enableStreaming(in body: [String: Any], for profile: AIServiceProfile) -> [String: Any] {
        var result = body
        switch profile.protocolType {
        case .openAI, .azureOpenAI, .someIM, .openRouter, .zhipuAI,
             .miniMaxCN, .miniMaxGlobal, .custom:
            result["stream"] = true
        case .dashScope:
            let endpoint = profile.effectiveEndpoint.lowercased()
            let usesOpenAICompatible = endpoint.contains("compatible-mode") || endpoint.contains("/chat/completions")
            if usesOpenAICompatible {
                result["stream"] = true
                // DashScope 兼容模式下需要 stream_options.include_usage 才有 usage 信息，这里不强制
            } else {
                // DashScope 原生需要 X-DashScope-SSE: enable 头，且 incremental_output 控制是否增量
                var parameters = (result["parameters"] as? [String: Any]) ?? [:]
                parameters["incremental_output"] = true
                result["parameters"] = parameters
            }
        case .claude:
            result["stream"] = true
        case .gemini:
            // Gemini 走原生流式端点（generateContent → streamGenerateContent），由 URL 控制；body 不需要变
            break
        case .ollama:
            // Ollama: stream 默认就是 true，显式置为 true 以防被前面 buildRequestBody 设为 false
            result["stream"] = true
        }
        return result
    }

    /// 流式调用专用的 URL：Gemini / DashScope 原生需要换路径或加查询参数
    func buildStreamURL(for profile: AIServiceProfile, model: String? = nil) throws -> URL {
        let url = try buildAPIURL(for: profile, useChatCompletions: true, model: model)
        switch profile.protocolType {
        case .gemini:
            // 把 :generateContent 改成 :streamGenerateContent，并带 alt=sse
            var absolute = url.absoluteString
            if absolute.contains(":generateContent") {
                absolute = absolute.replacingOccurrences(of: ":generateContent", with: ":streamGenerateContent")
            }
            if !absolute.contains("alt=sse") {
                absolute += absolute.contains("?") ? "&alt=sse" : "?alt=sse"
            }
            return URL(string: absolute) ?? url
        default:
            return url
        }
    }

    /// 流式调用要补的请求头（SSE）
    func buildStreamHeaders(for profile: AIServiceProfile) -> [String: String] {
        var headers = buildRequestHeaders(for: profile)
        headers["Accept"] = "text/event-stream"
        if profile.protocolType == .dashScope {
            let endpoint = profile.effectiveEndpoint.lowercased()
            let usesOpenAICompatible = endpoint.contains("compatible-mode") || endpoint.contains("/chat/completions")
            if !usesOpenAICompatible {
                headers["X-DashScope-SSE"] = "enable"
            }
        }
        return headers
    }

    /// 解析一段 SSE chunk（已剥掉 "data: " 前缀的 JSON 字符串），返回新增的文本增量。
    /// 流式结束/无内容时返回空字符串。Gemini/Ollama 用每行一个 JSON 的形式，也走这里。
    func parseStreamChunk(_ jsonString: String, for profile: AIServiceProfile) -> String {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed == "[DONE]" { return "" }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }

        switch profile.protocolType {
        case .openAI, .azureOpenAI, .someIM, .openRouter, .zhipuAI,
             .miniMaxCN, .miniMaxGlobal, .custom:
            return extractOpenAIDelta(from: json)
        case .dashScope:
            let endpoint = profile.effectiveEndpoint.lowercased()
            if endpoint.contains("compatible-mode") || endpoint.contains("/chat/completions") {
                return extractOpenAIDelta(from: json)
            }
            // 原生 DashScope：output.text 或 output.choices[0].message.content（开 incremental_output 后是 delta）
            if let output = json["output"] as? [String: Any] {
                if let text = output["text"] as? String { return text }
                if let choices = output["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any] {
                    if let content = message["content"] as? String { return content }
                    if let contentArr = message["content"] as? [[String: Any]] {
                        return contentArr.compactMap { $0["text"] as? String }.joined()
                    }
                }
            }
            return ""
        case .claude:
            // Claude SSE：每个事件是 {"type": "content_block_delta", "delta": {"type":"text_delta","text": "..."}}
            if let type = json["type"] as? String,
               type == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                return text
            }
            return ""
        case .gemini:
            // Gemini 流式：candidates[0].content.parts[0].text
            if let candidates = json["candidates"] as? [[String: Any]],
               let first = candidates.first,
               let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]] {
                return parts.compactMap { $0["text"] as? String }.joined()
            }
            return ""
        case .ollama:
            // Ollama 流式：每行一个 JSON，字段 response
            return (json["response"] as? String) ?? ""
        }
    }

    private func extractOpenAIDelta(from json: [String: Any]) -> String {
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first else { return "" }
        if let delta = first["delta"] as? [String: Any] {
            if let content = delta["content"] as? String { return content }
            if let arr = delta["content"] as? [[String: Any]] {
                return arr.compactMap { $0["text"] as? String }.joined()
            }
        }
        // 个别中转站不严格走 delta，会直接给完整 message
        if let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        return ""
    }
}

