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
    /// 获取视频信息
    static func getVideoInfo(from videoURL: URL) async throws -> VideoInfo {
        let asset = AVAsset(url: videoURL)
        
        // 检查是否有视频轨道
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoProcessingError.noVideoTrack
        }
        
        // 获取视频轨道信息
        let naturalSize = try await videoTrack.load(.naturalSize)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        
        // 获取文件大小
        let resourceValues = try videoURL.resourceValues(forKeys: [.fileSizeKey])
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

