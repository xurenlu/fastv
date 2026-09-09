//
//  SpeechTranscriptionModel.swift
//  fastv
//
//  Created for model caching - ONNX 模型单例复用
//

import Foundation

/// 语音转录模型缓存 Actor
/// 懒加载 ONNX 模型，复用已加载的实例，避免每次转录重新加载
actor SpeechTranscriptionModel {
    static let shared = SpeechTranscriptionModel()

    private var wrapper: ONNXRuntimeWrapper?
    private var loadedVariant: SpeechModelVariant?
    private var lastUseTime: Date?
    private var isInactivityMonitoringEnabled = false
    private var hasWarmedUp = false

    /// 进程内存超过该值时，即便模型仍在被频繁使用也卸载，优先保证系统不被拖垮。
    private static let memoryPressureThresholdMB: UInt64 = 4096

    /// 空闲多久后卸载模型。
    ///
    /// 旧实现对所有模型一律 5 分钟卸载，而 fp32 重新加载要 12~19 秒——用户「隔一会儿再说一句」
    /// 必然撞上冷加载，历史记录里 1~2 秒的短句识别耗时 6~8 秒基本都是这么来的。
    /// 加速版常驻内存约 250MB，对一个常驻菜单栏的语音输入工具是划算的，因此不再定时卸载；
    /// 历史 fp32 版本接近 1GB，仍保留一个长空闲阈值。
    private static func idleUnloadThreshold(for variant: SpeechModelVariant) -> TimeInterval? {
        switch variant {
        case .int8: return nil          // 常驻
        case .float32: return 1800      // 30 分钟
        }
    }

    private init() {}

    /// 检查模型文件是否存在（用于启动时决定是否预加载）
    static func hasModelFile() -> Bool {
        SpeechModelLocator.hasAnyModel()
    }

    /// 预加载模型（应用启动、快捷键按下时调用，首次语音输入即可直接使用）
    /// - Returns: true 表示已加载或已缓存，false 表示跳过（无模型文件）
    func preload() async -> Bool {
        guard SpeechModelLocator.resolvedModelURL() != nil else {
            return false
        }
        if wrapper != nil {
            warmUpIfNeeded()
            return true
        }
        do {
            _ = try getOrLoadWrapper()
            warmUpIfNeeded()
            return true
        } catch {
            print("⚠️ [SpeechTranscriptionModel] 预加载失败: \(error)")
            return false
        }
    }

    /// 当前加载的变体（未加载时为 nil），用于日志与设置页展示。
    func currentVariant() -> SpeechModelVariant? {
        loadedVariant
    }

    /// 获取或加载 ONNX 模型
    private func getOrLoadWrapper() throws -> ONNXRuntimeWrapper {
        if let w = wrapper {
            lastUseTime = Date()
            return w
        }
        guard let variant = SpeechModelLocator.resolvedVariant() else {
            let modelDir = SpeechModelLocator.modelDirectory()
            throw VideoProcessingError.modelLoadFailed(
                """
                模型文件未找到。

                请先在设置中下载语音识别模型。
                模型文件应位于：\(modelDir.path)

                注意：其他文件（tokens.json、config.yaml、am.mvn）已随应用提供，无需下载。
                """
            )
        }
        let path = SpeechModelLocator.fileURL(for: variant)
        let loadStart = CFAbsoluteTimeGetCurrent()
        let w = ONNXRuntimeWrapper()
        try w.loadModel(from: path.path)
        wrapper = w
        loadedVariant = variant
        hasWarmedUp = false
        lastUseTime = Date()
        print("🎤 [SpeechTranscriptionModel] 已加载 \(variant.rawValue) 模型，耗时 \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - loadStart)) 秒")

        // 只有会被定时卸载的变体才需要空闲监控；常驻变体不必每分钟醒来一次。
        if Self.idleUnloadThreshold(for: variant) != nil, !isInactivityMonitoringEnabled {
            isInactivityMonitoringEnabled = true
            Task.detached(priority: .utility) {
                await Self.monitorInactivity()
            }
        }

        return w
    }

    /// 空跑一次推理，把 ONNX Runtime 的惰性分配（内存 arena、线程池、算子 kernel）提前做掉。
    /// 本机实测：加载后第一次推理 203ms，之后稳定在 69ms，这 130ms 全在用户第一次说话时付。
    private func warmUpIfNeeded() {
        guard !hasWarmedUp, let w = wrapper else { return }
        hasWarmedUp = true
        let warmUpStart = CFAbsoluteTimeGetCurrent()
        // 约 2 秒语音对应的帧数（16kHz、10ms 帧移、LFR 降采样 6 倍）。
        let frames = 34
        let dimension = 560
        let silence: [[Float]] = Array(repeating: [Float](repeating: 0, count: dimension), count: frames)
        do {
            _ = try w.runInference(input: [silence], language: .auto, enableCTCDeduplication: false)
            print("🔥 [SpeechTranscriptionModel] 模型预热完成，耗时 \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - warmUpStart)) 秒")
        } catch {
            // 预热失败不影响正常识别，下一次真实推理会照常触发惰性分配。
            print("⚠️ [SpeechTranscriptionModel] 模型预热失败（不影响识别）: \(error)")
        }
    }

    /// 监控模型空闲时间，自动卸载
    private static func monitorInactivity() async {
        while true {
            try? await Task.sleep(nanoseconds: UInt64(60 * 1_000_000_000))  // 每分钟检查一次

            let shouldUnload = await shared.checkAndUnloadIfIdle()
            if shouldUnload {
                #if DEBUG
                print("🧹 [SpeechTranscriptionModel] 模型已因空闲自动卸载，释放内存")
                #endif
            }
        }
    }

    /// 检查并卸载空闲模型
    private func checkAndUnloadIfIdle() -> Bool {
        guard wrapper != nil,
              let lastUse = lastUseTime,
              let variant = loadedVariant else {
            return false
        }

        let idleTime = Date().timeIntervalSince(lastUse)
        let memoryUsedMB = Self.residentMemoryMB()
        let idleExceeded = Self.idleUnloadThreshold(for: variant).map { idleTime > $0 } ?? false

        if idleExceeded || memoryUsedMB > Self.memoryPressureThresholdMB {
            wrapper = nil
            loadedVariant = nil
            lastUseTime = nil
            hasWarmedUp = false
            return true
        }
        return false
    }

    /// 当前进程常驻内存（MB）。
    private static func residentMemoryMB() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size) / 1024 / 1024
    }

    /// 手动卸载模型（用于释放内存）
    func unloadModel() {
        wrapper = nil
        loadedVariant = nil
        lastUseTime = nil
        hasWarmedUp = false
        #if DEBUG
        print("🧹 [SpeechTranscriptionModel] 模型已手动卸载")
        #endif
    }

    /// 检查模型是否已加载
    func isModelLoaded() -> Bool {
        wrapper != nil
    }

    /// 运行推理，返回 token IDs
    /// - Parameters:
    ///   - features: 音频特征 [sequence_length, feature_dim]
    ///   - language: 语言类型
    ///   - enableCTCDeduplication: 是否启用 CTC 去重
    /// - Returns: token IDs
    func runInference(
        features: [[Float]],
        language: TranscriptLanguage,
        enableCTCDeduplication: Bool
    ) throws -> [Int] {
        let w = try getOrLoadWrapper()
        let inputFeatures: [[[Float]]] = [features]
        return try w.runInference(
            input: inputFeatures,
            language: language,
            enableCTCDeduplication: enableCTCDeduplication
        )
    }
}
