//
//  SceneChangePoint.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AppKit

/// 视频画面变更点
struct SceneChangePoint: Identifiable, Codable {
    let id: UUID
    let timestamp: TimeInterval  // 时间戳（秒）
    let frameNumber: Int         // 帧号
    let changeIntensity: Double  // 变更强度（0-1）
    let description: String      // 描述信息
    
    // 截图缩略图（不参与 Codable，仅用于运行时显示）
    var thumbnailImage: NSImage?
    
    enum CodingKeys: String, CodingKey {
        case id, timestamp, frameNumber, changeIntensity, description
        // thumbnailImage 不参与编码
    }
    
    init(id: UUID = UUID(), timestamp: TimeInterval, frameNumber: Int, changeIntensity: Double, description: String = "", thumbnailImage: NSImage? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.frameNumber = frameNumber
        self.changeIntensity = changeIntensity
        self.description = description.isEmpty ? String(format: "第%.1f秒：画面大幅变更", timestamp) : description
        self.thumbnailImage = thumbnailImage
    }
    
    /// 格式化时间显示
    var timeString: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "%.1f秒", timestamp)
        }
    }
}

