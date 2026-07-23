//
//  InputMethodBridgeContract.swift
//  fastv
//
//  主 App（轻语）与 QEchoIME 输入法进程之间的桥接契约。
//  本文件同时编译进 musetype 与 QEchoIME 两个 target，修改字段时同步递增 protocolVersion。
//

import Foundation

enum InputMethodBridgeContract {
    /// 输入法 app 的 bundle id（安装到 ~/Library/Input Methods 的产物）
    static let inputMethodBundleID = "com.17push.inputmethod.QEchoIME"

    /// TIS 输入源 ID，与 QEchoIME/Info.plist 的 TISInputSourceID 保持一致
    static let inputSourceID = "com.17push.inputmethod.QEchoIME"

    /// 语音上屏 CFMessagePort 端口名（IME 进程作为服务端监听）
    static let voiceCommitPortName = "com.17push.musetype.ime.voice-commit"

    /// 桥接协议版本；载荷字段变化时递增
    static let protocolVersion = 1

    /// 判断某个 TIS 输入源 ID 是否属于轻语输入法。
    /// 未来接入 librime 后可能出现 `<inputSourceID>.<mode>` 形式的输入模式子 ID。
    static func isQEchoInputSource(id: String) -> Bool {
        id == inputSourceID || id.hasPrefix(inputSourceID + ".")
    }
}

/// 语音上屏请求载荷
struct VoiceCommitPayload: Codable, Equatable {
    let version: Int
    let text: String

    init(text: String) {
        self.version = InputMethodBridgeContract.protocolVersion
        self.text = text
    }

    enum PayloadError: Error, Equatable {
        case unsupportedVersion(Int)
        case emptyText
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> VoiceCommitPayload {
        let payload = try JSONDecoder().decode(VoiceCommitPayload.self, from: data)
        guard payload.version <= InputMethodBridgeContract.protocolVersion else {
            throw PayloadError.unsupportedVersion(payload.version)
        }
        guard !payload.text.isEmpty else {
            throw PayloadError.emptyText
        }
        return payload
    }
}

/// 语音上屏回执。reason 只允许携带错误类别，不得携带用户文本。
struct VoiceCommitReply: Codable, Equatable {
    let ok: Bool
    let reason: String?

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> VoiceCommitReply {
        try JSONDecoder().decode(VoiceCommitReply.self, from: data)
    }
}
