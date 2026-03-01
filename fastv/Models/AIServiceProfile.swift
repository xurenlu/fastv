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
    case openRouter = "openrouter"
    case zhipuAI = "zhipu_ai"           // 智谱 AI
    case miniMaxCN = "minimax_cn"        // MiniMax 国内版
    case miniMaxGlobal = "minimax_global"  // MiniMax 国际版
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
        case .openRouter:
            return "OpenRouter"
        case .zhipuAI:
            return "智谱 AI"
        case .miniMaxCN:
            return "MiniMax (国内)"
        case .miniMaxGlobal:
            return "MiniMax (国际)"
        case .custom:
            return "自定义（中转站）"
        }
    }
    
    /// 图标名称（SF Symbols）
    var iconName: String {
        switch self {
        case .openAI:
            return "sparkles"
        case .azureOpenAI:
            return "cloud.fill"
        case .dashScope:
            return "cloud.sun.fill"
        case .ollama:
            return "server.rack"
        case .claude:
            return "brain.head.profile"
        case .someIM:
            return "message.fill"
        case .gemini:
            return "star.fill"
        case .openRouter:
            return "arrow.triangle.branch"
        case .zhipuAI:
            return "brain"
        case .miniMaxCN:
            return "globe.asia.australia.fill"
        case .miniMaxGlobal:
            return "globe.americas.fill"
        case .custom:
            return "gearshape.fill"
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
        case .openRouter:
            return "https://openrouter.ai/api/v1"
        case .zhipuAI:
            return "https://open.bigmodel.cn/api/paas/v4"
        case .miniMaxCN:
            return "https://api.minimaxi.com/v1"
        case .miniMaxGlobal:
            return "https://api.minimax.io/v1"
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
            return ["qwen-flash", "qwen3.5-flash", "qwen3.5-plus", "qwen-turbo", "qwen-plus", "qwen-max", "qwen-max-longcontext", "qwen-vl-plus", "qwen-vl-max"]
        case .ollama:
            return ["gemma2:2b", "deepseek-r1:1.5b", "qwen2.5:7b", "llama3.2:3b"]
        case .claude:
            return ["claude-3-5-sonnet-20241022", "claude-3-opus-20240229", "claude-3-sonnet-20240229"]
        case .someIM:
            return ["gpt-4o-mini", "gpt-4o", "gpt-3.5-turbo"]
        case .gemini:
            return ["gemini-3-pro-preview", "gemini-2.5-pro", "gemini-2.5-flash", "gemini-1.5-pro", "gemini-1.5-flash", "gemini-pro"]
        case .openRouter:
            return ["openai/gpt-4o-mini", "openai/gpt-4o", "anthropic/claude-3.5-sonnet", "google/gemini-2.0-flash", "deepseek/deepseek-chat", "meta-llama/llama-3.1-70b-instruct"]
        case .zhipuAI:
            return ["glm-4-flash", "glm-4-air", "glm-4", "glm-4-plus", "glm-4-long", "glm-4-airx", "glm-4v", "glm-4v-plus"]
        case .miniMaxCN, .miniMaxGlobal:
            return ["MiniMax-M2.5", "MiniMax-M2.5-highspeed", "MiniMax-M2.1", "MiniMax-M2.1-highspeed", "MiniMax-M2", "M2-her"]
        case .custom:
            return []
        }
    }
    
    /// 判断指定模型是否支持视觉（图片/多模态）
    func supportsVision(model: String) -> Bool {
        let m = model.lowercased()
        switch self {
        case .dashScope:
            return m.contains("qwen-vl") || m.contains("qwen2-vl")
        case .zhipuAI:
            return m.contains("glm-4v") || m.contains("glm-4-plus")
        case .miniMaxCN, .miniMaxGlobal:
            return m.contains("abab6.5s") || m.contains("vision") || m.contains("m2")
        case .openAI, .azureOpenAI:
            return m.contains("gpt-4o") || m.contains("gpt-4-vision") || m.contains("gpt-4-turbo")
        case .claude:
            return m.contains("claude-3")
        case .gemini:
            return m.contains("gemini-1.5") || m.contains("gemini-2")
        case .openRouter, .someIM, .custom:
            return m.contains("vision") || m.contains("vl") || m.contains("4o") || m.contains("gpt-4")
        case .ollama:
            return m.contains("llava") || m.contains("vision") || m.contains("qwen-vl")
        }
    }
    
    /// 默认超时时间（秒）
    var defaultTimeout: Double {
        switch self {
        case .ollama:
            return 5.0       // 本地服务，响应快
        case .dashScope:
            return 60.0      // DashScope 云端 API，推理较慢
        case .claude:
            return 60.0      // Claude 云端 API
        case .gemini:
            return 60.0      // Gemini 云端 API
        case .openAI, .azureOpenAI, .openRouter, .someIM:
            return 30.0      // OpenAI 系列通常较快
        case .zhipuAI, .miniMaxCN, .miniMaxGlobal:
            return 60.0      // 国内云端 API
        case .custom:
            return 60.0      // 自定义服务，预留更多时间
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
    
    /// API Key 申请页面 URL（nil 表示无专属申请页）
    var apiKeyApplicationURL: String? {
        switch self {
        case .dashScope:
            return "https://bailian.console.aliyun.com/?tab=model#/api-key"
        case .zhipuAI:
            return "https://open.bigmodel.cn/usercenter/apikeys"
        case .miniMaxCN:
            return "https://platform.minimaxi.com/user-center/basic-information/interface-key"
        case .miniMaxGlobal:
            return "https://platform.minimax.io/user-center/basic-information/interface-key"
        default:
            return nil
        }
    }
}

/// AI 服务使用场景
enum AIScenario: String, Codable, CaseIterable {
    case voiceInputOptimization = "voice_input_optimization"  // 语音输入优化
    case meetingSummary = "meeting_summary"                    // 会议记录（标题、摘要、行动项）
    case todoParsing = "todo_parsing"                          // Todo 解析
    case aiChat = "ai_chat"                                     // AI 聊天
    case textCorrection = "text_correction"                     // 文本纠错
    case errorDetection = "error_detection"                    // 错误检测
    case videoAnalysis = "video_analysis"                       // 视频分析（已移除）
    case diaryAnalysis = "diary_analysis"                       // 日记分析（已移除）
    case expenseParsing = "expense_parsing"                     // 记账解析（已移除）
    case intelGeneration = "intel_generation"                   // 情报生成（已移除）

    /// 当前版本仍在使用的场景，仅这些场景在设置中显示 AI 配置
    static var activeScenarios: [AIScenario] {
        [.voiceInputOptimization, .meetingSummary, .todoParsing, .aiChat]
    }

    var displayName: String {
        switch self {
        case .voiceInputOptimization:
            return "语音输入优化"
        case .meetingSummary:
            return "会议记录"
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
        timeout: Double? = nil,
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
        self.timeout = timeout ?? protocolType.defaultTimeout
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
        timeout = try container.decodeIfPresent(Double.self, forKey: .timeout) ?? protocolType.defaultTimeout
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
            timeout: protocolType.defaultTimeout
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

