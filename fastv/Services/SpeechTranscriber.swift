//
//  SpeechTranscriber.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AVFoundation

struct SpeechTranscriber {
    // 获取模型目录（优先使用下载的模型）
    private static func getModelDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent(NSLocalizedString("app.name", comment: ""))
        return appDir.appendingPathComponent("Models/sensevoice-small")
    }
    
    // model.onnx 文件使用下载的版本（不包含在 Bundle 中）
    private static var modelPath: URL? {
        let downloadedPath = getModelDirectory().appendingPathComponent("model.onnx")
        if FileManager.default.fileExists(atPath: downloadedPath.path) {
            return downloadedPath
        }
        // 如果不存在，返回 nil（不再回退到 Bundle）
        return nil
    }
    
    // tokens.json 文件从 Bundle 中读取（随 app 提供）
    private static var tokensPath: URL? {
        // 首先尝试在子目录中查找
        if let url = Bundle.main.url(forResource: "tokens", withExtension: "json", subdirectory: "Models/sensevoice-small") {
            return url
        }
        // 如果不在子目录，尝试在 Resources 根目录查找
        return Bundle.main.url(forResource: "tokens", withExtension: "json")
    }
    
    // config.yaml 文件从 Bundle 中读取（随 app 提供）
    private static var configPath: URL? {
        // 首先尝试在子目录中查找
        if let url = Bundle.main.url(forResource: "config", withExtension: "yaml", subdirectory: "Models/sensevoice-small") {
            return url
        }
        // 如果不在子目录，尝试在 Resources 根目录查找
        return Bundle.main.url(forResource: "config", withExtension: "yaml")
    }
    
    // 缓存 token 映射
    private static var tokenMap: [Int: String]?
    
    // am.mvn 文件从 Bundle 中读取（随 app 提供）
    private static func resolveCMVNURL() -> URL? {
        // 方式1: 使用子目录
        if let url = Bundle.main.url(forResource: "am", withExtension: "mvn", subdirectory: "Models/sensevoice-small") {
            return url
        }
        // 方式2: 根目录
        if let url = Bundle.main.url(forResource: "am", withExtension: "mvn") {
            return url
        }
        // 方式3: 手动拼路径
        if let resourcePath = Bundle.main.resourcePath {
            let sensevoicePath = (resourcePath as NSString).appendingPathComponent("Models/sensevoice-small/am.mvn")
            if FileManager.default.fileExists(atPath: sensevoicePath) {
                return URL(fileURLWithPath: sensevoicePath)
            }
            let fallbackPath = (resourcePath as NSString).appendingPathComponent("am.mvn")
            if FileManager.default.fileExists(atPath: fallbackPath) {
                return URL(fileURLWithPath: fallbackPath)
            }
        }
        #if DEBUG
        print("警告：未找到 am.mvn 文件，特征可能未归一化")
        #endif
        return nil
    }
    
    /// 从内存录音转文字（用于语音输入）
    static func transcribe(recording: VoiceRecording, language: TranscriptLanguage = .auto, enableCTCDeduplication: Bool? = nil) async throws -> String {
        guard recording.channelCount == 1 else {
            throw VideoProcessingError.transcriptionFailed("仅支持单声道录音")
        }
        guard abs(recording.sampleRate - 16000) < 1 else {
            throw VideoProcessingError.transcriptionFailed("录音采样率需为16kHz")
        }
        
        // 获取 CTC 去重设置（如果未指定，从用户偏好设置中获取）
        let ctcDedup: Bool
        if let enableCTCDeduplication = enableCTCDeduplication {
            ctcDedup = enableCTCDeduplication
        } else {
            ctcDedup = await MainActor.run { UserPreferences.shared.enableCTCDeduplication }
        }
        
        let cmvnURL = resolveCMVNURL()
        let features = try await AudioFeatureExtractor.extractMelFeatures(from: recording, cmvnURL: cmvnURL)
        let transcript = try await performTranscription(features: features, language: language, enableCTCDeduplication: ctcDedup)
        return transcript
    }
    
    /// 从音频文件转文字
    /// - Parameters:
    ///   - audioURL: 音频文件 URL
    ///   - language: 语言类型，默认为自动检测
    ///   - enableCTCDeduplication: 是否启用 CTC 去重，nil 则使用用户设置
    /// - Returns: 转录的文本
    static func transcribe(audioURL: URL, language: TranscriptLanguage = .auto, enableCTCDeduplication: Bool? = nil) async throws -> String {
        // 1. 预处理音频：转换为 16kHz 单声道 WAV
        let processedAudioURL = try await preprocessAudio(audioURL: audioURL)
        defer {
            // 清理临时文件
            try? FileManager.default.removeItem(at: processedAudioURL)
        }
        
        // 获取 CTC 去重设置（如果未指定，从用户偏好设置中获取）
        let ctcDedup: Bool
        if let enableCTCDeduplication = enableCTCDeduplication {
            ctcDedup = enableCTCDeduplication
        } else {
            ctcDedup = await MainActor.run { UserPreferences.shared.enableCTCDeduplication }
        }
        
        // 2. 提取音频特征
        let cmvnURL = resolveCMVNURL()
        let features = try await AudioFeatureExtractor.extractMelFeatures(from: processedAudioURL, cmvnURL: cmvnURL)
        
        // 3. 加载模型并推理
        let transcript = try await performTranscription(features: features, language: language, enableCTCDeduplication: ctcDedup)
        
        return transcript
    }
    
    /// 预处理音频：转换为 16kHz 单声道 WAV 格式
    private static func preprocessAudio(audioURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: audioURL)
        
        // 创建输出 URL
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")
        
        // 检查并删除已存在的文件
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // 创建音频格式设置（16kHz 单声道 PCM）
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false  // 单声道使用交错格式
        ]
        
        // 创建可编辑组合
        let composition = AVMutableComposition()
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw VideoProcessingError.noAudioTrack
        }
        
        // 将所有音频轨道添加到 composition，这样会自动混合所有声道
        var compositionAudioTracks: [AVMutableCompositionTrack] = []
        let duration = try await asset.load(.duration)
        
        for audioTrack in audioTracks {
            guard let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                continue
            }
            
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: audioTrack,
                at: .zero
            )
            
            compositionAudioTracks.append(compositionAudioTrack)
        }
        
        guard !compositionAudioTracks.isEmpty else {
            throw VideoProcessingError.compositionFailed
        }
        
        #if DEBUG
        print("找到 \(audioTracks.count) 个音频轨道，已全部添加到 composition")
        // 检查每个轨道的声道数
        for (index, track) in audioTracks.enumerated() {
            do {
                let formatDescriptions = try await track.load(.formatDescriptions)
                if let formatDescription = formatDescriptions.first {
                    let audioFormatDescription = formatDescription as CMAudioFormatDescription
                    // 尝试从格式描述中获取声道数
                    let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDescription)
                    if let asbd = asbd {
                        let channelCount = Int(asbd.pointee.mChannelsPerFrame)
                        print("音频轨道 \(index + 1): \(channelCount) 个声道")
                    } else {
                        print("音频轨道 \(index + 1): 无法获取声道信息")
                    }
                }
            } catch {
                print("音频轨道 \(index + 1): 无法加载格式描述 (\(error.localizedDescription))")
            }
        }
        #endif
        
        // 使用 AVAssetReader 和 AVAssetWriter 进行格式转换
        // AVAssetReaderAudioMixOutput 会自动将所有轨道混合成单声道
        let reader = try AVAssetReader(asset: composition)
        let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: compositionAudioTracks, audioSettings: nil)
        
        guard reader.canAdd(audioOutput) else {
            throw VideoProcessingError.transcriptionFailed("无法添加音频输出")
        }
        reader.add(audioOutput)
        
        // 创建 Writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        
        guard writer.canAdd(audioInput) else {
            throw VideoProcessingError.transcriptionFailed("无法添加音频输入")
        }
        writer.add(audioInput)
        
        // 开始转换
        guard reader.startReading() else {
            throw VideoProcessingError.transcriptionFailed("无法开始读取音频: \(reader.error?.localizedDescription ?? "未知错误")")
        }
        
        guard writer.startWriting() else {
            throw VideoProcessingError.transcriptionFailed("无法开始写入音频: \(writer.error?.localizedDescription ?? "未知错误")")
        }
        
        writer.startSession(atSourceTime: .zero)
        
        // 处理音频数据
        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "audio.conversion")
            nonisolated(unsafe) let audioInputCapture = audioInput
            nonisolated(unsafe) let audioOutputCapture = audioOutput
            nonisolated(unsafe) let writerCapture = writer
            audioInputCapture.requestMediaDataWhenReady(on: queue) {
                while audioInputCapture.isReadyForMoreMediaData {
                    guard let sampleBuffer = audioOutputCapture.copyNextSampleBuffer() else {
                        audioInputCapture.markAsFinished()
                        writerCapture.finishWriting {
                            if let error = writerCapture.error {
                                continuation.resume(throwing: VideoProcessingError.transcriptionFailed("音频预处理失败: \(error.localizedDescription)"))
                            } else {
                                continuation.resume(returning: outputURL)
                            }
                        }
                        return
                    }
                    if !audioInputCapture.append(sampleBuffer) {
                        audioInputCapture.markAsFinished()
                        writerCapture.finishWriting {
                            if let error = writerCapture.error {
                                continuation.resume(throwing: VideoProcessingError.transcriptionFailed("音频预处理失败: \(error.localizedDescription)"))
                            } else {
                                continuation.resume(returning: outputURL)
                            }
                        }
                        return
                    }
                }
            }
        }
    }
    
    /// 执行语音转文字推理
    /// - Parameters:
    ///   - features: 音频特征
    ///   - language: 语言类型
    ///   - enableCTCDeduplication: 是否启用 CTC 去重
    /// - Returns: 转录的文本
    private static func performTranscription(features: [[Float]], language: TranscriptLanguage, enableCTCDeduplication: Bool = false) async throws -> String {
        // 检查模型文件是否存在
        guard let tokensPath = tokensPath else {
            throw VideoProcessingError.modelLoadFailed("tokens 文件未找到")
        }
        
        // 加载 token 映射
        let tokenMap = try await loadTokenMap(from: tokensPath)
        
        // 准备输入：将特征转换为模型输入格式
        // 输入形状：[batch_size=1, sequence_length, feature_dim]
        let inputFeatures: [[[Float]]] = [features]
        
        // 使用 ONNX Runtime（通过 C wrapper）
        guard let modelPath = modelPath else {
            let modelDir = getModelDirectory()
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
        print("使用 ONNX Runtime 进行推理")
        print("模型路径: \(modelPath.path)")
        print("输入特征数量: \(features.count) 帧, 每帧 \(features.first?.count ?? 0) 维")
        if let firstFrame = features.first {
            let minVal = firstFrame.min() ?? 0
            let maxVal = firstFrame.max() ?? 0
            let avgVal = firstFrame.reduce(0, +) / Float(firstFrame.count)
            print("特征值范围: min=\(minVal), max=\(maxVal), avg=\(avgVal)")
            
            // 检查特征值是否全为 0 或异常
            let nonZeroCount = firstFrame.filter { abs($0) > 1e-6 }.count
            print("非零特征数量: \(nonZeroCount)/\(firstFrame.count)")
        }
        
        // 检查所有帧的特征值
        var allMin: Float = Float.infinity
        var allMax: Float = -Float.infinity
        var totalSum: Float = 0
        var totalCount = 0
        for frame in features {
            if let frameMin = frame.min() { allMin = min(allMin, frameMin) }
            if let frameMax = frame.max() { allMax = max(allMax, frameMax) }
            totalSum += frame.reduce(0, +)
            totalCount += frame.count
        }
        let allAvg = totalCount > 0 ? totalSum / Float(totalCount) : 0
        print("所有帧特征值范围: min=\(allMin), max=\(allMax), avg=\(allAvg)")
        #endif
        
        let onnxWrapper = ONNXRuntimeWrapper()
        try onnxWrapper.loadModel(from: modelPath.path)
        
        // 运行推理
        let tokenIDs = try onnxWrapper.runInference(input: inputFeatures, language: language, enableCTCDeduplication: enableCTCDeduplication)
        
        // 后处理：token 解码和文本规范化
        let text = postprocessTokens(tokenIDs: tokenIDs, tokenMap: tokenMap)
        
        return text
    }
    
    /// 加载 token 映射表
    private static func loadTokenMap(from url: URL) async throws -> [Int: String] {
        if let cached = tokenMap {
            return cached
        }
        
        let data = try Data(contentsOf: url)
        let tokens = try JSONDecoder().decode([String].self, from: data)
        
        var map: [Int: String] = [:]
        for (index, token) in tokens.enumerated() {
            map[index] = token
        }
        
        tokenMap = map
        return map
    }
    
    /// 后处理：将 token IDs 转换为文本
    private static func postprocessTokens(tokenIDs: [Int], tokenMap: [Int: String]) -> String {
        // 调试：打印原始 token IDs
        #if DEBUG
        print("原始 token IDs: \(tokenIDs.prefix(20))... (共 \(tokenIDs.count) 个)")
        #endif
        
        // 1. 过滤特殊 token
        let sosToken = 1  // <s>
        let eosToken = 2  // </s>
        let unkToken = 0  // <unk>
        
        let filteredTokens = tokenIDs.filter { token in
            token != sosToken && token != eosToken && token != unkToken && token >= 0
        }
        
        #if DEBUG
        print("过滤后 token IDs: \(filteredTokens.prefix(20))... (共 \(filteredTokens.count) 个)")
        #endif
        
        // 注意：CTC 去重已在 ONNXRuntimeWrapper 中完成，这里不再重复去重
        // 如果重复去重会导致叠词（如"谢谢"）被错误地合并为单字
        
        // 2. Token 到文本转换，同时过滤 SenseVoice 特殊 token
        var textParts: [String] = []
        var specialTokensFound: [String] = []
        for tokenID in filteredTokens {
            if let token = tokenMap[tokenID] {
                // 过滤所有 SenseVoice 特殊 token（以 <| 开头，以 |> 结尾）
                // 只有当 token 既以 <| 开头又以 |> 结尾时，才是特殊 token，需要过滤
                let isSpecialToken = token.hasPrefix("<|") && token.hasSuffix("|>")
                if isSpecialToken {
                    specialTokensFound.append(token)
                } else {
                textParts.append(token)
            }
        }
        }
        
        #if DEBUG
        if !specialTokensFound.isEmpty {
            print("过滤掉的特殊 token: \(specialTokensFound)")
        }
        print("保留的 token 文本: \(textParts.prefix(10))... (共 \(textParts.count) 个)")
        #endif
        
        // 4. 合并文本
        var text = textParts.joined(separator: "")
        
        // 5. 处理 SentencePiece 格式（移除 ▁ 前缀，转换为空格）
        text = text.replacingOccurrences(of: "▁", with: " ")
        
        // 6. 清理多余空格
        text = text.replacingOccurrences(of: "  ", with: " ")
        text = text.trimmingCharacters(in: .whitespaces)
        
        #if DEBUG
        print("最终文本: '\(text)'")
        #endif
        
        return text
    }
    
    // 注意：CTC 去重函数已移至 ONNXRuntimeWrapper 中统一处理
    // 这里不再进行第二次去重，以避免叠词（如"谢谢"）和连续数字（如"100"）被错误合并
}

