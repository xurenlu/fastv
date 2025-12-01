//
//  AIServiceProfile.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation

/// AI 协议类型
enum AIProtocolType: String, Codable, CaseIterable {
    case openAI = "openai"
    case azureOpenAI = "azure_openai"
    case dashScope = "dashscope"
    case ollama = "ollama"
    case claude = "claude"
    case someIM = "some_im"
    case gemini = "gemini"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .azureOpenAI:
            return "Azure OpenAI"
        case .dashScope:
            return "阿里云 DashScope"
        case .ollama:
            return "Ollama (本地)"
        case .claude:
            return "Claude (Anthropic)"
        case .someIM:
            return "Some.IM"
        case .gemini:
            return "Google Gemini"
        case .custom:
            return "自定义"
        }
    }
    
    /// 默认 API Endpoint
    var defaultEndpoint: String? {
        switch self {
        case .openAI:
            return "https://api.openai.com/v1"
        case .azureOpenAI:
            return nil // 需要用户提供
        case .dashScope:
            return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .ollama:
            return "http://127.0.0.1:11434"
        case .claude:
            return "https://api.anthropic.com/v1"
        case .someIM:
            return "https://api.some.im/api/v2/text-generation"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta"
        case .custom:
            return nil
        }
    }
    
    /// 是否需要 API Key
    var requiresAPIKey: Bool {
        switch self {
        case .ollama:
            return false
        default:
            return true
        }
    }
    
    /// Endpoint 是否可编辑
    var endpointEditable: Bool {
        switch self {
        case .someIM:
            return false // Some.IM 固定 endpoint
        default:
            return true
        }
    }
    
    /// 推荐模型列表
    var recommendedModels: [String] {
        switch self {
        case .openAI:
            return ["gpt-4o-mini", "gpt-4o", "gpt-3.5-turbo", "gpt-4-turbo"]
        case .azureOpenAI:
            return ["gpt-4o-mini", "gpt-4o", "gpt-3.5-turbo"]
        case .dashScope:
            return ["qwen-turbo", "qwen-plus", "qwen-max", "qwen-max-longcontext"]
        case .ollama:
            return ["gemma2:2b", "deepseek-r1:1.5b", "qwen2.5:7b", "llama3.2:3b"]
        case .claude:
            return ["claude-3-5-sonnet-20241022", "claude-3-opus-20240229", "claude-3-sonnet-20240229"]
        case .someIM:
            return ["gpt-4o-mini", "gpt-4o", "gpt-3.5-turbo"]
        case .gemini:
            return ["gemini-3-pro-preview", "gemini-2.5-pro", "gemini-2.5-flash", "gemini-1.5-pro", "gemini-1.5-flash", "gemini-pro"]
        case .custom:
            return []
        }
    }
    
    /// 认证 Header 名称
    var authHeaderName: String {
        switch self {
        case .claude:
            return "x-api-key"
        case .gemini:
            return "x-goog-api-key"
        default:
            return "Authorization"
        }
    }
    
    /// 认证 Header 值格式
    func formatAuthHeader(apiKey: String) -> String {
        switch self {
        case .claude, .gemini:
            return apiKey // 直接使用 API Key，不使用 Bearer
        default:
            return "Bearer \(apiKey)"
        }
    }
}

/// AI 服务使用场景
enum AIScenario: String, Codable, CaseIterable {
    case voiceInputOptimization = "voice_input_optimization"  // 语音输入优化
    case meetingSummary = "meeting_summary"                    // 会议摘要
    case todoParsing = "todo_parsing"                          // Todo 解析
    case aiChat = "ai_chat"                                     // AI 聊天
    case textCorrection = "text_correction"                     // 文本纠错
    case errorDetection = "error_detection"                    // 错误检测
    case videoAnalysis = "video_analysis"                       // 视频分析
    case diaryAnalysis = "diary_analysis"                       // 日记分析
    case expenseParsing = "expense_parsing"                     // 记账解析
    case intelGeneration = "intel_generation"                   // 情报生成
    
    var displayName: String {
        switch self {
        case .voiceInputOptimization:
            return "语音输入优化"
        case .meetingSummary:
            return "会议摘要"
        case .todoParsing:
            return "Todo 解析"
        case .aiChat:
            return "AI 聊天"
        case .textCorrection:
            return "文本纠错"
        case .errorDetection:
            return "错误检测"
        case .videoAnalysis:
            return "视频分析"
        case .diaryAnalysis:
            return "日记分析"
        case .expenseParsing:
            return "记账解析"
        case .intelGeneration:
            return "情报生成"
        }
    }
}

/// AI 服务配置 Profile
struct AIServiceProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var protocolType: AIProtocolType
    var endpoint: String
    var apiKey: String
    var defaultModel: String
    var timeout: Double
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        protocolType: AIProtocolType,
        endpoint: String? = nil,
        apiKey: String = "",
        defaultModel: String = "",
        timeout: Double = 30.0,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.protocolType = protocolType
        self.endpoint = endpoint ?? protocolType.defaultEndpoint ?? ""
        self.apiKey = apiKey
        self.defaultModel = defaultModel.isEmpty ? (protocolType.recommendedModels.first ?? "") : defaultModel
        self.timeout = timeout
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case protocolType
        case endpoint
        case apiKey
        case defaultModel
        case timeout
        case isDefault
        case createdAt
        case updatedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名服务"
        protocolType = try container.decodeIfPresent(AIProtocolType.self, forKey: .protocolType) ?? .ollama
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? protocolType.defaultEndpoint ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel) ?? (protocolType.recommendedModels.first ?? "")
        timeout = try container.decodeIfPresent(Double.self, forKey: .timeout) ?? (protocolType == .ollama ? 5.0 : 30.0)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
    
    /// 获取有效的 endpoint（Some.IM 等固定 endpoint）
    var effectiveEndpoint: String {
        if !protocolType.endpointEditable && protocolType.defaultEndpoint != nil {
            return protocolType.defaultEndpoint!
        }
        return endpoint
    }
    
    /// 创建默认 Profile
    static func createDefault(for protocolType: AIProtocolType) -> AIServiceProfile {
        return AIServiceProfile(
            name: protocolType.displayName,
            protocolType: protocolType,
            defaultModel: protocolType.recommendedModels.first ?? "",
            timeout: protocolType == .ollama ? 5.0 : 30.0
        )
    }
}

/// 场景配置绑定
struct AIScenarioBinding: Codable {
    var scenario: AIScenario
    var profileId: UUID?
    var modelOverride: String? // 可选：覆盖 Profile 的默认模型
    var timeoutOverride: Double? // 可选：覆盖 Profile 的默认超时
    
    init(scenario: AIScenario, profileId: UUID? = nil, modelOverride: String? = nil, timeoutOverride: Double? = nil) {
        self.scenario = scenario
        self.profileId = profileId
        self.modelOverride = modelOverride
        self.timeoutOverride = timeoutOverride
    }
}

