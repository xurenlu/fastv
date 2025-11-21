//
//  WaveformWindowPosition.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation

/// 波形窗口位置
enum WaveformWindowPosition: String, CaseIterable {
    case topLeft = "topLeft"
    case topRight = "topRight"
    case bottomLeft = "bottomLeft"
    case bottomRight = "bottomRight"
    case bottomCenter = "bottomCenter"
    
    /// 显示名称（中文）
    var displayName: String {
        switch self {
        case .topLeft:
            return "左上角"
        case .topRight:
            return "右上角"
        case .bottomLeft:
            return "左下角"
        case .bottomRight:
            return "右下角"
        case .bottomCenter:
            return "正中间下方"
        }
    }
}

