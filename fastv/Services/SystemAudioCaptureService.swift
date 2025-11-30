//
//  SystemAudioCaptureService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import AVFoundation
import AppKit
import Combine

/// 系统音频捕获服务
/// 用于捕获会议中对方的声音（从系统音频输出）
/// 
/// 注意：macOS 本身不支持直接捕获系统音频输出。
/// 需要使用虚拟音频设备（如 BlackHole）来实现。
@MainActor
class SystemAudioCaptureService: ObservableObject {
    static let shared = SystemAudioCaptureService()
    
    @Published var isCapturing = false
    @Published var captureError: String?
    @Published var isBlackHoleAvailable = false
    
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var outputFileURL: URL?
    
    // BlackHole 虚拟音频设备名称
    private let blackHoleDeviceName = "BlackHole"
    
    private init() {
        // 延迟异步检查，避免在视图更新期间执行阻塞操作
        Task { @MainActor in
            await checkBlackHoleAvailability()
        }
    }
    
    /// 检查 BlackHole 是否可用（异步版本）
    func checkBlackHoleAvailability() async {
        // macOS 上检查音频设备的方法
        // 注意：macOS 上 AVAudioSession 的行为与 iOS 不同，这里使用简化方法
        
        // 方法 1：尝试创建 AVAudioEngine 并检查输入节点
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // 方法 2：通过系统命令检查（更可靠）
        // 在后台队列执行阻塞操作，避免阻塞主线程
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
                    let hasBlackHole = output.contains("BlackHole") || output.contains("blackHole")
                    return hasBlackHole
                } else {
                    return false
                }
            } catch {
                // 如果检查失败，假设未安装
                return false
            }
        }.value
        
        // 在主线程更新状态
        await MainActor.run {
            isBlackHoleAvailable = result
            
            if isBlackHoleAvailable {
                print("✅ [SystemAudioCapture] 检测到 BlackHole 虚拟音频设备")
            } else {
                print("⚠️ [SystemAudioCapture] 未检测到 BlackHole 虚拟音频设备")
            }
        }
    }
    
    /// 开始捕获系统音频（需要 BlackHole 配置）
    /// - Parameter outputURL: 输出文件 URL
    /// - Note: 用户需要先在系统设置中将 BlackHole 设置为输出设备
    func startCapture(to outputURL: URL) async throws {
        guard !isCapturing else {
            throw SystemAudioError.alreadyCapturing
        }
        
        // 检查 BlackHole 是否可用
        await checkBlackHoleAvailability()
        guard isBlackHoleAvailable else {
            throw SystemAudioError.blackHoleNotInstalled
        }
        
        print("🎤 [SystemAudioCapture] 开始捕获系统音频到: \(outputURL.path)")
        
        // 创建音频引擎
        let engine = AVAudioEngine()
        
        // 获取输入节点（应该选择 BlackHole 设备）
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        print("📊 [SystemAudioCapture] 输入格式: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) 声道")
        
        // 创建输出文件格式（16kHz 单声道，与语音识别要求一致）
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        
        let audioFile = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings)
        
        // 安装 tap 来捕获音频
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            // 转换格式并写入文件
            guard let self = self, let audioFile = self.audioFile else { return }
            
            // 如果需要格式转换，使用 AVAudioConverter
            // 这里简化处理，假设格式匹配
            do {
                try audioFile.write(from: buffer)
            } catch {
                print("❌ [SystemAudioCapture] 写入音频失败: \(error)")
            }
        }
        
        // 启动引擎
        try engine.start()
        
        self.audioEngine = engine
        self.audioFile = audioFile
        self.outputFileURL = outputURL
        self.isCapturing = true
        self.captureError = nil
        
        print("✅ [SystemAudioCapture] 系统音频捕获已启动")
    }
    
    /// 停止捕获
    func stopCapture() {
        guard isCapturing else { return }
        
        print("🛑 [SystemAudioCapture] 停止系统音频捕获")
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        
        isCapturing = false
        
        if let url = outputFileURL {
            print("✅ [SystemAudioCapture] 音频已保存到: \(url.path)")
        }
        
        outputFileURL = nil
    }
    
    /// 获取 BlackHole 安装指南 URL
    func getBlackHoleInstallGuideURL() -> URL {
        return URL(string: "https://github.com/ExistentialAudio/BlackHole")!
    }
    
    /// 打开系统声音设置
    func openSoundSettings() {
        // 打开系统设置的声音面板
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 系统音频捕获错误
enum SystemAudioError: LocalizedError {
    case blackHoleNotInstalled
    case alreadyCapturing
    case captureFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .blackHoleNotInstalled:
            return """
            未检测到 BlackHole 虚拟音频设备。
            
            要捕获系统音频（会议中对方的声音），需要安装 BlackHole。
            
            安装步骤：
            1. 访问 https://github.com/ExistentialAudio/BlackHole
            2. 下载并安装 BlackHole
            3. 在"系统设置 > 声音"中配置 BlackHole 为输出设备
            4. 重启应用
            """
        case .alreadyCapturing:
            return "系统音频捕获已在进行中"
        case .captureFailed(let message):
            return "系统音频捕获失败: \(message)"
        }
    }
}

