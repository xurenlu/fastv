//
//  VoiceInputService.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AVFoundation
import Combine

/// 语音输入服务
@MainActor
class VoiceInputService: ObservableObject {
    static let shared = VoiceInputService()
    
    @Published private(set) var isRecording = false
    @Published private(set) var audioLevel: Float = 0.0 // 用于波形显示
    @Published private(set) var recordingDuration: TimeInterval = 0
    
    private var audioEngine: AVAudioEngine?
    private var audioLevelTimer: Timer?
    nonisolated(unsafe) private var recordedBuffers: [Data] = []
    private var recordingOriginalFormat: AVAudioFormat?
    private let recordingSampleRate: Double = 16000
    private let recordingChannels: AVAudioChannelCount = 1
    private let recordingDataQueue = DispatchQueue(label: "voiceInput.recordingDataQueue")
    
    // 分段录音支持
    private var recordingStartTime: Date?
    private var lastSegmentTime: Date?
    nonisolated(unsafe) private var segmentBuffers: [Data] = []  // 当前段落的缓冲
    
    // 音频数据回调，用于波形显示
    var onAudioData: ((Float) -> Void)?
    
    // 分段回调 - 当检测到静音段时触发
    var onSegmentReady: ((Data, TimeInterval, TimeInterval) -> Void)?
    
    // 实时转换后的音频数据回调 - 用于实时保存 WAV 文件
    // 参数：转换后的 PCM 数据（Int16 格式，16kHz 单声道）
    var onConvertedAudioData: ((Data) -> Void)?
    
    private init() {}
    
    /// 开始录音
    func startRecording() throws {
        print("🎤 [VoiceInputService] startRecording() 被调用，当前 isRecording=\(isRecording)")
        
        guard !isRecording else {
            print("ℹ️ [VoiceInputService] 已在录音中，跳过")
            return
        }
        
        // 检查麦克风权限
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("🎤 [VoiceInputService] 麦克风权限状态: \(status.rawValue) (\(statusDescription(status)))")
        
        // 添加 Bundle ID 诊断信息
        if let bundleId = Bundle.main.bundleIdentifier {
            print("🔍 [VoiceInputService] Bundle ID: \(bundleId)")
        }
        
        // 如果权限已授权，直接继续，不要再次请求
        if status == .authorized {
            print("✅ [VoiceInputService] 麦克风权限已授权，继续录音设置")
        } else if status == .notDetermined {
            // 只有在权限未确定时才请求
            print("🎤 [VoiceInputService] 权限未确定，请求麦克风权限...")
            print("💡 [VoiceInputService] 注意：如果系统设置中已授权但这里显示未确定，可能是 Bundle ID 不匹配")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("🎤 [VoiceInputService] 麦克风权限请求结果: \(granted)")
                Task { @MainActor in
                    if granted {
                        // 权限已授权，重新尝试录音
                        try? self.startRecording()
                    } else {
                        print("❌ [VoiceInputService] 用户拒绝了麦克风权限")
                        print("💡 [VoiceInputService] 请在'系统设置 > 隐私与安全性 > 麦克风'中授权应用")
                    }
                }
            }
            return
        } else {
            // 权限被拒绝或受限
            print("❌ [VoiceInputService] 麦克风权限未授权: \(statusDescription(status))")
            print("💡 [VoiceInputService] 请在'系统设置 > 隐私与安全性 > 麦克风'中找到应用并勾选")
            if let bundleId = Bundle.main.bundleIdentifier {
                print("💡 [VoiceInputService] 请确保系统设置中授权的是 Bundle ID: \(bundleId)")
            }
            throw VoiceInputError.microphonePermissionDenied
        }
        
        // 创建音频引擎
        let engine = AVAudioEngine()
        
        // 检查麦克风是否可用（可能被其他应用占用）
        let inputNode = engine.inputNode
        
        // 尝试获取输入格式，如果失败可能是麦克风被占用
        let format = inputNode.inputFormat(forBus: 0)
        print("✅ [VoiceInputService] 成功获取音频输入格式: \(format)")
        
        // 重置录音数据容器并保存原始格式
        recordingDataQueue.sync {
            self.recordedBuffers = []
            self.segmentBuffers = []
        }
        recordingOriginalFormat = format
        recordingStartTime = Date()
        lastSegmentTime = Date()
        recordingDuration = 0
        
        // 安装tap来捕获音频数据
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // 计算音频电平（用于波形显示）
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
                self.recordingDataQueue.async {
                    self.recordedBuffers.append(data)
                    self.segmentBuffers.append(data)  // 同时写入分段缓冲
                }
                
                // 实时转换音频数据（如果启用了回调）
                // 注意：为了避免性能问题，这里采用批量处理策略
                // 实际转换会在 MeetingRecordViewModel 中通过定时器批量处理
            }
        }

        self.audioEngine = engine
        
        // 启动引擎
        do {
            print("🎤 [VoiceInputService] 启动音频引擎...")
            try engine.start()
            isRecording = true
            print("✅ [VoiceInputService] 音频引擎已启动，isRecording=\(isRecording)")
            
            // 启动音频电平更新定时器
            audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
                // 定时器用于平滑音频电平衰减和更新录音时长
                guard let strongSelf = self else {
                    timer.invalidate()
                    return
                }
                Task { @MainActor in
                    if !strongSelf.isRecording {
                        strongSelf.audioLevel *= 0.9
                        if strongSelf.audioLevel < 0.01 {
                            strongSelf.audioLevel = 0.0
                        }
                    } else {
                        // 更新录音时长
                        if let startTime = strongSelf.recordingStartTime {
                            strongSelf.recordingDuration = Date().timeIntervalSince(startTime)
                        }
                    }
                }
            }
            print("✅ [VoiceInputService] 音频电平定时器已启动")
        } catch {
            print("❌ [VoiceInputService] 启动音频引擎失败: \(error)")
            throw VoiceInputError.failedToStartRecording(error.localizedDescription)
        }
    }
    
    /// 停止录音并返回音频数据
    func stopRecording() async throws -> VoiceRecording? {
        print("🎤 [VoiceInputService] stopRecording() 被调用，当前 isRecording=\(isRecording)")
        
        guard isRecording else {
            print("ℹ️ [VoiceInputService] 未在录音中，返回 nil")
            return nil
        }
        
        print("🎤 [VoiceInputService] 停止音频引擎和定时器...")
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        isRecording = false
        audioLevel = 0.0
        
        let buffers: [Data] = recordingDataQueue.sync {
            defer { self.recordedBuffers = [] }
            return self.recordedBuffers
        }
        
        guard !buffers.isEmpty,
              let originalFormat = recordingOriginalFormat else {
            print("⚠️ [VoiceInputService] 录音数据为空或未知原始格式")
            recordingOriginalFormat = nil
            return nil
        }
        recordingOriginalFormat = nil
        
        // 提取需要的参数值，避免在后台任务中访问实例属性
        let sampleRate = recordingSampleRate
        let channels = recordingChannels
        let onConverted = await self.onConvertedAudioData
        
        // 如果启用了实时保存回调，分批转换并实时保存
        if onConverted != nil {
            // 分批处理音频数据，每批约2秒的数据（16kHz * 2秒 * 4字节 = 128KB）
            let batchSize = 128 * 1024  // 每批约128KB
            var allConvertedData = Data()
            
            for i in stride(from: 0, to: buffers.count, by: max(1, buffers.count / 10)) {
                let endIndex = min(i + max(1, buffers.count / 10), buffers.count)
                let batchBuffers = Array(buffers[i..<endIndex])
                let batchData = batchBuffers.reduce(Data(), +)
                
                if !batchData.isEmpty {
                    do {
                        let converted = try await Task.detached(priority: .userInitiated) {
                            try await self.convertPCMData(
                                batchData,
                                originalFormat: originalFormat,
                                toSampleRate: sampleRate,
                                toChannels: channels
                            )
                        }.value
                        
                        allConvertedData.append(converted.pcmData)
                        
                        // 实时调用回调
                        if let callback = await self.onConvertedAudioData {
                            await MainActor.run {
                                callback(converted.pcmData)
                            }
                        }
                    } catch {
                        print("⚠️ [VoiceInputService] 批量转换失败: \(error)")
                    }
                }
            }
            
            // 返回合并后的数据
            if !allConvertedData.isEmpty {
                let recording = VoiceRecording(
                    pcmData: allConvertedData,
                    sampleRate: sampleRate,
                    channelCount: Int(channels)
                )
                print("✅ [VoiceInputService] 录音已停止，返回内存音频数据，字节数=\(recording.pcmData.count)")
                return recording
            }
        }
        
        // 如果没有启用实时保存，使用原来的方式一次性转换
        let combinedData = buffers.reduce(Data(), +)
        
        // 将转码操作移到后台线程，避免阻塞 UI
        do {
            let recording = try await Task.detached(priority: .userInitiated) {
                try await self.convertPCMData(
                    combinedData,
                    originalFormat: originalFormat,
                    toSampleRate: sampleRate,
                    toChannels: channels
                )
            }.value
            
            print("✅ [VoiceInputService] 录音已停止，返回内存音频数据，字节数=\(recording.pcmData.count)")
            return recording
        } catch {
            print("⚠️ [VoiceInputService] PCM转换失败: \(error)")
            return nil
        }
    }
    
    /// 取消录音（不保存文件）
    func cancelRecording() {
        Task { @MainActor in
            audioLevelTimer?.invalidate()
            audioLevelTimer = nil
            
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            audioEngine = nil
            
            recordingDataQueue.sync {
                self.recordedBuffers = []
                self.segmentBuffers = []
            }
            
            isRecording = false
            audioLevel = 0.0
            recordingDuration = 0
            recordingStartTime = nil
            lastSegmentTime = nil
        }
    }
    
    /// 提取当前段落的音频数据(用于增量转写)
    /// - Returns: 当前段落的PCM数据,如果数据为空则返回nil
    func extractCurrentSegment() async throws -> VoiceRecording? {
        guard isRecording else {
            print("⚠️ [VoiceInputService] 未在录音中,无法提取段落")
            return nil
        }
        
        guard let originalFormat = recordingOriginalFormat else {
            print("⚠️ [VoiceInputService] 未知录音格式")
            return nil
        }
        
        // 获取当前段落的缓冲数据
        let buffers: [Data] = recordingDataQueue.sync {
            let result = self.segmentBuffers
            self.segmentBuffers = []  // 清空段落缓冲,开始新段落
            return result
        }
        
        guard !buffers.isEmpty else {
            print("⚠️ [VoiceInputService] 段落数据为空")
            return nil
        }
        
        // 更新段落时间
        lastSegmentTime = Date()
        
        let combinedData = buffers.reduce(Data(), +)
        print("📊 [VoiceInputService] 提取段落数据: \(combinedData.count) 字节")
        
        // 提取需要的参数值，避免在后台任务中访问实例属性
        let sampleRate = recordingSampleRate
        let channels = recordingChannels
        
        // 将转码操作移到后台线程，避免阻塞 UI
        return try await Task.detached(priority: .userInitiated) {
            do {
                let recording = try await self.convertPCMData(
                    combinedData,
                    originalFormat: originalFormat,
                    toSampleRate: sampleRate,
                    toChannels: channels
                )
                return recording
            } catch {
                print("⚠️ [VoiceInputService] 段落PCM转换失败: \(error)")
                throw error
            }
        }.value
    }
    
    /// 获取当前录音的总时长
    func getCurrentDuration() -> TimeInterval {
        recordingDuration
    }
    
    /// 获取上一段落结束时的时间点
    func getLastSegmentTime() -> TimeInterval {
        guard let startTime = recordingStartTime,
              let segmentTime = lastSegmentTime else {
            return 0
        }
        return segmentTime.timeIntervalSince(startTime)
    }
    
    nonisolated private func convertPCMData(_ data: Data, originalFormat: AVAudioFormat, toSampleRate: Double, toChannels: AVAudioChannelCount) async throws -> VoiceRecording {
        let frames = data.count / MemoryLayout<Float>.size
        guard frames > 0 else {
            throw VoiceInputError.failedToStartRecording("无有效音频数据")
        }
        
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: originalFormat, frameCapacity: AVAudioFrameCount(frames)) else {
            throw VoiceInputError.failedToStartRecording("无法创建源缓冲")
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
            throw VoiceInputError.failedToStartRecording("无法创建转换器")
        }
        
        // 计算目标缓冲区需要的帧数（需要足够大以容纳转换后的数据）
        let estimatedOutputFrames = AVAudioFrameCount(ceil(Double(frames) * toSampleRate / originalFormat.sampleRate))
        // 额外增加10%的空间以防万一
        let outputCapacity = AVAudioFrameCount(Double(estimatedOutputFrames) * 1.1)
        
        guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputCapacity
              ) else {
            throw VoiceInputError.failedToStartRecording("无法创建输出缓冲")
        }
        
        print("🔄 [VoiceInputService] 开始转换: 源帧数=\(frames), 源采样率=\(originalFormat.sampleRate), 目标采样率=\(toSampleRate), 目标容量=\(outputCapacity)")
        
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
            throw VoiceInputError.failedToStartRecording("转换失败: \(error.localizedDescription)")
        }
        
        print("✅ [VoiceInputService] 转换完成: 输出帧数=\(convertedBuffer.frameLength)")
        
        guard let channelData = convertedBuffer.int16ChannelData else {
            throw VoiceInputError.failedToStartRecording("转换结果为空")
        }
        
        let convertedFrames = Int(convertedBuffer.frameLength)
        let byteCount = convertedFrames * MemoryLayout<Int16>.size
        let pcmPointer = channelData.pointee
        let pcmData = Data(bytes: pcmPointer, count: byteCount)
        
        return VoiceRecording(pcmData: pcmData, sampleRate: toSampleRate, channelCount: Int(toChannels))
    }
    
    /// 获取权限状态描述
    private func statusDescription(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "未确定"
        case .restricted:
            return "受限制"
        case .denied:
            return "已拒绝"
        case .authorized:
            return "已授权"
        @unknown default:
            return "未知状态"
        }
    }
}

/// 语音输入错误
enum VoiceInputError: LocalizedError {
    case microphonePermissionDenied
    case failedToStartRecording(String)
    case microphoneInUse
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "麦克风权限被拒绝，请在系统设置中允许访问麦克风"
        case .failedToStartRecording(let message):
            return "无法开始录音: \(message)"
        case .microphoneInUse:
            return "麦克风正被其他应用使用（如闪电说），请先关闭其他语音输入应用"
        }
    }
}

