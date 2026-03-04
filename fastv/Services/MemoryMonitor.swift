//
//  MemoryMonitor.swift
//  fastv
//
//  内存监控服务 - 分层记录内存使用历史
//

import Foundation
import Dispatch
import Darwin
import Combine

/// 内存记录数据点
struct MemoryRecord: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let memoryMB: Double
    let recordedAt: RecordGranularity

    enum RecordGranularity: String, Codable {
        case perMinute = "minute"      // 最近1小时：每分钟
        case per5Minutes = "5minutes"  // 1小时-5天：每5分钟
        case perHour = "hour"          // 超过5天：每小时
    }

    init(timestamp: Date, memoryMB: Double, recordedAt: RecordGranularity) {
        self.id = UUID()
        self.timestamp = timestamp
        self.memoryMB = memoryMB
        self.recordedAt = recordedAt
    }
}

/// 内存统计摘要
struct MemorySummary {
    let currentMB: Double
    let hourAvgMB: Double
    let hourMaxMB: Double
    let dayAvgMB: Double
    let dayMaxMB: Double
    let allMaxMB: Double
    let trend: MemoryTrend
    let recordCount: Int

    var currentFormatted: String {
        "\(Int(currentMB)) MB"
    }

    var hourAvgFormatted: String {
        "\(Int(hourAvgMB)) MB"
    }

    var hourMaxFormatted: String {
        "\(Int(hourMaxMB)) MB"
    }

    var trendDescription: String {
        switch trend {
        case .stable:
            return "稳定"
        case .rising(let percent):
            return "↑ \(Int(percent))%"
        case .falling(let percent):
            return "↓ \(Int(percent))%"
        }
    }
}

/// 内存趋势
enum MemoryTrend {
    case stable
    case rising(Double)  // 上升百分比
    case falling(Double) // 下降百分比
}

/// 内存监控服务
@MainActor
class MemoryMonitor: ObservableObject {
    static let shared = MemoryMonitor()

    // MARK: - Published Properties

    @Published private(set) var currentMemoryMB: Double = 0
    @Published private(set) var memoryHistory: [MemoryRecord] = []
    @Published private(set) var isMonitoring = false

    // MARK: - Constants

    // 时间阈值
    private let oneHourInterval: TimeInterval = 60 * 60           // 1小时
    private let fiveDaysInterval: TimeInterval = 5 * 24 * 60 * 60 // 5天

    // 采样间隔
    private let perMinuteInterval: TimeInterval = 60               // 每分钟
    private let per5MinutesInterval: TimeInterval = 5 * 60         // 每5分钟
    private let perHourInterval: TimeInterval = 60 * 60           // 每小时

    // 最大记录数量（防止无限增长）
    private let maxPerMinuteRecords = 60        // 1小时 × 60分钟
    private let maxPer5MinutesRecords = 1152    // (5天 - 1小时) / 5分钟 = 1152
    private let maxPerHourRecords = 720         // 保留最近30天的小时数据

    // 内存压力阈值（MB）
    private let warningThreshold: UInt64 = 2048   // 2GB 警告
    private let criticalThreshold: UInt64 = 4096  // 4GB 严重警告
    private let dangerThreshold: UInt64 = 6144    // 6GB 危险

    // MARK: - Private Properties

    private var monitorTimer: Timer?
    private let saveKey = "memoryMonitorData"

    // MARK: - Init

    private init() {
        loadFromDisk()
        startMonitoring()
    }

    deinit {
        // 在 deinit 中直接清理定时器（不调用 MainActor 方法）
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    // MARK: - Public Methods

    /// 开始监控
    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        updateMemory()

        // 立即检查并清理过期数据
        cleanupExpiredRecords()

        // 创建定时器，根据当前数据量决定采样频率
        scheduleNextSample()

        print("✅ [MemoryMonitor] 内存监控已启动")
    }

    /// 停止监控
    func stopMonitoring() {
        isMonitoring = false
        monitorTimer?.invalidate()
        monitorTimer = nil

        saveToDisk()
        print("⏸️ [MemoryMonitor] 内存监控已停止")
    }

    /// 立即记录一次内存使用
    func recordNow() {
        updateMemory()
        saveToDisk()
    }

    /// 获取指定时间范围的内存记录
    func getRecords(from startDate: Date, to endDate: Date) -> [MemoryRecord] {
        return memoryHistory.filter { record in
            record.timestamp >= startDate && record.timestamp <= endDate
        }.sorted { $0.timestamp < $1.timestamp }
    }

    /// 获取最近N分钟的记录
    func getRecentMinutes(_ count: Int) -> [MemoryRecord] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(count) * 60)
        return memoryHistory.filter { $0.timestamp >= cutoff && $0.recordedAt == .perMinute }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// 获取最近N小时的记录
    func getRecentHours(_ count: Int) -> [MemoryRecord] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(count) * 60 * 60)
        return memoryHistory.filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// 获取内存统计摘要
    func getMemorySummary() -> MemorySummary {
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-oneHourInterval)
        let recentDay = now.addingTimeInterval(-24 * 60 * 60)

        let recentHour = getRecords(from: oneHourAgo, to: now)
        let recentDayRecords = getRecords(from: recentDay, to: now)
        let allRecords = memoryHistory

        let currentMB = currentMemoryMB
        let hourAvg = recentHour.isEmpty ? 0 : recentHour.map { $0.memoryMB }.reduce(0, +) / Double(recentHour.count)
        let hourMax = recentHour.map { $0.memoryMB }.max() ?? 0
        let dayAvg = recentDayRecords.isEmpty ? 0 : recentDayRecords.map { $0.memoryMB }.reduce(0, +) / Double(recentDayRecords.count)
        let dayMax = recentDayRecords.map { $0.memoryMB }.max() ?? 0
        let allMax = allRecords.map { $0.memoryMB }.max() ?? 0

        // 计算趋势（最近1小时）
        let trend = calculateTrend(recentHour)

        return MemorySummary(
            currentMB: currentMB,
            hourAvgMB: hourAvg,
            hourMaxMB: hourMax,
            dayAvgMB: dayAvg,
            dayMaxMB: dayMax,
            allMaxMB: allMax,
            trend: trend,
            recordCount: allRecords.count
        )
    }

    /// 清除所有记录
    func clearAllRecords() {
        memoryHistory.removeAll()
        saveToDisk()
        print("🗑️ [MemoryMonitor] 已清除所有记录")
    }

    /// 获取格式化的内存使用字符串
    func getMemoryUsageString() -> String {
        return "\(Int(currentMemoryMB)) MB"
    }

    // MARK: - Private Methods

    private func scheduleNextSample() {
        monitorTimer?.invalidate()

        // 根据最旧的记录决定采样间隔
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-oneHourInterval)
        let fiveDaysAgo = now.addingTimeInterval(-fiveDaysInterval)

        // 检查是否有"每分钟"粒度的记录在1小时内
        let hasRecentMinuteRecord = memoryHistory.contains { record in
            record.recordedAt == .perMinute && record.timestamp > oneHourAgo
        }

        // 检查是否有"每5分钟"粒度的记录在5天内
        let hasRecent5MinRecord = memoryHistory.contains { record in
            record.recordedAt == .per5Minutes && record.timestamp > fiveDaysAgo
        }

        let interval: TimeInterval
        if hasRecentMinuteRecord {
            interval = perMinuteInterval
        } else if hasRecent5MinRecord {
            interval = per5MinutesInterval
        } else {
            interval = perHourInterval
        }

        monitorTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.updateMemory()
                self?.scheduleNextSample()
            }
        }
    }

    private func updateMemory() {
        let memoryMB = getCurrentMemoryUsage()
        currentMemoryMB = memoryMB

        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-oneHourInterval)
        let fiveDaysAgo = now.addingTimeInterval(-fiveDaysInterval)

        // 决定记录粒度
        let granularity: MemoryRecord.RecordGranularity
        let perMinuteCount = memoryHistory.filter { $0.recordedAt == .perMinute }.count
        let per5MinCount = memoryHistory.filter { $0.recordedAt == .per5Minutes }.count

        if perMinuteCount < maxPerMinuteRecords {
            // 最近1小时：每分钟记录
            granularity = .perMinute
        } else if per5MinCount < maxPer5MinutesRecords {
            // 1小时-5天：每5分钟记录
            granularity = .per5Minutes
        } else {
            // 超过5天：每小时记录
            granularity = .perHour
        }

        let record = MemoryRecord(timestamp: now, memoryMB: memoryMB, recordedAt: granularity)
        memoryHistory.append(record)

        // 清理过期数据和超出限制的数据
        cleanupAndCompactRecords()

        // 检查内存压力
        checkMemoryPressure(memoryMB)

        // 定期保存到磁盘（每10次更新保存一次）
        if memoryHistory.count % 10 == 0 {
            saveToDisk()
        }

        #if DEBUG
        print("📊 [MemoryMonitor] 内存: \(String(format: "%.1f", memoryMB)) MB | 粒度: \(granularity.rawValue) | 记录数: \(memoryHistory.count)")
        #endif
    }

    private func checkMemoryPressure(_ memoryMB: Double) {
        let memMB = UInt64(memoryMB)

        if memMB > dangerThreshold {
            print("🔴 [MemoryMonitor] 内存危险: \(Int(memoryMB))MB - 主动释放资源")
            performEmergencyCleanup()
        } else if memMB > criticalThreshold {
            print("🚨 [MemoryMonitor] 内存严重: \(Int(memoryMB))MB - 尝试释放资源")
            performMemoryCleanup()
        } else if memMB > warningThreshold {
            print("⚠️ [MemoryMonitor] 内存警告: \(Int(memoryMB))MB")
        }
    }

    /// 内存较高时清理可回收资源（token 缓存）
    private func performMemoryCleanup() {
        SpeechTranscriber.clearTokenCache()
        print("🧹 [MemoryMonitor] 已清除 token 缓存")
    }

    /// 内存危险时强制释放（卸载模型 + 清除缓存）
    private func performEmergencyCleanup() {
        SpeechTranscriber.clearTokenCache()
        Task {
            await SpeechTranscriptionModel.shared.unloadModel()
            print("🧹 [MemoryMonitor] 紧急清理完成：已卸载模型并清除缓存")
        }
    }

    private func cleanupAndCompactRecords() {
        let now = Date()
        var recordsToKeep: Set<UUID> = []

        // 1. 保留最近1小时的每分钟记录（最多60条）
        let oneHourAgo = now.addingTimeInterval(-oneHourInterval)
        let perMinuteRecords = memoryHistory.filter { $0.recordedAt == .perMinute && $0.timestamp > oneHourAgo }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(maxPerMinuteRecords)
        perMinuteRecords.forEach { recordsToKeep.insert($0.id) }

        // 2. 保留1小时到5天的每5分钟记录（最多1152条）
        let fiveDaysAgo = now.addingTimeInterval(-fiveDaysInterval)
        let per5MinRecords = memoryHistory.filter {
            $0.recordedAt == .per5Minutes && $0.timestamp > fiveDaysAgo && $0.timestamp <= oneHourAgo
        }.sorted { $0.timestamp > $1.timestamp }
         .prefix(maxPer5MinutesRecords)
        per5MinRecords.forEach { recordsToKeep.insert($0.id) }

        // 3. 保留超过5天的小时记录（最多720条，即30天）
        let perHourRecords = memoryHistory.filter {
            $0.recordedAt == .perHour && $0.timestamp <= fiveDaysAgo
        }.sorted { $0.timestamp > $1.timestamp }
         .prefix(maxPerHourRecords)
        perHourRecords.forEach { recordsToKeep.insert($0.id) }

        // 4. 保留最近的每分钟记录（填补空缺）
        let recentPerMinute = memoryHistory.filter { $0.recordedAt == .perMinute }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(60)
        recentPerMinute.forEach { recordsToKeep.insert($0.id) }

        // 应用过滤
        memoryHistory = memoryHistory.filter { recordsToKeep.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func cleanupExpiredRecords() {
        let now = Date()
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 60 * 60)

        // 删除超过30天的记录
        memoryHistory = memoryHistory.filter { $0.timestamp > thirtyDaysAgo }
    }

    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let capacity = MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            return Double(info.resident_size) / 1024 / 1024  // 转换为 MB
        }
        return 0
    }

    private func calculateTrend(_ records: [MemoryRecord]) -> MemoryTrend {
        guard records.count >= 2 else { return .stable }

        let recent = records.suffix(10)
        let firstHalf = recent.prefix(recent.count / 2)
        let secondHalf = recent.dropFirst(recent.count / 2)

        let firstAvg = firstHalf.map { $0.memoryMB }.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.map { $0.memoryMB }.reduce(0, +) / Double(secondHalf.count)

        let changePercent = (secondAvg - firstAvg) / firstAvg * 100

        if changePercent > 10 {
            return .rising(changePercent)
        } else if changePercent < -10 {
            return .falling(-changePercent)
        } else {
            return .stable
        }
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let snapshot = memoryHistory
        let key = saveKey
        DispatchQueue.global(qos: .utility).async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(snapshot)
                UserDefaults.standard.set(data, forKey: key)
            } catch {
                print("❌ [MemoryMonitor] 保存失败: \(error)")
            }
        }
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: saveKey) else { return }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            memoryHistory = try decoder.decode([MemoryRecord].self, from: data)
            currentMemoryMB = getCurrentMemoryUsage()

            // 清理过期数据
            cleanupAndCompactRecords()

            print("✅ [MemoryMonitor] 已加载 \(memoryHistory.count) 条记录")
        } catch {
            print("❌ [MemoryMonitor] 加载失败: \(error)")
            memoryHistory = []
        }
    }
}
