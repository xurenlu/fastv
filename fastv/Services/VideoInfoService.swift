//
//  VideoInfoService.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AVFoundation
import CoreGraphics
import CoreMedia

struct VideoInfoService {
    /// 标准化文件 URL，正确处理特殊字符（中文、冒号、加号等）
    private static func normalizeFileURL(_ url: URL) -> URL {
        // 保留安全作用域信息，避免用 fileURLWithPath 重新构造
        guard url.isFileURL else { return url }
        if let resolved = (url as NSURL).resolvingSymlinksInPath {
            return resolved
        }
        return url
    }
    /// 获取视频信息
    static func getVideoInfo(from videoURL: URL) async throws -> VideoInfo {
        // 标准化 URL，正确处理特殊字符（中文、冒号、加号等）
        let normalizedURL = normalizeFileURL(videoURL)
        
        // 获取安全作用域访问权限（若有）
        let hasAccess = normalizedURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { normalizedURL.stopAccessingSecurityScopedResource() } }
        
        // 使用标准化的 URL 创建 AVAsset
        let asset = AVURLAsset(url: normalizedURL)
        
        // 检查是否有视频轨道
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoProcessingError.noVideoTrack
        }
        
        // 获取视频轨道信息
        let naturalSize = try await videoTrack.load(.naturalSize)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        
        // 获取文件大小（使用标准化后的 URL）
        let resourceValues = try normalizedURL.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = Int64(resourceValues.fileSize ?? 0)
        
        // 获取音频轨道信息
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let audioInfo = try await audioTracks.asyncMap { track -> AudioTrackInfo in
            let formatDescriptions = try await track.load(.formatDescriptions)
            var sampleRate: Double = 44100.0 // 默认值
            var channelCount: Int? = nil
            
            if let formatDescription = formatDescriptions.first {
                let audioFormatDescription = formatDescription as CMAudioFormatDescription
                if let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDescription) {
                    sampleRate = Double(audioStreamBasicDescription.pointee.mSampleRate)
                    channelCount = Int(audioStreamBasicDescription.pointee.mChannelsPerFrame)
                }
            }
            
            return AudioTrackInfo(sampleRate: sampleRate, channels: channelCount)
        }
        
        return VideoInfo(
            duration: duration.seconds,
            resolution: naturalSize,
            frameRate: frameRate,
            fileSize: fileSize,
            audioTracks: audioInfo
        )
    }
}

// 辅助扩展：异步 map
extension Sequence {
    func asyncMap<T>(
        _ transform: @escaping (Element) async throws -> T
    ) async rethrows -> [T] {
        var results: [T] = []
        for element in self {
            try await results.append(transform(element))
        }
        return results
    }
}

