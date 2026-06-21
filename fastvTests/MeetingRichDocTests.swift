//
//  MeetingRichDocTests.swift
//  fastvTests
//
//  Created by rocky on 2026/06/03.
//

import Testing
@testable import musetype

struct MeetingRichDocTests {

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
