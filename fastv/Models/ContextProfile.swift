//
//  ContextProfile.swift
//  fastv
//
//  Power Mode 上下文模板：按前台 App / 浏览器 URL 匹配，为「语音输入优化」
//  这条 AI 后处理替换 prompt 模板（覆盖 UserPreferences.aiSystemPrompt 默认值）。
//
//  对标 VoiceInk Power Mode / Superwhisper Custom Mode / Wispr Flow Writing Styles。
//

import Foundation

/// 匹配规则。一个 ContextProfile 可以挂多条规则，任一命中即视为命中（OR 语义）。
enum MatchRule: Codable, Equatable, Hashable {
    /// 严格按前台 App 的 bundleId 匹配（例 "com.apple.mail"）。
    case bundleId(String)
    /// 浏览器 URL 通配，支持 `*`（例 "*.slack.com/*"）。仅当 AppContext.browserURL 非 nil 时才参与。
    case urlPattern(String)
    /// App 名子串匹配（例 "Visual Studio Code"）。大小写不敏感。
    case appNameContains(String)

    enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case bundleId, urlPattern, appNameContains }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bundleId(let v):
            try c.encode(Kind.bundleId, forKey: .type); try c.encode(v, forKey: .value)
        case .urlPattern(let v):
            try c.encode(Kind.urlPattern, forKey: .type); try c.encode(v, forKey: .value)
        case .appNameContains(let v):
            try c.encode(Kind.appNameContains, forKey: .type); try c.encode(v, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        let value = try c.decode(String.self, forKey: .value)
        switch kind {
        case .bundleId: self = .bundleId(value)
        case .urlPattern: self = .urlPattern(value)
        case .appNameContains: self = .appNameContains(value)
        }
    }

    /// 规则的优先级权重：bundleId(100) > urlPattern(50) > appNameContains(10)。
    /// 用于多 profile 同时命中时挑出最具体的那一个。
    var precedence: Int {
        switch self {
        case .bundleId: return 100
        case .urlPattern: return 50
        case .appNameContains: return 10
        }
    }

    /// 判断该规则是否匹配给定上下文。
    func matches(_ ctx: AppContext) -> Bool {
        switch self {
        case .bundleId(let id):
            guard let cur = ctx.bundleId else { return false }
            return cur.caseInsensitiveCompare(id) == .orderedSame

        case .urlPattern(let pattern):
            guard let url = ctx.browserURL, !url.isEmpty else { return false }
            return Self.globMatch(pattern: pattern, text: url)

        case .appNameContains(let needle):
            guard let name = ctx.appName, !needle.isEmpty else { return false }
            return name.range(of: needle, options: .caseInsensitive) != nil
        }
    }

    /// 简易 glob：把 `*` 翻译成 `.*`，其余字符走正则转义，整段加 ^…$ 锚定。
    static func globMatch(pattern: String, text: String) -> Bool {
        var regex = "^"
        for ch in pattern {
            if ch == "*" {
                regex += ".*"
            } else {
                regex += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        regex += "$"
        return text.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// 上下文 Profile：一组匹配规则 + 一个 prompt 模板。
struct ContextProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var matchRules: [MatchRule]
    /// prompt 模板，支持占位符：{transcript} {appName} {browserURL}。空串视作"沿用默认 aiSystemPrompt"。
    var promptTemplate: String
    /// 可选：命中时使用特定 AIServiceProfile（按 id 关联）。nil 表示沿用当前 voiceInputOptimization 绑定。
    var aiProfileId: UUID?
    /// 是否内置预设（不可删，但可改）。
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        matchRules: [MatchRule],
        promptTemplate: String,
        aiProfileId: UUID? = nil,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.matchRules = matchRules
        self.promptTemplate = promptTemplate
        self.aiProfileId = aiProfileId
        self.isBuiltIn = isBuiltIn
    }

    /// 把 promptTemplate 里的占位符替换成实际值。
    /// 注意：transcript 通常单独作为 user message 传，本函数主要替换 appName / browserURL。
    func renderedPrompt(appName: String?, browserURL: String?, transcript: String?) -> String {
        var out = promptTemplate
        if let appName { out = out.replacingOccurrences(of: "{appName}", with: appName) }
        if let browserURL { out = out.replacingOccurrences(of: "{browserURL}", with: browserURL) }
        if let transcript { out = out.replacingOccurrences(of: "{transcript}", with: transcript) }
        // 没传值的占位符清空，避免字面 {appName} 出现在最终 prompt
        out = out.replacingOccurrences(of: "{appName}", with: "")
        out = out.replacingOccurrences(of: "{browserURL}", with: "")
        out = out.replacingOccurrences(of: "{transcript}", with: "")
        return out
    }

    /// 命中权重 = 命中规则的最大 precedence；未命中返回 0。
    /// 用于在 ContextProfileManager 多 profile 命中时选最具体的那一个。
    func matchScore(for ctx: AppContext) -> Int {
        matchRules
            .filter { $0.matches(ctx) }
            .map { $0.precedence }
            .max() ?? 0
    }
}
