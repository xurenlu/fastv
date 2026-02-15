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
    
    private init() {}
    
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
        return w
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
