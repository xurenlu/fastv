//
//  ActiveTextInputContextService.swift
//  fastv
//
//  Created on 2026/05/24.
//

import Foundation
import AppKit
import ApplicationServices

struct ActiveTextInputTextAnalyzer {
    static func looksLikeRewriteInstruction(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")

        guard !normalized.isEmpty else { return false }

        let prefixes = [
            "修改", "改一下", "改成", "把上一句", "把这句", "把這句", "把刚才", "把剛才",
            "上一句改", "这句话改", "這句話改", "重写", "重寫", "重新写", "重新寫",
            "润色", "潤色", "优化上一句", "優化上一句", "优化这句", "優化這句",
            "替换", "替換", "修正", "纠正", "糾正", "帮我改", "幫我改",
            "rewrite", "replace", "change", "polish", "revise", "correct"
        ]

        return prefixes.contains { normalized.hasPrefix($0) }
    }

    static func recentSentenceRange(in text: String, cursorLocation: Int, maxLength: Int) -> CFRange? {
        let textLength = text.utf16.count
        guard textLength > 0 else { return nil }

        var end = max(0, min(cursorLocation, textLength))
        end = trimTrailingInlineWhitespace(in: text, utf16End: end)
        guard end > 0 else { return nil }

        var start = 0
        var offset = 0
        for character in text {
            let nextOffset = offset + character.utf16.count
            if nextOffset > end { break }
            if isSentenceBoundary(character) {
                start = nextOffset
            }
            offset = nextOffset
        }

        start = trimLeadingWhitespace(in: text, utf16Start: start, utf16End: end)

        if end - start > maxLength {
            start = end - maxLength
            start = alignToScalarBoundary(in: text, utf16Offset: start, direction: .forward)
        }

        guard end > start else { return nil }
        return CFRange(location: start, length: end - start)
    }

    static func clamp(range: CFRange, upperBound: Int) -> CFRange {
        let location = max(0, min(range.location, upperBound))
        let length = max(0, min(range.length, upperBound - location))
        return CFRange(location: location, length: length)
    }

    static func substring(_ text: String, range: CFRange) -> String? {
        guard range.location >= 0,
              range.length >= 0,
              range.location + range.length <= text.utf16.count else {
            return nil
        }
        let start = String.Index(utf16Offset: range.location, in: text)
        let end = String.Index(utf16Offset: range.location + range.length, in: text)
        return String(text[start..<end])
    }

    static func replacing(in text: String, range: CFRange, with replacement: String) -> String? {
        guard range.location >= 0,
              range.length >= 0,
              range.location + range.length <= text.utf16.count else {
            return nil
        }
        let start = String.Index(utf16Offset: range.location, in: text)
        let end = String.Index(utf16Offset: range.location + range.length, in: text)
        var newText = text
        newText.replaceSubrange(start..<end, with: replacement)
        return newText
    }

    static func referenceContextBeforeCursor(in text: String, cursorLocation: Int, maxLength: Int) -> String? {
        let textLength = text.utf16.count
        guard textLength > 0, maxLength > 0 else { return nil }

        var end = max(0, min(cursorLocation, textLength))
        end = trimTrailingInlineWhitespace(in: text, utf16End: end)
        guard end > 0 else { return nil }

        var start = max(0, end - maxLength)
        start = alignToScalarBoundary(in: text, utf16Offset: start, direction: .forward)
        start = trimLeadingWhitespace(in: text, utf16Start: start, utf16End: end)

        guard end > start,
              let context = substring(text, range: CFRange(location: start, length: end - start)) else {
            return nil
        }

        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private enum BoundaryDirection {
        case forward
        case backward
    }

    private static func alignToScalarBoundary(in text: String, utf16Offset: Int, direction: BoundaryDirection) -> Int {
        var offset = max(0, min(utf16Offset, text.utf16.count))
        while offset >= 0 && offset <= text.utf16.count {
            if String.Index(utf16Offset: offset, in: text).samePosition(in: text) != nil {
                return offset
            }
            offset += direction == .forward ? 1 : -1
        }
        return direction == .forward ? text.utf16.count : 0
    }

    private static func trimTrailingInlineWhitespace(in text: String, utf16End: Int) -> Int {
        var end = utf16End
        while end > 0 {
            let previous = characterBefore(in: text, utf16Offset: end)
            guard let character = previous.character,
                  character != "\n",
                  character != "\r",
                  String(character).trimmingCharacters(in: .whitespaces).isEmpty else {
                break
            }
            end = previous.offset
        }
        return end
    }

    private static func trimLeadingWhitespace(in text: String, utf16Start: Int, utf16End: Int) -> Int {
        var start = utf16Start
        while start < utf16End {
            guard let character = characterAt(in: text, utf16Offset: start),
                  String(character).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                break
            }
            start += character.utf16.count
        }
        return start
    }

    private static func characterBefore(in text: String, utf16Offset: Int) -> (character: Character?, offset: Int) {
        var offset = 0
        var previous: (Character?, Int) = (nil, 0)
        for character in text {
            let nextOffset = offset + character.utf16.count
            if nextOffset >= utf16Offset {
                return (character, offset)
            }
            previous = (character, offset)
            offset = nextOffset
        }
        return previous
    }

    private static func characterAt(in text: String, utf16Offset: Int) -> Character? {
        var offset = 0
        for character in text {
            if offset == utf16Offset {
                return character
            }
            offset += character.utf16.count
        }
        return nil
    }

    private static func isSentenceBoundary(_ character: Character) -> Bool {
        switch character {
        case "\n", "\r", "。", "！", "？", "；", ".", "!", "?", ";":
            return true
        default:
            return false
        }
    }
}

/// 读取并回写当前焦点输入框的文本上下文。
///
/// 主要服务于语音输入的“回改最近一句”：优先使用选中文本；没有选区时，按光标前的标点或换行截取最近一句。
@MainActor
final class ActiveTextInputContextService {
    static let shared = ActiveTextInputContextService()

    struct EditableContext {
        let element: AXUIElement
        let fullText: String
        let targetText: String
        let targetRange: CFRange
        let selectionRange: CFRange
        let isSelectedText: Bool
    }

    private init() {}

    func captureRecentEditableContext(maxSentenceLength: Int = 800) -> EditableContext? {
        guard let focusedElement = focusedUIElement(),
              let fullText = stringAttribute(kAXValueAttribute, from: focusedElement) else {
            return nil
        }

        let textLength = fullText.utf16.count
        let selection = selectedTextRange(from: focusedElement) ?? CFRange(location: textLength, length: 0)
        let safeSelection = ActiveTextInputTextAnalyzer.clamp(range: selection, upperBound: textLength)

        if safeSelection.length > 0,
           let selectedText = ActiveTextInputTextAnalyzer.substring(fullText, range: safeSelection),
           !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return EditableContext(
                element: focusedElement,
                fullText: fullText,
                targetText: selectedText,
                targetRange: safeSelection,
                selectionRange: safeSelection,
                isSelectedText: true
            )
        }

        guard let recentRange = ActiveTextInputTextAnalyzer.recentSentenceRange(in: fullText, cursorLocation: safeSelection.location, maxLength: maxSentenceLength),
              let recentText = ActiveTextInputTextAnalyzer.substring(fullText, range: recentRange),
              !recentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return EditableContext(
            element: focusedElement,
            fullText: fullText,
            targetText: recentText,
            targetRange: recentRange,
            selectionRange: safeSelection,
            isSelectedText: false
        )
    }

    func captureShortReferenceContext(maxLength: Int = 260) -> String? {
        guard let focusedElement = focusedUIElement(),
              let fullText = stringAttribute(kAXValueAttribute, from: focusedElement) else {
            return nil
        }

        let textLength = fullText.utf16.count
        let selection = selectedTextRange(from: focusedElement) ?? CFRange(location: textLength, length: 0)
        let safeSelection = ActiveTextInputTextAnalyzer.clamp(range: selection, upperBound: textLength)
        return ActiveTextInputTextAnalyzer.referenceContextBeforeCursor(
            in: fullText,
            cursorLocation: safeSelection.location,
            maxLength: maxLength
        )
    }

    func replaceTarget(in context: EditableContext, with replacement: String) -> Bool {
        let cleanReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanReplacement.isEmpty else { return false }
        guard let newText = ActiveTextInputTextAnalyzer.replacing(in: context.fullText, range: context.targetRange, with: cleanReplacement) else {
            return false
        }

        let setValueResult = AXUIElementSetAttributeValue(
            context.element,
            kAXValueAttribute as CFString,
            newText as CFTypeRef
        )

        guard setValueResult == .success else {
            print("⚠️ [ActiveTextInputContextService] 回写 AXValue 失败: \(setValueResult.rawValue)")
            return false
        }

        let cursorLocation = context.targetRange.location + cleanReplacement.utf16.count
        _ = setSelectedTextRange(CFRange(location: cursorLocation, length: 0), on: context.element)
        return true
    }

    func selectTarget(in context: EditableContext) -> Bool {
        setSelectedTextRange(context.targetRange, on: context.element)
    }

    func looksLikeRewriteInstruction(_ text: String) -> Bool {
        ActiveTextInputTextAnalyzer.looksLikeRewriteInstruction(text)
    }

    private func focusedUIElement() -> AXUIElement? {
        let systemElement = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard result == .success else {
            print("⚠️ [ActiveTextInputContextService] 获取焦点元素失败: \(result.rawValue)")
            return nil
        }
        return focused.map { $0 as! AXUIElement }
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func selectedTextRange(from element: AXUIElement) -> CFRange? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )
        guard result == .success,
              let axValue = value,
              AXValueGetType(axValue as! AXValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        let ok = AXValueGetValue(axValue as! AXValue, .cfRange, &range)
        return ok ? range : nil
    }

    private func setSelectedTextRange(_ range: CFRange, on element: AXUIElement) -> Bool {
        var mutableRange = range
        guard let axRange = AXValueCreate(.cfRange, &mutableRange) else { return false }
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            axRange
        )
        return result == .success
    }

}
