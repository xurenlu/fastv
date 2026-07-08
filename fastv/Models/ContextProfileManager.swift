//
//  ContextProfileManager.swift
//  fastv
//
//  Power Mode 路由器：根据当前 AppContext 查找最具体匹配的 ContextProfile，
//  返回该 profile 的 prompt 模板（覆盖默认 aiSystemPrompt）与可选 AI Profile。
//
//  持久化：UserDefaults("contextProfiles")。出厂自动注入 4 个内置预设。
//

import Foundation
import Combine

@MainActor
final class ContextProfileManager: ObservableObject {
    static let shared = ContextProfileManager()

    @Published var profiles: [ContextProfile] = []
    @Published var enablePowerMode: Bool {
        didSet { UserDefaults.standard.set(enablePowerMode, forKey: Keys.enablePowerMode) }
    }

    private enum Keys {
        static let profiles = "contextProfiles_v1"
        static let enablePowerMode = "enablePowerMode"
        static let hasInitializedBuiltIns = "contextProfiles_hasInitializedBuiltIns_v1"
        static let hasMigratedLightStructure = "contextProfiles_hasMigratedLightStructure_v1"
        static let hasMigratedMixedLanguageTerms = "contextProfiles_hasMigratedMixedLanguageTerms_v1"
        static let hasMigratedShortReferenceContext = "contextProfiles_hasMigratedShortReferenceContext_v1"
    }

    private init() {
        enablePowerMode = UserDefaults.standard.object(forKey: Keys.enablePowerMode) as? Bool ?? true
        load()
        initializeBuiltInsIfNeeded()
        migrateBuiltInsForLightStructureIfNeeded()
        migrateBuiltInsForMixedLanguageTermsIfNeeded()
        migrateBuiltInsForShortReferenceContextIfNeeded()
    }

    // MARK: - 查询

    /// 根据上下文找出最具体匹配的 profile。
    /// 优先级：bundleId > urlPattern > appNameContains。同级时取数组中靠前者。
    /// 未启用 Power Mode 或无命中返回 nil（调用方应回退到默认 aiSystemPrompt）。
    func match(_ ctx: AppContext) -> ContextProfile? {
        guard enablePowerMode else { return nil }
        let scored = profiles
            .map { (profile: $0, score: $0.matchScore(for: ctx)) }
            .filter { $0.score > 0 }
        return scored.max(by: { $0.score < $1.score })?.profile
    }

    /// 解析最终用于本次 AI 后处理的 system prompt。
    /// - 已启用 Power Mode + 有命中 profile + profile.promptTemplate 非空 → 返回模板渲染结果
    /// - 否则 → 返回 defaultPrompt（来自 UserPreferences.aiSystemPrompt）
    func resolveSystemPrompt(
        defaultPrompt: String,
        context: AppContext,
        transcript: String?
    ) -> String {
        guard let profile = match(context),
              !profile.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultPrompt
        }
        return profile.renderedPrompt(
            appName: context.appName,
            browserURL: context.browserURL,
            transcript: transcript
        )
    }

    // MARK: - 编辑

    func add(_ profile: ContextProfile) {
        profiles.append(profile)
        save()
    }

    func remove(_ profile: ContextProfile) {
        guard !profile.isBuiltIn else { return } // 内置不可删（可改）
        profiles.removeAll { $0.id == profile.id }
        save()
    }

    func update(_ profile: ContextProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        save()
    }

    /// 还原所有内置预设到出厂状态（不影响用户自建条目）。
    func resetBuiltInsToDefault() {
        profiles.removeAll { $0.isBuiltIn }
        profiles.append(contentsOf: Self.builtInDefaults())
        save()
    }

    // MARK: - 持久化

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: Keys.profiles)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Keys.profiles),
              let decoded = try? JSONDecoder().decode([ContextProfile].self, from: data) else {
            profiles = []
            return
        }
        profiles = decoded
    }

    private func initializeBuiltInsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Keys.hasInitializedBuiltIns) else { return }
        // 先去重 / 移除可能残留的旧 isBuiltIn
        profiles.removeAll { $0.isBuiltIn }
        profiles.append(contentsOf: Self.builtInDefaults())
        UserDefaults.standard.set(true, forKey: Keys.hasInitializedBuiltIns)
        save()
    }

    /// 仅迁移仍保持旧出厂文案的内置预设；用户改过 promptTemplate 的预设不动。
    private func migrateBuiltInsForLightStructureIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Keys.hasMigratedLightStructure) else { return }

        let legacyDefaults = Self.legacyBuiltInDefaults()
        let currentDefaults = Self.builtInDefaults()
        var didChange = false

        for index in profiles.indices where profiles[index].isBuiltIn {
            guard let legacy = legacyDefaults.first(where: { $0.promptTemplate == profiles[index].promptTemplate }),
                  let current = currentDefaults.first(where: { Set($0.matchRules) == Set(legacy.matchRules) }) else {
                continue
            }

            profiles[index].promptTemplate = current.promptTemplate
            didChange = true
        }

        UserDefaults.standard.set(true, forKey: Keys.hasMigratedLightStructure)
        if didChange {
            save()
        }
    }

    /// 仅迁移仍保持出厂文案的内置预设；用户改过 promptTemplate 的预设不动。
    private func migrateBuiltInsForMixedLanguageTermsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Keys.hasMigratedMixedLanguageTerms) else { return }

        let previousDefaults = Self.builtInDefaults(
            includeLightStructure: true,
            includeMixedLanguageTerms: false,
            includeShortReferenceContext: false
        )
        let currentDefaults = Self.builtInDefaults()
        var didChange = false

        for index in profiles.indices where profiles[index].isBuiltIn {
            guard let previous = previousDefaults.first(where: { $0.promptTemplate == profiles[index].promptTemplate }),
                  let current = currentDefaults.first(where: { Set($0.matchRules) == Set(previous.matchRules) }) else {
                continue
            }

            profiles[index].promptTemplate = current.promptTemplate
            didChange = true
        }

        UserDefaults.standard.set(true, forKey: Keys.hasMigratedMixedLanguageTerms)
        if didChange {
            save()
        }
    }

    /// 仅迁移仍保持出厂文案的内置预设；用户改过 promptTemplate 的预设不动。
    private func migrateBuiltInsForShortReferenceContextIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Keys.hasMigratedShortReferenceContext) else { return }

        let previousDefaults = Self.builtInDefaults(
            includeLightStructure: true,
            includeMixedLanguageTerms: true,
            includeShortReferenceContext: false
        )
        let currentDefaults = Self.builtInDefaults()
        var didChange = false

        for index in profiles.indices where profiles[index].isBuiltIn {
            guard let previous = previousDefaults.first(where: { $0.promptTemplate == profiles[index].promptTemplate }),
                  let current = currentDefaults.first(where: { Set($0.matchRules) == Set(previous.matchRules) }) else {
                continue
            }

            profiles[index].promptTemplate = current.promptTemplate
            didChange = true
        }

        UserDefaults.standard.set(true, forKey: Keys.hasMigratedShortReferenceContext)
        if didChange {
            save()
        }
    }

    // MARK: - 内置预设

    /// 4 个出厂预设。它们的 promptTemplate 在用户首次进入设置时可被改写，
    /// 也支持通过 resetBuiltInsToDefault() 还原。
    static func builtInDefaults() -> [ContextProfile] {
        builtInDefaults(
            includeLightStructure: true,
            includeMixedLanguageTerms: true,
            includeShortReferenceContext: true
        )
    }

    private static func legacyBuiltInDefaults() -> [ContextProfile] {
        builtInDefaults(
            includeLightStructure: false,
            includeMixedLanguageTerms: false,
            includeShortReferenceContext: false
        )
    }

    private static func builtInDefaults(
        includeLightStructure: Bool,
        includeMixedLanguageTerms: Bool,
        includeShortReferenceContext: Bool
    ) -> [ContextProfile] {
        let sharedStructureRules = includeLightStructure
            ? """
- 多事项内容可以用短列表提升可读性
- 如果原文天然包含多个事项、条件、步骤或请求，可以整理成 2-5 条短列表；不要强行列表化单句闲聊，不要新增原文没有的信息
"""
            : ""
        let sharedMixedLanguageRules = includeMixedLanguageTerms
            ? """
- 高置信度修正常见中英混合术语、产品名、技术词和流行词：麦克 app→Mac app，麦克 OS / Mac OS→macOS，open ai→OpenAI，chat gpt→ChatGPT，git hub→GitHub，type script→TypeScript，swift ui→SwiftUI，vs code→VS Code
- 只在语境明确时修正；不确定时保留原文，不要臆造术语或新增信息
"""
            : ""
        let sharedReferenceContextRules = includeShortReferenceContext
            ? """
- 如果用户消息包含“同一 App 短上下文”，只把它当作当前 App 当前输入框光标前的一小段参考，用于修正本次语音里的同音/近音错误；例如编程语境中“保持工作去干净”应修正为“保持工作区干净”
- 不要复述、总结、续写短上下文；不要引入其他 App、历史会话、全局记忆或外部事实
"""
            : ""
        let emailFormatRules = includeLightStructure
            ? """
- 必要时拆段
\(sharedStructureRules)
- 称呼/结尾敬语自然保留
"""
            : """
- 必要时拆段
- 称呼/结尾敬语自然保留
"""
        let conversationalFormatRules = includeLightStructure
            ? """
- 短句更短，不要硬塞书面语
\(sharedStructureRules)
"""
            : "- 短句更短，不要硬塞书面语"
        let codeOutputRules = includeLightStructure
            ? """
- 涉及 API/类型/函数名时保留原大小写（iPhone / OpenAI / NSURL）
- 如果口述包含多项 TODO、步骤或条件，可以输出多行 `// - ` 列表注释；否则保持默认单行注释
- 不输出中文，除非口述明确要求"中文注释"
"""
            : """
- 涉及 API/类型/函数名时保留原大小写（iPhone / OpenAI / NSURL）
- 不输出中文，除非口述明确要求"中文注释"
"""
        let slackListRules = includeLightStructure
            ? """
- 列表型内容用 - 项目符号
\(sharedStructureRules)
"""
            : "- 列表型内容用 - 项目符号"

        let emailPrompt = """
你是一个邮件语境的语音输入优化助手。把口述文本改写成正式、礼貌、适合邮件正文的书面语。

【规则】
- 去口水词、加标点
\(emailFormatRules)
\(sharedMixedLanguageRules)
\(sharedReferenceContextRules)
- 不要新增原文没有的信息
- 只输出改写后的正文，不要加引号或解释

当前应用：{appName}
"""

        let imPrompt = """
你是一个 IM / 群聊语境的语音输入优化助手。保持口语化、自然、轻松的语气。

【规则】
- 去掉无意义填充词（嗯/啊/那个/就是）但保留语气
\(conversationalFormatRules)
- 不加多余敬语
- 中英文之间留半角空格
\(sharedMixedLanguageRules)
\(sharedReferenceContextRules)
- 只输出改写后的文本

当前应用：{appName}
"""

        let codePrompt = """
你是一个 IDE / 代码编辑器内的语音输入优化助手。把口述改写为简洁的英文代码注释或英文标识符候选。

【规则】
- 默认输出 `// ` 开头的单行英文注释；如口述含有"多行""block"等词则输出 `/* ... */`
- 去口水词、保留技术术语
\(codeOutputRules)
\(sharedMixedLanguageRules)
\(sharedReferenceContextRules)
- 只输出注释/标识符本身

当前应用：{appName}
"""

        let slackPrompt = """
你是一个 Slack 语境的语音输入优化助手。保持简短、直接、可读的英文/中文消息风格。

【规则】
- 去口水词、加必要标点
- 涉及代码片段时用 `code` 反引号
\(slackListRules)
\(sharedMixedLanguageRules)
\(sharedReferenceContextRules)
- 称呼以 @name 形式时保留 @ 符号
- 只输出改写后的消息

当前应用：{appName}
"""

        return [
            // 1) 邮件正式
            ContextProfile(
                name: NSLocalizedString("context.profile.builtin.email", comment: ""),
                matchRules: [
                    .bundleId("com.apple.mail"),
                    .bundleId("com.microsoft.Outlook"),
                    .bundleId("com.readdle.smartemail-Mac"), // Spark
                    .urlPattern("*mail.google.com/*"),
                    .urlPattern("*outlook.live.com/*"),
                    .urlPattern("*outlook.office.com/*"),
                ],
                promptTemplate: emailPrompt,
                isBuiltIn: true
            ),
            // 2) Slack
            ContextProfile(
                name: NSLocalizedString("context.profile.builtin.slack", comment: ""),
                matchRules: [
                    .bundleId("com.tinyspeck.slackmacgap"),
                    .urlPattern("*.slack.com/*"),
                ],
                promptTemplate: slackPrompt,
                isBuiltIn: true
            ),
            // 3) IM / 微信 / Discord（口语风格）
            ContextProfile(
                name: NSLocalizedString("context.profile.builtin.im", comment: ""),
                matchRules: [
                    .bundleId("com.tencent.xinWeChat"),     // 微信
                    .bundleId("com.tencent.wemeetapp"),     // 腾讯会议
                    .bundleId("com.hnc.Discord"),
                    .bundleId("com.electron.discord"),
                    .bundleId("ru.keepcoder.Telegram"),
                    .bundleId("net.whatsapp.WhatsApp"),
                ],
                promptTemplate: imPrompt,
                isBuiltIn: true
            ),
            // 4) 代码/IDE
            ContextProfile(
                name: NSLocalizedString("context.profile.builtin.code", comment: ""),
                matchRules: [
                    .bundleId("com.apple.dt.Xcode"),
                    .bundleId("com.microsoft.VSCode"),
                    .bundleId("com.microsoft.VSCodeInsiders"),
                    .bundleId("com.todesktop.230313mzl4w4u92"), // Cursor
                    .appNameContains("JetBrains"),
                ],
                promptTemplate: codePrompt,
                isBuiltIn: true
            ),
        ]
    }
}
