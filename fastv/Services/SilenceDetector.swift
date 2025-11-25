//
//  SilenceDetector.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import AVFoundation

/// 停顿检测服务
/// 用于检测音频中的静音/低音量段，实现智能分段转文字
@MainActor
class SilenceDetector: ObservableObject {
    static let shared = SilenceDetector()
    
    /// 停顿阈值（默认1.5秒）
    var silenceThreshold: TimeInterval = 1.5
    
    /// 音量阈值（低于此值认为是静音）
    var volumeThreshold: Float = 0.01
    
    /// 检测到停顿的回调
    var onSilenceDetected: (() -> Void)?
    
    private var lastSoundTime: Date?
    private var isInSilence = false
    private var silenceStartTime: Date?
    
    private init() {}
    
    /// 处理音频电平数据
    /// - Parameter audioLevel: 音频电平（RMS值，0.0-1.0）
    func processAudioLevel(_ audioLevel: Float) {
        let now = Date()
        
        if audioLevel > volumeThreshold {
            // 检测到声音
            lastSoundTime = now
            isInSilence = false
            silenceStartTime = nil
        } else {
            // 检测到静音
            if !isInSilence {
                // 刚进入静音状态
                isInSilence = true
                silenceStartTime = now
            } else {
                // 已经在静音状态中
                if let silenceStart = silenceStartTime {
                    let silenceDuration = now.timeIntervalSince(silenceStart)
                    if silenceDuration >= silenceThreshold {
                        // 检测到足够长的停顿
                        if let callback = onSilenceDetected {
                            callback()
                            // 重置状态，避免重复触发
                            silenceStartTime = nil
                            isInSilence = false
                        }
                    }
                }
            }
        }
    }
    
    /// 重置检测状态
    func reset() {
        lastSoundTime = nil
        isInSilence = false
        silenceStartTime = nil
    }
}

