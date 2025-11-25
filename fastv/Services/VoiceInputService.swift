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
    
    private var audioEngine: AVAudioEngine?
    private var audioLevelTimer: Timer?
    nonisolated(unsafe) private var recordedBuffers: [Data] = []
    // 分段录音：当前段的缓冲区
    nonisolated(unsafe) private var currentSegmentBuffers: [Data] = []
    // 分段录音：已完成的段（用于最后一段的处理）
    nonisolated(unsafe) private var completedSegments: [Data] = []
    private var recordingOriginalFormat: AVAudioFormat?
    private let recordingSampleRate: Double = 16000
    private let recordingChannels: AVAudioChannelCount = 1
    private let recordingDataQueue = DispatchQueue(label: "voiceInput.recordingDataQueue")
    
    // 音频数据回调，用于波形显示
    var onAudioData: ((Float) -> Void)?
    
    // 分段转文字回调：当检测到停顿时，自动转文字
    var onSegmentReady: ((VoiceRecording) async -> Void)?
    
    // 是否启用智能分段转文字
    var enableSegmentTranscription: Bool = false
    
    private let silenceDetector = SilenceDetector.shared
    
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
            self.currentSegmentBuffers = []
            self.completedSegments = []
        }
        recordingOriginalFormat = format
        
        // 重置停顿检测器
        silenceDetector.reset()
        
        // 设置停顿检测回调
        if enableSegmentTranscription {
            silenceDetector.onSilenceDetected = { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.processSegment()
                }
            }
        }
        
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
                    
                    // 处理停顿检测
                    if self.enableSegmentTranscription {
                        self.silenceDetector.processAudioLevel(rms)
                    }
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
                    // 如果启用分段转文字，同时保存到当前段
                    if self.enableSegmentTranscription {
                        self.currentSegmentBuffers.append(data)
                    }
                }
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
                // 定时器用于平滑音频电平衰减
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
                    }
                }
            }
            print("✅ [VoiceInputService] 音频电平定时器已启动")
        } catch {
            print("❌ [VoiceInputService] 启动音频引擎失败: \(error)")
            throw VoiceInputError.failedToStartRecording(error.localizedDescription)
        }
    }
    
    /// 处理当前段（检测到停顿时调用）
    private func processSegment() async {
        guard enableSegmentTranscription else { return }
        
        let segmentBuffers: [Data] = recordingDataQueue.sync {
            guard !self.currentSegmentBuffers.isEmpty else {
                return []
            }
            let buffers = self.currentSegmentBuffers
            // 保存到已完成段（用于最后合并）
            self.completedSegments.append(contentsOf: buffers)
            // 清空当前段，准备下一段
            self.currentSegmentBuffers = []
            return buffers
        }
        
        guard !segmentBuffers.isEmpty,
              let originalFormat = recordingOriginalFormat else {
            print("⚠️ [VoiceInputService] 段数据为空，跳过")
            return
        }
        
        let segmentData = segmentBuffers.reduce(Data(), +)
        
        do {
            let segmentRecording = try convertPCMData(
                segmentData,
                originalFormat: originalFormat,
                toSampleRate: recordingSampleRate,
                toChannels: recordingChannels
            )
            
            print("✅ [VoiceInputService] 检测到停顿，准备转文字，段长度=\(segmentRecording.pcmData.count)字节")
            
            // 调用回调进行转文字
            if let callback = onSegmentReady {
                await callback(segmentRecording)
            }
        } catch {
            print("⚠️ [VoiceInputService] 段转换失败: \(error)")
        }
    }
    
    /// 停止录音并返回音频数据
    func stopRecording() async throws -> VoiceRecording? {
        print("🎤 [VoiceInputService] stopRecording() 被调用，当前 isRecording=\(isRecording)")
        
        guard isRecording else {
            print("ℹ️ [VoiceInputService] 未在录音中，返回 nil")
            return nil
        }
        
        // 如果启用分段转文字，处理最后一段
        if enableSegmentTranscription {
            let lastSegmentBuffers: [Data] = recordingDataQueue.sync {
                let buffers = self.currentSegmentBuffers
                self.currentSegmentBuffers = []
                return buffers
            }
            
            if !lastSegmentBuffers.isEmpty {
                print("🎤 [VoiceInputService] 处理最后一段音频")
                let lastSegmentData = lastSegmentBuffers.reduce(Data(), +)
                if let originalFormat = recordingOriginalFormat {
                    do {
                        let lastSegmentRecording = try convertPCMData(
                            lastSegmentData,
                            originalFormat: originalFormat,
                            toSampleRate: recordingSampleRate,
                            toChannels: recordingChannels
                        )
                        if let callback = onSegmentReady {
                            await callback(lastSegmentRecording)
                        }
                    } catch {
                        print("⚠️ [VoiceInputService] 最后一段转换失败: \(error)")
                    }
                }
            }
        }
        
        print("🎤 [VoiceInputService] 停止音频引擎和定时器...")
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        isRecording = false
        audioLevel = 0.0
        
        // 重置停顿检测器
        silenceDetector.reset()
        
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
        
        let combinedData = buffers.reduce(Data(), +)
        do {
            let recording = try convertPCMData(
                combinedData,
                originalFormat: originalFormat,
                toSampleRate: recordingSampleRate,
                toChannels: recordingChannels
            )
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
            }
            
            isRecording = false
            audioLevel = 0.0
        }
    }
    
    private func convertPCMData(_ data: Data, originalFormat: AVAudioFormat, toSampleRate: Double, toChannels: AVAudioChannelCount) throws -> VoiceRecording {
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

