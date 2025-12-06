//
//  MicroAppProcessPoolManager.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import WebKit

/// Micro-App 进程池管理器
/// 为每个 microAPP 创建独立的进程池，确保进程隔离
/// 当某个 microAPP 崩溃时，不会影响其他 microAPP 或主进程
@MainActor
class MicroAppProcessPoolManager {
    static let shared = MicroAppProcessPoolManager()
    
    /// 存储每个应用的进程池
    private var processPools: [String: WKProcessPool] = [:]
    
    /// 存储进程池的使用计数（用于清理）
    private var processPoolRefCounts: [String: Int] = [:]
    
    private init() {
        // 监听应用终止通知，清理进程池
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }
    
    /// 获取或创建指定应用的进程池
    /// - Parameter appId: 应用 ID
    /// - Returns: 独立的进程池
    func getProcessPool(for appId: String) -> WKProcessPool {
        if let existingPool = processPools[appId] {
            // 增加引用计数
            processPoolRefCounts[appId, default: 0] += 1
            return existingPool
        }
        
        // 创建新的进程池
        let pool = WKProcessPool()
        processPools[appId] = pool
        processPoolRefCounts[appId] = 1
        
        print("🔒 [MicroAppProcessPoolManager] 为应用 \(appId) 创建独立进程池")
        
        return pool
    }
    
    /// 释放进程池引用
    /// - Parameter appId: 应用 ID
    func releaseProcessPool(for appId: String) {
        guard let refCount = processPoolRefCounts[appId] else { return }
        
        let newRefCount = refCount - 1
        processPoolRefCounts[appId] = newRefCount
        
        // 如果引用计数为 0，清理进程池
        if newRefCount <= 0 {
            processPools.removeValue(forKey: appId)
            processPoolRefCounts.removeValue(forKey: appId)
            print("🗑️ [MicroAppProcessPoolManager] 清理应用 \(appId) 的进程池")
        }
    }
    
    /// 强制清理指定应用的进程池（用于崩溃恢复）
    /// - Parameter appId: 应用 ID
    func forceCleanupProcessPool(for appId: String) {
        processPools.removeValue(forKey: appId)
        processPoolRefCounts.removeValue(forKey: appId)
        print("🛑 [MicroAppProcessPoolManager] 强制清理应用 \(appId) 的进程池（进程崩溃）")
    }
    
    /// 清理所有进程池
    func cleanupAll() {
        processPools.removeAll()
        processPoolRefCounts.removeAll()
        print("🧹 [MicroAppProcessPoolManager] 清理所有进程池")
    }
    
    @objc private func applicationWillTerminate() {
        cleanupAll()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        // deinit 是非隔离上下文，不能直接调用 @MainActor 方法
        // 由于这是单例且在应用终止时才会触发 deinit，
        // applicationWillTerminate 已经处理了清理工作
    }
}

