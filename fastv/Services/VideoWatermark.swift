//
//  VideoWatermark.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import Foundation
import AppKit

/// 水印位置
enum WatermarkPosition: String, CaseIterable {
    case topLeft = "top-left"
    case topCenter = "top-center"
    case topRight = "top-right"
    case middleLeft = "middle-left"
    case center = "center"
    case middleRight = "middle-right"
    case bottomLeft = "bottom-left"
    case bottomCenter = "bottom-center"
    case bottomRight = "bottom-right"
    
    var displayName: String {
        switch self {
        case .topLeft: return "左上"
        case .topCenter: return "上中"
        case .topRight: return "右上"
        case .middleLeft: return "左中"
        case .center: return "中心"
        case .middleRight: return "右中"
        case .bottomLeft: return "左下"
        case .bottomCenter: return "下中"
        case .bottomRight: return "右下"
        }
    }
    
    /// 计算 overlay 位置表达式
    func overlayPosition(watermarkWidth: Int, watermarkHeight: Int, videoWidth: Int, videoHeight: Int, margin: Int = 20) -> String {
        let w = watermarkWidth
        let h = watermarkHeight
        let W = videoWidth
        let H = videoHeight
        let m = margin
        
        switch self {
        case .topLeft:
            return "\(m):\(m)"
        case .topCenter:
            return "(W-w)/2:\(m)"
        case .topRight:
            return "W-w-\(m):\(m)"
        case .middleLeft:
            return "\(m):(H-h)/2"
        case .center:
            return "(W-w)/2:(H-h)/2"
        case .middleRight:
            return "W-w-\(m):(H-h)/2"
        case .bottomLeft:
            return "\(m):H-h-\(m)"
        case .bottomCenter:
            return "(W-w)/2:H-h-\(m)"
        case .bottomRight:
            return "W-w-\(m):H-h-\(m)"
        }
    }
    
    /// 计算 drawtext 位置表达式
    func textPosition(margin: Int = 20) -> String {
        let m = margin
        
        switch self {
        case .topLeft:
            return "x=\(m):y=\(m)"
        case .topCenter:
            return "x=(w-text_w)/2:y=\(m)"
        case .topRight:
            return "x=w-tw-\(m):y=\(m)"
        case .middleLeft:
            return "x=\(m):y=(h-text_h)/2"
        case .center:
            return "x=(w-text_w)/2:y=(h-text_h)/2"
        case .middleRight:
            return "x=w-tw-\(m):y=(h-text_h)/2"
        case .bottomLeft:
            return "x=\(m):y=h-th-\(m)"
        case .bottomCenter:
            return "x=(w-text_w)/2:y=h-th-\(m)"
        case .bottomRight:
            return "x=w-tw-\(m):y=h-th-\(m)"
        }
    }
}

/// 视频水印服务
struct VideoWatermark {
    
    /// 添加图片水印
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - watermarkImageURL: 水印图片文件 URL
    ///   - position: 水印位置（当 customPosition 为 nil 时使用）
    ///   - customPosition: 自定义位置（视频坐标系，nil 表示使用预设位置）
    ///   - customSize: 自定义大小（视频坐标系，nil 表示使用默认大小）
    ///   - opacity: 透明度（0.0-1.0）
    ///   - margin: 边距（像素）
    ///   - progressHandler: 进度回调
    static func addImageWatermark(
        inputURL: URL,
        outputURL: URL,
        watermarkImageURL: URL,
        position: WatermarkPosition,
        customPosition: CGPoint? = nil,
        customSize: CGSize? = nil,
        opacity: Double = 1.0,
        margin: Int = 20,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        // 在后台线程执行，避免阻塞主线程
        try await Task.detached(priority: .userInitiated) {
            // 开启安全作用域
            let hasInputAccess = inputURL.startAccessingSecurityScopedResource()
            let hasWatermarkAccess = watermarkImageURL.startAccessingSecurityScopedResource()
            defer {
                if hasInputAccess { inputURL.stopAccessingSecurityScopedResource() }
                if hasWatermarkAccess { watermarkImageURL.stopAccessingSecurityScopedResource() }
            }
            
            // 验证输入文件是否存在
            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                throw NSError(domain: "VideoWatermark", code: -1, userInfo: [NSLocalizedDescriptionKey: "输入视频文件不存在"])
            }
            
            guard FileManager.default.fileExists(atPath: watermarkImageURL.path) else {
                throw NSError(domain: "VideoWatermark", code: -1, userInfo: [NSLocalizedDescriptionKey: "水印图片文件不存在"])
            }
            
            await MainActor.run {
                progressHandler(0.05, "正在获取视频信息...")
            }
            
            // 获取视频尺寸
            let videoInfo = try await VideoInfoService.getVideoInfo(from: inputURL)
            let videoWidth = Int(videoInfo.resolution.width)
            let videoHeight = Int(videoInfo.resolution.height)
            
            await MainActor.run {
                progressHandler(0.1, "正在加载水印图片...")
            }
            
            // 获取水印图片尺寸（在后台线程加载）
            guard let watermarkImage = NSImage(contentsOf: watermarkImageURL) else {
                throw NSError(domain: "VideoWatermark", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法加载水印图片"])
            }
            
            // 基本有效性检查，避免生成 0 尺寸导致 ffmpeg 报错
            guard videoWidth > 0, videoHeight > 0 else {
                throw NSError(domain: "VideoWatermark", code: -1, userInfo: [NSLocalizedDescriptionKey: "视频尺寸无效"])
            }
            guard watermarkImage.size.width > 0, watermarkImage.size.height > 0 else {
                throw NSError(domain: "VideoWatermark", code: -1, userInfo: [NSLocalizedDescriptionKey: "水印图片尺寸无效"])
            }
        
        // 计算实际使用的水印尺寸
        let finalWatermarkSize: CGSize
        if let customSize = customSize {
            finalWatermarkSize = customSize
        } else {
            // 使用默认大小计算（限制为视频宽度的 15%）
            let maxWidth = CGFloat(videoWidth) * 0.15
            let maxHeight = CGFloat(videoHeight) * 0.15
            let aspectRatio = watermarkImage.size.width / watermarkImage.size.height
            
            if watermarkImage.size.width > maxWidth || watermarkImage.size.height > maxHeight {
                if watermarkImage.size.width / maxWidth > watermarkImage.size.height / maxHeight {
                    finalWatermarkSize = CGSize(width: maxWidth, height: maxWidth / aspectRatio)
                } else {
                    finalWatermarkSize = CGSize(width: maxHeight * aspectRatio, height: maxHeight)
                }
            } else {
                finalWatermarkSize = watermarkImage.size
            }
        }
        
            let watermarkWidth = Int(finalWatermarkSize.width)
            let watermarkHeight = Int(finalWatermarkSize.height)
            
            await MainActor.run {
                progressHandler(0.15, "正在构建水印滤镜...")
            }
            
            var arguments: [String] = []
            arguments.append("-y") // 允许覆盖
            arguments.append("-hide_banner")
            // 开启 info 日志，让错误时能拿到 stderr 详情
            arguments.append("-loglevel")
            arguments.append("info")
            arguments.append("-i")
            arguments.append(inputURL.path)
            arguments.append("-i")
            arguments.append(watermarkImageURL.path)
        
            // 构建 overlay 滤镜
            // 格式: overlay=x:y:format=auto
            // 位置表达式需要根据视频尺寸动态计算
            let overlayExpr: String
            if let customPos = customPosition {
                // 使用自定义位置
                overlayExpr = "\(Int(customPos.x)):\(Int(customPos.y))"
            } else {
                // 使用预设位置
                overlayExpr = position.overlayPosition(
                    watermarkWidth: watermarkWidth,
                    watermarkHeight: watermarkHeight,
                    videoWidth: videoWidth,
                    videoHeight: videoHeight,
                    margin: margin
                )
            }
            
            // 构建滤镜链
            var filterComplex = ""
            
            // 如果需要调整大小，先缩放水印图片
            if customSize != nil {
                // 缩放水印图片到指定大小
                if opacity < 1.0 {
                    // 缩放 + 透明度
                    filterComplex = "[1:v]scale=\(watermarkWidth):\(watermarkHeight),format=rgba,colorchannelmixer=aa=\(opacity)[watermark];"
                    filterComplex += "[0:v][watermark]overlay=\(overlayExpr)"
                } else {
                    // 只缩放
                    filterComplex = "[1:v]scale=\(watermarkWidth):\(watermarkHeight)[scaled_watermark];"
                    filterComplex += "[0:v][scaled_watermark]overlay=\(overlayExpr)"
                }
            } else {
                // 不调整大小
                if opacity < 1.0 {
                    // 只透明度
                    filterComplex = "[1:v]format=rgba,colorchannelmixer=aa=\(opacity)[watermark];"
                    filterComplex += "[0:v][watermark]overlay=\(overlayExpr)"
                } else {
                    // 直接叠加
                    filterComplex = "[0:v][1:v]overlay=\(overlayExpr)"
                }
            }
            
            arguments.append("-filter_complex")
            arguments.append(filterComplex)
            
            // 视频编码
            arguments.append("-c:v")
            arguments.append("libx264")
            
            // 音频编码（复制）
            arguments.append("-c:a")
            arguments.append("copy")
            
            // 明确指定输出格式（根据文件扩展名）
            let outputExtension = outputURL.pathExtension.lowercased()
            if outputExtension == "mov" {
                arguments.append("-f")
                arguments.append("mov")
            } else {
                // 默认使用 mp4
                arguments.append("-f")
                arguments.append("mp4")
            }
            
            arguments.append("-y")
            arguments.append(outputURL.path)
            
            await MainActor.run {
                progressHandler(0.2, "正在处理视频...")
            }
            
            var ffmpegLog = ""
            // 记录命令行，方便诊断
            let cmdLine = "ffmpeg " + arguments.joined(separator: " ")
            ffmpegLog.append(cmdLine + "\n")
            print("▶️ [VideoWatermark] cmd: \(cmdLine)")
            do {
                try await FFmpegService.execute(
                    arguments: arguments,
                    progressHandler: { progress, status in
                        let mappedProgress = 0.2 + (progress * 0.8)
                        Task { @MainActor in
                            progressHandler(mappedProgress, status)
                        }
                    },
                    outputHandler: { line in
                        ffmpegLog.append(line + "\n")
                    }
                )
            } catch let error as FFmpegError {
                switch error {
                case .executionFailed(let code, let message):
                    let merged = message.isEmpty ? ffmpegLog : message
                    print("❌ [VideoWatermark] FFmpeg failed code=\(code)\n\(merged)")
                    throw FFmpegError.executionFailed(code: code, message: merged)
                default:
                    print("❌ [VideoWatermark] FFmpeg error: \(error)")
                    throw error
                }
            } catch {
                print("❌ [VideoWatermark] error: \(error)")
                throw error
            }
            
            // 验证输出文件是否创建成功
            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                throw NSError(domain: "VideoWatermark", code: -1, userInfo: [NSLocalizedDescriptionKey: "输出文件创建失败"])
            }
            
            await MainActor.run {
                progressHandler(1.0, "水印添加完成！")
            }
        }.value
    }
    
    /// 添加文字水印
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - text: 水印文字
    ///   - position: 水印位置
    ///   - fontSize: 字体大小
    ///   - fontColor: 字体颜色（十六进制，如 FFFFFF）
    ///   - fontPath: 字体文件路径（可选，用于中文字体）
    ///   - opacity: 透明度（0.0-1.0）
    ///   - margin: 边距（像素）
    ///   - progressHandler: 进度回调
    static func addTextWatermark(
        inputURL: URL,
        outputURL: URL,
        text: String,
        position: WatermarkPosition,
        fontSize: Int = 24,
        fontColor: String = "FFFFFF",
        fontPath: String? = nil,
        opacity: Double = 1.0,
        margin: Int = 20,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        // 在后台线程执行，避免阻塞主线程
        try await Task.detached(priority: .userInitiated) {
            let hasInputAccess = inputURL.startAccessingSecurityScopedResource()
            defer { if hasInputAccess { inputURL.stopAccessingSecurityScopedResource() } }
            
            // 验证输入文件是否存在
            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                throw NSError(domain: "VideoWatermark", code: -1, userInfo: [NSLocalizedDescriptionKey: "输入视频文件不存在"])
            }
            
            await MainActor.run {
                progressHandler(0.1, "正在处理视频...")
            }
            
            // 强制要求字体文件
            guard let fontPath = fontPath, FileManager.default.fileExists(atPath: fontPath) else {
                throw NSError(domain: "VideoWatermark", code: -1, userInfo: [NSLocalizedDescriptionKey: "字体文件不存在或未指定，请先选择字体文件"])
            }
            
            var arguments: [String] = []
            arguments.append("-y")
            arguments.append("-hide_banner")
            arguments.append("-loglevel")
            arguments.append("info")
            
            arguments.append("-i")
            arguments.append(inputURL.path)
            
            // 构建 drawtext 滤镜
            // FFmpeg drawtext 滤镜格式：drawtext=text='...':x=...:y=...:fontsize=...:fontcolor=...:fontfile='...'
            
            // 转义文字内容中的特殊字符
            // 需要转义：单引号、冒号、反斜杠
            let escapedText = text
                .replacingOccurrences(of: "\\", with: "\\\\")  // 先转义反斜杠
                .replacingOccurrences(of: "'", with: "\\'")     // 转义单引号
                .replacingOccurrences(of: ":", with: "\\:")     // 转义冒号
            
            // 转义字体文件路径中的特殊字符
            let escapedFontPath = fontPath
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: ":", with: "\\:")
            
            // 位置表达式
            let posExpr = position.textPosition(margin: margin)
            
            // 字体颜色和透明度
            let alpha = Int(opacity * 255)
            let colorHex = String(format: "%@%02X", fontColor, alpha)
            
            // 构建完整的 drawtext 滤镜字符串
            // 注意：所有参数值如果包含特殊字符，需要用单引号包裹
            let drawtextFilter = "drawtext=text='\(escapedText)':\(posExpr):fontsize=\(fontSize):fontcolor=0x\(colorHex):fontfile='\(escapedFontPath)':borderw=2:bordercolor=0x00000080"
            
            arguments.append("-vf")
            arguments.append(drawtextFilter)
            
            // 视频编码
            arguments.append("-c:v")
            arguments.append("libx264")
            
            // 音频编码（复制）
            arguments.append("-c:a")
            arguments.append("copy")
            
            // 明确指定输出格式（根据文件扩展名）
            let outputExtension = outputURL.pathExtension.lowercased()
            if outputExtension == "mov" {
                arguments.append("-f")
                arguments.append("mov")
            } else {
                arguments.append("-f")
                arguments.append("mp4")
            }
            
            arguments.append(outputURL.path)
            
            var ffmpegLog = ""
            let cmdLine = "ffmpeg " + arguments.joined(separator: " ")
            ffmpegLog.append(cmdLine + "\n")
            print("▶️ [VideoWatermark] cmd: \(cmdLine)")
            
            do {
                try await FFmpegService.execute(
                    arguments: arguments,
                    progressHandler: { progress, status in
                        let mappedProgress = 0.1 + (progress * 0.9)
                        Task { @MainActor in
                            progressHandler(mappedProgress, status)
                        }
                    },
                    outputHandler: { line in
                        ffmpegLog.append(line + "\n")
                    }
                )
            } catch let error as FFmpegError {
                switch error {
                case .executionFailed(let code, let message):
                    let merged = message.isEmpty ? ffmpegLog : message
                    print("❌ [VideoWatermark] FFmpeg failed code=\(code)\n\(merged)")
                    throw FFmpegError.executionFailed(code: code, message: merged)
                default:
                    print("❌ [VideoWatermark] FFmpeg error: \(error)")
                    throw error
                }
            } catch {
                print("❌ [VideoWatermark] error: \(error)")
                throw error
            }
            
            // 验证输出文件是否创建成功
            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                throw NSError(domain: "VideoWatermark", code: -1, userInfo: [NSLocalizedDescriptionKey: "输出文件创建失败"])
            }
            
            await MainActor.run {
                progressHandler(1.0, "水印添加完成！")
            }
        }.value
    }
    
    /// 添加时间戳水印
    static func addTimestampWatermark(
        inputURL: URL,
        outputURL: URL,
        position: WatermarkPosition,
        fontSize: Int = 20,
        fontColor: String = "FFFFFF",
        fontPath: String? = nil,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        // 在后台线程执行，避免阻塞主线程
        try await Task.detached(priority: .userInitiated) {
            let hasInputAccess = inputURL.startAccessingSecurityScopedResource()
            defer { if hasInputAccess { inputURL.stopAccessingSecurityScopedResource() } }
            
            // 验证输入文件是否存在
            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                throw NSError(domain: "VideoWatermark", code: -1, userInfo: [NSLocalizedDescriptionKey: "输入视频文件不存在"])
            }
            
            await MainActor.run {
                progressHandler(0.1, "正在处理视频...")
            }
            
            // 强制要求字体文件
            guard let fontPath = fontPath, FileManager.default.fileExists(atPath: fontPath) else {
                throw NSError(domain: "VideoWatermark", code: -1, userInfo: [NSLocalizedDescriptionKey: "字体文件不存在或未指定，请先选择字体文件"])
            }
            
            var arguments: [String] = []
            arguments.append("-y")
            arguments.append("-hide_banner")
            arguments.append("-loglevel")
            arguments.append("info")
            arguments.append("-i")
            arguments.append(inputURL.path)
            
            // 转义字体文件路径中的特殊字符
            let escapedFontPath = fontPath
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: ":", with: "\\:")
            
            let posExpr = position.textPosition(margin: 20)
            
            // 构建完整的 drawtext 滤镜字符串
            let drawtextFilter = "drawtext=text='%{localtime:%Y-%m-%d %H:%M:%S}':\(posExpr):fontsize=\(fontSize):fontcolor=0x\(fontColor):fontfile='\(escapedFontPath)':borderw=2:bordercolor=0x00000080"
            
            arguments.append("-vf")
            arguments.append(drawtextFilter)
            arguments.append("-c:v")
            arguments.append("libx264")
            arguments.append("-c:a")
            arguments.append("copy")
            
            let outputExtension = outputURL.pathExtension.lowercased()
            if outputExtension == "mov" {
                arguments.append("-f")
                arguments.append("mov")
            } else {
                arguments.append("-f")
                arguments.append("mp4")
            }
            arguments.append(outputURL.path)
            
            var ffmpegLog = ""
            let cmdLine = "ffmpeg " + arguments.joined(separator: " ")
            ffmpegLog.append(cmdLine + "\n")
            print("▶️ [VideoWatermark] cmd: \(cmdLine)")
            
            do {
                try await FFmpegService.execute(
                    arguments: arguments,
                    progressHandler: { progress, status in
                        let mappedProgress = 0.1 + (progress * 0.9)
                        Task { @MainActor in
                            progressHandler(mappedProgress, status)
                        }
                    },
                    outputHandler: { line in
                        ffmpegLog.append(line + "\n")
                    }
                )
            } catch let error as FFmpegError {
                switch error {
                case .executionFailed(let code, let message):
                    let merged = message.isEmpty ? ffmpegLog : message
                    print("❌ [VideoWatermark] FFmpeg failed code=\(code)\n\(merged)")
                    throw FFmpegError.executionFailed(code: code, message: merged)
                default:
                    print("❌ [VideoWatermark] FFmpeg error: \(error)")
                    throw error
                }
            } catch {
                print("❌ [VideoWatermark] error: \(error)")
                throw error
            }
            
            // 验证输出文件是否创建成功
            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                throw NSError(domain: "VideoWatermark", code: -1, userInfo: [NSLocalizedDescriptionKey: "输出文件创建失败"])
            }
            
            await MainActor.run {
                progressHandler(1.0, "水印添加完成！")
            }
        }.value
    }
}
