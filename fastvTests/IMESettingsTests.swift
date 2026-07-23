//
//  IMESettingsTests.swift
//  fastvTests
//
//  IME 设置模型与 Rime custom 补丁生成器的单元测试。
//

import XCTest
@testable import musetype

final class IMESettingsTests: XCTestCase {

    // MARK: - IMESettings

    func testDefaultSettings() {
        let settings = IMESettings.default
        XCTAssertEqual(settings.schema, .mixed)
        XCTAssertTrue(settings.enableUserDict)
        XCTAssertEqual(settings.version, InputMethodBridgeContract.protocolVersion)
    }

    func testSettingsCodableRoundtrip() throws {
        var settings = IMESettings.default
        settings.schemaId = IMESchema.wubi.rawValue
        settings.enableUserDict = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(IMESettings.self, from: data)
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.schema, .wubi)
    }

    func testUnknownSchemaIdFallsBackToMixed() {
        var settings = IMESettings.default
        settings.schemaId = "not_a_schema"
        XCTAssertEqual(settings.schema, .mixed)
    }

    func testSchemaRawValuesMatchRimeSchemaIds() {
        XCTAssertEqual(IMESchema.mixed.rawValue, "wubi_pinyin")
        XCTAssertEqual(IMESchema.wubi.rawValue, "wubi86")
        XCTAssertEqual(IMESchema.pinyin.rawValue, "pinyin_simp")
    }

    // MARK: - RimePatchGenerator

    func testMixedPatchRemovesSemicolonFromDelimiterAndBindsSecondCandidate() {
        let yaml = RimePatchGenerator.customYAML(for: .mixed, enableUserDict: true)
        XCTAssertTrue(yaml.contains("speller/delimiter: \" '\""))
        XCTAssertTrue(yaml.contains("accept: semicolon, send: 2"))
        XCTAssertFalse(yaml.contains("apostrophe"), "混打方案引号要留给拼音音节分隔")
        XCTAssertTrue(yaml.contains("translator/enable_user_dict: true"))
    }

    func testWubiPatchBindsSecondAndThirdCandidate() {
        let yaml = RimePatchGenerator.customYAML(for: .wubi, enableUserDict: true)
        XCTAssertTrue(yaml.contains("speller/delimiter: \" \""))
        XCTAssertTrue(yaml.contains("accept: semicolon, send: 2"))
        XCTAssertTrue(yaml.contains("accept: apostrophe, send: 3"))
    }

    func testPinyinPatchKeepsApostropheAsSyllableDivider() {
        let yaml = RimePatchGenerator.customYAML(for: .pinyin, enableUserDict: true)
        XCTAssertFalse(yaml.contains("speller/delimiter"), "纯拼音不覆盖 delimiter，保留 ' 分隔音节")
        XCTAssertTrue(yaml.contains("accept: semicolon, send: 2"))
        XCTAssertFalse(yaml.contains("apostrophe"))
    }

    func testUserDictDisabledIsWrittenToAllSchemas() {
        let files = RimePatchGenerator.userCustomFiles(enableUserDict: false)
        XCTAssertEqual(Set(files.keys), Set([
            "wubi_pinyin.custom.yaml",
            "wubi86.custom.yaml",
            "pinyin_simp.custom.yaml",
        ]))
        for (name, content) in files {
            XCTAssertTrue(
                content.contains("translator/enable_user_dict: false"),
                "\(name) 应包含关闭用户词典的补丁"
            )
        }
    }

    /// 随包 RimeData 里的默认 custom 文件必须与生成器输出一致（默认设置 = enableUserDict true），
    /// 否则「随包默认」与「用户目录覆盖」两套文件会漂移。
    func testShippedCustomFilesMatchGeneratorDefaults() throws {
        let repoRimeData = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // fastvTests/
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("QEchoIME/RimeData")
        for (fileName, generated) in RimePatchGenerator.userCustomFiles(enableUserDict: true) {
            let shippedURL = repoRimeData.appendingPathComponent(fileName)
            let shipped = try String(contentsOf: shippedURL, encoding: .utf8)
            // 随包文件允许多带注释行，逐行比对非注释内容
            let strip: (String) -> [String] = { text in
                text.split(separator: "\n")
                    .map(String.init)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
            XCTAssertEqual(strip(shipped), strip(generated), "\(fileName) 随包内容与生成器输出漂移")
        }
    }
}
