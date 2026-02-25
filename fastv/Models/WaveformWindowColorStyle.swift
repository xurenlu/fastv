//
//  WaveformWindowColorStyle.swift
//  fastv
//
//  Created by rocky on 2025/11/21.
//

import SwiftUI

/// 颜色样式配置
struct ColorStyleConfig {
    let backgroundColor: Color
    let barColor: Color
    let backgroundOpacity: Double
    let useMaterial: Bool  // 是否使用毛玻璃效果
    
    init(
        backgroundColor: Color,
        barColor: Color,
        backgroundOpacity: Double = 0.25,
        useMaterial: Bool = true
    ) {
        self.backgroundColor = backgroundColor
        self.barColor = barColor
        self.backgroundOpacity = backgroundOpacity
        self.useMaterial = useMaterial
    }
}

/// 悬浮窗口颜色风格
enum WaveformWindowColorStyle: String, CaseIterable {
    // 基础彩色系列
    case blue = "blue"                    // 蓝色
    case purple = "purple"                 // 紫色
    case pink = "pink"                     // 粉色
    case green = "green"                   // 绿色
    case orange = "orange"                 // 橙色
    case red = "red"                       // 红色
    
    // 经典黑白系列
    case blackWhite = "blackWhite"         // 黑色背景+白色音量条
    case whiteBlack = "whiteBlack"         // 白色背景+黑色音量条
    case darkGrayWhite = "darkGrayWhite"   // 深灰背景+白色音量条
    
    // 深色背景+亮色音量条系列
    case darkBlueCyan = "darkBlueCyan"     // 深蓝背景+青色音量条
    case darkPurplePink = "darkPurplePink" // 深紫背景+粉色音量条
    case darkGreenLime = "darkGreenLime"   // 深绿背景+亮绿音量条
    case darkRedCoral = "darkRedCoral"    // 深红背景+珊瑚色音量条
    
    // 深灰背景+彩色音量条系列
    case darkGrayBlue = "darkGrayBlue"     // 深灰背景+蓝色音量条
    case darkGrayGreen = "darkGrayGreen"   // 深灰背景+绿色音量条
    case darkGrayOrange = "darkGrayOrange" // 深灰背景+橙色音量条
    case darkGrayPink = "darkGrayPink"     // 深灰背景+粉色音量条
    case darkGrayPurple = "darkGrayPurple" // 深灰背景+紫色音量条
    case darkGrayRed = "darkGrayRed"       // 深灰背景+红色音量条
    case darkGrayYellow = "darkGrayYellow" // 深灰背景+黄色音量条
    case darkGrayCyan = "darkGrayCyan"     // 深灰背景+青色音量条
    
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
        case .blackWhite:
            return "黑色+白色"
        case .whiteBlack:
            return "白色+黑色"
        case .darkGrayWhite:
            return "深灰+白色"
        case .darkBlueCyan:
            return "深蓝+青色"
        case .darkPurplePink:
            return "深紫+粉色"
        case .darkGreenLime:
            return "深绿+亮绿"
        case .darkRedCoral:
            return "深红+珊瑚"
        case .darkGrayBlue:
            return "深灰+蓝色"
        case .darkGrayGreen:
            return "深灰+绿色"
        case .darkGrayOrange:
            return "深灰+橙色"
        case .darkGrayPink:
            return "深灰+粉色"
        case .darkGrayPurple:
            return "深灰+紫色"
        case .darkGrayRed:
            return "深灰+红色"
        case .darkGrayYellow:
            return "深灰+黄色"
        case .darkGrayCyan:
            return "深灰+青色"
        }
    }
    
    /// 获取颜色配置
    func colorConfig(for colorScheme: ColorScheme) -> ColorStyleConfig {
        switch self {
        // 基础彩色系列 - 使用毛玻璃效果
        case .blue:
            let bgColor = Color(red: 0.0, green: 0.48, blue: 1.0)  // 系统蓝
            let barColor = Color(red: 0.0, green: 0.48, blue: 1.0)
            return ColorStyleConfig(
                backgroundColor: bgColor,
                barColor: barColor,
                backgroundOpacity: colorScheme == .dark ? 0.3 : 0.2,
                useMaterial: true
            )
            
        case .purple:
            let bgColor = Color(red: 0.69, green: 0.32, blue: 0.87)  // #AF52DE
            let barColor = Color(red: 0.69, green: 0.32, blue: 0.87)
            return ColorStyleConfig(
                backgroundColor: bgColor,
                barColor: barColor,
                backgroundOpacity: colorScheme == .dark ? 0.3 : 0.2,
                useMaterial: true
            )
            
        case .pink:
            let bgColor = Color(red: 1.0, green: 0.22, blue: 0.37)   // #FF3758
            let barColor = Color(red: 1.0, green: 0.22, blue: 0.37)
            return ColorStyleConfig(
                backgroundColor: bgColor,
                barColor: barColor,
                backgroundOpacity: colorScheme == .dark ? 0.3 : 0.2,
                useMaterial: true
            )
            
        case .green:
            let bgColor = Color(red: 0.20, green: 0.78, blue: 0.35)  // #34C759
            let barColor = Color(red: 0.20, green: 0.78, blue: 0.35)
            return ColorStyleConfig(
                backgroundColor: bgColor,
                barColor: barColor,
                backgroundOpacity: colorScheme == .dark ? 0.3 : 0.2,
                useMaterial: true
            )
            
        case .orange:
            let bgColor = Color(red: 1.0, green: 0.58, blue: 0.0)    // #FF9500
            let barColor = Color(red: 1.0, green: 0.58, blue: 0.0)
            return ColorStyleConfig(
                backgroundColor: bgColor,
                barColor: barColor,
                backgroundOpacity: colorScheme == .dark ? 0.3 : 0.2,
                useMaterial: true
            )
            
        case .red:
            let bgColor = Color(red: 1.0, green: 0.27, blue: 0.23)   // #FF453A
            let barColor = Color(red: 1.0, green: 0.27, blue: 0.23)
            return ColorStyleConfig(
                backgroundColor: bgColor,
                barColor: barColor,
                backgroundOpacity: colorScheme == .dark ? 0.3 : 0.2,
                useMaterial: true
            )
        
        // 经典黑白系列 - 不使用毛玻璃，使用纯色背景
        case .blackWhite:
            return ColorStyleConfig(
                backgroundColor: Color.black,
                barColor: Color.white,
                backgroundOpacity: 0.85,
                useMaterial: false
            )
            
        case .whiteBlack:
            return ColorStyleConfig(
                backgroundColor: Color.white,
                barColor: Color.black,
                backgroundOpacity: 0.9,
                useMaterial: false
            )
            
        case .darkGrayWhite:
            return ColorStyleConfig(
                backgroundColor: Color(red: 0.15, green: 0.15, blue: 0.15),
                barColor: Color.white,
                backgroundOpacity: 0.85,
                useMaterial: false
            )
        
        // 深色背景+亮色音量条系列
        case .darkBlueCyan:
            return ColorStyleConfig(
                backgroundColor: Color(red: 0.1, green: 0.2, blue: 0.35),
                barColor: Color(red: 0.0, green: 0.9, blue: 1.0),  // 青色
                backgroundOpacity: 0.85,
                useMaterial: false
            )
            
        case .darkPurplePink:
            return ColorStyleConfig(
                backgroundColor: Color(red: 0.25, green: 0.1, blue: 0.35),
                barColor: Color(red: 1.0, green: 0.4, blue: 0.7),  // 粉色
                backgroundOpacity: 0.85,
                useMaterial: false
            )
            
        case .darkGreenLime:
            return ColorStyleConfig(
                backgroundColor: Color(red: 0.1, green: 0.3, blue: 0.15),
                barColor: Color(red: 0.5, green: 1.0, blue: 0.3),  // 亮绿
                backgroundOpacity: 0.85,
                useMaterial: false
            )
            
        case .darkRedCoral:
            return ColorStyleConfig(
                backgroundColor: Color(red: 0.35, green: 0.1, blue: 0.1),
                barColor: Color(red: 1.0, green: 0.5, blue: 0.4),  // 珊瑚色
                backgroundOpacity: 0.85,
                useMaterial: false
            )
        
        // 深灰背景+彩色音量条系列
        case .darkGrayBlue:
            return ColorStyleConfig(
                backgroundColor: Color(red: 0.2, green: 0.2, blue: 0.2),
                barColor: Color(red: 0.0, green: 0.6, blue: 1.0),  // 蓝色
                backgroundOpacity: 0.85,
                useMaterial: false
            )
            
        case .darkGrayGreen:
            return ColorStyleConfig(
                backgroundColor: Color(red: 0.2, green: 0.2, blue: 0.2),
                barColor: Color(red: 0.2, green: 0.8, blue: 0.4),  // 绿色
                backgroundOpacity: 0.85,
                useMaterial: false
            )
            
        case .darkGrayOrange:
            return ColorStyleConfig(
                backgroundColor: Color(red: 0.2, green: 0.2, blue: 0.2),
                barColor: Color(red: 1.0, green: 0.6, blue: 0.0),  // 橙色
                backgroundOpacity: 0.85,
                useMaterial: false
            )
            
        case .darkGrayPink:
            return ColorStyleConfig(
                backgroundColor: Color(red: 0.2, green: 0.2, blue: 0.2),
                barColor: Color(red: 1.0, green: 0.3, blue: 0.5),  // 粉色
                backgroundOpacity: 0.85,
                useMaterial: false
            )
            
        case .darkGrayPurple:
            return ColorStyleConfig(
                backgroundColor: Color(red: 0.2, green: 0.2, blue: 0.2),
                barColor: Color(red: 0.7, green: 0.4, blue: 0.9),  // 紫色
                backgroundOpacity: 0.85,
                useMaterial: false
            )
            
        case .darkGrayRed:
            return ColorStyleConfig(
                backgroundColor: Color(red: 0.2, green: 0.2, blue: 0.2),
                barColor: Color(red: 1.0, green: 0.3, blue: 0.3),  // 红色
                backgroundOpacity: 0.85,
                useMaterial: false
            )
            
        case .darkGrayYellow:
            return ColorStyleConfig(
                backgroundColor: Color(red: 0.2, green: 0.2, blue: 0.2),
                barColor: Color(red: 1.0, green: 0.9, blue: 0.2),  // 黄色
                backgroundOpacity: 0.85,
                useMaterial: false
            )
            
        case .darkGrayCyan:
            return ColorStyleConfig(
                backgroundColor: Color(red: 0.2, green: 0.2, blue: 0.2),
                barColor: Color(red: 0.0, green: 0.8, blue: 0.9),  // 青色
                backgroundOpacity: 0.85,
                useMaterial: false
            )
        }
    }
    
    /// 兼容旧版本的 color 属性
    var color: Color {
        return colorConfig(for: .dark).barColor
    }
    
    /// 兼容旧版本的 adaptiveColor 方法
    func adaptiveColor(for colorScheme: ColorScheme) -> Color {
        return colorConfig(for: colorScheme).barColor
    }
}

