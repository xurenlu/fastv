//
//  MicroAppCPUMonitor.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import WebKit
import AppKit
import UserNotifications
import Darwin
import Combine

/// Micro-App CPU 监控服务
/// 监控 WebView 进程的 CPU 使用率，当超过阈值时自动终止应用
@MainActor
class MicroAppCPUMonitor: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    /// CPU 使用率阈值（百分比），默认 80%
    var cpuThreshold: Double = 80.0
    
    /// 检测间隔（秒），默认 2 秒
    var checkInterval: TimeInterval = 2.0
    
    /// 连续超过阈值的次数，超过此次数后才会终止，默认 3 次（即 6 秒）
    var consecutiveThreshold: Int = 3
    
    private var webView: WKWebView?
    private var monitoringTask: Task<Void, Never>?
    private var consecutiveHighCPUCount: Int = 0
    private var onTerminate: (() -> Void)?
    
    /// 开始监控
    /// - Parameters:
    ///   - webView: 要监控的 WebView
    ///   - appId: 应用 ID（用于日志）
    ///   - onTerminate: 当需要终止时调用的回调
    func startMonitoring(webView: WKWebView, appId: String, onTerminate: @escaping () -> Void) {
        stopMonitoring()
        
        self.webView = webView
        self.onTerminate = onTerminate
        self.consecutiveHighCPUCount = 0
        
        monitoringTask = Task { [weak self] in
            await self?.monitorLoop(appId: appId)
        }
        
        print("🔍 [MicroAppCPUMonitor] 开始监控应用: \(appId), CPU阈值: \(cpuThreshold)%, 检测间隔: \(checkInterval)秒")
    }
    
    /// 停止监控
    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        webView = nil
        onTerminate = nil
        consecutiveHighCPUCount = 0
    }
    
    /// 监控循环
    private func monitorLoop(appId: String) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
                
                if Task.isCancelled { break }
                
                let cpuUsage = await getWebViewCPUUsage()
                
                if cpuUsage >= cpuThreshold {
                    consecutiveHighCPUCount += 1
                    print("⚠️ [MicroAppCPUMonitor] 应用 \(appId) CPU使用率: \(String(format: "%.1f", cpuUsage))% (连续 \(consecutiveHighCPUCount)/\(consecutiveThreshold) 次超过阈值)")
                    
                    if consecutiveHighCPUCount >= consecutiveThreshold {
                        print("🛑 [MicroAppCPUMonitor] 应用 \(appId) CPU使用率持续过高，自动终止")
                        await terminateMicroApp(appId: appId)
                        break
                    }
                } else {
                    // CPU 恢复正常，重置计数
                    if consecutiveHighCPUCount > 0 {
                        print("✅ [MicroAppCPUMonitor] 应用 \(appId) CPU使用率恢复正常: \(String(format: "%.1f", cpuUsage))%")
                        consecutiveHighCPUCount = 0
                    }
                }
            } catch {
                // Task 被取消
                break
            }
        }
    }
    
    /// 获取 WebView 进程的 CPU 使用率
    /// 使用多种方法综合判断：WebContent 进程 CPU + JavaScript 性能检测
    private func getWebViewCPUUsage() async -> Double {
        guard let webView = webView else { return 0.0 }
        
        // 方法1: 查找 WebContent 进程的 CPU 使用率（最准确）
        let webContentCPU = await getWebContentProcessCPU()
        
        // 方法2: 使用 JavaScript 检测主线程响应性（辅助判断）
        let jsPerformance = await getWebViewPerformanceCPU()
        
        // 综合判断：优先使用 WebContent 进程的 CPU，如果无法获取则使用 JS 性能检测
        let cpuUsage = webContentCPU > 0 ? webContentCPU : jsPerformance
        
        return min(cpuUsage, 100.0)
    }
    
    /// 通过进程名称查找并监控 WebContent 进程的 CPU
    /// WKWebView 在 macOS 上运行在 com.apple.WebKit.WebContent 进程中
    private func getWebContentProcessCPU() async -> Double {
        return await Task.detached {
            // 使用 ps 命令查找 WebContent 进程
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", "ps -eo pid,pcpu,comm | grep -i 'WebContent' | grep -v grep | awk '{print $2}' | head -1"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            
            do {
                try task.run()
                task.waitUntilExit()
                
                guard task.terminationStatus == 0 else {
                    return 0.0
                }
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !output.isEmpty,
                      let cpuUsage = Double(output) else {
                    return 0.0
                }
                
                return cpuUsage
            } catch {
                print("⚠️ [MicroAppCPUMonitor] 获取 WebContent 进程 CPU 失败: \(error.localizedDescription)")
                return 0.0
            }
        }.value
    }
    
    /// 使用 JavaScript 性能 API 监控（辅助方法）
    /// 通过注入 JavaScript 代码来检测 WebView 的主线程响应性
    private func getWebViewPerformanceCPU() async -> Double {
        guard let webView = webView else { return 0.0 }
        
        return await withCheckedContinuation { continuation in
            let script = """
            (function() {
                // 检测主线程是否被阻塞
                const start = performance.now();
                
                // 执行一个简单的计算来检测响应性
                // 如果主线程被阻塞，这个计算会花费更长时间
                let sum = 0;
                for (let i = 0; i < 100000; i++) {
                    sum += i;
                }
                
                const end = performance.now();
                const duration = end - start;
                
                // 正常应该在 1-5ms 内完成
                // 如果超过 50ms，说明主线程可能被阻塞，CPU 使用率可能较高
                // 将响应时间转换为 CPU 使用率估算（0-100%）
                if (duration > 50) {
                    return 100; // 主线程严重阻塞
                } else if (duration > 20) {
                    return 80; // 主线程中度阻塞
                } else if (duration > 10) {
                    return 50; // 主线程轻度阻塞
                } else {
                    return (duration / 10) * 30; // 正常范围，转换为较低的 CPU 估算
                }
            })();
            """
            
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    // JavaScript 执行失败可能意味着页面未加载完成或已关闭
                    // 返回 0 表示无法检测
                    continuation.resume(returning: 0.0)
                    return
                }
                
                if let cpuValue = result as? Double {
                    continuation.resume(returning: cpuValue)
                } else if let cpuValue = result as? Int {
                    continuation.resume(returning: Double(cpuValue))
                } else {
                    continuation.resume(returning: 0.0)
                }
            }
        }
    }
    
    /// 终止 microAPP
    private func terminateMicroApp(appId: String) async {
        // 显示通知
        await showTerminationNotification(appId: appId)
        
        // 调用终止回调
        onTerminate?()
        
        // 停止监控
        stopMonitoring()
    }
    
    /// 显示终止通知
    private func showTerminationNotification(appId: String) async {
        // 请求通知权限（如果尚未请求）
        let center = UNUserNotificationCenter.current()
        let authOptions: UNAuthorizationOptions = [.alert, .sound, .badge]
        
        do {
            let granted = try await center.requestAuthorization(options: authOptions)
            if !granted {
                print("⚠️ [MicroAppCPUMonitor] 通知权限未授予")
            }
        } catch {
            print("⚠️ [MicroAppCPUMonitor] 请求通知权限失败: \(error.localizedDescription)")
        }
        
        // 创建通知内容
        let content = UNMutableNotificationContent()
        content.title = "MicroAPP 已终止"
        content.body = "应用 \"\(appId)\" 因 CPU 使用率过高（超过 \(Int(cpuThreshold))%）已被自动终止"
        content.sound = .default
        
        // 创建通知请求
        let request = UNNotificationRequest(
            identifier: "microapp-terminated-\(appId)-\(UUID().uuidString)",
            content: content,
            trigger: nil // 立即触发
        )
        
        // 发送通知
        do {
            try await center.add(request)
            print("🔔 [MicroAppCPUMonitor] 已发送终止通知: \(appId)")
        } catch {
            print("⚠️ [MicroAppCPUMonitor] 发送通知失败: \(error.localizedDescription)")
        }
    }
    
    deinit {
        // deinit 是非隔离上下文，不能直接调用 @MainActor 方法
        // 直接取消 task 即可
        monitoringTask?.cancel()
    }
}

