//
//  VideoSubtitle.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import Foundation

/// 字幕样式
struct SubtitleStyle {
    var fontSize: Int = 28
    var fontColor: String = "FFFFFF" // 十六进制颜色
    var backgroundColor: String? = nil // 背景色（可选）
    var outlineColor: String = "000000" // 描边颜色
    var outlineWidth: Int = 2 // 描边宽度
    var shadowColor: String? = nil // 阴影颜色（可选）
    var shadowOffset: Int = 2 // 阴影偏移
    var alignment: Int = 2 // 对齐方式：1=左，2=中，3=右
    var marginV: Int = 40 // 垂直边距（从底部）
    var fontName: String = "PingFang SC" // 字体名称
    
    /// 转换为 ASS 样式字符串
    func toASSStyle() -> String {
        var style = "FontName=\(fontName),"
        style += "FontSize=\(fontSize),"
        style += "PrimaryColour=&H\(fontColor),"
        
        if let bgColor = backgroundColor {
            style += "BackColour=&H\(bgColor),"
        }
        
        style += "OutlineColour=&H\(outlineColor),"
        style += "Outline=\(outlineWidth),"
        
        if let shadowColor = shadowColor {
            style += "ShadowColour=&H\(shadowColor),"
            style += "Shadow=\(shadowOffset),"
        }
        
        style += "Alignment=\(alignment),"
        style += "MarginV=\(marginV)"
        
        return style
    }
}

/// 视频字幕服务
struct VideoSubtitle {
    
    /// 烧录 SRT 字幕文件
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - subtitleURL: SRT 字幕文件 URL
    ///   - style: 字幕样式
    ///   - fontPath: 字体文件路径（用于中文字体）
    ///   - progressHandler: 进度回调
    static func burnSRTSubtitle(
        inputURL: URL,
        outputURL: URL,
        subtitleURL: URL,
        style: SubtitleStyle = SubtitleStyle(),
        fontPath: String? = nil,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        // 构建 subtitles 滤镜
        var subtitleFilter = "subtitles='\(subtitleURL.path)'"
        
        // 添加样式
        let styleStr = style.toASSStyle()
        subtitleFilter += ":force_style='\(styleStr)'"
        
        // 如果指定了字体文件，使用 fontsdir 参数
        if let fontPath = fontPath, FileManager.default.fileExists(atPath: fontPath) {
            let fontDir = (fontPath as NSString).deletingLastPathComponent
            subtitleFilter += ":fontsdir='\(fontDir)'"
        }
        
        arguments.append("-vf")
        arguments.append(subtitleFilter)
        
        // 视频编码
        arguments.append("-c:v")
        arguments.append("libx264")
        
        // 音频编码（复制）
        arguments.append("-c:a")
        arguments.append("copy")
        
        arguments.append("-y")
        arguments.append(outputURL.path)
        
        try await FFmpegService.execute(
            arguments: arguments,
            progressHandler: progressHandler
        )
    }
    
    /// 烧录 ASS 字幕文件
    static func burnASSSubtitle(
        inputURL: URL,
        outputURL: URL,
        subtitleURL: URL,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        // ASS 字幕直接使用 subtitles 滤镜
        arguments.append("-vf")
        arguments.append("subtitles='\(subtitleURL.path)'")
        
        arguments.append("-c:v")
        arguments.append("libx264")
        
        arguments.append("-c:a")
        arguments.append("copy")
        
        arguments.append("-y")
        arguments.append(outputURL.path)
        
        try await FFmpegService.execute(
            arguments: arguments,
            progressHandler: progressHandler
        )
    }
    
    /// 添加固定文字字幕（使用 drawtext）
    static func addFixedSubtitle(
        inputURL: URL,
        outputURL: URL,
        text: String,
        startTime: TimeInterval = 0,
        duration: TimeInterval? = nil,
        style: SubtitleStyle = SubtitleStyle(),
        fontPath: String? = nil,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        // 构建 drawtext 滤镜
        var drawtextParams: [String] = []
        
        // 文字内容
        let escapedText = text.replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: "'", with: "\\'")
        drawtextParams.append("text='\(escapedText)'")
        
        // 位置（底部居中）
        drawtextParams.append("x=(w-text_w)/2")
        drawtextParams.append("y=h-th-\(style.marginV)")
        
        // 字体大小
        drawtextParams.append("fontsize=\(style.fontSize)")
        
        // 字体颜色
        drawtextParams.append("fontcolor=0x\(style.fontColor)")
        
        // 字体文件
        if let fontPath = fontPath {
            drawtextParams.append("fontfile='\(fontPath)'")
        } else {
            // 使用系统字体（macOS 中文字体）
            drawtextParams.append("font='\(style.fontName)'")
        }
        
        // 描边
        drawtextParams.append("borderw=\(style.outlineWidth)")
        drawtextParams.append("bordercolor=0x\(style.outlineColor)")
        
        // 时间范围
        if let duration = duration {
            drawtextParams.append("enable='between(t,\(startTime),\(startTime + duration))'")
        } else {
            drawtextParams.append("enable='gte(t,\(startTime))'")
        }
        
        let drawtextFilter = drawtextParams.joined(separator: ":")
        
        arguments.append("-vf")
        arguments.append(drawtextFilter)
        
        arguments.append("-c:v")
        arguments.append("libx264")
        
        arguments.append("-c:a")
        arguments.append("copy")
        
        arguments.append("-y")
        arguments.append(outputURL.path)
        
        try await FFmpegService.execute(
            arguments: arguments,
            progressHandler: progressHandler
        )
    }
    
    /// 获取系统默认中文字体路径
    static func getDefaultChineseFontPath() -> String? {
        // macOS 系统字体路径
        let systemFonts = [
            "/System/Library/Fonts/PingFang.ttc",
            "/System/Library/Fonts/STHeiti Light.ttc",
            "/System/Library/Fonts/STSong.ttc"
        ]
        
        for fontPath in systemFonts {
            if FileManager.default.fileExists(atPath: fontPath) {
                return fontPath
            }
        }
        
        return nil
    }
}
