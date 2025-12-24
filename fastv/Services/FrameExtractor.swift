//
//  FrameExtractor.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AVFoundation
import AppKit

struct FrameExtractor {
    /// 标准化文件 URL，正确处理特殊字符（中文、冒号、加号等）
    private static func normalizeFileURL(_ url: URL) -> URL {
        // 保留安全作用域信息，不要用 fileURLWithPath 重新构造
        guard url.isFileURL else { return url }
        
        // 仅做符号链接解析，不改变原始 URL 的安全作用域
        if let resolved = (url as NSURL).resolvingSymlinksInPath {
            return resolved
        }
        return url
    }
    
    /// 提取帧，带容错（首次尝试失败则略微偏移时间重试，并放宽时间容差）
    private static func generateImage(asset: AVURLAsset, at time: CMTime) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        do {
            return try await generator.image(at: time).image
        } catch {
            // 回退：向后偏移 0.1 秒，放宽容差再试
            let fallbackTime = CMTime(seconds: max(0, time.seconds + 0.1), preferredTimescale: 600)
            let fallbackGen = AVAssetImageGenerator(asset: asset)
            fallbackGen.appliesPreferredTrackTransform = true
            fallbackGen.requestedTimeToleranceBefore = CMTime.positiveInfinity
            fallbackGen.requestedTimeToleranceAfter = CMTime.positiveInfinity
            return try await fallbackGen.image(at: fallbackTime).image
        }
    }
    /// 提取第一帧
    static func extractFirstFrame(from videoURL: URL) async throws -> NSImage {
        // 标准化 URL，正确处理特殊字符（中文、冒号、加号等）
        let normalizedURL = normalizeFileURL(videoURL)
        
        // 获取安全作用域访问权限（若有）
        let hasAccess = normalizedURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { normalizedURL.stopAccessingSecurityScopedResource() } }
        
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: normalizedURL.path) else {
            throw NSError(
                domain: "FrameExtractor",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "视频文件不存在: \(normalizedURL.path)"]
            )
        }
        
        // 使用标准化的 URL 创建 AVAsset
        let asset = AVURLAsset(url: normalizedURL)
        
        // 检查资产是否可加载
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard !tracks.isEmpty else {
                throw NSError(
                    domain: "FrameExtractor",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "视频文件中没有视频轨道"]
                )
            }
        } catch {
            // 如果加载失败，提供更详细的错误信息
            if let nsError = error as NSError? {
                throw NSError(
                    domain: "FrameExtractor",
                    code: nsError.code,
                    userInfo: [
                        NSLocalizedDescriptionKey: "无法加载视频文件: \(nsError.localizedDescription)\n文件路径: \(normalizedURL.path)"
                    ]
                )
            }
            throw error
        }
        
        // 提取第一帧（时间为零），带回退逻辑
        do {
            let cgImage = try await generateImage(asset: asset, at: .zero)
            return NSImage(cgImage: cgImage, size: .zero)
        } catch {
            if let nsError = error as NSError? {
                throw NSError(
                    domain: "FrameExtractor",
                    code: nsError.code,
                    userInfo: [
                        NSLocalizedDescriptionKey: "提取视频帧失败: \(nsError.localizedDescription)\n文件路径: \(normalizedURL.path)"
                    ]
                )
            }
            throw error
        }
    }
    
    /// 提取最后一帧
    static func extractLastFrame(from videoURL: URL) async throws -> NSImage {
        // 标准化 URL，正确处理特殊字符
        let normalizedURL = normalizeFileURL(videoURL)
        
        // 获取安全作用域访问权限
        let hasAccess = normalizedURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { normalizedURL.stopAccessingSecurityScopedResource() } }
        
        let asset = AVURLAsset(url: normalizedURL)
        let duration = try await asset.load(.duration)
        
        // 计算最后一帧的时间（减去一小段时间确保获取最后一帧）
        // 使用 1/30 秒作为最小时间单位
        let lastFrameTime = CMTimeSubtract(duration, CMTime(value: 1, timescale: 30))
        
        // 确保时间不为负
        let safeTime = max(lastFrameTime, CMTime.zero)
        
        let cgImage = try await generateImage(asset: asset, at: safeTime)
        return NSImage(cgImage: cgImage, size: .zero)
    }
    
    /// 提取指定时间点的帧
    /// - Parameters:
    ///   - time: 时间点（秒）
    ///   - videoURL: 视频文件URL
    /// - Returns: 提取的帧图像
    static func extractFrame(at time: TimeInterval, from videoURL: URL) async throws -> NSImage {
        // 标准化 URL，正确处理特殊字符
        let normalizedURL = normalizeFileURL(videoURL)
        
        // 获取安全作用域访问权限
        let hasAccess = normalizedURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { normalizedURL.stopAccessingSecurityScopedResource() } }
        
        let asset = AVURLAsset(url: normalizedURL)
        
        // 创建时间点
        let timePoint = CMTime(seconds: time, preferredTimescale: 600)
        
        // 提取帧（带回退逻辑）
        let cgImage = try await generateImage(asset: asset, at: timePoint)
        return NSImage(cgImage: cgImage, size: .zero)
    }
}

