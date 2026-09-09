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
@MainActor
@Observable
final class SpeechModelPreloadManager {
    static let shared = SpeechModelPreloadManager()
    
    /// 是否正在预加载
    private(set) var isPreloading = false
    
    /// 预加载是否已完成（含跳过：无模型时）
    private(set) var isPreloadComplete = false
    
    /// 预加载耗时（秒），用于日志
    private(set) var preloadDuration: Double = 0

    private var interactiveWarmUpTask: Task<Void, Never>?
    
    private init() {}
    
    /// 启动预加载流程
    /// 若有模型文件则预加载并显示启动屏，否则直接完成
    func startPreloadIfNeeded() {
        guard !Self.isRunningUnderXCTest else {
            isPreloading = false
            isPreloadComplete = true
            preloadDuration = 0
            print("ℹ️ [SpeechModelPreload] XCTest 环境跳过启动预加载")
            return
        }

        guard !isPreloading, !isPreloadComplete else {
            return
        }

        guard !SpeechTranscriptionModel.hasModelFile() else {
            // 有模型文件，开始预加载
            isPreloading = true
            isPreloadComplete = false
            let startTime = CFAbsoluteTimeGetCurrent()

            // 必须用 .userInitiated 而不是 .utility：ONNX Runtime 的线程池是在建会话时懒创建的，
            // 这些线程会继承创建者的 QoS 并一直沿用。用 .utility 预加载等于把整个进程后续每一次
            // 推理都钉在低优先级上——本机实测同配置下 utility QoS 比正常优先级慢 1.5~2 倍。
            //
            // 2.0.0-rc10 当初降到 .utility 是为了不让模型加载拖慢启动首屏；这个诉求现在由调用方
            // 的延迟满足（主窗口 1.5 秒、静默启动 3 秒后才调本方法），所以这里不必再压优先级。
            // 若日后又出现「启动变慢」，请加大调用方延迟，不要把这里降回 .utility。
            Task.detached(priority: .userInitiated) {
                let loaded = await SpeechTranscriptionModel.shared.preload()
                let duration = CFAbsoluteTimeGetCurrent() - startTime

                await MainActor.run {
                    let manager = SpeechModelPreloadManager.shared
                    manager.isPreloading = false
                    manager.isPreloadComplete = true
                    manager.preloadDuration = duration
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

    /// 快捷键按下时的轻量预热。
    /// 模型可能因长时间空闲被卸载；这里不展示启动屏，只尽早把加载工作与用户说话时间重叠。
    func warmUpForImmediateVoiceInput() {
        guard SpeechTranscriptionModel.hasModelFile() else { return }
        guard interactiveWarmUpTask == nil else { return }

        interactiveWarmUpTask = Task.detached(priority: .userInitiated) {
            let startTime = CFAbsoluteTimeGetCurrent()
            let loaded = await SpeechTranscriptionModel.shared.preload()
            let duration = CFAbsoluteTimeGetCurrent() - startTime

            await MainActor.run {
                let manager = SpeechModelPreloadManager.shared
                manager.interactiveWarmUpTask = nil
                if loaded {
                    manager.isPreloadComplete = true
                    manager.preloadDuration = duration
                    print("🔥 [SpeechModelPreload] 语音输入即时预热完成，耗时: \(String(format: "%.2f", duration)) 秒")
                } else {
                    print("⚠️ [SpeechModelPreload] 语音输入即时预热跳过或失败")
                }
            }
        }
    }

    private static var isRunningUnderXCTest: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
            return true
        }

        return ProcessInfo.processInfo.arguments.contains { argument in
            argument.contains(".xctest") || argument == "-XCTest"
        }
    }
}
