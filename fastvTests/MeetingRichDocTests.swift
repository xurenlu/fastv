//
//  MeetingRichDocTests.swift
//  fastvTests
//
//  Created by rocky on 2026/06/03.
//

import Testing
@testable import musetype

struct MeetingRichDocTests {

    // MARK: - decideRichDocTrigger

    @Test func skipsWhenIntervalTooShort() {
        let input = RichDocTriggerInput(
            unconsumedCharCount: 500,
            secondsSinceLastTrigger: 5,           // 刚刚触发过
            secondsSinceLastTranscriptUpdate: 0,
            isRecording: true
        )
        #expect(decideRichDocTrigger(input: input) == .skip)
    }

    @Test func triggersWhenCharThresholdReached() {
        let input = RichDocTriggerInput(
            unconsumedCharCount: 200,
            secondsSinceLastTrigger: .infinity,
            secondsSinceLastTranscriptUpdate: 0,
            isRecording: true
        )
        if case .skip = decideRichDocTrigger(input: input) { Issue.record("应当触发") }
    }

    @Test func triggersOnPauseWithEnoughNewChars() {
        let input = RichDocTriggerInput(
            unconsumedCharCount: 50,
            secondsSinceLastTrigger: 60,           // 间隔够长
            secondsSinceLastTranscriptUpdate: 15,  // 已经停顿 15 秒
            isRecording: true
        )
        if case .skip = decideRichDocTrigger(input: input) { Issue.record("停顿态应当触发") }
    }

    @Test func skipsPauseWhenNotEnoughNewChars() {
        let input = RichDocTriggerInput(
            unconsumedCharCount: 5,                // 新增过少
            secondsSinceLastTrigger: 60,
            secondsSinceLastTranscriptUpdate: 20,
            isRecording: true
        )
        #expect(decideRichDocTrigger(input: input) == .skip)
    }

    @Test func skipsWhenNothingNewEvenAfterLongInterval() {
        let input = RichDocTriggerInput(
            unconsumedCharCount: 0,
            secondsSinceLastTrigger: 600,
            secondsSinceLastTranscriptUpdate: 600,
            isRecording: true
        )
        #expect(decideRichDocTrigger(input: input) == .skip)
    }

    @Test func customConfigOverridesThresholds() {
        var cfg = RichDocTriggerConfig()
        cfg.charThreshold = 80
        let input = RichDocTriggerInput(
            unconsumedCharCount: 100,
            secondsSinceLastTrigger: .infinity,
            secondsSinceLastTranscriptUpdate: 0,
            isRecording: true
        )
        if case .skip = decideRichDocTrigger(input: input, config: cfg) {
            Issue.record("调小阈值后应当触发")
        }
    }

    // MARK: - Markdown mermaid 解析

    @Test func parsesMermaidAsCodeBlockWithLanguage() {
        let md = """
        # 会议
        ```mermaid
        graph TD
          A --> B
        ```
        正文
        """
        let elements = parseMarkdown(md)
        let mermaidEl = elements.first { el in
            if case .codeBlock(let lang) = el.type, lang?.lowercased() == "mermaid" {
                return true
            }
            return false
        }
        #expect(mermaidEl != nil)
        #expect(mermaidEl?.content.contains("A --> B") == true)
    }

    @Test func parsesRegularCodeBlockSeparately() {
        let md = """
        ```swift
        let x = 1
        ```
        """
        let elements = parseMarkdown(md)
        let swiftEl = elements.first { el in
            if case .codeBlock(let lang) = el.type, lang?.lowercased() == "swift" {
                return true
            }
            return false
        }
        #expect(swiftEl != nil)
    }

    // MARK: - AIScenario 新增场景

    @Test func newScenariosAreActive() {
        let active = Set(AIScenario.activeScenarios)
        #expect(active.contains(.meetingTranscriptRevision))
        #expect(active.contains(.meetingRichDoc))
        #expect(active.contains(.meetingSummary))
    }

    @Test func newScenariosHaveDisplayNamesAndDescriptions() {
        #expect(!AIScenario.meetingTranscriptRevision.displayName.isEmpty)
        #expect(!AIScenario.meetingRichDoc.displayName.isEmpty)
        #expect(!AIScenario.meetingTranscriptRevision.sceneDescription.isEmpty)
        #expect(!AIScenario.meetingRichDoc.sceneDescription.isEmpty)
    }
}
