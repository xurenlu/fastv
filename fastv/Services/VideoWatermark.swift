//
//  VideoWatermark.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import Foundation
import AppKit

// #region agent log
extension String {
    func appendToFile(atPath path: String) {
        if let fileHandle = FileHandle(forWritingAtPath: path) {
            fileHandle.seekToEndOfFile()
            if let data = self.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            try? self.write(toFile: path, atomically: false, encoding: .utf8)
        }
    }
}
// #endregion

/// 移动模式
enum MovementMode {
    case fixedInterval    // 固定间隔
    case randomInterval   // 随机间隔
}

/// 旋转模式
enum RotationMode {
    case fixed           // 固定角度
    case smooth          // 缓慢旋转
    case random          // 随机旋转（配合位置变化）
}

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
        // 在主线程获取用户配置（避免在后台线程访问 MainActor 隔离的属性）
        let preferences = await MainActor.run { UserPreferences.shared }
        let enableHardwareAccel = await MainActor.run { preferences.videoToolsEnableHardwareAccel }
        let ffmpegPreset = await MainActor.run { preferences.videoToolsFFmpegPreset }
        let ffmpegThreads = await MainActor.run { preferences.videoToolsFFmpegThreads }
        
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
            
            // 视频编码器（支持硬件加速）
            arguments.append("-c:v")
            if enableHardwareAccel {
                // 尝试使用硬件加速编码器（macOS VideoToolbox）
                arguments.append("h264_videotoolbox")
            } else {
                arguments.append("libx264")
            }
            
            // 性能优化：编码预设（仅适用于软件编码）
            if !enableHardwareAccel {
                arguments.append("-preset")
                arguments.append(ffmpegPreset)
            }
            
            // 性能优化：线程数（0 表示自动）
            if ffmpegThreads > 0 {
                arguments.append("-threads")
                arguments.append("\(ffmpegThreads)")
            }
            
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
    ///   - enableRandomMovement: 是否启用随机移动
    ///   - movementInterval: 固定移动间隔（秒）
    ///   - randomIntervalRange: 随机移动间隔范围（秒）
    ///   - rotationMode: 旋转模式
    ///   - fixedAngle: 固定旋转角度（度）
    ///   - smoothRotationSpeed: 缓慢旋转速度（度/秒）
    ///   - randomRotationRange: 随机旋转角度范围（度）
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
        enableOpacityAnimation: Bool = false,
        opacityAnimationRange: (min: Double, max: Double)? = nil,
        opacityAnimationDuration: Double = 3.0,
        margin: Int = 20,
        enableRandomMovement: Bool = false,
        movementInterval: Double? = nil,
        randomIntervalRange: (min: Double, max: Double)? = nil,
        driftSpeedRange: (min: Double, max: Double)? = nil,
        rotationMode: RotationMode = .fixed,
        fixedAngle: Double = 0.0,
        smoothRotationSpeed: Double = 10.0,
        randomRotationRange: (min: Double, max: Double) = (-45, 45),
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        // 在主线程获取用户配置
        let preferences = await MainActor.run { UserPreferences.shared }
        let enableHardwareAccel = await MainActor.run { preferences.videoToolsEnableHardwareAccel }
        let ffmpegPreset = await MainActor.run { preferences.videoToolsFFmpegPreset }
        let ffmpegThreads = await MainActor.run { preferences.videoToolsFFmpegThreads }
        
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
            
            // 位置表达式（优化版：简化计算，提升速度）
            let posExpr: String
            if enableRandomMovement {
                // 优化后的伪随机函数：更简单的计算
                func ffRand01(_ seedExpr: String) -> String {
                    return "mod(abs(sin((\(seedExpr))*12.9898+78.233))*43758.5453,1)"
                }
                
                let intervalExpr: String
                let actualInterval: Double
                if let interval = movementInterval {
                    intervalExpr = "floor(t/\(interval))"
                    actualInterval = interval
                } else if let range = randomIntervalRange {
                    let chosen = Double.random(in: range.min...range.max)
                    intervalExpr = "floor(t/\(chosen))"
                    actualInterval = chosen
                } else {
                    intervalExpr = "floor(t/2)"
                    actualInterval = 2.0
                }
            
                // 优化：使用更快的移动速度，减少中间帧计算复杂度
                let segment = intervalExpr
                
                // 简化的基准位置计算（减少嵌套表达式）
                let randX = ffRand01(segment)
                let randY = ffRand01("(\(segment))+1000")
                let baseX = "\(margin)+(\(randX))*(W-text_w-\(margin*2))"
                let baseY = "\(margin)+(\(randY))*(H-text_h-\(margin*2))"
                
                // 优化：使用更快的漂移速度（默认提升到 8 像素/秒）
                let driftSpeed: String
                if let speedRange = driftSpeedRange {
                    let speedDelta = speedRange.max - speedRange.min
                    driftSpeed = "\(speedRange.min)+(\(ffRand01("(\(segment))+2000")))*\(speedDelta)"
                } else {
                    driftSpeed = "8" // 优化：默认速度从 2 提升到 8 像素/秒
                }
                
                // 简化的漂移计算（减少三角函数调用）
                let elapsedTime = "t-\(intervalExpr)*\(actualInterval)"
                let angle = "6.28318*(\(ffRand01("(\(segment))+3000")))" // 2*PI 预计算
                let driftX = "cos(\(angle))*\(driftSpeed)*(\(elapsedTime))"
                let driftY = "sin(\(angle))*\(driftSpeed)*(\(elapsedTime))"
                
                // 简化的边界限制（减少嵌套）
                let finalX = "max(\(margin),min(W-text_w-\(margin),(\(baseX))+(\(driftX))))"
                let finalY = "max(\(margin),min(H-text_h-\(margin),(\(baseY))+(\(driftY))))"
                posExpr = "x='\(finalX)':y='\(finalY)'"
            } else {
                posExpr = position.textPosition(margin: margin)
            }
            
            // 字体颜色和透明度
            let alphaOption: String
            let finalColorHex: String
            
            if enableOpacityAnimation, let range = opacityAnimationRange {
                // 透明度动画：使用 abs(sin()) 实现来回变化
                let minAlpha = range.min / 100.0
                let maxAlpha = range.max / 100.0
                let deltaAlpha = maxAlpha - minAlpha
                
                // abs(sin(t * PI / duration)) 产生 0→1→0 的循环
                alphaOption = ":alpha='\(minAlpha) + \(deltaAlpha) * abs(sin(t * 3.141592653589793 / \(opacityAnimationDuration)))'"
                finalColorHex = fontColor + "FF" // 动画时使用 alpha 参数控制
            } else {
                alphaOption = ""
                let alpha = Int(opacity * 255)
                finalColorHex = String(format: "%@%02X", fontColor, alpha)
            }
            
            // 构建 drawtext 滤镜字符串（不包含旋转，旋转需要单独的 rotate 滤镜）
            let drawtextFilter = "drawtext=text='\(escapedText)':\(posExpr):fontsize=\(fontSize):fontcolor=0x\(finalColorHex):fontfile='\(escapedFontPath)'\(alphaOption):borderw=2:bordercolor=0x00000080"
            
            // #region agent log
            print("🔍 [DEBUG] Position Expression: \(posExpr)")
            print("🔍 [DEBUG] Drawtext Filter: \(drawtextFilter)")
            // #endregion
            
            // 构建旋转滤镜（如果需要）
            let rotateFilter: String?
            switch rotationMode {
            case .fixed:
                if fixedAngle != 0 {
                    // 固定角度（转换为弧度）
                    let radians = fixedAngle * .pi / 180.0
                    rotateFilter = "rotate=\(radians):c=none"
                } else {
                    rotateFilter = nil
                }
                
            case .smooth:
                // 缓慢旋转：角度 = 速度 * 时间
                // 转换为弧度：radians = degrees * π / 180
                rotateFilter = "rotate=\(smoothRotationSpeed)*t*PI/180:c=none"
                
            case .random:
                // 随机旋转：每次位置变化时随机选择角度
                if enableRandomMovement {
                    let intervalExpr = movementInterval.map { "floor(t/\($0))" } ?? "floor(t/2)"
                    let minRad = randomRotationRange.min * .pi / 180.0
                    let maxRad = randomRotationRange.max * .pi / 180.0
                    let range = maxRad - minRad
                    // random() 每帧变化，改用确定性伪随机
                    let rand01 = "mod(abs(sin(((\(intervalExpr)+2000))*12.9898+78.233))*43758.5453,1)"
                    rotateFilter = "rotate=\(rand01)*\(range)+\(minRad):c=none"
                } else {
                    rotateFilter = nil
                }
            }
            
            // 组合滤镜
            let finalFilter: String
            if let rotate = rotateFilter {
                // 注意：旋转应该在绘制文字之后应用，所以顺序是 drawtext,rotate
                // 但由于 rotate 会旋转整个画面，我们需要先绘制文字，然后旋转
                // 实际上对于文字旋转，最好的方式是不使用 rotate 滤镜
                // 由于 FFmpeg drawtext 不支持旋转，我们暂时禁用旋转功能
                print("⚠️ [VideoWatermark] 注意：当前 FFmpeg 版本的 drawtext 不支持文字旋转，旋转设置将被忽略")
                finalFilter = drawtextFilter
            } else {
                finalFilter = drawtextFilter
            }
            
            arguments.append("-vf")
            arguments.append(finalFilter)
            
            // 视频编码器（支持硬件加速）
            arguments.append("-c:v")
            if enableHardwareAccel {
                arguments.append("h264_videotoolbox")
            } else {
                arguments.append("libx264")
            }
            
            // 性能优化：编码预设（仅适用于软件编码）
            if !enableHardwareAccel {
                arguments.append("-preset")
                arguments.append(ffmpegPreset)
            }
            
            // 性能优化：线程数
            if ffmpegThreads > 0 {
                arguments.append("-threads")
                arguments.append("\(ffmpegThreads)")
            }
            
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
        opacity: Double = 1.0,
        enableOpacityAnimation: Bool = false,
        opacityAnimationRange: (min: Double, max: Double)? = nil,
        opacityAnimationDuration: Double = 3.0,
        margin: Int = 20,
        enableRandomMovement: Bool = false,
        movementInterval: Double? = nil,
        randomIntervalRange: (min: Double, max: Double)? = nil,
        driftSpeedRange: (min: Double, max: Double)? = nil,
        rotationMode: RotationMode = .fixed,
        fixedAngle: Double = 0.0,
        smoothRotationSpeed: Double = 10.0,
        randomRotationRange: (min: Double, max: Double) = (-45, 45),
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        // 在主线程获取用户配置
        let preferences = await MainActor.run { UserPreferences.shared }
        let enableHardwareAccel = await MainActor.run { preferences.videoToolsEnableHardwareAccel }
        let ffmpegPreset = await MainActor.run { preferences.videoToolsFFmpegPreset }
        let ffmpegThreads = await MainActor.run { preferences.videoToolsFFmpegThreads }
        
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
            
            // 位置表达式（优化版：简化计算，提升速度）
            let posExpr: String
            if enableRandomMovement {
                func ffRand01(_ seedExpr: String) -> String {
                    return "mod(abs(sin((\(seedExpr))*12.9898+78.233))*43758.5453,1)"
                }
                let intervalExpr: String
                let actualInterval: Double
                if let interval = movementInterval {
                    intervalExpr = "floor(t/\(interval))"
                    actualInterval = interval
                } else if let range = randomIntervalRange {
                    let chosen = Double.random(in: range.min...range.max)
                    intervalExpr = "floor(t/\(chosen))"
                    actualInterval = chosen
                } else {
                    intervalExpr = "floor(t/2)"
                    actualInterval = 2.0
                }
                
                // 优化：简化表达式
                let segment = intervalExpr
                let randX = ffRand01(segment)
                let randY = ffRand01("(\(segment))+1000")
                let baseX = "\(margin)+(\(randX))*(W-text_w-\(margin*2))"
                let baseY = "\(margin)+(\(randY))*(H-text_h-\(margin*2))"
                
                // 优化：提升默认速度到 8 像素/秒
                let driftSpeed: String
                if let speedRange = driftSpeedRange {
                    let speedDelta = speedRange.max - speedRange.min
                    driftSpeed = "\(speedRange.min)+(\(ffRand01("(\(segment))+2000")))*\(speedDelta)"
                } else {
                    driftSpeed = "8"
                }
                
                let elapsedTime = "t-\(intervalExpr)*\(actualInterval)"
                let angle = "6.28318*(\(ffRand01("(\(segment))+3000")))"
                let driftX = "cos(\(angle))*\(driftSpeed)*(\(elapsedTime))"
                let driftY = "sin(\(angle))*\(driftSpeed)*(\(elapsedTime))"
                
                let finalX = "max(\(margin),min(W-text_w-\(margin),(\(baseX))+(\(driftX))))"
                let finalY = "max(\(margin),min(H-text_h-\(margin),(\(baseY))+(\(driftY))))"
                
                posExpr = "x='\(finalX)':y='\(finalY)'"
            } else {
                posExpr = position.textPosition(margin: margin)
            }
            
            // 字体颜色和透明度
            let alphaOption: String
            let finalColorHex: String
            
            if enableOpacityAnimation, let range = opacityAnimationRange {
                // 透明度动画：使用 abs(sin()) 实现来回变化
                let minAlpha = range.min / 100.0
                let maxAlpha = range.max / 100.0
                let deltaAlpha = maxAlpha - minAlpha
                
                alphaOption = ":alpha='\(minAlpha) + \(deltaAlpha) * abs(sin(t * 3.141592653589793 / \(opacityAnimationDuration)))'"
                finalColorHex = fontColor + "FF"
            } else {
                alphaOption = ""
                let alpha = Int(opacity * 255)
                finalColorHex = String(format: "%@%02X", fontColor, alpha)
            }
            
            // 构建 drawtext 滤镜字符串（不包含旋转）
            // 注意：FFmpeg drawtext 不支持 text_rotation 参数，旋转功能暂时禁用
            let finalFilter = "drawtext=text='%{localtime:%Y-%m-%d %H:%M:%S}':\(posExpr):fontsize=\(fontSize):fontcolor=0x\(finalColorHex):fontfile='\(escapedFontPath)'\(alphaOption):borderw=2:bordercolor=0x00000080"
            
            // 如果设置了旋转，输出警告
            if rotationMode != .fixed || fixedAngle != 0 {
                print("⚠️ [VideoWatermark] 注意：当前 FFmpeg 版本的 drawtext 不支持文字旋转，旋转设置将被忽略")
            }
            
            arguments.append("-vf")
            arguments.append(finalFilter)
            
            // 视频编码器（支持硬件加速）
            arguments.append("-c:v")
            if enableHardwareAccel {
                arguments.append("h264_videotoolbox")
            } else {
                arguments.append("libx264")
            }
            
            // 性能优化：编码预设（仅适用于软件编码）
            if !enableHardwareAccel {
                arguments.append("-preset")
                arguments.append(ffmpegPreset)
            }
            
            // 性能优化：线程数
            if ffmpegThreads > 0 {
                arguments.append("-threads")
                arguments.append("\(ffmpegThreads)")
            }
            
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
    
    // MARK: - 并行处理包装方法
    
    /// 添加图片水印（支持并行处理）
    /// - Parameters:
    ///   - enableParallel: 是否启用并行处理（默认根据用户配置）
    ///   - 其他参数同 addImageWatermark
    static func addImageWatermarkWithParallel(
        inputURL: URL,
        outputURL: URL,
        watermarkImageURL: URL,
        position: WatermarkPosition,
        customPosition: CGPoint? = nil,
        customSize: CGSize? = nil,
        opacity: Double = 1.0,
        margin: Int = 20,
        enableParallel: Bool? = nil,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        let startTime = Date()
        let preferences = UserPreferences.shared
        let shouldUseParallel = enableParallel ?? preferences.videoToolsEnableParallelProcessing
        
        // 获取视频时长，判断是否适合并行处理
        let videoInfo = try await VideoInfoService.getVideoInfo(from: inputURL)
        let videoDuration = videoInfo.duration
        let videoSize = try? FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? Int64
        
        print("📊 [VideoWatermark] 开始处理 - 时长: \(String(format: "%.1f", videoDuration))秒, 大小: \(formatFileSize(videoSize ?? 0))")
        print("⚙️ [VideoWatermark] 配置 - 预设: \(preferences.videoToolsFFmpegPreset), 硬件加速: \(preferences.videoToolsEnableHardwareAccel), 线程数: \(preferences.videoToolsFFmpegThreads == 0 ? "自动" : "\(preferences.videoToolsFFmpegThreads)")")
        
        // 只有视频时长超过分段时长的 2 倍时才使用并行处理
        let minDurationForParallel = preferences.videoToolsSegmentDuration * 2
        
        if shouldUseParallel && videoDuration >= minDurationForParallel {
            print("🚀 [VideoWatermark] 使用并行处理模式（分段: \(Int(preferences.videoToolsSegmentDuration))秒, 并发: \(preferences.videoToolsMaxConcurrentTasks)）")
            
            try await VideoSegmentProcessor.processInParallel(
                inputURL: inputURL,
                outputURL: outputURL,
                segmentDuration: preferences.videoToolsSegmentDuration,
                maxConcurrentTasks: preferences.videoToolsMaxConcurrentTasks,
                processSegment: { segmentInput, segmentOutput in
                    try await addImageWatermark(
                        inputURL: segmentInput,
                        outputURL: segmentOutput,
                        watermarkImageURL: watermarkImageURL,
                        position: position,
                        customPosition: customPosition,
                        customSize: customSize,
                        opacity: opacity,
                        margin: margin,
                        progressHandler: { _, _ in } // 片段内部进度由 VideoSegmentProcessor 管理
                    )
                },
                progressHandler: progressHandler
            )
        } else {
            print("📝 [VideoWatermark] 使用单进程处理模式")
            
            try await addImageWatermark(
                inputURL: inputURL,
                outputURL: outputURL,
                watermarkImageURL: watermarkImageURL,
                position: position,
                customPosition: customPosition,
                customSize: customSize,
                opacity: opacity,
                margin: margin,
                progressHandler: progressHandler
            )
        }
        
        // 性能统计
        let elapsed = Date().timeIntervalSince(startTime)
        let outputSize = try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64
        let processingSpeed = videoDuration / elapsed
        
        print("✅ [VideoWatermark] 处理完成")
        print("⏱️ [VideoWatermark] 耗时: \(String(format: "%.1f", elapsed))秒, 处理速度: \(String(format: "%.2f", processingSpeed))x")
        print("📦 [VideoWatermark] 输出大小: \(formatFileSize(outputSize ?? 0))")
        
        if let inputSize = videoSize, let outputSize = outputSize, inputSize > 0 {
            let ratio = Double(outputSize) / Double(inputSize) * 100.0
            print("📊 [VideoWatermark] 大小比例: \(String(format: "%.1f", ratio))%")
        }
    }
    
    /// 格式化文件大小
    private static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// 添加文字水印（支持并行处理）
    static func addTextWatermarkWithParallel(
        inputURL: URL,
        outputURL: URL,
        text: String,
        position: WatermarkPosition,
        fontSize: Int = 24,
        fontColor: String = "FFFFFF",
        fontPath: String? = nil,
        opacity: Double = 1.0,
        enableOpacityAnimation: Bool = false,
        opacityAnimationRange: (min: Double, max: Double)? = nil,
        opacityAnimationDuration: Double = 3.0,
        margin: Int = 20,
        enableRandomMovement: Bool = false,
        movementInterval: Double? = nil,
        randomIntervalRange: (min: Double, max: Double)? = nil,
        driftSpeedRange: (min: Double, max: Double)? = nil,
        rotationMode: RotationMode = .fixed,
        fixedAngle: Double = 0.0,
        smoothRotationSpeed: Double = 10.0,
        randomRotationRange: (min: Double, max: Double) = (-45, 45),
        enableParallel: Bool? = nil,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        let startTime = Date()
        let preferences = UserPreferences.shared
        let shouldUseParallel = enableParallel ?? preferences.videoToolsEnableParallelProcessing
        
        let videoInfo = try await VideoInfoService.getVideoInfo(from: inputURL)
        let videoDuration = videoInfo.duration
        let videoSize = try? FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? Int64
        
        print("📊 [VideoWatermark] 开始处理文字水印 - 时长: \(String(format: "%.1f", videoDuration))秒")
        print("⚙️ [VideoWatermark] 配置 - 预设: \(preferences.videoToolsFFmpegPreset), 硬件加速: \(preferences.videoToolsEnableHardwareAccel)")
        
        let minDurationForParallel = preferences.videoToolsSegmentDuration * 2
        
        if shouldUseParallel && videoDuration >= minDurationForParallel {
            print("🚀 [VideoWatermark] 使用并行处理模式（分段: \(Int(preferences.videoToolsSegmentDuration))秒, 并发: \(preferences.videoToolsMaxConcurrentTasks)）")
            
            try await VideoSegmentProcessor.processInParallel(
                inputURL: inputURL,
                outputURL: outputURL,
                segmentDuration: preferences.videoToolsSegmentDuration,
                maxConcurrentTasks: preferences.videoToolsMaxConcurrentTasks,
                processSegment: { segmentInput, segmentOutput in
                    try await addTextWatermark(
                        inputURL: segmentInput,
                        outputURL: segmentOutput,
                        text: text,
                        position: position,
                        fontSize: fontSize,
                        fontColor: fontColor,
                        fontPath: fontPath,
                        opacity: opacity,
                        enableOpacityAnimation: enableOpacityAnimation,
                        opacityAnimationRange: opacityAnimationRange,
                        opacityAnimationDuration: opacityAnimationDuration,
                        margin: margin,
                        enableRandomMovement: enableRandomMovement,
                        movementInterval: movementInterval,
                        randomIntervalRange: randomIntervalRange,
                        driftSpeedRange: driftSpeedRange,
                        rotationMode: rotationMode,
                        fixedAngle: fixedAngle,
                        smoothRotationSpeed: smoothRotationSpeed,
                        randomRotationRange: randomRotationRange,
                        progressHandler: { _, _ in }
                    )
                },
                progressHandler: progressHandler
            )
        } else {
            print("📝 [VideoWatermark] 使用单进程处理模式")
            
            try await addTextWatermark(
                inputURL: inputURL,
                outputURL: outputURL,
                text: text,
                position: position,
                fontSize: fontSize,
                fontColor: fontColor,
                fontPath: fontPath,
                opacity: opacity,
                enableOpacityAnimation: enableOpacityAnimation,
                opacityAnimationRange: opacityAnimationRange,
                opacityAnimationDuration: opacityAnimationDuration,
                margin: margin,
                enableRandomMovement: enableRandomMovement,
                movementInterval: movementInterval,
                randomIntervalRange: randomIntervalRange,
                driftSpeedRange: driftSpeedRange,
                rotationMode: rotationMode,
                fixedAngle: fixedAngle,
                smoothRotationSpeed: smoothRotationSpeed,
                randomRotationRange: randomRotationRange,
                progressHandler: progressHandler
            )
        }
        
        // 性能统计
        let elapsed = Date().timeIntervalSince(startTime)
        let outputSize = try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64
        let processingSpeed = videoDuration / elapsed
        
        print("✅ [VideoWatermark] 文字水印处理完成")
        print("⏱️ [VideoWatermark] 耗时: \(String(format: "%.1f", elapsed))秒, 处理速度: \(String(format: "%.2f", processingSpeed))x")
        print("📦 [VideoWatermark] 输出大小: \(formatFileSize(outputSize ?? 0))")
        
        if let inputSize = videoSize, let outputSize = outputSize, inputSize > 0 {
            let ratio = Double(outputSize) / Double(inputSize) * 100.0
            print("📊 [VideoWatermark] 大小比例: \(String(format: "%.1f", ratio))%")
        }
    }
}
