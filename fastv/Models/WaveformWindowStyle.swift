//
//  WaveformWindowStyle.swift
//  fastv
//
//  Created by rocky on 2025/11/21.
//

import Foundation
import CoreGraphics

/// 悬浮窗口样式
enum WaveformWindowStyle: String, CaseIterable {
    case compact = "compact"       // 紧凑
    case normal = "normal"         // 正常
    case large = "large"           // 大
    
    var displayName: String {
        switch self {
        case .compact:
            return "紧凑"
        case .normal:
            return "正常"
        case .large:
            return "大"
        }
    }
    
    var size: CGSize {
        switch self {
        case .compact:
            // 优化比例：更接近黄金比例 (1.618)，同时保持紧凑
            return CGSize(width: 88, height: 32)
        case .normal:
            return CGSize(width: 108, height: 36)
        case .large:
            return CGSize(width: 128, height: 44)
        }
    }
    
    var cornerRadius: CGFloat {
        switch self {
        case .compact:
            return 12
        case .normal:
            return 14
        case .large:
            return 16
        }
    }
    
    var horizontalPadding: CGFloat {
        switch self {
        case .compact:
            return 8  // 增加内边距，减少压迫感
        case .normal:
            return 10
        case .large:
            return 12
        }
    }
    
    var verticalPadding: CGFloat {
        switch self {
        case .compact:
            return 6  // 增加垂直内边距
        case .normal:
            return 7
        case .large:
            return 8
        }
    }
    
    var barWidth: CGFloat {
        switch self {
        case .compact:
            return 3.5  // 稍微增加宽度
        case .normal:
            return 4
        case .large:
            return 4.5
        }
    }
    
    var barSpacing: CGFloat {
        switch self {
        case .compact:
            return 3  // 增加间距，符合黄金比例
        case .normal:
            return 3.5
        case .large:
            return 4
        }
    }
    
    var maxBarHeight: CGFloat {
        switch self {
        case .compact:
            return 16  // 增加最大高度，更明显
        case .normal:
            return 18
        case .large:
            return 24
        }
    }
    
    var spinnerSize: CGFloat {
        switch self {
        case .compact:
            return 18  // 增加spinner尺寸
        case .normal:
            return 20
        case .large:
            return 24
        }
    }
    
    var textSize: CGFloat {
        switch self {
        case .compact:
            return 8
        case .normal:
            return 9
        case .large:
            return 10
        }
    }
    
    var showText: Bool {
        switch self {
        case .compact:
            return false  // 紧凑模式不显示文字
        case .normal, .large:
            return true
        }
    }
}

