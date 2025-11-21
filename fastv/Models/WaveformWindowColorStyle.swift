//
//  WaveformWindowColorStyle.swift
//  fastv
//
//  Created by rocky on 2025/11/21.
//

import SwiftUI

/// 悬浮窗口颜色风格
enum WaveformWindowColorStyle: String, CaseIterable {
    case blue = "blue"           // 蓝色（系统强调色）
    case purple = "purple"       // 紫色
    case pink = "pink"           // 粉色
    case green = "green"         // 绿色
    case orange = "orange"       // 橙色
    case red = "red"             // 红色
    
    var displayName: String {
        switch self {
        case .blue:
            return "蓝色"
        case .purple:
            return "紫色"
        case .pink:
            return "粉色"
        case .green:
            return "绿色"
        case .orange:
            return "橙色"
        case .red:
            return "红色"
        }
    }
    
    var color: Color {
        switch self {
        case .blue:
            return .accentColor
        case .purple:
            // 使用更精确的颜色值，确保在深浅模式下都好看
            return Color(red: 0.69, green: 0.32, blue: 0.87)  // #AF52DE
        case .pink:
            return Color(red: 1.0, green: 0.22, blue: 0.37)   // #FF3758
        case .green:
            return Color(red: 0.20, green: 0.78, blue: 0.35)  // #34C759
        case .orange:
            return Color(red: 1.0, green: 0.58, blue: 0.0)    // #FF9500
        case .red:
            return Color(red: 1.0, green: 0.27, blue: 0.23)   // #FF453A
        }
    }
    
    /// 获取适配深浅模式的颜色
    func adaptiveColor(for colorScheme: ColorScheme) -> Color {
        // 在浅色模式下，颜色稍微深一些以保证对比度
        // 在深色模式下，颜色稍微亮一些
        switch colorScheme {
        case .light:
            switch self {
            case .blue:
                return .accentColor
            case .purple:
                return Color(red: 0.59, green: 0.22, blue: 0.77)
            case .pink:
                return Color(red: 0.90, green: 0.12, blue: 0.27)
            case .green:
                return Color(red: 0.15, green: 0.68, blue: 0.30)
            case .orange:
                return Color(red: 0.90, green: 0.48, blue: 0.0)
            case .red:
                return Color(red: 0.90, green: 0.17, blue: 0.13)
            }
        case .dark:
            return color
        @unknown default:
            return color
        }
    }
}

