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

    /// 主 App（轻语）的 bundle id，输入法菜单「打开轻语设置」用
    static let mainAppBundleID = "com.17push.musetype"

    /// TIS 输入源 ID，与 QEchoIME/Info.plist 的 TISInputSourceID 保持一致
    static let inputSourceID = "com.17push.inputmethod.QEchoIME"

    /// 语音上屏 CFMessagePort 端口名（IME 进程作为服务端监听）
    static let voiceCommitPortName = "com.17push.musetype.ime.voice-commit"

    /// CFMessagePort 消息类型：语音上屏（载荷 VoiceCommitPayload）
    static let voiceCommitMessageID: Int32 = 1
    /// CFMessagePort 消息类型：设置变更通知（无载荷，IME 收到后重读设置文件）
    static let settingsChangedMessageID: Int32 = 2

    /// 桥接协议版本；载荷字段变化时递增（消息类型新增不递增，保持升级窗口内新旧互通）
    static let protocolVersion = 1

    /// IME 设置文件名（位于 IME 用户数据目录，主 App 写、IME 读；输入法菜单切方案时 IME 也回写）
    static let settingsFileName = "qecho-ime-settings.json"

    /// 主 App 打开设置窗口的分布式通知名（输入法菜单「轻语设置…」触发；不携带任何用户数据）
    static let openSettingsDistributedNotification = "com.17push.musetype.ime.open-settings"

    /// IME 用户数据目录：~/Library/Application Support/QEchoIME/
    /// 与 RimeEngine 的 user_data_dir 保持一致；主 App 与 IME 进程都按此路径读写。
    static func imeUserDataDirectory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QEchoIME", isDirectory: true)
    }

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

/// 输入方案（rawValue 即 Rime schema_id，与 RimeData 随包方案一一对应）
enum IMESchema: String, Codable, CaseIterable {
    case mixed = "wubi_pinyin"
    case wubi = "wubi86"
    case pinyin = "pinyin_simp"

    /// 设置页 / 输入法菜单显示名的 i18n key
    var displayNameKey: String {
        switch self {
        case .mixed: return "ime.scheme.mixed"
        case .wubi: return "ime.scheme.wubi"
        case .pinyin: return "ime.scheme.pinyin"
        }
    }
}

/// IME 设置（主 App 设置页与输入法菜单共同维护，JSON 落盘于 IME 用户数据目录）
struct IMESettings: Codable, Equatable {
    var version: Int
    var schemaId: String
    var enableUserDict: Bool

    static let `default` = IMESettings(
        version: InputMethodBridgeContract.protocolVersion,
        schemaId: IMESchema.mixed.rawValue,
        enableUserDict: true
    )

    var schema: IMESchema {
        IMESchema(rawValue: schemaId) ?? .mixed
    }

    static func settingsFileURL() -> URL {
        InputMethodBridgeContract.imeUserDataDirectory()
            .appendingPathComponent(InputMethodBridgeContract.settingsFileName)
    }

    /// 读取失败（文件不存在 / 解析失败）时返回默认值，保证两侧行为一致
    static func load() -> IMESettings {
        guard let data = try? Data(contentsOf: settingsFileURL()),
              let settings = try? JSONDecoder().decode(IMESettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func write() throws {
        let directory = InputMethodBridgeContract.imeUserDataDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.settingsFileURL(), options: .atomic)
    }
}

/// 生成各方案的 Rime custom 补丁。
/// 输出必须与 QEchoIME/RimeData 随包的 *.custom.yaml 默认内容保持同构：
/// 随包文件覆盖「默认设置」场景，用户改设置后主 App 用本生成器写用户目录同名文件（优先级更高）。
enum RimePatchGenerator {
    static func customYAML(for schema: IMESchema, enableUserDict: Bool) -> String {
        var lines: [String] = [
            "# 由轻语输入法自动生成，请勿手改；设置请在 QEcho（轻语）App 中调整。",
            "patch:",
        ]
        switch schema {
        case .mixed:
            lines.append("  speller/delimiter: \" '\"")
            lines.append("  key_binder/bindings/+:")
            lines.append("    - { when: has_menu, accept: semicolon, send: 2 }")
        case .wubi:
            lines.append("  speller/delimiter: \" \"")
            lines.append("  key_binder/bindings/+:")
            lines.append("    - { when: has_menu, accept: semicolon, send: 2 }")
            lines.append("    - { when: has_menu, accept: apostrophe, send: 3 }")
        case .pinyin:
            lines.append("  key_binder/bindings/+:")
            lines.append("    - { when: has_menu, accept: semicolon, send: 2 }")
        }
        lines.append("  translator/enable_user_dict: \(enableUserDict)")
        return lines.joined(separator: "\n") + "\n"
    }

    /// 把当前设置展开为用户目录里的全部 custom 文件内容（文件名 → 内容）
    static func userCustomFiles(enableUserDict: Bool) -> [String: String] {
        var files: [String: String] = [:]
        for schema in IMESchema.allCases {
            files["\(schema.rawValue).custom.yaml"] = customYAML(for: schema, enableUserDict: enableUserDict)
        }
        return files
    }
}
