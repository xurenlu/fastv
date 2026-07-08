//
//  TerminologyCorrectionTests.swift
//  fastvTests
//
//  覆盖术语包（CorrectionCategory.terminology）在 CommonMistakeManager
//  替换管线中的优先级与大小写感知行为。
//

import Testing
import Foundation
@testable import musetype

@Suite("TerminologyCorrection")
@MainActor
struct TerminologyCorrectionTests {

    // CommonMistakeManager 是单例，不便重建。
    // 我们只清掉用户自定义规则，保留内置规则不动（避免污染其它测试套件）。
    private func resetManager(_ m: CommonMistakeManager) {
        let custom = m.mistakes.filter { !$0.isBuiltIn }
        m.remove(custom)
        m.enableAutoCorrection = true
    }

    @Test("术语条目大小写不敏感命中：'open ai' → 'OpenAI'")
    func terminologyCaseInsensitiveMatch() {
        let m = CommonMistakeManager.shared
        resetManager(m)
        m.addOrUpdate(wrong: "open ai", correct: "OpenAI", category: .terminology)

        let out = m.applyCorrections(to: "I love open ai products.")
        #expect(out == "I love OpenAI products.")
    }

    @Test("术语条目同样命中大写变体：'OPEN AI' → 'OpenAI'")
    func terminologyMatchesUppercase() {
        let m = CommonMistakeManager.shared
        resetManager(m)
        m.addOrUpdate(wrong: "open ai", correct: "OpenAI", category: .terminology)

        let out = m.applyCorrections(to: "OPEN AI rocks")
        #expect(out == "OpenAI rocks")
    }

    @Test("非术语条目仍走大小写敏感（保留历史行为）")
    func nonTerminologyKeepsCaseSensitive() {
        let m = CommonMistakeManager.shared
        resetManager(m)
        m.addOrUpdate(wrong: "foo", correct: "bar", category: .other)

        // 大小写不一致不应该命中
        let out = m.applyCorrections(to: "FOO baz Foo")
        #expect(out == "FOO baz Foo")
        // 完整匹配才命中
        let out2 = m.applyCorrections(to: "say foo here")
        #expect(out2 == "say bar here")
    }

    @Test("术语优先于普通错字：同 wrong 时术语先替换，普通规则被旁路")
    func terminologyTakesPrecedence() {
        let m = CommonMistakeManager.shared
        resetManager(m)
        // 两条规则同 wrong 不同 correct + 不同 category：
        // - 普通错字 confidence 高
        // - 术语 confidence 低
        // 但术语应当优先生效（拍前），且替换后的字符串不再匹配普通规则
        m.addOrUpdate(wrong: "hello", correct: "HELLO_OTHER", confidence: 0.99, category: .other)
        m.addOrUpdate(wrong: "hello", correct: "HELLO_TERM", confidence: 0.10, category: .terminology)

        // 期望：术语先把 hello → HELLO_TERM；普通规则的 \bhello\b 在 HELLO_TERM 里
        // 因 _ 是单词字符不构成边界，所以再也不匹配，结果稳定为 HELLO_TERM。
        let out = m.applyCorrections(to: "hello world")
        #expect(out == "HELLO_TERM world")
    }

    @Test("术语包：addOrUpdate 同 wrong/correct 时 category 升级为 terminology")
    func addOrUpdateUpgradesToTerminology() {
        let m = CommonMistakeManager.shared
        resetManager(m)
        m.addOrUpdate(wrong: "k8s", correct: "Kubernetes", category: .other)
        m.addOrUpdate(wrong: "k8s", correct: "Kubernetes", category: .terminology)
        let entry = m.mistakes.first { $0.wrong == "k8s" && $0.correct == "Kubernetes" }
        #expect(entry?.category == .terminology)
    }

    @Test("内置中英混合术语：'麦克 app' → 'Mac app'")
    func builtInMixedLanguageMacAppCorrection() {
        let m = CommonMistakeManager.shared
        resetManager(m)

        let out = m.applyCorrections(to: "我想做一个麦克 app，然后发布到麦克系统。")
        #expect(out == "我想做一个Mac app，然后发布到macOS。")
    }

    @Test("内置流行技术词：OpenAI / GitHub / TypeScript")
    func builtInPopularTechTermCorrections() {
        let m = CommonMistakeManager.shared
        resetManager(m)

        let out = m.applyCorrections(to: "open ai 的 sdk 放在 git hub，用 type script 写。")
        #expect(out == "OpenAI 的 sdk 放在 GitHub，用 TypeScript 写。")
    }
}
