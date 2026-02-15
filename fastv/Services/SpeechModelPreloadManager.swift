//
//  SpeechModelPreloadManager.swift
//  fastv
//
//  应用启动时预加载语音识别模型，首次语音输入即可直接使用
//

import Foundation
import SwiftUI

/// 语音模型预加载状态管理
/// 应用启动时若有模型文件则后台预加载，显示启动屏转移注意力
final class SpeechModelPreloadManager: ObservableObject {
    static let shared = SpeechModelPreloadManager()
    
    /// 是否正在预加载
    @Published private(set) var isPreloading = false
    
    /// 预加载是否已完成（含跳过：无模型时）
    @Published private(set) var isPreloadComplete = false
    
    /// 预加载耗时（秒），用于日志
    @Published private(set) var preloadDuration: Double = 0
    
    private init() {}
    
    /// 启动预加载流程
    /// 若有模型文件则预加载并显示启动屏，否则直接完成
    func startPreloadIfNeeded() {
        guard !SpeechTranscriptionModel.hasModelFile() else {
            // 有模型文件，开始预加载
            isPreloading = true
            isPreloadComplete = false
            let startTime = CFAbsoluteTimeGetCurrent()
            
            Task.detached(priority: .userInitiated) { [weak self] in
                let loaded = await SpeechTranscriptionModel.shared.preload()
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                
                await MainActor.run {
                    self?.isPreloading = false
                    self?.isPreloadComplete = true
                    self?.preloadDuration = duration
                    if loaded {
                        print("✅ [SpeechModelPreload] 模型预加载完成，耗时: \(String(format: "%.2f", duration)) 秒")
                    } else {
                        print("⚠️ [SpeechModelPreload] 模型预加载跳过或失败")
                    }
                }
            }
            return
        }
        
        // 无模型文件，直接完成
        isPreloadComplete = true
        print("ℹ️ [SpeechModelPreload] 无模型文件，跳过预加载")
    }
}
