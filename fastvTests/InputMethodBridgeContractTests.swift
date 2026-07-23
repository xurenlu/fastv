//
//  InputMethodBridgeContractTests.swift
//  fastvTests
//
//  主 App 与 QEchoIME 输入法之间桥接契约的单元测试：
//  载荷编解码、版本兼容、输入源 ID 判定。
//

import XCTest
@testable import musetype

final class InputMethodBridgeContractTests: XCTestCase {

    // MARK: - VoiceCommitPayload

    func testPayloadRoundTrip() throws {
        let payload = VoiceCommitPayload(text: "你好，轻语输入法")
        let data = try payload.encoded()
        let decoded = try VoiceCommitPayload.decode(data)
        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.version, InputMethodBridgeContract.protocolVersion)
        XCTAssertEqual(decoded.text, "你好，轻语输入法")
    }

    func testPayloadDecodeRejectsNewerVersion() throws {
        let newerVersion = InputMethodBridgeContract.protocolVersion + 1
        let json: [String: Any] = ["version": newerVersion, "text": "hi"]
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try VoiceCommitPayload.decode(data)) { error in
            XCTAssertEqual(
                error as? VoiceCommitPayload.PayloadError,
                .unsupportedVersion(newerVersion)
            )
        }
    }

    func testPayloadDecodeRejectsEmptyText() throws {
        let json: [String: Any] = ["version": InputMethodBridgeContract.protocolVersion, "text": ""]
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try VoiceCommitPayload.decode(data)) { error in
            XCTAssertEqual(error as? VoiceCommitPayload.PayloadError, .emptyText)
        }
    }

    func testPayloadDecodeRejectsGarbage() {
        XCTAssertThrowsError(try VoiceCommitPayload.decode(Data("not-json".utf8)))
    }

    // MARK: - VoiceCommitReply

    func testReplyRoundTrip() throws {
        let okReply = VoiceCommitReply(ok: true, reason: nil)
        XCTAssertEqual(try VoiceCommitReply.decode(okReply.encoded()), okReply)

        let failReply = VoiceCommitReply(ok: false, reason: "no-active-client")
        XCTAssertEqual(try VoiceCommitReply.decode(failReply.encoded()), failReply)
    }

    // MARK: - 输入源 ID 判定

    func testInputSourceIDMatching() {
        XCTAssertTrue(InputMethodBridgeContract.isQEchoInputSource(id: "com.17push.inputmethod.QEchoIME"))
        // 未来 librime 接入后的输入模式子 ID 也应命中
        XCTAssertTrue(InputMethodBridgeContract.isQEchoInputSource(id: "com.17push.inputmethod.QEchoIME.pinyin"))
        XCTAssertFalse(InputMethodBridgeContract.isQEchoInputSource(id: "com.apple.keylayout.ABC"))
        XCTAssertFalse(InputMethodBridgeContract.isQEchoInputSource(id: "com.apple.inputmethod.SCIM.ITABC"))
        // 前缀相似但不是子 ID 的不能误命中
        XCTAssertFalse(InputMethodBridgeContract.isQEchoInputSource(id: "com.17push.inputmethod.QEchoIMEX"))
    }
}
