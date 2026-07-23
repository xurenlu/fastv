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

// MARK: - 候选窗外观

/// 候选排列方向
enum CandidateLayout: String, Codable, CaseIterable {
    case horizontal
    case vertical

    var displayNameKey: String {
        switch self {
        case .horizontal: return "ime.cand.layout.horizontal"
        case .vertical: return "ime.cand.layout.vertical"
        }
    }
}

/// RGBA 颜色（0~1），Codable 友好；避免依赖 AppKit/SwiftUI，两 target 与单测都能用
struct CandidateColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// 从 #RRGGBB / #RRGGBBAA 十六进制解析，失败返回 nil
    static func hex(_ string: String) -> CandidateColor? {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            return CandidateColor(
                Double((value >> 16) & 0xff) / 255,
                Double((value >> 8) & 0xff) / 255,
                Double(value & 0xff) / 255
            )
        }
        return CandidateColor(
            Double((value >> 24) & 0xff) / 255,
            Double((value >> 16) & 0xff) / 255,
            Double((value >> 8) & 0xff) / 255,
            Double(value & 0xff) / 255
        )
    }

    var hexString: String {
        let ri = Int((r * 255).rounded()), gi = Int((g * 255).rounded()), bi = Int((b * 255).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}

/// 一套配色（浅色或深色其一）
struct CandidatePalette: Codable, Equatable {
    var background: CandidateColor
    var text: CandidateColor
    var comment: CandidateColor        // 编码/拼音提示文字
    var label: CandidateColor          // 序号文字
    var highlightBackground: CandidateColor
    var highlightText: CandidateColor
    var border: CandidateColor

    static let light = CandidatePalette(
        background: CandidateColor(0.98, 0.98, 0.98),
        text: CandidateColor(0.11, 0.11, 0.12),
        comment: CandidateColor(0.55, 0.55, 0.58),
        label: CandidateColor(0.62, 0.62, 0.66),
        highlightBackground: CandidateColor(0.20, 0.52, 0.96),
        highlightText: CandidateColor(1, 1, 1),
        border: CandidateColor(0.82, 0.82, 0.85)
    )

    static let dark = CandidatePalette(
        background: CandidateColor(0.16, 0.16, 0.18),
        text: CandidateColor(0.94, 0.94, 0.96),
        comment: CandidateColor(0.60, 0.60, 0.64),
        label: CandidateColor(0.55, 0.55, 0.60),
        highlightBackground: CandidateColor(0.24, 0.55, 0.98),
        highlightText: CandidateColor(1, 1, 1),
        border: CandidateColor(0.30, 0.30, 0.34)
    )
}

/// 候选窗外观设置（自绘窗渲染依据）
struct CandidateAppearance: Codable, Equatable {
    var layout: CandidateLayout
    var fontName: String?              // nil = 系统字体
    var fontSize: Double               // 候选文字字号
    var labelFontSize: Double          // 序号/编码提示字号
    var cornerRadius: Double
    var itemSpacing: Double            // 候选之间间距
    var padding: Double                // 窗口内边距
    var showLabel: Bool                // 显示序号 1 2 3
    var showComment: Bool              // 显示编码/拼音提示
    var followSystemDarkMode: Bool     // 跟随系统深浅色
    var lightPalette: CandidatePalette
    var darkPalette: CandidatePalette

    static let `default` = CandidateAppearance(
        layout: .horizontal,
        fontName: nil,
        fontSize: 18,
        labelFontSize: 12,
        cornerRadius: 8,
        itemSpacing: 6,
        padding: 8,
        showLabel: true,
        showComment: true,
        followSystemDarkMode: true,
        lightPalette: .light,
        darkPalette: .dark
    )

    /// 字号/间距等钳制到合理范围，防止用户/损坏文件写入极端值
    func sanitized() -> CandidateAppearance {
        var a = self
        a.fontSize = min(max(fontSize, 12), 48)
        a.labelFontSize = min(max(labelFontSize, 8), 24)
        a.cornerRadius = min(max(cornerRadius, 0), 24)
        a.itemSpacing = min(max(itemSpacing, 0), 40)
        a.padding = min(max(padding, 2), 40)
        return a
    }
}

/// 候选窗预设皮肤：每套皮肤都是一整组现有可选项的取值，一键套用后仍可继续微调。
/// rawValue 用于稳定标识（不落盘，仅设置面板选中态判断），显示名走 i18n。
enum CandidatePreset: String, CaseIterable, Identifiable {
    case classicLight    // 经典浅色（= 默认）
    case night           // 夜幕
    case wechatGreen     // 清新绿
    case minimalMono     // 极简黑白
    case bigReading      // 大字护眼
    case verticalInk     // 竖排水墨

    var id: String { rawValue }

    var displayNameKey: String { "ime.cand.preset.\(rawValue)" }

    var appearance: CandidateAppearance {
        switch self {
        case .classicLight:
            return .default

        case .night:
            // 深色为主、强制不跟随系统（始终暗），科技蓝高亮
            var a = CandidateAppearance.default
            a.followSystemDarkMode = false
            a.cornerRadius = 10
            a.lightPalette = CandidatePalette(
                background: CandidateColor(0.16, 0.16, 0.18),
                text: CandidateColor(0.94, 0.94, 0.96),
                comment: CandidateColor(0.60, 0.60, 0.64),
                label: CandidateColor(0.55, 0.55, 0.60),
                highlightBackground: CandidateColor(0.24, 0.55, 0.98),
                highlightText: CandidateColor(1, 1, 1),
                border: CandidateColor(0.30, 0.30, 0.34)
            )
            a.darkPalette = a.lightPalette
            return a

        case .wechatGreen:
            var a = CandidateAppearance.default
            a.cornerRadius = 6
            a.lightPalette = CandidatePalette(
                background: CandidateColor(0.99, 0.99, 0.99),
                text: CandidateColor(0.13, 0.13, 0.14),
                comment: CandidateColor(0.58, 0.58, 0.60),
                label: CandidateColor(0.64, 0.64, 0.66),
                highlightBackground: CandidateColor(0.02, 0.76, 0.35),
                highlightText: CandidateColor(1, 1, 1),
                border: CandidateColor(0.86, 0.86, 0.88)
            )
            a.darkPalette = CandidatePalette(
                background: CandidateColor(0.15, 0.16, 0.15),
                text: CandidateColor(0.93, 0.94, 0.93),
                comment: CandidateColor(0.58, 0.60, 0.58),
                label: CandidateColor(0.52, 0.54, 0.52),
                highlightBackground: CandidateColor(0.05, 0.70, 0.35),
                highlightText: CandidateColor(1, 1, 1),
                border: CandidateColor(0.28, 0.30, 0.28)
            )
            return a

        case .minimalMono:
            // 极简黑白：无编码提示、直角、黑底白字高亮
            var a = CandidateAppearance.default
            a.showComment = false
            a.cornerRadius = 2
            a.itemSpacing = 4
            a.lightPalette = CandidatePalette(
                background: CandidateColor(1, 1, 1),
                text: CandidateColor(0.10, 0.10, 0.10),
                comment: CandidateColor(0.60, 0.60, 0.60),
                label: CandidateColor(0.70, 0.70, 0.70),
                highlightBackground: CandidateColor(0.12, 0.12, 0.12),
                highlightText: CandidateColor(1, 1, 1),
                border: CandidateColor(0.80, 0.80, 0.80)
            )
            a.darkPalette = CandidatePalette(
                background: CandidateColor(0.10, 0.10, 0.10),
                text: CandidateColor(0.95, 0.95, 0.95),
                comment: CandidateColor(0.55, 0.55, 0.55),
                label: CandidateColor(0.45, 0.45, 0.45),
                highlightBackground: CandidateColor(0.92, 0.92, 0.92),
                highlightText: CandidateColor(0.10, 0.10, 0.10),
                border: CandidateColor(0.30, 0.30, 0.30)
            )
            return a

        case .bigReading:
            // 大字护眼：大字号、暖白底、宽松间距
            var a = CandidateAppearance.default
            a.fontSize = 26
            a.labelFontSize = 16
            a.itemSpacing = 10
            a.padding = 12
            a.cornerRadius = 12
            a.lightPalette = CandidatePalette(
                background: CandidateColor(0.99, 0.97, 0.90),
                text: CandidateColor(0.18, 0.16, 0.12),
                comment: CandidateColor(0.55, 0.50, 0.42),
                label: CandidateColor(0.62, 0.57, 0.48),
                highlightBackground: CandidateColor(0.86, 0.55, 0.20),
                highlightText: CandidateColor(1, 1, 1),
                border: CandidateColor(0.82, 0.76, 0.62)
            )
            a.darkPalette = CandidatePalette(
                background: CandidateColor(0.14, 0.13, 0.11),
                text: CandidateColor(0.95, 0.92, 0.86),
                comment: CandidateColor(0.62, 0.58, 0.50),
                label: CandidateColor(0.52, 0.48, 0.42),
                highlightBackground: CandidateColor(0.86, 0.58, 0.24),
                highlightText: CandidateColor(1, 1, 1),
                border: CandidateColor(0.32, 0.30, 0.26)
            )
            return a

        case .verticalInk:
            // 竖排水墨：竖排、宋体（缺失回退系统）、米色纸感
            var a = CandidateAppearance.default
            a.layout = .vertical
            a.fontName = "Songti SC"
            a.fontSize = 20
            a.cornerRadius = 4
            a.itemSpacing = 4
            a.lightPalette = CandidatePalette(
                background: CandidateColor(0.96, 0.94, 0.87),
                text: CandidateColor(0.16, 0.14, 0.11),
                comment: CandidateColor(0.52, 0.46, 0.36),
                label: CandidateColor(0.60, 0.54, 0.44),
                highlightBackground: CandidateColor(0.42, 0.28, 0.20),
                highlightText: CandidateColor(0.98, 0.95, 0.88),
                border: CandidateColor(0.72, 0.64, 0.50)
            )
            a.darkPalette = CandidatePalette(
                background: CandidateColor(0.15, 0.14, 0.12),
                text: CandidateColor(0.92, 0.89, 0.82),
                comment: CandidateColor(0.60, 0.55, 0.46),
                label: CandidateColor(0.50, 0.46, 0.38),
                highlightBackground: CandidateColor(0.60, 0.42, 0.30),
                highlightText: CandidateColor(0.98, 0.95, 0.88),
                border: CandidateColor(0.34, 0.30, 0.24)
            )
            return a
        }
    }

    /// 判断某外观是否恰好等于本预设（用于设置面板高亮当前选中的预设）
    func matches(_ appearance: CandidateAppearance) -> Bool {
        self.appearance.sanitized() == appearance.sanitized()
    }
}

/// IME 设置（主 App 设置页与输入法菜单共同维护，JSON 落盘于 IME 用户数据目录）
struct IMESettings: Codable, Equatable {
    var version: Int
    var schemaId: String
    var enableUserDict: Bool
    /// 每页候选个数（5~9）；旧设置文件无此字段时解码为 nil，经 `pageSize` 计算属性回落默认
    var candidatePageSize: Int?
    /// 候选窗外观；旧设置文件无此字段时解码为 nil，经 `appearance` 计算属性回落默认值
    var candidateAppearance: CandidateAppearance?

    /// 候选个数允许范围
    static let pageSizeRange = 5...9
    static let defaultPageSize = 5

    static let `default` = IMESettings(
        version: InputMethodBridgeContract.protocolVersion,
        schemaId: IMESchema.mixed.rawValue,
        enableUserDict: true,
        candidatePageSize: defaultPageSize,
        candidateAppearance: .default
    )

    var schema: IMESchema {
        IMESchema(rawValue: schemaId) ?? .mixed
    }

    /// 候选个数读取入口：缺失或越界时钳制到 5~9
    var pageSize: Int {
        min(max(candidatePageSize ?? Self.defaultPageSize, Self.pageSizeRange.lowerBound),
            Self.pageSizeRange.upperBound)
    }

    /// 外观读取入口：缺失或损坏时回落默认并钳制，渲染侧只认这个
    var appearance: CandidateAppearance {
        (candidateAppearance ?? .default).sanitized()
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
    static func customYAML(for schema: IMESchema, enableUserDict: Bool, pageSize: Int) -> String {
        let clampedPage = min(max(pageSize, IMESettings.pageSizeRange.lowerBound),
                              IMESettings.pageSizeRange.upperBound)
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
        lines.append("  menu/page_size: \(clampedPage)")
        lines.append("  translator/enable_user_dict: \(enableUserDict)")
        return lines.joined(separator: "\n") + "\n"
    }

    /// 把当前设置展开为用户目录里的全部 custom 文件内容（文件名 → 内容）
    static func userCustomFiles(enableUserDict: Bool, pageSize: Int) -> [String: String] {
        var files: [String: String] = [:]
        for schema in IMESchema.allCases {
            files["\(schema.rawValue).custom.yaml"] =
                customYAML(for: schema, enableUserDict: enableUserDict, pageSize: pageSize)
        }
        return files
    }
}
