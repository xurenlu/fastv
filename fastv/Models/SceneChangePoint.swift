//
//  SceneChangePoint.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation

/// 视频画面变更点
struct SceneChangePoint: Identifiable, Codable {
    let id: UUID
    let timestamp: TimeInterval  // 时间戳（秒）
    let frameNumber: Int         // 帧号
    let changeIntensity: Double  // 变更强度（0-1）
    let description: String      // 描述信息
    
    init(id: UUID = UUID(), timestamp: TimeInterval, frameNumber: Int, changeIntensity: Double, description: String = "") {
        self.id = id
        self.timestamp = timestamp
        self.frameNumber = frameNumber
        self.changeIntensity = changeIntensity
        self.description = description.isEmpty ? String(format: "第%.1f秒：画面大幅变更", timestamp) : description
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

