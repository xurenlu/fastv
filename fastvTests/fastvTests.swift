//
//  fastvTests.swift
//  fastvTests
//
//  Created by rocky on 2025/11/19.
//

import Testing
@testable import row1

struct fastvTests {

    @Test func recentSentenceRangeUsesChinesePunctuationBoundary() async throws {
        let text = "第一句已经完成。第二句需要回改"
        let range = try #require(ActiveTextInputTextAnalyzer.recentSentenceRange(
            in: text,
            cursorLocation: text.utf16.count,
            maxLength: 800
        ))
        #expect(ActiveTextInputTextAnalyzer.substring(text, range: range) == "第二句需要回改")
    }

    @Test func recentSentenceRangeUsesNewlineBoundary() async throws {
        let text = "标题\n这一段需要润色   "
        let range = try #require(ActiveTextInputTextAnalyzer.recentSentenceRange(
            in: text,
            cursorLocation: text.utf16.count,
            maxLength: 800
        ))
        #expect(ActiveTextInputTextAnalyzer.substring(text, range: range) == "这一段需要润色")
    }

    @Test func recentSentenceRangeKeepsEmojiScalarBoundaryWhenClamped() async throws {
        let text = "前文。请把这个🙂句子改短一些"
        let range = try #require(ActiveTextInputTextAnalyzer.recentSentenceRange(
            in: text,
            cursorLocation: text.utf16.count,
            maxLength: 7
        ))
        let fragment = try #require(ActiveTextInputTextAnalyzer.substring(text, range: range))
        #expect(fragment == "句子改短一些")
    }

    @Test func replacingUsesUtf16RangesSafely() async throws {
        let text = "第一句。第二句🙂"
        let range = try #require(ActiveTextInputTextAnalyzer.recentSentenceRange(
            in: text,
            cursorLocation: text.utf16.count,
            maxLength: 800
        ))
        let replaced = ActiveTextInputTextAnalyzer.replacing(in: text, range: range, with: "第二句已经改好。")
        #expect(replaced == "第一句。第二句已经改好。")
    }

    @Test func rewriteInstructionDetectionAllowsCommandsButRejectsPlainDictation() async throws {
        #expect(ActiveTextInputTextAnalyzer.looksLikeRewriteInstruction("润色上一句，语气自然一点"))
        #expect(ActiveTextInputTextAnalyzer.looksLikeRewriteInstruction("rewrite this sentence"))
        #expect(!ActiveTextInputTextAnalyzer.looksLikeRewriteInstruction("今天下午三点开会"))
    }

}
