import Combine
import Foundation

enum VoiceAITrigger: String, CaseIterable, Identifiable {
    case off, shortcut, always
    var id: String { rawValue }
    var titleKey: String { "experience.ai.\(rawValue)" }
    func shouldProcess(isAIShortcut: Bool) -> Bool {
        self == .always || (self == .shortcut && isAIShortcut)
    }
}

nonisolated enum AudioRetentionPolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    case recent500, fiveGB
    var id: String { rawValue }
    var titleKey: String { "experience.retention.\(rawValue)" }
    var countLimit: Int { self == .recent500 ? 500 : Int.max }
    static let byteLimit: Int64 = 5_000_000_000
}

@MainActor
final class InputExperiencePreferences: ObservableObject {
    static let shared = InputExperiencePreferences()
    private let defaults: UserDefaults
    @Published var aiTrigger: VoiceAITrigger {
        didSet { defaults.set(aiTrigger.rawValue, forKey: "voiceAITrigger") }
    }
    @Published var retainAudio: Bool {
        didSet {
            defaults.set(retainAudio, forKey: "retainEvaluationAudio")
            if !retainAudio { consentGeneration += 1 }
        }
    }
    @Published var retention: AudioRetentionPolicy {
        didSet { defaults.set(retention.rawValue, forKey: "evaluationAudioRetention") }
    }
    @Published var allowReferenceContext: Bool {
        didSet { defaults.set(allowReferenceContext, forKey: "allowVoiceAIReferenceContext") }
    }
    private(set) var consentGeneration = 0

    func invalidatePendingRecordings() { consentGeneration += 1 }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 老用户保留原先专用 AI 快捷键的行为；首次引导明确选择后保存新枚举。
        let migrated: VoiceAITrigger = defaults.bool(forKey: "hasCompletedOnboarding") ? .shortcut : .off
        aiTrigger = defaults.string(forKey: "voiceAITrigger").flatMap(VoiceAITrigger.init) ?? migrated
        retainAudio = defaults.bool(forKey: "retainEvaluationAudio")
        retention = defaults.string(forKey: "evaluationAudioRetention").flatMap(AudioRetentionPolicy.init) ?? .recent500
        allowReferenceContext = defaults.bool(forKey: "allowVoiceAIReferenceContext")
        defaults.set(aiTrigger.rawValue, forKey: "voiceAITrigger")
    }
}

/// 本次处理使用的配置快照。设置测试与真实输入共用解析和执行入口。
struct VoiceAIConfiguration {
    let profile: AIServiceProfile
    let model: String
    let timeout: Double
    let prompt: String
    let referenceContext: String?

    @MainActor
    static func resolve() -> VoiceAIConfiguration? {
        let preferences = UserPreferences.shared
        if let binding = preferences.aiScenarioBindings.first(where: { $0.scenario == .voiceInputOptimization }),
           let id = binding.profileId, preferences.getProfile(id: id) == nil { return nil }
        let config = preferences.getConfig(for: .voiceInputOptimization)
        guard let url = URL(string: config.profile.effectiveEndpoint),
              ["http", "https"].contains(url.scheme ?? ""), url.host != nil,
              !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let prompt = ContextProfileManager.shared.resolveSystemPrompt(
            defaultPrompt: preferences.aiSystemPrompt,
            context: AppContextResolver.shared.resolve(), transcript: "{transcript}"
        )
        return VoiceAIConfiguration(profile: config.profile, model: config.model, timeout: config.timeout,
            prompt: prompt, referenceContext: InputExperiencePreferences.shared.allowReferenceContext
                ? ActiveTextInputContextService.shared.captureShortReferenceContext() : nil)
    }

    @MainActor
    func optimize(_ text: String) async throws -> String {
        let result = try await OllamaService.shared.optimizeTranscript(
            text: text, profile: profile, model: model, timeout: timeout,
            systemPrompt: prompt.replacingOccurrences(of: "{transcript}", with: text),
            useMistakes: true, useHighFrequencyWords: true, referenceContext: referenceContext)
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "VoiceAI", code: 1,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("experience.ai.empty", comment: "")])
        }
        return result
    }
}
