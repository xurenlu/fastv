//
//  LiveTranscriptionAudioService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import AVFoundation
import Combine

/// 直播转录音频服务
/// 用于从系统音频输出中实时捕获音频数据
@MainActor
class LiveTranscriptionAudioService: ObservableObject {
    static let shared = LiveTranscriptionAudioService()
    
    @Published private(set) var isCapturing = false
    @Published private(set) var audioLevel: Float = 0.0 // 用于波形显示和停顿检测
    @Published private(set) var capturingDuration: TimeInterval = 0
    
    private var audioEngine: AVAudioEngine?
    private var audioLevelTimer: Timer?
    nonisolated(unsafe) private var capturedBuffers: [Data] = []
    private var capturingOriginalFormat: AVAudioFormat?
    private let capturingSampleRate: Double = 16000
    private let capturingChannels: AVAudioChannelCount = 1
    private let capturingDataQueue = DispatchQueue(label: "liveTranscription.capturingDataQueue")
    
    // 分段捕获支持
    private var capturingStartTime: Date?
    private var lastSegmentTime: Date?
    nonisolated(unsafe) private var segmentBuffers: [Data] = []  // 当前段落的缓冲
    
    // 音频数据回调，用于波形显示和停顿检测
    var onAudioData: ((Float) -> Void)?
    
    // 分段回调 - 当检测到静音段时触发
    var onSegmentReady: ((Data, TimeInterval, TimeInterval) -> Void)?
    
    private init() {}
    
    /// 开始捕获系统音频
    func startCapturing() throws {
        print("🎤 [LiveTranscriptionAudioService] startCapturing() 被调用，当前 isCapturing=\(isCapturing)")
        
        guard !isCapturing else {
            print("ℹ️ [LiveTranscriptionAudioService] 已在捕获中，跳过")
            return
        }
        
        // 检查 BlackHole 是否可用
        let systemAudioCapture = SystemAudioCaptureService.shared
        systemAudioCapture.checkBlackHoleAvailability()
        guard systemAudioCapture.isBlackHoleAvailable else {
            throw LiveTranscriptionError.blackHoleNotInstalled
        }
        
        // 创建音频引擎
        let engine = AVAudioEngine()
        
        // 获取输入节点（应该选择 BlackHole 设备）
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        print("✅ [LiveTranscriptionAudioService] 成功获取音频输入格式: \(format)")
        
        // 重置捕获数据容器并保存原始格式
        capturingDataQueue.sync {
            self.capturedBuffers = []
            self.segmentBuffers = []
        }
        capturingOriginalFormat = format
        capturingStartTime = Date()
        lastSegmentTime = Date()
        capturingDuration = 0
        
        // 安装tap来捕获音频数据
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // 计算音频电平（用于波形显示和停顿检测）
            if let channelData = buffer.floatChannelData {
                let channelDataValue = channelData.pointee
                let frameCount = Int(buffer.frameLength)
                let channelDataValueArray = stride(from: 0, to: frameCount, by: 1).map { channelDataValue[$0] }
                
                // 计算RMS
                let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(channelDataValueArray.count))
                
                Task { @MainActor in
                    self.audioLevel = rms
                    self.onAudioData?(rms)
                }
            }
            
            // 写入缓冲
            if let channelData = buffer.floatChannelData {
                let frames = Int(buffer.frameLength)
                let byteCount = frames * MemoryLayout<Float>.size
                let pcmPointer = channelData.pointee
                let data = Data(bytes: pcmPointer, count: byteCount)
                self.capturingDataQueue.async {
                    self.capturedBuffers.append(data)
                    self.segmentBuffers.append(data)  // 同时写入分段缓冲
                }
            }
        }
        
        self.audioEngine = engine
        
        // 启动引擎
        do {
            print("🎤 [LiveTranscriptionAudioService] 启动音频引擎...")
            try engine.start()
            isCapturing = true
            print("✅ [LiveTranscriptionAudioService] 音频引擎已启动，isCapturing=\(isCapturing)")
            
            // 启动音频电平更新定时器
            audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
                guard let strongSelf = self else {
                    timer.invalidate()
                    return
                }
                Task { @MainActor in
                    if !strongSelf.isCapturing {
                        strongSelf.audioLevel *= 0.9
                        if strongSelf.audioLevel < 0.01 {
                            strongSelf.audioLevel = 0.0
                        }
                    } else {
                        // 更新捕获时长
                        if let startTime = strongSelf.capturingStartTime {
                            strongSelf.capturingDuration = Date().timeIntervalSince(startTime)
                        }
                    }
                }
            }
            print("✅ [LiveTranscriptionAudioService] 音频电平定时器已启动")
        } catch {
            print("❌ [LiveTranscriptionAudioService] 启动音频引擎失败: \(error)")
            throw LiveTranscriptionError.failedToStartCapturing(error.localizedDescription)
        }
    }
    
    /// 停止捕获并返回音频数据
    func stopCapturing() async throws -> VoiceRecording? {
        print("🎤 [LiveTranscriptionAudioService] stopCapturing() 被调用，当前 isCapturing=\(isCapturing)")
        
        guard isCapturing else {
            print("ℹ️ [LiveTranscriptionAudioService] 未在捕获中，返回 nil")
            return nil
        }
        
        print("🎤 [LiveTranscriptionAudioService] 停止音频引擎和定时器...")
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        isCapturing = false
        audioLevel = 0.0
        
        let buffers: [Data] = capturingDataQueue.sync {
            defer { self.capturedBuffers = [] }
            return self.capturedBuffers
        }
        
        guard !buffers.isEmpty,
              let originalFormat = capturingOriginalFormat else {
            print("⚠️ [LiveTranscriptionAudioService] 捕获数据为空或未知原始格式")
            capturingOriginalFormat = nil
            return nil
        }
        let formatToConvert = originalFormat
        capturingOriginalFormat = nil
        
        let combinedData = buffers.reduce(Data(), +)
        
        // 提取需要的参数值，避免在后台任务中访问实例属性
        let sampleRate = capturingSampleRate
        let channels = capturingChannels
        
        // 将转码操作移到后台线程，避免阻塞 UI
        return try await Task.detached(priority: .userInitiated) {
            do {
                let recording = try self.convertPCMData(
                    combinedData,
                    originalFormat: formatToConvert,
                    toSampleRate: sampleRate,
                    toChannels: channels
                )
                print("✅ [LiveTranscriptionAudioService] 捕获已停止，返回内存音频数据，字节数=\(recording.pcmData.count)")
                return recording
            } catch {
                print("⚠️ [LiveTranscriptionAudioService] PCM转换失败: \(error)")
                throw error
            }
        }.value
    }
    
    /// 取消捕获（不保存文件）
    func cancelCapturing() {
        Task { @MainActor in
            audioLevelTimer?.invalidate()
            audioLevelTimer = nil
            
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            audioEngine = nil
            
            capturingDataQueue.sync {
                self.capturedBuffers = []
                self.segmentBuffers = []
            }
            
            isCapturing = false
            audioLevel = 0.0
            capturingDuration = 0
            capturingStartTime = nil
            lastSegmentTime = nil
        }
    }
    
    /// 提取当前段落的音频数据(用于增量转写)
    /// - Returns: 当前段落的PCM数据,如果数据为空则返回nil
    func extractCurrentSegment() async throws -> VoiceRecording? {
        guard isCapturing else {
            print("⚠️ [LiveTranscriptionAudioService] 未在捕获中,无法提取段落")
            return nil
        }
        
        guard let originalFormat = capturingOriginalFormat else {
            print("⚠️ [LiveTranscriptionAudioService] 未知捕获格式")
            return nil
        }
        
        // 获取当前段落的缓冲数据
        let buffers: [Data] = capturingDataQueue.sync {
            let result = self.segmentBuffers
            self.segmentBuffers = []  // 清空段落缓冲,开始新段落
            return result
        }
        
        guard !buffers.isEmpty else {
            print("⚠️ [LiveTranscriptionAudioService] 段落数据为空")
            return nil
        }
        
        // 更新段落时间
        lastSegmentTime = Date()
        
        let combinedData = buffers.reduce(Data(), +)
        print("📊 [LiveTranscriptionAudioService] 提取段落数据: \(combinedData.count) 字节")
        
        // 提取需要的参数值，避免在后台任务中访问实例属性
        let sampleRate = capturingSampleRate
        let channels = capturingChannels
        
        // 将转码操作移到后台线程，避免阻塞 UI
        return try await Task.detached(priority: .userInitiated) {
            do {
                let recording = try self.convertPCMData(
                    combinedData,
                    originalFormat: originalFormat,
                    toSampleRate: sampleRate,
                    toChannels: channels
                )
                return recording
            } catch {
                print("⚠️ [LiveTranscriptionAudioService] 段落PCM转换失败: \(error)")
                throw error
            }
        }.value
    }
    
    /// 获取当前捕获的总时长
    func getCurrentDuration() -> TimeInterval {
        capturingDuration
    }
    
    /// 获取上一段落结束时的时间点
    func getLastSegmentTime() -> TimeInterval {
        guard let startTime = capturingStartTime,
              let segmentTime = lastSegmentTime else {
            return 0
        }
        return segmentTime.timeIntervalSince(startTime)
    }
    
    nonisolated private func convertPCMData(_ data: Data, originalFormat: AVAudioFormat, toSampleRate: Double, toChannels: AVAudioChannelCount) throws -> VoiceRecording {
        let frames = data.count / MemoryLayout<Float>.size
        guard frames > 0 else {
            throw LiveTranscriptionError.failedToStartCapturing("无有效音频数据")
        }
        
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: originalFormat, frameCapacity: AVAudioFrameCount(frames)) else {
            throw LiveTranscriptionError.failedToStartCapturing("无法创建源缓冲")
        }
        
        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress,
               let channelPointer = sourceBuffer.floatChannelData?.pointee {
                memcpy(channelPointer, baseAddress, data.count)
            }
        }
        sourceBuffer.frameLength = AVAudioFrameCount(frames)
        
        guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: toSampleRate,
                channels: toChannels,
                interleaved: false),
              let converter = AVAudioConverter(from: originalFormat, to: targetFormat) else {
            throw LiveTranscriptionError.failedToStartCapturing("无法创建转换器")
        }
        
        // 计算目标缓冲区需要的帧数（需要足够大以容纳转换后的数据）
        let estimatedOutputFrames = AVAudioFrameCount(ceil(Double(frames) * toSampleRate / originalFormat.sampleRate))
        // 额外增加10%的空间以防万一
        let outputCapacity = AVAudioFrameCount(Double(estimatedOutputFrames) * 1.1)
        
        guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputCapacity
              ) else {
            throw LiveTranscriptionError.failedToStartCapturing("无法创建输出缓冲")
        }
        
        print("🔄 [LiveTranscriptionAudioService] 开始转换: 源帧数=\(frames), 源采样率=\(originalFormat.sampleRate), 目标采样率=\(toSampleRate), 目标容量=\(outputCapacity)")
        
        var error: NSError?
        let inputExhaustedLock = NSLock()
        let inputExhaustedRef = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        inputExhaustedRef.initialize(to: false)
        defer {
            inputExhaustedRef.deinitialize(count: 1)
            inputExhaustedRef.deallocate()
        }
        
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            // 确保只提供一次数据
            inputExhaustedLock.lock()
            defer { inputExhaustedLock.unlock() }
            
            if inputExhaustedRef.pointee {
                outStatus.pointee = .noDataNow
                return nil
            }
            
            inputExhaustedRef.pointee = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }
        
        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            throw LiveTranscriptionError.failedToStartCapturing("转换失败: \(error.localizedDescription)")
        }
        
        print("✅ [LiveTranscriptionAudioService] 转换完成: 输出帧数=\(convertedBuffer.frameLength)")
        
        guard let channelData = convertedBuffer.int16ChannelData else {
            throw LiveTranscriptionError.failedToStartCapturing("转换结果为空")
        }
        
        let convertedFrames = Int(convertedBuffer.frameLength)
        let byteCount = convertedFrames * MemoryLayout<Int16>.size
        let pcmPointer = channelData.pointee
        let pcmData = Data(bytes: pcmPointer, count: byteCount)
        
        return VoiceRecording(pcmData: pcmData, sampleRate: toSampleRate, channelCount: Int(toChannels))
    }
}

/// 直播转录错误
enum LiveTranscriptionError: LocalizedError {
    case blackHoleNotInstalled
    case failedToStartCapturing(String)
    case capturingInUse
    
    var errorDescription: String? {
        switch self {
        case .blackHoleNotInstalled:
            return """
            未检测到 BlackHole 虚拟音频设备。
            
            要捕获系统音频，需要安装 BlackHole。
            
            安装步骤：
            1. 访问 https://github.com/ExistentialAudio/BlackHole
            2. 下载并安装 BlackHole
            3. 在"系统设置 > 声音"中配置 BlackHole 为输出设备
            4. 重启应用
            """
        case .failedToStartCapturing(let message):
            return "无法开始捕获: \(message)"
        case .capturingInUse:
            return "系统音频捕获正被其他应用使用"
        }
    }
}

