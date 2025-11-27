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
    /// 提取第一帧
    static func extractFirstFrame(from videoURL: URL) async throws -> NSImage {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        
        // 确保正确处理视频方向
        imageGenerator.appliesPreferredTrackTransform = true
        
        // 设置精确的时间容差
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        // 提取第一帧（时间为零）
        let cgImage = try await imageGenerator.image(at: .zero).image
        
        return NSImage(cgImage: cgImage, size: .zero)
    }
    
    /// 提取最后一帧
    static func extractLastFrame(from videoURL: URL) async throws -> NSImage {
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        // 计算最后一帧的时间（减去一小段时间确保获取最后一帧）
        // 使用 1/30 秒作为最小时间单位
        let lastFrameTime = CMTimeSubtract(duration, CMTime(value: 1, timescale: 30))
        
        // 确保时间不为负
        let safeTime = max(lastFrameTime, .zero)
        
        let cgImage = try await imageGenerator.image(at: safeTime).image
        
        return NSImage(cgImage: cgImage, size: .zero)
    }
    
    /// 提取指定时间点的帧
    /// - Parameters:
    ///   - time: 时间点（秒）
    ///   - videoURL: 视频文件URL
    /// - Returns: 提取的帧图像
    static func extractFrame(at time: TimeInterval, from videoURL: URL) async throws -> NSImage {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        
        // 确保正确处理视频方向
        imageGenerator.appliesPreferredTrackTransform = true
        
        // 设置精确的时间容差
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        // 创建时间点
        let timePoint = CMTime(seconds: time, preferredTimescale: 600)
        
        // 提取帧
        let cgImage = try await imageGenerator.image(at: timePoint).image
        
        return NSImage(cgImage: cgImage, size: .zero)
    }
}

