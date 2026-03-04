//
//  SpeechTranscriptionModel.swift
//  fastv
//
//  Created for model caching - ONNX 模型单例复用
//

import Foundation

/// 语音转录模型缓存 Actor
/// 懒加载 ONNX 模型，复用已加载的实例，避免每次转录重新加载（约 1-5 秒）
actor SpeechTranscriptionModel {
    static let shared = SpeechTranscriptionModel()

    private var wrapper: ONNXRuntimeWrapper?
    private var lastUseTime: Date?
    private var isInactivityMonitoringEnabled = false
    private var monitoringTask: Task<Void, Never>?  // 添加任务引用，用于取消

    // 空闲后自动卸载模型的时间阈值（秒）
    private static let inactivityThreshold: TimeInterval = 300  // 5分钟

    private init() {}

    /// 停止监控（用于清理资源）
    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        isInactivityMonitoringEnabled = false
        #if DEBUG
        print("🛑 [SpeechTranscriptionModel] 监控已停止")
        #endif
    }

    /// 获取模型路径（与 SpeechTranscriber 逻辑一致）
    private static func getModelPath() -> URL? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent(NSLocalizedString("app.name", comment: ""))
        let downloadedPath = appDir.appendingPathComponent("Models/sensevoice-small/model.onnx")
        if FileManager.default.fileExists(atPath: downloadedPath.path) {
            return downloadedPath
        }
        return nil
    }

    /// 检查模型文件是否存在（用于启动时决定是否预加载）
    static func hasModelFile() -> Bool {
        getModelPath() != nil
    }

    /// 预加载模型（应用启动时调用，首次语音输入时即可直接使用）
    /// - Returns: true 表示已加载或已缓存，false 表示跳过（无模型文件）
    func preload() async -> Bool {
        if wrapper != nil {
            return true
        }
        guard Self.getModelPath() != nil else {
            return false
        }
        do {
            _ = try getOrLoadWrapper()
            return true
        } catch {
            print("⚠️ [SpeechTranscriptionModel] 预加载失败: \(error)")
            return false
        }
    }

    /// 获取或加载 ONNX 模型
    private func getOrLoadWrapper() throws -> ONNXRuntimeWrapper {
        if let w = wrapper {
            lastUseTime = Date()
            return w
        }
        guard let path = Self.getModelPath() else {
            let modelDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent(NSLocalizedString("app.name", comment: ""))
                .appendingPathComponent("Models/sensevoice-small")
            throw VideoProcessingError.modelLoadFailed(
                """
                模型文件未找到。

                请先在设置中下载 model.onnx 文件。
                模型文件应位于：\(modelDir.path)

                注意：其他文件（tokens.json、config.yaml、am.mvn）已随应用提供，无需下载。
                """
            )
        }
        #if DEBUG
        print("🎤 [SpeechTranscriptionModel] 首次加载模型: \(path.path)")
        #endif
        let w = ONNXRuntimeWrapper()
        try w.loadModel(from: path.path)
        wrapper = w
        lastUseTime = Date()

        // 启动空闲监控（仅当用户开启「动态清理内存」时）
        if !isInactivityMonitoringEnabled {
            isInactivityMonitoringEnabled = true
            // 保存任务引用以便后续取消
            // 注意：Task.detached 不支持 [weak self]，我们通过 shared 实例访问
            let task = Task.detached(priority: .utility) {
                await Self.monitorInactivity()
            }
            monitoringTask = task
        }

        return w
    }

    /// 监控模型空闲时间，自动卸载（仅当 enableAutoUnloadSpeechModel 为 true 时执行）
    private static func monitorInactivity() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(60 * 1_000_000_000))
            } catch {
                #if DEBUG
                print("🛑 [SpeechTranscriptionModel] 监控任务睡眠被中断，退出监控")
                #endif
                return
            }

            // 模型未加载时跳过检查，节省 MainActor 调度开销
            let isLoaded = await shared.isModelLoaded()
            guard isLoaded else { continue }

            let enabled = await MainActor.run { UserPreferences.shared.enableAutoUnloadSpeechModel }
            guard enabled else { continue }

            let shouldUnload = await shared.checkAndUnloadIfIdle()
            if shouldUnload {
                #if DEBUG
                print("🧹 [SpeechTranscriptionModel] 模型已因空闲自动卸载，释放内存")
                #endif
            }
        }
        #if DEBUG
        print("🛑 [SpeechTranscriptionModel] 监控循环已退出")
        #endif
    }

    /// 检查并卸载空闲模型
    private func checkAndUnloadIfIdle() -> Bool {
        guard wrapper != nil,
              let lastUse = lastUseTime else {
            return false
        }

        let idleTime = Date().timeIntervalSince(lastUse)

        // 检查内存压力
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        // task_info 失败时仅按空闲时间判断，不依赖可能无效的内存数据
        guard result == KERN_SUCCESS else {
            if idleTime > Self.inactivityThreshold {
                self.wrapper = nil
                self.lastUseTime = nil
                return true
            }
            return false
        }

        let memoryUsedMB = UInt64(info.resident_size) / 1024 / 1024

        let shouldUnload = idleTime > Self.inactivityThreshold || memoryUsedMB > 4096
        let isMemoryPressureHigh = memoryUsedMB > 2048

        if shouldUnload || (isMemoryPressureHigh && idleTime > 60) {
            #if DEBUG
            print("💾 [SpeechTranscriptionModel] 内存检查: 已用 \(memoryUsedMB)MB, 空闲 \(Int(idleTime))s")
            print("🧹 [SpeechTranscriptionModel] 卸载模型以释放内存")
            #endif
            self.wrapper = nil
            self.lastUseTime = nil
            return true
        }

        return false
    }

    /// 手动卸载模型（用于释放内存）
    func unloadModel() {
        wrapper = nil
        lastUseTime = nil
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
        let result = try w.runInference(
            input: inputFeatures,
            language: language,
            enableCTCDeduplication: enableCTCDeduplication
        )

        return result
    }
}
