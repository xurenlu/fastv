//
//  RimeKeyMappingTests.swift
//  fastvTests
//
//  macOS 键盘事件 → Rime keysym 映射与 UTF-8/UTF-16 光标偏移转换的单元测试。
//

import XCTest
@testable import musetype

final class RimeKeyMappingTests: XCTestCase {

    // MARK: - keysym 映射

    func testPrintableASCIIMapsToItself() {
        XCTAssertEqual(RimeKeyMapping.keysym(macKeyCode: 0, characters: "a"), 97)
        XCTAssertEqual(RimeKeyMapping.keysym(macKeyCode: 0, characters: "A"), 65)
        XCTAssertEqual(RimeKeyMapping.keysym(macKeyCode: 18, characters: "1"), 49)
        XCTAssertEqual(RimeKeyMapping.keysym(macKeyCode: 41, characters: ";"), 59)
        XCTAssertEqual(RimeKeyMapping.keysym(macKeyCode: 50, characters: "`"), 96) // 拼音反查前缀
    }

    func testFunctionKeysMapByKeyCode() {
        XCTAssertEqual(RimeKeyMapping.keysym(macKeyCode: 36, characters: "\r"), RimeKeyMapping.XK_Return)
        XCTAssertEqual(RimeKeyMapping.keysym(macKeyCode: 76, characters: nil), RimeKeyMapping.XK_Return)
        XCTAssertEqual(RimeKeyMapping.keysym(macKeyCode: 51, characters: nil), RimeKeyMapping.XK_BackSpace)
        XCTAssertEqual(RimeKeyMapping.keysym(macKeyCode: 53, characters: nil), RimeKeyMapping.XK_Escape)
        XCTAssertEqual(RimeKeyMapping.keysym(macKeyCode: 49, characters: " "), RimeKeyMapping.XK_space)
        XCTAssertEqual(RimeKeyMapping.keysym(macKeyCode: 116, characters: nil), RimeKeyMapping.XK_PageUp)
        XCTAssertEqual(RimeKeyMapping.keysym(macKeyCode: 121, characters: nil), RimeKeyMapping.XK_PageDown)
        XCTAssertEqual(RimeKeyMapping.keysym(macKeyCode: 123, characters: nil), RimeKeyMapping.XK_Left)
        XCTAssertEqual(RimeKeyMapping.keysym(macKeyCode: 126, characters: nil), RimeKeyMapping.XK_Up)
    }

    func testUnmappedKeysReturnNil() {
        // F1（键码 122）无字符
        XCTAssertNil(RimeKeyMapping.keysym(macKeyCode: 122, characters: nil))
        // 非 ASCII 字符不交给 Rime，透传宿主
        XCTAssertNil(RimeKeyMapping.keysym(macKeyCode: 0, characters: "中"))
        // 多字符输入不映射
        XCTAssertNil(RimeKeyMapping.keysym(macKeyCode: 0, characters: "ab"))
        // 控制字符（除已映射功能键）不映射
        XCTAssertNil(RimeKeyMapping.keysym(macKeyCode: 99, characters: "\u{10}"))
    }

    // MARK: - 独立 Shift 策略

    func testStandaloneShiftCommitsRawInputOnlyForHanCandidatesInChineseMode() {
        XCTAssertTrue(
            RimeKeyMapping.shouldCommitRawInputOnStandaloneShift(
                isASCIIMode: false,
                candidates: ["输入", "書入"]
            )
        )
        XCTAssertFalse(
            RimeKeyMapping.shouldCommitRawInputOnStandaloneShift(
                isASCIIMode: false,
                candidates: ["hello", "123"]
            )
        )
        XCTAssertFalse(
            RimeKeyMapping.shouldCommitRawInputOnStandaloneShift(
                isASCIIMode: true,
                candidates: ["输入"]
            )
        )
    }

    func testHanCandidateDetectionCoversCommonAndSupplementaryIdeographs() {
        XCTAssertTrue(RimeKeyMapping.containsHanCharacter("轻语"))
        XCTAssertTrue(RimeKeyMapping.containsHanCharacter("候选（推荐）"))
        XCTAssertTrue(RimeKeyMapping.containsHanCharacter("\u{20000}"))
        XCTAssertFalse(RimeKeyMapping.containsHanCharacter("Qecho 123"))
    }

    func testCandidateSelectionShortcutsMapToCurrentPageIndexes() {
        XCTAssertEqual(
            RimeKeyMapping.selectedCandidateIndex(
                for: RimeKeyMapping.XK_space,
                highlightedIndex: 3,
                candidateCount: 5,
                apostropheSelectsThird: false
            ),
            3
        )
        XCTAssertEqual(
            RimeKeyMapping.selectedCandidateIndex(
                for: 49,
                highlightedIndex: 0,
                candidateCount: 5,
                apostropheSelectsThird: false
            ),
            0
        )
        XCTAssertEqual(
            RimeKeyMapping.selectedCandidateIndex(
                for: 59,
                highlightedIndex: 0,
                candidateCount: 5,
                apostropheSelectsThird: false
            ),
            1
        )
        XCTAssertEqual(
            RimeKeyMapping.selectedCandidateIndex(
                for: 39,
                highlightedIndex: 0,
                candidateCount: 5,
                apostropheSelectsThird: true
            ),
            2
        )
        XCTAssertNil(
            RimeKeyMapping.selectedCandidateIndex(
                for: 39,
                highlightedIndex: 0,
                candidateCount: 5,
                apostropheSelectsThird: false
            )
        )
        XCTAssertNil(
            RimeKeyMapping.selectedCandidateIndex(
                for: 57,
                highlightedIndex: 0,
                candidateCount: 5,
                apostropheSelectsThird: false
            )
        )
    }

    // MARK: - 修饰键掩码

    func testModifierMaskComposition() {
        XCTAssertEqual(
            RimeKeyMapping.modifierMask(shift: false, control: false, option: false, command: false, capsLock: false),
            0
        )
        XCTAssertEqual(
            RimeKeyMapping.modifierMask(shift: true, control: false, option: false, command: false, capsLock: false),
            RimeKeyMapping.shiftMask
        )
        XCTAssertEqual(
            RimeKeyMapping.modifierMask(shift: true, control: true, option: true, command: false, capsLock: false),
            RimeKeyMapping.shiftMask | RimeKeyMapping.controlMask | RimeKeyMapping.altMask
        )
        XCTAssertEqual(
            RimeKeyMapping.modifierMask(shift: true, control: false, option: false, command: false, capsLock: false, isRelease: true),
            RimeKeyMapping.shiftMask | RimeKeyMapping.releaseMask
        )
    }

    // MARK: - UTF-8 → UTF-16 光标偏移

    func testUTF16OffsetConversion() {
        let text = "你好ab" // UTF-8: 你(3) 好(3) a(1) b(1)
        XCTAssertEqual(RimeKeyMapping.utf16Offset(fromUTF8Offset: 0, in: text), 0)
        XCTAssertEqual(RimeKeyMapping.utf16Offset(fromUTF8Offset: 3, in: text), 1)
        XCTAssertEqual(RimeKeyMapping.utf16Offset(fromUTF8Offset: 6, in: text), 2)
        XCTAssertEqual(RimeKeyMapping.utf16Offset(fromUTF8Offset: 7, in: text), 3)
        XCTAssertEqual(RimeKeyMapping.utf16Offset(fromUTF8Offset: 8, in: text), 4)
    }

    func testUTF16OffsetFallsBackToEndOnInvalidOffset() {
        let text = "你好"
        // 落在多字节字符中间 → 兜底末尾
        XCTAssertEqual(RimeKeyMapping.utf16Offset(fromUTF8Offset: 1, in: text), text.utf16.count)
        // 超出长度 → 兜底末尾
        XCTAssertEqual(RimeKeyMapping.utf16Offset(fromUTF8Offset: 99, in: text), text.utf16.count)
    }

    func testUTF16OffsetWithEmoji() {
        let text = "😀a" // 😀 UTF-8 4 字节 / UTF-16 2 个 code unit
        XCTAssertEqual(RimeKeyMapping.utf16Offset(fromUTF8Offset: 4, in: text), 2)
        XCTAssertEqual(RimeKeyMapping.utf16Offset(fromUTF8Offset: 5, in: text), 3)
    }
}
