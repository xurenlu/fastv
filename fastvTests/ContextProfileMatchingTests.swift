//
//  ContextProfileMatchingTests.swift
//  fastvTests
//
//  覆盖 Power Mode 的核心匹配语义：
//  - MatchRule.matches（bundleId / urlPattern / appNameContains）
//  - MatchRule.globMatch（* 通配）
//  - ContextProfile.matchScore + renderedPrompt 占位符替换
//  - ContextProfileManager.match 优先级（bundleId > urlPattern > appNameContains）
//

import Testing
import Foundation
@testable import musetype

@Suite("ContextProfileMatching")
@MainActor
struct ContextProfileMatchingTests {

    private func ctx(bundle: String? = nil, name: String? = nil, url: String? = nil) -> AppContext {
        AppContext(bundleId: bundle, appName: name, browserURL: url, resolvedAt: Date(timeIntervalSince1970: 0))
    }

    // MARK: - MatchRule

    @Test("bundleId 严格匹配，大小写不敏感")
    func bundleIdMatch() {
        let rule = MatchRule.bundleId("com.apple.mail")
        #expect(rule.matches(ctx(bundle: "com.apple.mail")))
        #expect(rule.matches(ctx(bundle: "COM.apple.MAIL")))
        #expect(!rule.matches(ctx(bundle: "com.tinyspeck.slackmacgap")))
        #expect(!rule.matches(ctx(bundle: nil)))
    }

    @Test("urlPattern * 通配命中浏览器 URL")
    func urlPatternMatch() {
        let r1 = MatchRule.urlPattern("*.slack.com/*")
        #expect(r1.matches(ctx(url: "https://my-team.slack.com/messages/C1")))
        #expect(r1.matches(ctx(url: "https://foo.slack.com/")))
        #expect(!r1.matches(ctx(url: "https://example.com/")))
        #expect(!r1.matches(ctx(url: nil)))

        // Gmail 邮件
        let r2 = MatchRule.urlPattern("*mail.google.com/*")
        #expect(r2.matches(ctx(url: "https://mail.google.com/mail/u/0/#inbox")))
        #expect(!r2.matches(ctx(url: "https://google.com/")))
    }

    @Test("appNameContains 子串匹配，大小写不敏感")
    func appNameMatch() {
        let rule = MatchRule.appNameContains("Visual Studio Code")
        #expect(rule.matches(ctx(name: "Visual Studio Code")))
        #expect(rule.matches(ctx(name: "visual studio code")))
        #expect(rule.matches(ctx(name: "Microsoft Visual Studio Code Insiders")))
        #expect(!rule.matches(ctx(name: "Xcode")))
        #expect(!rule.matches(ctx(name: nil)))
    }

    @Test("globMatch 正则字符被转义")
    func globEscapesRegex() {
        // 模式里含 . 应当只匹配字面点号，而不是任意字符
        let pattern = "*.slack.com/*"
        #expect(MatchRule.globMatch(pattern: pattern, text: "x.slack.com/y"))
        #expect(!MatchRule.globMatch(pattern: pattern, text: "xXslackXcom/y"))
    }

    // MARK: - ContextProfile

    @Test("matchScore 返回命中规则的最大 precedence")
    func matchScorePrecedence() {
        let p = ContextProfile(
            name: "test",
            matchRules: [
                .appNameContains("Mail"),          // 10
                .bundleId("com.apple.mail"),       // 100
            ],
            promptTemplate: ""
        )
        #expect(p.matchScore(for: ctx(bundle: "com.apple.mail", name: "Mail")) == 100)
        #expect(p.matchScore(for: ctx(name: "Mail")) == 10)
        #expect(p.matchScore(for: ctx(bundle: "other")) == 0)
    }

    @Test("renderedPrompt 替换 {appName} {browserURL} 占位符；未提供值清空字面占位符")
    func renderedPromptVariables() {
        let p = ContextProfile(
            name: "x",
            matchRules: [],
            promptTemplate: "App: {appName}\nURL: {browserURL}\nText: {transcript}"
        )
        let out = p.renderedPrompt(appName: "Mail", browserURL: "https://x", transcript: "hi")
        #expect(out.contains("App: Mail"))
        #expect(out.contains("URL: https://x"))
        #expect(out.contains("Text: hi"))

        let outEmpty = p.renderedPrompt(appName: nil, browserURL: nil, transcript: nil)
        #expect(!outEmpty.contains("{appName}"))
        #expect(!outEmpty.contains("{browserURL}"))
        #expect(!outEmpty.contains("{transcript}"))
    }

    // MARK: - ContextProfileManager

    @Test("Manager.match 取最高 precedence 命中（bundleId 击败 urlPattern 与 appNameContains）")
    func managerPicksHighestPrecedence() {
        let mgr = ContextProfileManager.shared
        // 备份现状再清空
        let backup = mgr.profiles
        defer {
            // 还原（这里直接覆盖 profiles 数组不会触发 save 的强一致，足够测试用）
            for p in mgr.profiles where !backup.contains(where: { $0.id == p.id }) {
                if !p.isBuiltIn { mgr.remove(p) }
            }
        }

        // 注入两个测试 profile
        let pBundle = ContextProfile(
            name: "B", matchRules: [.bundleId("com.example.app")],
            promptTemplate: "BUNDLE_PROMPT"
        )
        let pUrl = ContextProfile(
            name: "U", matchRules: [.urlPattern("*example.com/*")],
            promptTemplate: "URL_PROMPT"
        )
        let pName = ContextProfile(
            name: "N", matchRules: [.appNameContains("Example")],
            promptTemplate: "NAME_PROMPT"
        )
        mgr.add(pName)
        mgr.add(pUrl)
        mgr.add(pBundle)

        mgr.enablePowerMode = true
        let hit = mgr.match(ctx(
            bundle: "com.example.app",
            name: "Example",
            url: "https://example.com/x"
        ))
        #expect(hit?.name == "B", "bundleId 优先级应当最高")

        // 移除 bundle 后，urlPattern 接力
        mgr.remove(pBundle)
        let hit2 = mgr.match(ctx(name: "Example", url: "https://example.com/x"))
        #expect(hit2?.name == "U", "urlPattern 优先于 appNameContains")

        // 清理测试 profile
        mgr.remove(pUrl)
        mgr.remove(pName)
    }

    @Test("Manager.match 关闭 Power Mode 时返回 nil")
    func managerHonorsDisableFlag() {
        let mgr = ContextProfileManager.shared
        let saved = mgr.enablePowerMode
        defer { mgr.enablePowerMode = saved }

        mgr.enablePowerMode = false
        let hit = mgr.match(ctx(bundle: "com.apple.mail"))
        #expect(hit == nil)
    }

    @Test("Manager.resolveSystemPrompt 未命中走 default，命中走模板")
    func resolvePromptFallback() {
        let mgr = ContextProfileManager.shared
        let saved = mgr.enablePowerMode
        defer { mgr.enablePowerMode = saved }
        mgr.enablePowerMode = true

        let defaultPrompt = "DEFAULT_FALLBACK"
        // 未命中（一个根本没有匹配规则的奇怪 bundle）
        let out1 = mgr.resolveSystemPrompt(
            defaultPrompt: defaultPrompt,
            context: ctx(bundle: "com.does.not.exist.zzzzz"),
            transcript: "hi"
        )
        #expect(out1 == defaultPrompt)

        // 命中：临时加一个 profile
        let p = ContextProfile(
            name: "T", matchRules: [.bundleId("com.example.resolve.test")],
            promptTemplate: "HIT:{appName}"
        )
        mgr.add(p)
        defer { mgr.remove(p) }

        let out2 = mgr.resolveSystemPrompt(
            defaultPrompt: defaultPrompt,
            context: ctx(bundle: "com.example.resolve.test", name: "MyApp"),
            transcript: "hi"
        )
        #expect(out2 == "HIT:MyApp")
    }
}
