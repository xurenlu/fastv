//
//  SilenceDetector.swift
//  fastv
//
//  Created by rocky on 2025/11/28.
//

import Foundation
import Combine

/// 静音段检测结果
struct SilenceDetection {
    let isSilent: Bool
    let duration: TimeInterval  // 当前静音持续时长
}

/// 静音检测器 - 用于实时检测音频中的静音段
@MainActor
class SilenceDetector: ObservableObject {
    // 配置参数
    var silenceThreshold: Float = 0.01        // RMS绝对阈值,低于此值视为静音
    var relativeThreshold: Float = 0.3         // 相对阈值百分比(0.3表示30%),当电平下降到峰值的此百分比时也视为静音
    var minimumSilenceDuration: TimeInterval = 1.5  // 最短静音持续时长(秒)
    var windowSize: Int = 10                  // 滑动窗口大小(采样点数)
    
    // 状态
    @Published private(set) var isSilent = false
    @Published private(set) var currentSilenceDuration: TimeInterval = 0
    
    private var audioLevelHistory: [Float] = []
    private var silenceStartTime: Date?
    private var lastUpdateTime: Date = Date()
    
    // 相对检测相关
    private var speechPeakLevel: Float = 0.0   // 说话时的峰值电平
    private var hasDetectedSpeech: Bool = false // 是否已检测到说话(用于判断是否可以使用相对阈值)
    
    // 回调
    var onSilenceDetected: ((TimeInterval) -> Void)?
    var onSpeechDetected: (() -> Void)?
    
    init() {}
    
    /// 重置检测器
    func reset() {
        audioLevelHistory.removeAll()
        silenceStartTime = nil
        isSilent = false
        currentSilenceDuration = 0
        lastUpdateTime = Date()
        speechPeakLevel = 0.0
        hasDetectedSpeech = false
    }
    
    /// 处理新的音频电平数据
    /// - Parameter level: 音频RMS电平值
    /// - Returns: 检测结果
    @discardableResult
    func processAudioLevel(_ level: Float) -> SilenceDetection {
        let now = Date()
        
        // 添加到历史记录
        audioLevelHistory.append(level)
        if audioLevelHistory.count > windowSize {
            audioLevelHistory.removeFirst()
        }
        
        // 计算滑动窗口平均值(平滑处理)
        let averageLevel = audioLevelHistory.reduce(0, +) / Float(audioLevelHistory.count)
        
        // 更新说话峰值电平(用于相对检测)
        if level > speechPeakLevel {
            speechPeakLevel = level
            hasDetectedSpeech = true
        }
        
        // 混合检测：绝对阈值 OR 相对下降检测
        let absoluteSilent = averageLevel < silenceThreshold
        var relativeSilent = false
        
        // 只有在已检测到说话且峰值足够大时才使用相对检测
        if hasDetectedSpeech && speechPeakLevel > silenceThreshold * 2 {
            let relativeThresholdLevel = speechPeakLevel * relativeThreshold
            relativeSilent = averageLevel < relativeThresholdLevel
        }
        
        // 判断是否静音(混合检测)
        let currentIsSilent = absoluteSilent || relativeSilent
        
        if currentIsSilent {
            // 静音状态
            if !isSilent {
                // 刚进入静音
                silenceStartTime = now
                isSilent = true
                let detectionType = absoluteSilent ? "绝对阈值" : "相对下降"
                print("🔇 [SilenceDetector] 检测到静音开始(\(detectionType)), 当前电平=\(String(format: "%.4f", averageLevel)), 峰值=\(String(format: "%.4f", speechPeakLevel))")
            }
            
            // 计算静音持续时长
            if let startTime = silenceStartTime {
                currentSilenceDuration = now.timeIntervalSince(startTime)
                
                // 如果达到最小静音时长,触发回调(只触发一次)
                if currentSilenceDuration >= minimumSilenceDuration {
                    let shouldTrigger = (currentSilenceDuration - minimumSilenceDuration) < 0.2 // 容差200ms
                    if shouldTrigger {
                        print("🔇 [SilenceDetector] 检测到有效静音段,持续时长: \(String(format: "%.2f", currentSilenceDuration))秒")
                        onSilenceDetected?(currentSilenceDuration)
                    }
                }
            }
        } else {
            // 有声音
            if isSilent {
                // 从静音恢复到有声
                print("🔊 [SilenceDetector] 检测到语音恢复")
                onSpeechDetected?()
                // 重置峰值,为下一段说话做准备
                speechPeakLevel = 0.0
                hasDetectedSpeech = false
            }
            isSilent = false
            silenceStartTime = nil
            currentSilenceDuration = 0
        }
        
        lastUpdateTime = now
        
        return SilenceDetection(isSilent: currentIsSilent, duration: currentSilenceDuration)
    }
    
    /// 获取当前状态描述
    func getStatusDescription() -> String {
        if isSilent {
            return "静音中 (\(String(format: "%.1f", currentSilenceDuration))s)"
        } else {
            return "说话中"
        }
    }
}

