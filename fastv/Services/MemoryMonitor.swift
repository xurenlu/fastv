//
//  MemoryMonitor.swift
//  fastv
//
//  Created on 2025/12/07.
//

import Foundation
import Dispatch
import Darwin

/// 内存监控服务
/// 用于监控应用内存使用情况，在内存压力时记录日志并建议清理
class MemoryMonitor {
    static let shared = MemoryMonitor()

    private init() {}

    // 内存压力阈值（MB）
    private let warningThreshold: UInt64 = 500   // 500MB 警告
    private let criticalThreshold: UInt64 = 800  // 800MB 严重警告
    private let dangerThreshold: UInt64 = 1200   // 1.2GB 危险

    // 监控定时器
    private var monitorTimer: DispatchSourceTimer?

    /// 开始监控内存使用
    func startMonitoring(interval: TimeInterval = 5.0) {
        guard monitorTimer == nil else { return }

        let queue = DispatchQueue(label: "com.fastv.memoryMonitor")
        monitorTimer = DispatchSource.makeTimerSource(queue: queue)

        monitorTimer?.schedule(deadline: .now() + interval, repeating: interval)

        monitorTimer?.setEventHandler { [weak self] in
            self?.checkMemoryUsage()
        }

        monitorTimer?.resume()

        print("📊 [MemoryMonitor] 内存监控已启动")
    }

    /// 停止监控
    func stopMonitoring() {
        monitorTimer?.cancel()
        monitorTimer = nil
        print("📊 [MemoryMonitor] 内存监控已停止")
    }

    /// 检查当前内存使用情况
    func checkMemoryUsage() {
        let memoryInfo = getMemoryUsage()
        let usedMB = memoryInfo.used / 1024 / 1024
        let systemFreeMB = getSystemFreeMemoryMB()

        #if DEBUG
        if usedMB > warningThreshold {
            // used=本进程驻留内存；systemFree=系统空闲内存（来自 host_statistics64）
            let freeStr = systemFreeMB.map { "系统可用: \($0)MB" } ?? "本进程占用"
            print("⚠️ [MemoryMonitor] 内存使用: \(usedMB)MB (\(freeStr))")

            if usedMB > criticalThreshold {
                print("🚨 [MemoryMonitor] 内存使用严重: \(usedMB)MB")
                print("💡 建议: 清理缓存、释放不需要的资源")
            }

            if usedMB > dangerThreshold {
                print("🔴 [MemoryMonitor] 内存使用危险: \(usedMB)MB")
                print("💡 建议: 立即释放资源，重启应用")
            }
        }
        #endif
    }

    /// 获取系统空闲内存（MB），来自 host_statistics64，失败时返回 nil
    private func getSystemFreeMemoryMB() -> UInt64? {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let host = mach_host_self()
        let kerr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return nil }
        // free_count + inactive_count 约等于可回收/可用内存（页大小通常 16KB）
        let pageSize = UInt64(vm_kernel_page_size)
        let freeBytes = (UInt64(stats.free_count) + UInt64(stats.inactive_count)) * pageSize
        return freeBytes / 1024 / 1024
    }

    /// 获取当前内存使用信息
    func getMemoryUsage() -> (used: UInt64, free: UInt64, total: UInt64) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return (used: info.resident_size, free: 0, total: info.resident_size)
        } else {
            return (used: 0, free: 0, total: 0)
        }
    }

    /// 获取格式化的内存使用字符串
    func getMemoryUsageString() -> String {
        let memoryInfo = getMemoryUsage()
        let usedMB = memoryInfo.used / 1024 / 1024
        return "\(usedMB)MB"
    }

    /// 强制垃圾回收（释放可释放的内存）
    func forceGarbageCollection() {
        autoreleasepool {
            // 触发 autorelease pool 清理
        }

        // 在 macOS 上无法手动触发 Swift 的垃圾回收
        // 但可以通过创建和释放大对象来促进内存回收
        let _ = Data(repeating: 0, count: 1024 * 1024)  // 1MB
        print("🧹 [MemoryMonitor] 已尝试释放内存")
    }

    deinit {
        stopMonitoring()
    }
}

// MARK: - 内存使用统计信息
extension MemoryMonitor {
    struct MemoryStats {
        let usedMemory: UInt64      // 已使用内存（字节）
        let freeMemory: UInt64      // 可用内存（字节）
        let totalMemory: UInt64     // 总内存（字节）
        let usagePercentage: Double // 使用百分比

        var usedMB: UInt64 {
            return usedMemory / 1024 / 1024
        }

        var freeMB: UInt64 {
            return freeMemory / 1024 / 1024
        }

        var totalMB: UInt64 {
            return totalMemory / 1024 / 1024
        }
    }

    /// 获取详细的内存统计信息（简化版本，避免不兼容的字段）
    func getDetailedStats() -> MemoryStats? {
        // host_basic_info 不包含 free_count 字段，使用简化版本
        let memoryInfo = getMemoryUsage()

        // 估算可用内存（基于经验值）
        let estimatedFree = max(0, Int64(8 * 1024 * 1024 * 1024) - Int64(memoryInfo.used))

        let total: UInt64 = 8 * 1024 * 1024 * 1024  // 假设 8GB 总内存
        let used = memoryInfo.used
        let percentage = Double(used) / Double(total) * 100

        return MemoryStats(
            usedMemory: used,
            freeMemory: UInt64(max(0, estimatedFree)),
            totalMemory: total,
            usagePercentage: percentage
        )
    }
}
