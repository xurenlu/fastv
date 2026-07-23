//
//  CandidateAppearanceTests.swift
//  fastvTests
//
//  候选窗外观模型的单元测试：颜色解析、钳制、编解码、旧设置文件兼容。
//

import XCTest
@testable import musetype

final class CandidateAppearanceTests: XCTestCase {

    // MARK: - CandidateColor

    func testHexParsing6Digits() {
        let c = CandidateColor.hex("#3B82F6")
        XCTAssertNotNil(c)
        XCTAssertEqual(c!.r, 0x3B / 255.0, accuracy: 0.001)
        XCTAssertEqual(c!.g, 0x82 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c!.b, 0xF6 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c!.a, 1.0, accuracy: 0.001)
    }

    func testHexParsing8DigitsWithAlpha() {
        // 8 位按 RRGGBBAA（CSS/Web 顺序）：末两位是 alpha
        let c = CandidateColor.hex("FF000080")
        XCTAssertNotNil(c)
        XCTAssertEqual(c!.r, 1.0, accuracy: 0.001)
        XCTAssertEqual(c!.g, 0.0, accuracy: 0.001)
        XCTAssertEqual(c!.b, 0.0, accuracy: 0.001)
        XCTAssertEqual(c!.a, 0x80 / 255.0, accuracy: 0.001)
    }

    func testHexParsingRejectsInvalid() {
        XCTAssertNil(CandidateColor.hex("#XYZ"))
        XCTAssertNil(CandidateColor.hex("12345"))
        XCTAssertNil(CandidateColor.hex(""))
    }

    func testHexStringRoundtrip() {
        let c = CandidateColor(0.2, 0.51, 0.96)
        let parsed = CandidateColor.hex(c.hexString)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed!.r, c.r, accuracy: 0.01)
        XCTAssertEqual(parsed!.g, c.g, accuracy: 0.01)
        XCTAssertEqual(parsed!.b, c.b, accuracy: 0.01)
    }

    // MARK: - sanitize 钳制

    func testSanitizeClampsExtremeValues() {
        var a = CandidateAppearance.default
        a.fontSize = 999
        a.labelFontSize = 1
        a.cornerRadius = -5
        a.itemSpacing = 500
        a.padding = 0
        let s = a.sanitized()
        XCTAssertEqual(s.fontSize, 48)
        XCTAssertEqual(s.labelFontSize, 8)
        XCTAssertEqual(s.cornerRadius, 0)
        XCTAssertEqual(s.itemSpacing, 40)
        XCTAssertEqual(s.padding, 2)
    }

    func testSanitizeKeepsValidValues() {
        var a = CandidateAppearance.default
        a.fontSize = 20
        XCTAssertEqual(a.sanitized().fontSize, 20)
    }

    // MARK: - 编解码

    func testAppearanceCodableRoundtrip() throws {
        var a = CandidateAppearance.default
        a.layout = .vertical
        a.fontName = "PingFang SC"
        a.fontSize = 22
        a.lightPalette.background = CandidateColor(0.9, 0.9, 0.9)
        let data = try JSONEncoder().encode(a)
        let decoded = try JSONDecoder().decode(CandidateAppearance.self, from: data)
        XCTAssertEqual(decoded, a)
        XCTAssertEqual(decoded.layout, .vertical)
        XCTAssertEqual(decoded.fontName, "PingFang SC")
    }

    // MARK: - 旧设置文件兼容（无 candidateAppearance 字段）

    func testOldSettingsWithoutAppearanceDecodes() throws {
        let oldJSON = """
        { "version": 1, "schemaId": "wubi_pinyin", "enableUserDict": true }
        """
        let data = Data(oldJSON.utf8)
        let settings = try JSONDecoder().decode(IMESettings.self, from: data)
        XCTAssertNil(settings.candidateAppearance)
        // appearance 计算属性回落默认值，渲染侧不受影响
        XCTAssertEqual(settings.appearance, CandidateAppearance.default)
        XCTAssertEqual(settings.appearance.layout, .horizontal)
    }

    func testSettingsWithAppearanceRoundtrip() throws {
        var settings = IMESettings.default
        var a = CandidateAppearance.default
        a.layout = .vertical
        settings.candidateAppearance = a
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(IMESettings.self, from: data)
        XCTAssertEqual(decoded.appearance.layout, .vertical)
    }

    // MARK: - 预设配色区分明暗

    func testLightAndDarkPalettesDiffer() {
        XCTAssertNotEqual(CandidatePalette.light.background, CandidatePalette.dark.background)
        XCTAssertNotEqual(CandidatePalette.light.text, CandidatePalette.dark.text)
    }

    func testDefaultLayoutIsHorizontal() {
        XCTAssertEqual(CandidateAppearance.default.layout, .horizontal)
        XCTAssertTrue(CandidateAppearance.default.followSystemDarkMode)
    }
}
