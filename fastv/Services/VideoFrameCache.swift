//
//  VideoFrameCache.swift
//  fastv
//
//  Created by rocky on 2025/12/25.
//

import Foundation
import AppKit

/// 视频帧缓存管理器
/// 用于缓存已提取的视频帧，避免重复提取
actor VideoFrameCache {
    static let shared = VideoFrameCache()
    
    private var cache: [String: NSImage] = [:]
    private var cacheOrder: [String] = []
    private let maxCacheSize = 20 // 最多缓存 20 帧
    
    private init() {}
    
    /// 生成缓存键
    /// - Parameters:
    ///   - videoURL: 视频文件 URL
    ///   - timestamp: 时间点（秒）
    /// - Returns: 缓存键
    private func cacheKey(for videoURL: URL, at timestamp: TimeInterval) -> String {
        return "\(videoURL.path)_\(String(format: "%.2f", timestamp))"
    }
    
    /// 获取缓存的帧
    /// - Parameters:
    ///   - videoURL: 视频文件 URL
    ///   - timestamp: 时间点（秒）
    /// - Returns: 缓存的图片，如果不存在则返回 nil
    func getFrame(for videoURL: URL, at timestamp: TimeInterval) -> NSImage? {
        let key = cacheKey(for: videoURL, at: timestamp)
        
        if let image = cache[key] {
            // 更新访问顺序
            if let index = cacheOrder.firstIndex(of: key) {
                cacheOrder.remove(at: index)
            }
            cacheOrder.append(key)
            return image
        }
        
        return nil
    }
    
    /// 缓存帧
    /// - Parameters:
    ///   - image: 要缓存的图片
    ///   - videoURL: 视频文件 URL
    ///   - timestamp: 时间点（秒）
    func setFrame(_ image: NSImage, for videoURL: URL, at timestamp: TimeInterval) {
        let key = cacheKey(for: videoURL, at: timestamp)
        
        // 如果缓存已满，移除最旧的项
        if cache.count >= maxCacheSize, !cache.keys.contains(key) {
            if let oldestKey = cacheOrder.first {
                cache.removeValue(forKey: oldestKey)
                cacheOrder.removeFirst()
            }
        }
        
        cache[key] = image
        
        // 更新访问顺序
        if let index = cacheOrder.firstIndex(of: key) {
            cacheOrder.remove(at: index)
        }
        cacheOrder.append(key)
    }
    
    /// 清除指定视频的缓存
    /// - Parameter videoURL: 视频文件 URL
    func clearCache(for videoURL: URL) {
        let prefix = videoURL.path + "_"
        let keysToRemove = cache.keys.filter { $0.hasPrefix(prefix) }
        
        for key in keysToRemove {
            cache.removeValue(forKey: key)
            if let index = cacheOrder.firstIndex(of: key) {
                cacheOrder.remove(at: index)
            }
        }
    }
    
    /// 清除所有缓存
    func clearAll() {
        cache.removeAll()
        cacheOrder.removeAll()
    }
    
    /// 获取缓存统计信息
    func getCacheStats() -> (count: Int, maxSize: Int) {
        return (cache.count, maxCacheSize)
    }
}

