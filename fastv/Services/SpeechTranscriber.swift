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
    
    /// 从内存录音转文字（用于语音输入、会议记录、直播转录）
    /// 自动检测录音时长，超过60秒自动分段处理
    /// 使用 Task.detached 确保在后台线程执行，避免阻塞主线程
    /// - Parameters:
    ///   - cancellationCheck: 取消检查函数，定期调用以检查是否应该取消操作
    static func transcribe(
        recording: VoiceRecording,
        language: TranscriptLanguage = .auto,
        enableCTCDeduplication: Bool? = nil,
        cancellationCheck: (() -> Bool)? = nil
    ) async throws -> String {
        return try await Task.detached(priority: .userInitiated) {
            try await transcribeImpl(
                recording: recording,
                language: language,
                enableCTCDeduplication: enableCTCDeduplication,
                cancellationCheck: cancellationCheck
            )
        }.value
    }

    /// 转录实现（在后台线程执行）
    private static func transcribeImpl(
        recording: VoiceRecording,
        language: TranscriptLanguage = .auto,
        enableCTCDeduplication: Bool? = nil,
        cancellationCheck: (() -> Bool)? = nil
    ) async throws -> String {
        // 检查取消
        if let check = cancellationCheck, check() {
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        }

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

        // 检查取消
        if let check = cancellationCheck, check() {
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        }

        // 获取归一化的音频样本
        let samples = recording.normalizedSamples()
        let duration = Double(samples.count) / recording.sampleRate

        #if DEBUG
        print("🎤 [SpeechTranscriber] 录音时长: \(String(format: "%.2f", duration))s")
        #endif

        // 如果录音时长超过60秒，使用分段处理
        if AudioSegmenter.needsSegmentation(samples: samples, config: .realtime) {
            #if DEBUG
            print("📊 [SpeechTranscriber] 录音超过60秒，使用分段处理")
            #endif
            return try await transcribeRecordingWithSegmentation(
                samples: samples,
                sampleRate: recording.sampleRate,
                language: language,
                enableCTCDeduplication: ctcDedup,
                cancellationCheck: cancellationCheck
            )
        }
        
        // 短录音：直接处理
        let cmvnURL = resolveCMVNURL()
        let features = try await AudioFeatureExtractor.extractMelFeatures(from: recording, cmvnURL: cmvnURL)
        let transcript = try await performTranscription(features: features, language: language, enableCTCDeduplication: ctcDedup)
        // 短录音单次处理完成后回收
        autoreleasepool { }
        return transcript
    }
    
    /// 分段转录录音数据（内部方法）
    private static func transcribeRecordingWithSegmentation(
        samples: [Float],
        sampleRate: Double,
        language: TranscriptLanguage,
        enableCTCDeduplication: Bool,
        cancellationCheck: (() -> Bool)? = nil
    ) async throws -> String {
        // 使用实时配置进行分段
        let segments = AudioSegmenter.segmentAudio(samples: samples, sampleRate: sampleRate, config: .realtime)

        #if DEBUG
        print("📊 [SpeechTranscriber] 录音分成 \(segments.count) 个片段")
        #endif

        var transcripts: [String] = []
        let cmvnURL = resolveCMVNURL()

        for (index, segment) in segments.enumerated() {
            // 检查取消
            if let check = cancellationCheck, check() {
                print("⚠️ [SpeechTranscriber] 分段转写已取消")
                throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
            }

            #if DEBUG
            print("🎤 [SpeechTranscriber] 处理片段 \(index + 1)/\(segments.count): \(String(format: "%.2f", segment.startTime))s - \(String(format: "%.2f", segment.endTime))s")
            #endif

            // 将 Float 样本转换为 PCM Data
            let pcmData = floatSamplesToPCMData(segment.samples)
            let segmentRecording = VoiceRecording(pcmData: pcmData, sampleRate: sampleRate, channelCount: 1)

            // 提取特征并推理
            let features = try await AudioFeatureExtractor.extractMelFeatures(from: segmentRecording, cmvnURL: cmvnURL)

            // 再次检查取消
            if let check = cancellationCheck, check() {
                print("⚠️ [SpeechTranscriber] 分段转写已取消")
                throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
            }

            let segmentTranscript = try await performTranscription(
                features: features,
                language: language,
                enableCTCDeduplication: enableCTCDeduplication,
                cancellationCheck: cancellationCheck
            )

            if !segmentTranscript.isEmpty {
                transcripts.append(segmentTranscript)
            }

            #if DEBUG
            print("✅ [SpeechTranscriber] 片段 \(index + 1) 转录完成: \(segmentTranscript.prefix(30))...")
            #endif

            // 每段处理完后主动回收 C/ObjC 层可能产生的 autorelease 对象，防止长录音分段时内存累积
            autoreleasepool { }
        }

        // 合并结果
        let finalTranscript = mergeTranscripts(transcripts, language: language)

        #if DEBUG
        print("📝 [SpeechTranscriber] 分段录音转录完成，共 \(transcripts.count) 个片段")
        #endif
        
        return finalTranscript
    }
    
    /// 从音频文件转文字
    /// - Parameters:
    ///   - audioURL: 音频文件 URL
    ///   - language: 语言类型，默认为自动检测
    ///   - enableCTCDeduplication: 是否启用 CTC 去重，nil 则使用用户设置
    /// - Returns: 转录的文本
    static func transcribe(audioURL: URL, language: TranscriptLanguage = .auto, enableCTCDeduplication: Bool? = nil) async throws -> String {
        // 使用分段转录，但不显示进度
        return try await transcribeWithSegmentation(
            audioURL: audioURL,
            language: language,
            enableCTCDeduplication: enableCTCDeduplication,
            progressHandler: { _, _ in }
        )
    }
    
    /// 从音频文件转文字（带进度回调，支持长音频分段处理）
    /// - Parameters:
    ///   - audioURL: 音频文件 URL
    ///   - language: 语言类型，默认为自动检测
    ///   - enableCTCDeduplication: 是否启用 CTC 去重，nil 则使用用户设置
    ///   - progressHandler: 进度回调 (进度 0.0-1.0, 状态消息)
    /// - Returns: 转录的文本
    static func transcribeWithSegmentation(
        audioURL: URL,
        language: TranscriptLanguage = .auto,
        enableCTCDeduplication: Bool? = nil,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> String {
        // 1. 预处理音频：转换为 16kHz 单声道 WAV
        await MainActor.run { progressHandler(0.05, "正在预处理音频...") }
        
        let processedAudioURL = try await preprocessAudio(audioURL: audioURL)
        defer {
            // 清理临时文件
            try? FileManager.default.removeItem(at: processedAudioURL)
        }
        
        // 获取 CTC 去重设置
        let ctcDedup: Bool
        if let enableCTCDeduplication = enableCTCDeduplication {
            ctcDedup = enableCTCDeduplication
        } else {
            ctcDedup = await MainActor.run { UserPreferences.shared.enableCTCDeduplication }
        }
        
        // 2. 加载音频数据
        await MainActor.run { progressHandler(0.1, "正在加载音频数据...") }
        let audioSamples = try await loadAudioSamples(from: processedAudioURL)
        
        let totalDuration = Double(audioSamples.count) / 16000.0
        #if DEBUG
        print("🎵 音频总时长: \(String(format: "%.2f", totalDuration)) 秒")
        #endif
        
        // 3. 判断是否需要分段
        if !AudioSegmenter.needsSegmentation(samples: audioSamples) {
            // 短音频：直接处理
            await MainActor.run { progressHandler(0.2, "正在提取特征...") }
            let cmvnURL = resolveCMVNURL()
            let features = try await AudioFeatureExtractor.extractMelFeatures(from: processedAudioURL, cmvnURL: cmvnURL)
            
            await MainActor.run { progressHandler(0.4, "正在转录...") }
            let transcript = try await performTranscription(features: features, language: language, enableCTCDeduplication: ctcDedup)
            
            await MainActor.run { progressHandler(1.0, "转录完成") }
            return transcript
        }
        
        // 4. 长音频：分段处理
        await MainActor.run { progressHandler(0.1, "正在分析音频结构...") }
        let segments = AudioSegmenter.segmentAudio(samples: audioSamples)
        
        #if DEBUG
        print("📊 音频分成 \(segments.count) 个片段")
        #endif
        
        // 5. 逐个片段处理
        var transcripts: [String] = []
        let cmvnURL = resolveCMVNURL()
        
        for (index, segment) in segments.enumerated() {
            let segmentProgress = 0.1 + 0.85 * (Double(index) / Double(segments.count))
            let statusMessage = "转录中: 片段 \(index + 1)/\(segments.count) (\(Int(segment.startTime))s-\(Int(segment.endTime))s)"
            await MainActor.run { progressHandler(segmentProgress, statusMessage) }
            
            #if DEBUG
            print("🎤 处理片段 \(index + 1)/\(segments.count): \(String(format: "%.2f", segment.startTime))s - \(String(format: "%.2f", segment.endTime))s")
            #endif
            
            // 将 Float 样本转换为 Int16 PCM 数据
            let pcmData = floatSamplesToPCMData(segment.samples)
            let recording = VoiceRecording(pcmData: pcmData, sampleRate: 16000, channelCount: 1)
            
            // 提取该片段的特征
            let features = try await AudioFeatureExtractor.extractMelFeatures(
                from: recording,
                cmvnURL: cmvnURL
            )
            
            // 推理
            let segmentTranscript = try await performTranscription(
                features: features,
                language: language,
                enableCTCDeduplication: ctcDedup
            )
            
            if !segmentTranscript.isEmpty {
                transcripts.append(segmentTranscript)
            }
            
            #if DEBUG
            print("✅ 片段 \(index + 1) 转录结果: \(segmentTranscript.prefix(50))...")
            #endif
            
            // 每段处理完后回收 C/ObjC 层 autorelease 对象，防止长音频分段时内存累积
            autoreleasepool { }
        }
        
        // 6. 合并结果
        await MainActor.run { progressHandler(0.95, "正在合并结果...") }
        let finalTranscript = mergeTranscripts(transcripts, language: language)
        
        await MainActor.run { progressHandler(1.0, "转录完成") }
        
        #if DEBUG
        print("📝 最终转录结果: \(finalTranscript.prefix(100))...")
        #endif
        
        return finalTranscript
    }
    
    /// 加载音频样本数据
    private static func loadAudioSamples(from audioURL: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: audioURL)
        
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw VideoProcessingError.noAudioTrack
        }
        
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        guard reader.canAdd(audioOutput) else {
            throw VideoProcessingError.transcriptionFailed("无法添加音频输出")
        }
        reader.add(audioOutput)
        
        guard reader.startReading() else {
            throw VideoProcessingError.transcriptionFailed("无法开始读取音频: \(reader.error?.localizedDescription ?? "未知错误")")
        }
        
        var audioSamples: [Float] = []
        var sampleCount = 0  // 用于定期清理

        while let sampleBuffer = audioOutput.copyNextSampleBuffer() {
            // 每 100 个样本缓冲区回收一次，防止内存累积
            sampleCount += 1
            if sampleCount % 100 == 0 {
                autoreleasepool { }
            }

            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }

            var length: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>? = nil
            let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            
            guard status == noErr, let data = dataPointer else {
                continue
            }
            
            let sampleCount = length / 2
            let floatSamples = data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { int16Ptr -> [Float] in
                let buffer = UnsafeBufferPointer(start: int16Ptr, count: sampleCount)
                return buffer.map { Float($0) / 32768.0 }
            }
            
            audioSamples.append(contentsOf: floatSamples)
        }
        
        return audioSamples
    }
    
    /// 将 Float 样本数据转换为 Int16 PCM Data
    private static func floatSamplesToPCMData(_ samples: [Float]) -> Data {
        var pcmData = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            // 将 -1.0 ~ 1.0 的 Float 转换为 Int16
            let clamped = max(-1.0, min(1.0, sample))
            let int16Value = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: int16Value.littleEndian) { bytes in
                pcmData.append(contentsOf: bytes)
            }
        }
        return pcmData
    }
    
    /// 合并多个片段的转录结果
    private static func mergeTranscripts(_ transcripts: [String], language: TranscriptLanguage) -> String {
        guard !transcripts.isEmpty else { return "" }
        
        // 根据语言决定分隔符
        // 中文/日文/韩文不需要空格，英文等需要空格
        let needsSpace: Bool
        switch language {
        case .zh, .ja, .ko, .yue:
            needsSpace = false
        case .en:
            needsSpace = true
        case .auto, .nospeech:
            // 自动检测：如果第一个转录结果主要是 CJK 字符，不加空格
            if let first = transcripts.first {
                let cjkCount = first.unicodeScalars.filter { scalar in
                    // CJK 统一汉字范围
                    (scalar.value >= 0x4E00 && scalar.value <= 0x9FFF) ||
                    // 日文平假名
                    (scalar.value >= 0x3040 && scalar.value <= 0x309F) ||
                    // 日文片假名
                    (scalar.value >= 0x30A0 && scalar.value <= 0x30FF) ||
                    // 韩文
                    (scalar.value >= 0xAC00 && scalar.value <= 0xD7AF)
                }.count
                needsSpace = cjkCount < first.count / 2
            } else {
                needsSpace = true
            }
        }
        
        if needsSpace {
            return transcripts.joined(separator: " ")
        } else {
            return transcripts.joined(separator: "")
        }
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
    /// 使用缓存的 ONNX 模型（SpeechTranscriptionModel），避免每次重新加载
    /// - Parameters:
    ///   - features: 音频特征
    ///   - language: 语言类型
    ///   - enableCTCDeduplication: 是否启用 CTC 去重
    ///   - cancellationCheck: 取消检查函数
    /// - Returns: 转录的文本
    private static func performTranscription(
        features: [[Float]],
        language: TranscriptLanguage,
        enableCTCDeduplication: Bool = false,
        cancellationCheck: (() -> Bool)? = nil
    ) async throws -> String {
        // 检查取消
        if let check = cancellationCheck, check() {
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        }

        // 检查 tokens 文件
        guard let tokensPath = tokensPath else {
            throw VideoProcessingError.modelLoadFailed("tokens 文件未找到")
        }

        // 加载 token 映射
        let tokenMap = try await loadTokenMap(from: tokensPath)

        // 使用缓存的模型运行推理（首次调用时加载，后续复用）
        let tokenIDs = try await SpeechTranscriptionModel.shared.runInference(
            features: features,
            language: language,
            enableCTCDeduplication: enableCTCDeduplication
        )
        
        // 后处理：token 解码和文本规范化
        let text = postprocessTokens(tokenIDs: tokenIDs, tokenMap: tokenMap, enableCTCDeduplication: enableCTCDeduplication)
        
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
    /// - Parameter enableCTCDeduplication: 启用时额外清理连续不同标点（。，、，。），分段边界常见
    private static func postprocessTokens(tokenIDs: [Int], tokenMap: [Int: String], enableCTCDeduplication: Bool = false) -> String {
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
        
        // 7. 启用 CTC 去重时，清理分段边界常见的连续不同标点（。，、，。等）
        if enableCTCDeduplication {
            let crossPunctuationPatterns = [("。，", "。"), ("，。", "。"), ("、，", "、"), ("，、", "，")]
            for (pattern, replacement) in crossPunctuationPatterns {
                text = text.replacingOccurrences(of: pattern, with: replacement)
            }
        }
        
        #if DEBUG
        print("最终文本: '\(text)'")
        #endif
        
        return text
    }
    
    // 注意：CTC 去重函数已移至 ONNXRuntimeWrapper 中统一处理
    // 这里不再进行第二次去重，以避免叠词（如"谢谢"）和连续数字（如"100"）被错误合并
}

