//
//  TextCorrectionTracker.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AppKit
import ApplicationServices

/// 文本校正追踪服务
@MainActor
class TextCorrectionTracker {
    static let shared = TextCorrectionTracker()
    
    private var trackingTimer: Timer?
    private var trackingStartTime: Date?
    private var insertedText: String?
    private var lastSnapshot: String?
    private var lastValidSnapshot: String? // 最后一次有效快照（非空）
    private let maxSnapshots = 20 // 最多保存20个快照，避免内存问题
    private var snapshots: [String] = [] // 记录所有快照
    private let trackingDuration: TimeInterval = 30.0 // 监听时长30秒
    private let pollingInterval: TimeInterval = 1.5 // 轮询间隔1.5秒
    private var currentApp: NSRunningApplication?
    private var currentElement: AXUIElement?
    private var lastElementUpdateTime: Date?
    private let elementUpdateInterval: TimeInterval = 3.0 // 每3秒更新一次元素，减少API调用
    
    private init() {}
    
    /// 开始追踪文本变化
    /// - Parameters:
    ///   - insertedText: 插入的文本
    ///   - appBundleId: 应用Bundle ID
    /// - Note: 此功能已禁用，不再读取其他应用的文本内容
    func startTracking(insertedText: String, appBundleId: String? = nil) {
        // 功能已禁用：不再读取其他应用的文本内容
        // 仅保留接口以保持兼容性，但不执行任何操作
        print("ℹ️ [TextCorrectionTracker] 文本校正追踪功能已禁用")
        stopTracking()
    }
    
    /// 停止追踪
    func stopTracking() {
        if trackingTimer != nil {
            print("🛑 [TextCorrectionTracker] 停止追踪")
            trackingTimer?.invalidate()
            trackingTimer = nil
        }
        
        // 如果还在追踪窗口内，记录最后一次快照
        if let insertedText = insertedText,
           let lastSnapshot = lastSnapshot,
           let startTime = trackingStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > 1.0 && lastSnapshot != insertedText {
                // 文本发生了变化，记录校正
                recordCorrection(originalText: insertedText, correctedText: lastSnapshot)
            }
        }
        
        // 清理状态
        trackingStartTime = nil
        insertedText = nil
        lastSnapshot = nil
        lastValidSnapshot = nil
        snapshots.removeAll()
        currentApp = nil
        currentElement = nil
        lastElementUpdateTime = nil
    }
    
    /// 更新当前焦点元素
    /// - Note: 此功能已禁用，不再读取其他应用的UI元素
    private func updateCurrentElement() {
        // 功能已禁用：不再读取其他应用的UI元素
        currentElement = nil
    }
    
    /// 启动轮询
    private func startPolling() {
        trackingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.pollTextChange()
            }
        }
    }
    
    /// 轮询文本变化
    private func pollTextChange() {
        guard let startTime = trackingStartTime,
              let insertedText = insertedText else {
            stopTracking()
            return
        }
        
        // 检查是否超时
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed > trackingDuration {
            print("⏰ [TextCorrectionTracker] 追踪超时（\(trackingDuration)秒），停止追踪")
            stopTracking()
            return
        }
        
        // 检查应用是否切换（减少调用频率）
        if elapsed.truncatingRemainder(dividingBy: 3.0) < pollingInterval {
            let currentFrontmostApp = NSWorkspace.shared.frontmostApplication
            if let currentApp = currentApp,
               currentFrontmostApp?.bundleIdentifier != currentApp.bundleIdentifier {
                print("🔄 [TextCorrectionTracker] 检测到应用切换，停止追踪")
                stopTracking()
                return
            }
        }
        
        // 更新当前元素（减少API调用频率）
        if let lastUpdate = lastElementUpdateTime,
           Date().timeIntervalSince(lastUpdate) >= elementUpdateInterval {
            updateCurrentElement()
            lastElementUpdateTime = Date()
        } else if lastElementUpdateTime == nil {
            updateCurrentElement()
            lastElementUpdateTime = Date()
        }
        
        // 获取当前文本
        guard let currentText = getCurrentText() else {
            // 无法获取文本，可能是元素无效或失去焦点
            return
        }
        
        // 记录快照（限制数量，避免内存问题）
        if !currentText.isEmpty && !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastValidSnapshot = currentText
        }
        
        snapshots.append(currentText)
        if snapshots.count > maxSnapshots {
            snapshots.removeFirst() // 移除最旧的快照
        }
        lastSnapshot = currentText
        
        // 检查文本是否被清空
        if currentText.isEmpty || currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 文本被清空，可能是用户发送了消息
            // 使用最后一次有效快照
            if let lastValid = lastValidSnapshot,
               lastValid != insertedText {
                print("📤 [TextCorrectionTracker] 检测到文本被清空，使用最后一次有效快照")
                recordCorrection(originalText: insertedText, correctedText: lastValid)
            }
            stopTracking()
            return
        }
        
        // 检查文本是否变化
        if currentText != insertedText {
            // 检查是否是有效的修改（不是完全替换）
            if isBasedOnOriginal(original: insertedText, current: currentText) {
                // 文本还在变化中，继续监听
                print("📝 [TextCorrectionTracker] 检测到文本变化: \(currentText.prefix(50))...")
            } else {
                // 文本被完全替换，不是基于原始文本的修改
                print("⚠️ [TextCorrectionTracker] 文本被完全替换，不记录为校正")
                stopTracking()
            }
        }
    }
    
    /// 获取当前文本字段的内容
    /// - Note: 此功能已禁用，不再读取其他应用的文本内容
    private func getCurrentText() -> String? {
        // 功能已禁用：不再读取其他应用的文本内容
        return nil
    }
    
    /// 检查当前文本是否基于原始文本
    private func isBasedOnOriginal(original: String, current: String) -> Bool {
        // 简单的检查：如果当前文本包含原始文本的大部分内容，认为是基于原始文本的修改
        if current.contains(original) {
            return true
        }
        
        // 或者原始文本包含当前文本的大部分内容（用户删除了部分）
        if original.contains(current) && current.count >= Int(Double(original.count) * 0.5) {
            return true
        }
        
        // 计算相似度
        let similarity = calculateSimilarity(str1: original, str2: current)
        return similarity > 0.3 // 相似度阈值
    }
    
    /// 计算字符串相似度（简单的编辑距离）
    private func calculateSimilarity(str1: String, str2: String) -> Double {
        let len1 = str1.count
        let len2 = str2.count
        
        if len1 == 0 && len2 == 0 {
            return 1.0
        }
        
        if len1 == 0 || len2 == 0 {
            return 0.0
        }
        
        // 简单的字符重叠度计算
        let set1 = Set(str1)
        let set2 = Set(str2)
        let intersection = set1.intersection(set2)
        let union = set1.union(set2)
        
        if union.isEmpty {
            return 0.0
        }
        
        return Double(intersection.count) / Double(union.count)
    }
    
    /// 记录校正
    private func recordCorrection(originalText: String, correctedText: String) {
        guard originalText != correctedText else {
            return
        }
        
        // 如果文本被清空且时间很短（5秒内），可能是误操作，不记录
        if let startTime = trackingStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            if correctedText.isEmpty && elapsed < 5.0 {
                print("⚠️ [TextCorrectionTracker] 文本在短时间内被清空，可能是误操作，不记录")
                return
            }
        }
        
        let appName = currentApp?.localizedName
        let appBundleId = currentApp?.bundleIdentifier
        
        let record = TextCorrectionRecord(
            originalText: originalText,
            correctedText: correctedText,
            appName: appName,
            appBundleId: appBundleId
        )
        
        TextCorrectionManager.shared.add(record)
        print("✅ [TextCorrectionTracker] 已记录校正: \"\(originalText.prefix(30))...\" -> \"\(correctedText.prefix(30))...\"")
    }
}

