//
//  SpeechModelVariant.swift
//  fastv
//
//  语音识别模型变体目录。
//
//  轻语原本只分发 SenseVoice-small 的 fp32 导出（937MB）。本机实测该模型在
//  「8 线程 + 自旋」下 2 秒语音要 219ms、6 秒语音 479ms，机器一忙会退化到数秒；
//  官方 int8 量化导出（iic/SenseVoiceSmall-onnx 的 model_quant.onnx，241MB）在
//  15 句中文测试集上与 fp32 逐字一致，速度约为其两倍，体积只有四分之一。
//
//  因此 int8 成为默认分发版本，fp32 作为历史版本继续被识别，老用户不必重新下载。
//

import Foundation

/// 语音识别模型变体。
///
/// 工程默认 actor 隔离是 MainActor，而模型路径要在 `SpeechTranscriptionModel` 这个 actor 内部
/// 和后台任务里同步取用，因此显式标 `nonisolated`——这里只有纯常量与文件系统查询，没有共享状态。
nonisolated enum SpeechModelVariant: String, CaseIterable, Sendable {
    /// 官方 int8 量化版（默认分发）。
    case int8
    /// 历史 fp32 版本，2.5.0-rc6 之前分发的版本。
    case float32

    /// 落盘文件名。两个变体并存，互不覆盖。
    var fileName: String {
        switch self {
        case .int8: return "model.int8.onnx"
        case .float32: return "model.onnx"
        }
    }

    /// 精确文件字节数，用于下载完整性校验。
    var expectedByteSize: Int64 {
        switch self {
        case .int8: return 241_216_270
        case .float32: return 937_615_562
        }
    }

    /// 官方下载地址。
    var officialDownloadURL: String {
        switch self {
        case .int8: return "https://img.niuwoai.com/models/sensevoice-small/model.int8.onnx"
        case .float32: return "https://img.niuwoai.com/models/sensevoice-small/model.onnx"
        }
    }

    /// 供界面展示的体积（MB，四舍五入）。
    var approximateMegabytes: Int {
        Int((Double(expectedByteSize) / (1024 * 1024)).rounded())
    }

    /// 供界面展示的名称。
    var displayName: String {
        switch self {
        case .int8: return NSLocalizedString("model.variant.int8", comment: "加速版（int8）")
        case .float32: return NSLocalizedString("model.variant.float32", comment: "标准版（fp32）")
        }
    }

    /// 历史版本里出现过的默认下载地址。用户没有改过下载地址时，这些值会被迁移到当前默认值。
    static let legacyDefaultDownloadURLs: Set<String> = [
        "https://cdn.wxside.com/upload/202511/1763737361-dTESP.onnx"
    ]

    /// 当前默认分发的变体。
    static let preferred: SpeechModelVariant = .int8

    /// 加载时的选取顺序：优先加速版，没有才回退历史版本。
    static let resolutionOrder: [SpeechModelVariant] = [.int8, .float32]
}

/// 语音识别模型文件定位器。
///
/// `SpeechTranscriber`、`SpeechTranscriptionModel`、`ModelDownloader` 三处原本各自拼一遍
/// 模型路径，改动时极易漏改；统一收口到这里。
nonisolated enum SpeechModelLocator {

    /// 模型目录：`~/Library/Application Support/<应用名>/Models/sensevoice-small`。
    static func modelDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent(NSLocalizedString("app.name", comment: ""))
        return appDir.appendingPathComponent("Models/sensevoice-small")
    }

    /// 指定变体的落盘路径（不判断是否存在）。
    static func fileURL(for variant: SpeechModelVariant) -> URL {
        modelDirectory().appendingPathComponent(variant.fileName)
    }

    /// 该变体是否已经装好。
    static func isInstalled(_ variant: SpeechModelVariant) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: variant).path)
    }

    /// 已安装的变体，按选取顺序排列。
    static func installedVariants() -> [SpeechModelVariant] {
        SpeechModelVariant.resolutionOrder.filter { isInstalled($0) }
    }

    /// 实际会被加载的变体。
    static func resolvedVariant() -> SpeechModelVariant? {
        installedVariants().first
    }

    /// 实际会被加载的模型文件；一个都没装时返回 nil。
    static func resolvedModelURL() -> URL? {
        resolvedVariant().map { fileURL(for: $0) }
    }

    /// 是否装了任意可用模型。
    static func hasAnyModel() -> Bool {
        resolvedVariant() != nil
    }

    /// 是否可以升级到加速版：装了历史版本但没装加速版。
    static func canUpgradeToPreferred() -> Bool {
        !isInstalled(.preferred) && !installedVariants().isEmpty
    }

    /// 文件字节数与该变体的期望值是否一致（允许 1KB 误差，规避文件系统差异）。
    static func matchesExpectedSize(_ variant: SpeechModelVariant, byteSize: Int64) -> Bool {
        abs(byteSize - variant.expectedByteSize) <= 1024
    }

    /// 把历史默认下载地址迁移到当前默认地址；用户自己改过的地址保持不动。
    /// - Returns: 迁移后的地址。
    static func migratedDownloadURL(from stored: String?) -> String {
        guard let stored, !stored.isEmpty else {
            return SpeechModelVariant.preferred.officialDownloadURL
        }
        if SpeechModelVariant.legacyDefaultDownloadURLs.contains(stored) {
            return SpeechModelVariant.preferred.officialDownloadURL
        }
        return stored
    }

    /// 从下载地址推断目标变体：地址指向哪个变体的官方文件就下哪个，
    /// 认不出来（用户自定义地址）时按当前默认变体处理。
    static func variant(forDownloadURL url: String) -> SpeechModelVariant {
        for variant in SpeechModelVariant.allCases where url == variant.officialDownloadURL {
            return variant
        }
        if url.contains(SpeechModelVariant.float32.fileName) && !url.contains(SpeechModelVariant.int8.fileName) {
            return .float32
        }
        if SpeechModelVariant.legacyDefaultDownloadURLs.contains(url) {
            return .float32
        }
        return .preferred
    }
}
