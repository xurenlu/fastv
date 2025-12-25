//
//  VideoInfo.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import CoreGraphics

struct VideoInfo {
    let duration: TimeInterval
    let resolution: CGSize
    let frameRate: Float
    let fileSize: Int64
    let audioTracks: [AudioTrackInfo]
    
    var hasAudio: Bool {
        return !audioTracks.isEmpty
    }
    
    var durationString: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    var resolutionString: String {
        return "\(Int(resolution.width))×\(Int(resolution.height))"
    }
    
    var fileSizeString: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

struct AudioTrackInfo {
    let sampleRate: Double
    let channels: Int?
    
    var sampleRateString: String {
        return String(format: "%.0f Hz", sampleRate)
    }
    
    var channelsString: String {
        if let channels = channels {
            return "\(channels) 声道"
        }
        return "未知"
    }
}

