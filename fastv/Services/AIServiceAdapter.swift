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
        case .openAI, .azureOpenAI, .someIM:
            path = "/v1/chat/completions"
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
        case .openAI, .azureOpenAI, .someIM:
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
                "stream": false
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
        case .openAI, .azureOpenAI, .someIM:
            // OpenAI 格式
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

