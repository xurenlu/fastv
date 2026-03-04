//
//  VoiceInputService.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AVFoundation
import Combine
import CoreAudio

/// 语音输入服务
/// 支持同时录制麦克风和系统音频（需要 BlackHole 虚拟音频设备）
@MainActor
class VoiceInputService: ObservableObject {
    static let shared = VoiceInputService()
    
    @Published private(set) var isRecording = false
    @Published private(set) var audioLevel: Float = 0.0 // 用于波形显示
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var isSystemAudioAvailable = false  // 系统音频是否可用
    @Published private(set) var systemAudioStatus: String = ""  // 系统音频状态说明
    
    private var audioEngine: AVAudioEngine?
    private var systemAudioEngine: AVAudioEngine?  // 用于捕获系统音频的独立引擎
    private var mixerNode: AVAudioMixerNode?
    private var audioLevelTimer: Timer?
    // 跟踪 tap 安装状态，确保正确清理
    private var isMicTapInstalled = false
    private var isSystemAudioTapInstalled = false
    private var engineConfigObserver: NSObjectProtocol?
    nonisolated(unsafe) private var recordedBuffers: [Data] = []
    private var recordingOriginalFormat: AVAudioFormat?
    private let recordingSampleRate: Double = 16000
    private let recordingChannels: AVAudioChannelCount = 1
    private let recordingDataQueue = DispatchQueue(label: "voiceInput.recordingDataQueue")
    
    // 分段录音支持
    private var recordingStartTime: Date?
    private var lastSegmentTime: Date?
    nonisolated(unsafe) private var segmentBuffers: [Data] = []  // 当前段落的缓冲
    
    // 系统音频缓冲（用于混合）
    nonisolated(unsafe) private var systemAudioBuffers: [Data] = []
    private let systemAudioQueue = DispatchQueue(label: "voiceInput.systemAudioQueue")
    
    // 音频数据回调，用于波形显示
    var onAudioData: ((Float) -> Void)?
    
    // 分段回调 - 当检测到静音段时触发
    var onSegmentReady: ((Data, TimeInterval, TimeInterval) -> Void)?
    
    // 实时转换后的音频数据回调 - 用于实时保存 WAV 文件
    // 参数：转换后的 PCM 数据（Int16 格式，16kHz 单声道）
    var onConvertedAudioData: ((Data) -> Void)?
    
    // 缓冲区大小限制（防止内存泄漏）
    // 按照 48kHz * 4字节/样本 * 30秒 ≈ 5.8MB，限制为 10MB（降低内存占用）
    private let maxBufferSizeBytes = 10 * 1024 * 1024
    private var currentBufferSizeBytes = 0
    private var currentSegmentSizeBytes = 0

    // 系统音频缓冲区限制（防止内存问题）
    private let maxSystemAudioBuffers = 50  // 减半
    private let maxSystemAudioBytes = 3 * 1024 * 1024  // 3MB（降低）
    nonisolated(unsafe) private var currentSystemAudioBytes = 0
    
    private init() {
        // 初始化时检查系统音频可用性
        Task { @MainActor in
            await checkSystemAudioAvailability()
        }
    }
    
    deinit {
        // 確保資源被正確釋放
        print("🧹 [VoiceInputService] deinit - 清理資源")
        audioLevelTimer?.invalidate()
        
        // 注意：由於是 @MainActor 類，這裡需要小心處理
        // 但至少確保 Timer 被清理
    }
    
    // MARK: - 系统音频检测
    
    /// 检查系统音频（BlackHole）是否可用
    func checkSystemAudioAvailability() async {
        let result = await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPAudioDataType"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    return output.contains("BlackHole") || output.contains("blackHole")
                }
                return false
            } catch {
                return false
            }
        }.value
        
        isSystemAudioAvailable = result
        if result {
            systemAudioStatus = "系统音频录制已启用"
            print("✅ [VoiceInputService] BlackHole 虚拟音频设备可用，支持系统音频录制")
        } else {
            systemAudioStatus = "仅录制麦克风（安装 BlackHole 可录制系统音频）"
            print("⚠️ [VoiceInputService] BlackHole 未安装，仅使用麦克风录制")
        }
    }
    
    /// 配置 AVAudioSession 以优化蓝牙设备支持
    /// 蓝牙设备（如 AirPods、其他蓝牙耳机）需要特定的会话配置才能稳定工作
    private func configureAudioSessionForBluetooth() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // 设置为录音和播放模式，允许蓝牙输入和输出
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
            )

            // 设置首选采样率（蓝牙设备通常使用 16kHz）
            try session.setPreferredSampleRate(16000)

            // 设置首选 IO 缓冲区时长
            // 对于实时对话，较长的缓冲区可以减少蓝牙丢帧，但会增加延迟
            // 0.02 秒 = 20ms，在延迟和稳定性之间取得平衡
            try session.setPreferredIOBufferDuration(0.02)

            // 激活会话
            try session.setActive(true)

            print("✅ [VoiceInputService] AVAudioSession 配置成功:")
            print("   - Category: \(session.category.rawValue)")
            print("   - Mode: \(session.mode.rawValue)")
            print("   - Sample Rate: \(session.sampleRate) Hz")
            print("   - IO Buffer Duration: \(session.ioBufferDuration) 秒")
            print("   - Input Available: \(session.isInputAvailable)")
            if let inputRoute = session.currentRoute.inputs.first {
                print("   - Input Route: \(inputRoute.portName) (type: \(inputRoute.portType.rawValue))")
            }
        } catch {
            print("⚠️ [VoiceInputService] AVAudioSession 配置失败: \(error)")
            // 配置失败不影响继续录音，使用系统默认设置
        }
        #else
        // macOS 不使用 AVAudioSession，使用 AVAudioEngine 即可
        print("ℹ️ [VoiceInputService] macOS 平台，跳过 AVAudioSession 配置")
        #endif
    }

    /// 停用 AVAudioSession（iOS 上）
    private func deactivateAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false)
            print("✅ [VoiceInputService] AVAudioSession 已停用")
        } catch {
            print("⚠️ [VoiceInputService] AVAudioSession 停用失败: \(error)")
        }
        #endif
    }

    /// 获取 BlackHole 设备 ID
    nonisolated private func getBlackHoleDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else { return nil }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else { return nil }
        
        for deviceID in deviceIDs {
            var namePropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var deviceName: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            
            status = AudioObjectGetPropertyData(
                deviceID,
                &namePropertyAddress,
                0,
                nil,
                &nameSize,
                &deviceName
            )
            
            if status == noErr {
                let name = deviceName as String
                if name.lowercased().contains("blackhole") {
                    return deviceID
                }
            }
        }
        
        return nil
    }
    
    /// 检测当前音频输入设备是否为蓝牙设备
    private func isBluetoothDevice() -> Bool {
        #if os(macOS)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        ) == noErr else { return false }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else { return false }

        // 获取当前输入设备
        var inputDeviceID = AudioDeviceID()
        var inputDeviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var inputDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &inputDeviceAddress,
            0,
            nil,
            &inputDeviceSize,
            &inputDeviceID
        ) == noErr else { return false }

        // 检查当前输入设备是否为蓝牙设备
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType = UInt32()
        var transportSize = UInt32(MemoryLayout<UInt32>.size)

        guard AudioObjectGetPropertyData(
            inputDeviceID,
            &transportAddress,
            0,
            nil,
            &transportSize,
            &transportType
        ) == noErr else { return false }

        // kAudioDeviceTransportTypeBluetooth = 0x0004
        // kAudioDeviceTransportTypeBluetoothLE = 0x0012
        return transportType == 0x0004 || transportType == 0x0012
        #else
        // iOS: 通过 AVAudioSession 检查
        let session = AVAudioSession.sharedInstance()
        guard let route = session.currentRoute.inputs.first else { return false }
        return route.portType == .bluetoothA2DP ||
               route.portType == .bluetoothHFP ||
               route.portType == .bluetoothLE
        #endif
    }

    /// 开始录音（同时录制麦克风和系统音频）
    func startRecording() throws {
        print("🎤 [VoiceInputService] startRecording() 被调用，当前 isRecording=\(isRecording)")

        guard !isRecording else {
            print("ℹ️ [VoiceInputService] 已在录音中，跳过")
            return
        }

        // 配置 AVAudioSession 以优化蓝牙设备支持
        configureAudioSessionForBluetooth()

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
        
        // 重置录音数据容器和大小计数器
        recordingDataQueue.sync {
            self.recordedBuffers = []
            self.segmentBuffers = []
            self.currentBufferSizeBytes = 0
            self.currentSegmentSizeBytes = 0
        }
        systemAudioQueue.sync {
            self.systemAudioBuffers = []
            self.currentSystemAudioBytes = 0
        }
        recordingStartTime = Date()
        lastSegmentTime = Date()
        recordingDuration = 0
        
        // 创建主音频引擎（麦克风）
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        print("✅ [VoiceInputService] 麦克风输入格式: \(format)")
        recordingOriginalFormat = format

        // 安装 tap 来捕获麦克风音频
        // 检测是否为蓝牙设备，使用更大的缓冲区以减少丢帧
        let isBluetooth = isBluetoothDevice()
        let bufferSize: AVAudioFrameCount
        if isBluetooth {
            // 蓝牙设备需要更大的缓冲区来减少丢帧和卡顿
            // 8192 帧在 48kHz 下约 170ms，在 16kHz 下约 512ms
            bufferSize = 8192
            print("🎤 [VoiceInputService] 检测到蓝牙设备，使用更大的缓冲区")
        } else if format.sampleRate >= 44100 {
            bufferSize = 4096  // 高采样率下约 85-93ms
        } else {
            bufferSize = 2048  // 低采样率下约 128ms
        }
        print("🎤 [VoiceInputService] 使用缓冲区大小: \(bufferSize) 帧 (约 \(Double(bufferSize) / format.sampleRate * 1000)ms), 蓝牙: \(isBluetooth)")
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            self.processMicrophoneBuffer(buffer)
        }
        isMicTapInstalled = true

        self.audioEngine = engine

        // 尝试启动系统音频捕获（如果 BlackHole 可用）
        if isSystemAudioAvailable {
            startSystemAudioCapture()
        }

        // 启动麦克风引擎
        do {
            print("🎤 [VoiceInputService] 启动麦克风音频引擎...")
            try engine.start()
            isRecording = true
            print("✅ [VoiceInputService] 麦克风音频引擎已启动")

            // 监听音频引擎配置变更（蓝牙设备断开等），自动恢复录音
            engineConfigObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleAudioEngineConfigurationChange()
                }
            }

            // 启动音频电平更新定时器
            audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
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
                        if let startTime = strongSelf.recordingStartTime {
                            strongSelf.recordingDuration = Date().timeIntervalSince(startTime)
                        }
                    }
                }
            }
            print("✅ [VoiceInputService] 音频电平定时器已启动")
        } catch {
            print("❌ [VoiceInputService] 启动音频引擎失败: \(error)")
            // 启动失败时清理 tap
            cleanupAudioTap()
            throw VoiceInputError.failedToStartRecording(error.localizedDescription)
        }
    }

    /// 强制释放麦克风（用于应用退出/崩溃时的同步清理，不处理录音数据）
    /// 确保状态栏的橙色麦克风图标能及时消失
    func forceReleaseMicrophone() {
        guard isRecording else { return }
        print("🧹 [VoiceInputService] forceReleaseMicrophone() - 应用退出时强制释放麦克风")
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        cleanupAudioTap()
        audioEngine?.stop()
        audioEngine = nil
        systemAudioEngine?.stop()
        systemAudioEngine = nil
        onAudioData = nil
        onSegmentReady = nil
        onConvertedAudioData = nil
        isRecording = false
        audioLevel = 0.0
        print("✅ [VoiceInputService] 麦克风已释放")
    }

    /// 清理音频 tap（确保在所有退出路径中调用）
    private func cleanupAudioTap() {
        if isMicTapInstalled, let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            isMicTapInstalled = false
            print("🧹 [VoiceInputService] 已移除麦克风 tap")
        }
        if isSystemAudioTapInstalled, let sysEngine = systemAudioEngine {
            sysEngine.inputNode.removeTap(onBus: 0)
            isSystemAudioTapInstalled = false
            print("🧹 [VoiceInputService] 已移除系统音频 tap")
        }
        if let observer = engineConfigObserver {
            NotificationCenter.default.removeObserver(observer)
            engineConfigObserver = nil
        }
    }

    /// 音频引擎配置变更时（蓝牙断开/音频设备切换）尝试恢复录音
    private func handleAudioEngineConfigurationChange() {
        guard isRecording, let engine = audioEngine else { return }
        print("⚠️ [VoiceInputService] 检测到音频设备配置变更，尝试恢复录音")

        let newFormat = engine.inputNode.inputFormat(forBus: 0)
        guard newFormat.sampleRate > 0, newFormat.channelCount > 0 else {
            print("❌ [VoiceInputService] 新的音频格式无效（设备可能已断开），等待设备恢复")
            return
        }

        if isMicTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isMicTapInstalled = false
        }

        recordingOriginalFormat = newFormat
        let isBluetooth = isBluetoothDevice()
        let bufferSize: AVAudioFrameCount = isBluetooth ? 8192 : (newFormat.sampleRate >= 44100 ? 4096 : 2048)

        engine.inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: newFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.processMicrophoneBuffer(buffer)
        }
        isMicTapInstalled = true

        do {
            try engine.start()
            print("✅ [VoiceInputService] 音频引擎已恢复，新格式: \(newFormat)")
        } catch {
            print("❌ [VoiceInputService] 音频引擎恢复失败: \(error)")
        }
    }
    
    /// 处理麦克风音频缓冲
    nonisolated private func processMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
        // 计算音频电平（用于波形显示和静音检测）
        if let channelData = buffer.floatChannelData {
            let channelDataValue = channelData.pointee
            let frameCount = Int(buffer.frameLength)
            let channelDataValueArray = stride(from: 0, to: frameCount, by: 1).map { channelDataValue[$0] }
            
            // 计算RMS（原始值用于静音检测）
            let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(channelDataValueArray.count))
            
            // 将 RMS 值放大并归一化到 0-1 范围（用于波形显示）
            let displayLevel: Float
            if rms > 0.0001 {
                let logRms = log10(max(rms, 0.001))
                let normalized = (logRms + 3.0) / 2.7
                displayLevel = min(max(normalized, 0.05), 1.0)
            } else {
                displayLevel = 0.05
            }
            
            Task { @MainActor [weak self] in
                self?.audioLevel = displayLevel
                self?.onAudioData?(rms)
            }
        }
        
        // 写入缓冲（混合麦克风和系统音频）
        if let channelData = buffer.floatChannelData {
            let frames = Int(buffer.frameLength)
            let byteCount = frames * MemoryLayout<Float>.size
            let pcmPointer = channelData.pointee
            var micData = Data(bytes: pcmPointer, count: byteCount)
            
            // 尝试混合系统音频
            systemAudioQueue.sync {
                if !self.systemAudioBuffers.isEmpty {
                    // 取出对应大小的系统音频数据进行混合
                    let systemData = self.systemAudioBuffers.removeFirst()
                    micData = self.mixAudioData(micData, with: systemData)
                }
            }
            
            recordingDataQueue.async {
                let dataSize = micData.count
                
                // 檢查緩衝區大小限制，防止內存泄漏
                if self.currentBufferSizeBytes + dataSize > self.maxBufferSizeBytes {
                    // 達到限制時，移除最舊的數據
                    while self.currentBufferSizeBytes + dataSize > self.maxBufferSizeBytes && !self.recordedBuffers.isEmpty {
                        let removed = self.recordedBuffers.removeFirst()
                        self.currentBufferSizeBytes -= removed.count
                    }
                    print("⚠️ [VoiceInputService] 緩衝區達到上限，移除舊數據以防止內存泄漏")
                }
                
                self.recordedBuffers.append(micData)
                self.segmentBuffers.append(micData)
                self.currentBufferSizeBytes += dataSize
                self.currentSegmentSizeBytes += dataSize
            }
        }
    }
    
    /// 启动系统音频捕获
    private func startSystemAudioCapture() {
        // 注意：在 macOS 上，使用 BlackHole 需要用户在系统设置中配置
        // 这里我们尝试创建一个独立的引擎来捕获系统音频
        // 但这需要用户将 BlackHole 设置为系统输入设备之一

        print("🔊 [VoiceInputService] 尝试启动系统音频捕获...")

        // 检查 BlackHole 设备
        guard let blackHoleID = getBlackHoleDeviceID() else {
            print("⚠️ [VoiceInputService] 未找到 BlackHole 设备 ID，跳过系统音频捕获")
            return
        }

        print("✅ [VoiceInputService] 找到 BlackHole 设备 ID: \(blackHoleID)")

        // 创建系统音频引擎
        let sysEngine = AVAudioEngine()
        let sysInputNode = sysEngine.inputNode

        // 尝试设置输入设备为 BlackHole
        do {
            try setAudioInputDevice(blackHoleID, for: sysEngine)
        } catch {
            print("⚠️ [VoiceInputService] 无法设置 BlackHole 为输入设备: \(error)")
            print("💡 [VoiceInputService] 请在系统设置中将 BlackHole 添加到输入设备")
            return
        }

        let sysFormat = sysInputNode.inputFormat(forBus: 0)
        print("✅ [VoiceInputService] 系统音频输入格式: \(sysFormat)")

        // 安装 tap 来捕获系统音频
        // 使用与麦克风相同的缓冲区大小策略（包括蓝牙检测）
        let isBluetooth = isBluetoothDevice()
        let sysBufferSize: AVAudioFrameCount
        if isBluetooth {
            sysBufferSize = 8192
        } else if sysFormat.sampleRate >= 44100 {
            sysBufferSize = 4096
        } else {
            sysBufferSize = 2048
        }
        sysInputNode.installTap(onBus: 0, bufferSize: sysBufferSize, format: sysFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            self.processSystemAudioBuffer(buffer)
        }
        isSystemAudioTapInstalled = true

        // 启动系统音频引擎
        do {
            try sysEngine.start()
            self.systemAudioEngine = sysEngine
            print("✅ [VoiceInputService] 系统音频引擎已启动")
        } catch {
            print("⚠️ [VoiceInputService] 启动系统音频引擎失败: \(error)")
            // 失败时清理 tap
            if isSystemAudioTapInstalled {
                sysInputNode.removeTap(onBus: 0)
                isSystemAudioTapInstalled = false
            }
        }
    }
    
    /// 处理系统音频缓冲
    nonisolated private func processSystemAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        if let channelData = buffer.floatChannelData {
            let frames = Int(buffer.frameLength)
            let byteCount = frames * MemoryLayout<Float>.size
            let pcmPointer = channelData.pointee
            let data = Data(bytes: pcmPointer, count: byteCount)

            systemAudioQueue.async {
                // 同时检查缓冲区数量和字节大小
                while (self.systemAudioBuffers.count >= self.maxSystemAudioBuffers ||
                       self.currentSystemAudioBytes >= self.maxSystemAudioBytes),
                      !self.systemAudioBuffers.isEmpty {
                    let removed = self.systemAudioBuffers.removeFirst()
                    self.currentSystemAudioBytes -= removed.count
                }

                self.systemAudioBuffers.append(data)
                self.currentSystemAudioBytes += byteCount

                // 监控和警告
                if self.systemAudioBuffers.count > self.maxSystemAudioBuffers / 2 {
                    print("⚠️ [VoiceInputService] 系统音频缓冲区使用: \(self.systemAudioBuffers.count)/\(self.maxSystemAudioBuffers), \(self.currentSystemAudioBytes / 1024)KB/\(self.maxSystemAudioBytes / 1024)KB")
                }
            }
        }
    }
    
    /// 混合两路音频数据
    nonisolated private func mixAudioData(_ data1: Data, with data2: Data) -> Data {
        let count1 = data1.count / MemoryLayout<Float>.size
        let count2 = data2.count / MemoryLayout<Float>.size
        let minCount = min(count1, count2)
        
        guard minCount > 0 else { return data1 }
        
        var result = [Float](repeating: 0, count: count1)
        
        data1.withUnsafeBytes { ptr1 in
            if let baseAddress1 = ptr1.baseAddress?.assumingMemoryBound(to: Float.self) {
                for i in 0..<count1 {
                    result[i] = baseAddress1[i]
                }
            }
        }
        
        data2.withUnsafeBytes { ptr2 in
            if let baseAddress2 = ptr2.baseAddress?.assumingMemoryBound(to: Float.self) {
                for i in 0..<minCount {
                    // 简单混合：两路信号相加后除以2
                    result[i] = (result[i] + baseAddress2[i]) * 0.5
                }
            }
        }
        
        return Data(bytes: result, count: count1 * MemoryLayout<Float>.size)
    }
    
    /// 设置音频输入设备
    nonisolated private func setAudioInputDevice(_ deviceID: AudioDeviceID, for engine: AVAudioEngine) throws {
        let inputNode = engine.inputNode
        let audioUnit = inputNode.audioUnit!
        
        var deviceIDVar = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDVar,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        
        if status != noErr {
            throw VoiceInputError.failedToStartRecording("无法设置音频输入设备: \(status)")
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

        // 清理所有 tap
        cleanupAudioTap()

        // 停止麦克风引擎
        audioEngine?.stop()
        audioEngine = nil

        // 停止系统音频引擎
        systemAudioEngine?.stop()
        systemAudioEngine = nil

        // 清空系统音频缓冲
        systemAudioQueue.sync {
            self.systemAudioBuffers = []
            self.currentSystemAudioBytes = 0
        }

        // 停用 AVAudioSession（iOS 上）
        #if os(iOS)
        deactivateAudioSession()
        #endif

        // 清空回調，避免循環引用
        onAudioData = nil
        onSegmentReady = nil
        // 注意：onConvertedAudioData 在使用後再清空

        isRecording = false
        audioLevel = 0.0
        
        let buffers: [Data] = recordingDataQueue.sync {
            let result = self.recordedBuffers
            // 彻底清理所有录音相关缓冲，防止内存累积
            self.recordedBuffers = []
            self.segmentBuffers = []
            self.currentBufferSizeBytes = 0
            self.currentSegmentSizeBytes = 0
            return result
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
        let onConverted = self.onConvertedAudioData
        
        // 如果启用了实时保存回调，分批转换并实时保存
        if onConverted != nil {
            // 分批处理音频数据，每批约2秒的数据（16kHz * 2秒 * 4字节 = 128KB）
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
                        if let callback = self.onConvertedAudioData {
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

            // 清理所有 tap
            cleanupAudioTap()

            // 停止麦克风引擎
            audioEngine?.stop()
            audioEngine = nil

            // 停止系统音频引擎
            systemAudioEngine?.stop()
            systemAudioEngine = nil

            recordingDataQueue.sync {
                self.recordedBuffers = []
                self.segmentBuffers = []
                self.currentBufferSizeBytes = 0
                self.currentSegmentSizeBytes = 0
            }

            systemAudioQueue.sync {
                self.systemAudioBuffers = []
                self.currentSystemAudioBytes = 0
            }

            // 清空回調，避免循環引用
            onAudioData = nil
            onSegmentReady = nil
            onConvertedAudioData = nil

            isRecording = false
            audioLevel = 0.0
            recordingDuration = 0
            recordingStartTime = nil
            lastSegmentTime = nil
        }
    }

    /// 強制清理所有資源（用於調試內存泄漏時調用）
    func forceCleanup() {
        print("🧹 [VoiceInputService] forceCleanup() - 強制清理所有資源")

        audioLevelTimer?.invalidate()
        audioLevelTimer = nil

        // 清理所有 tap
        cleanupAudioTap()

        // 停止所有引擎
        audioEngine?.stop()
        audioEngine = nil

        systemAudioEngine?.stop()
        systemAudioEngine = nil
        
        // 清空所有緩衝區
        recordingDataQueue.sync {
            self.recordedBuffers = []
            self.segmentBuffers = []
            self.currentBufferSizeBytes = 0
            self.currentSegmentSizeBytes = 0
        }
        
        systemAudioQueue.sync {
            self.systemAudioBuffers = []
            self.currentSystemAudioBytes = 0
        }
        
        // 清空所有回調
        onAudioData = nil
        onSegmentReady = nil
        onConvertedAudioData = nil
        
        isRecording = false
        audioLevel = 0.0
        recordingDuration = 0
        recordingStartTime = nil
        lastSegmentTime = nil
        recordingOriginalFormat = nil
        
        print("✅ [VoiceInputService] 強制清理完成")
    }
    
    /// 段落提取结果
    struct SegmentResult {
        let recording: VoiceRecording
        let startTime: TimeInterval
        let endTime: TimeInterval
        var duration: TimeInterval { endTime - startTime }
    }
    
    /// 提取当前段落的音频数据(用于增量转写)
    /// - Returns: 当前段落的PCM数据,如果数据为空则返回nil
    func extractCurrentSegment() async throws -> VoiceRecording? {
        let result = try await extractCurrentSegmentWithTiming()
        return result?.recording
    }
    
    /// 提取当前段落的音频数据及时间信息
    /// - Returns: 段落结果包含录音数据和时间信息
    func extractCurrentSegmentWithTiming() async throws -> SegmentResult? {
        guard isRecording else {
            print("⚠️ [VoiceInputService] 未在录音中,无法提取段落")
            return nil
        }
        
        guard let originalFormat = recordingOriginalFormat else {
            print("⚠️ [VoiceInputService] 未知录音格式")
            return nil
        }
        
        // 记录段落开始时间（提取前）
        let segmentStartTime = getLastSegmentTime()
        let segmentEndTime = recordingDuration
        
        // 获取当前段落的缓冲数据
        let buffers: [Data] = recordingDataQueue.sync {
            let result = self.segmentBuffers
            self.segmentBuffers = []  // 清空段落缓冲,开始新段落
            self.currentSegmentSizeBytes = 0
            return result
        }
        
        guard !buffers.isEmpty else {
            print("⚠️ [VoiceInputService] 段落数据为空")
            return nil
        }
        
        // 更新段落时间（提取后）
        lastSegmentTime = Date()
        
        let combinedData = buffers.reduce(Data(), +)
        let duration = segmentEndTime - segmentStartTime
        print("📊 [VoiceInputService] 提取段落数据: \(combinedData.count) 字节, 时长: \(String(format: "%.1f", duration))秒")
        
        // 提取需要的参数值，避免在后台任务中访问实例属性
        let sampleRate = recordingSampleRate
        let channels = recordingChannels
        
        // 将转码操作移到后台线程，避免阻塞 UI
        let recording = try await Task.detached(priority: .userInitiated) {
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
        
        return SegmentResult(recording: recording, startTime: segmentStartTime, endTime: segmentEndTime)
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

        var error: NSError?
        // 使用 os_unfair_lock 替代 NSLock，性能更好且避免死锁风险
        var inputExhaustedLock = os_unfair_lock()
        let inputExhaustedRef = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        inputExhaustedRef.initialize(to: false)
        defer {
            inputExhaustedRef.deinitialize(count: 1)
            inputExhaustedRef.deallocate()
        }

        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            // 使用 os_unfair_lock 确保只提供一次数据
            os_unfair_lock_lock(&inputExhaustedLock)
            defer { os_unfair_lock_unlock(&inputExhaustedLock) }

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

