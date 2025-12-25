//
//  VideoColorAdjuster.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import Foundation
import AppKit

/// 颜色调整参数
struct ColorAdjustment {
    var brightness: Double = 0.0 // -1.0 到 1.0
    var contrast: Double = 1.0 // 0.0 到 3.0
    var saturation: Double = 1.0 // 0.0 到 3.0
    var hue: Double = 0.0 // 色调偏移（度）
    var gamma: Double = 1.0 // Gamma 校正
    var temperature: Double? = nil // 色温（开尔文，如 6500）
    
    init() {}
    
    /// 转换为 FFmpeg eq 滤镜参数
    func toEQFilter() -> String {
        var params: [String] = []
        
        if brightness != 0.0 {
            params.append("brightness=\(brightness)")
        }
        
        if contrast != 1.0 {
            params.append("contrast=\(contrast)")
        }
        
        if saturation != 1.0 {
            params.append("saturation=\(saturation)")
        }
        
        if gamma != 1.0 {
            params.append("gamma=\(gamma)")
        }
        
        if params.isEmpty {
            return ""
        }
        
        return "eq=" + params.joined(separator: ":")
    }
    
    /// 转换为 FFmpeg hue 滤镜参数
    func toHueFilter() -> String? {
        if hue == 0.0 {
            return nil
        }
        
        // hue 参数是弧度，需要转换
        let hueRadians = hue * .pi / 180.0
        return "hue=h=\(hueRadians)"
    }
    
    /// 转换为 FFmpeg colortemperature 滤镜参数
    func toColorTemperatureFilter() -> String? {
        if let temp = temperature {
            return "colortemperature=temperature=\(temp)"
        }
        return nil
    }
}

/// 视频颜色调整服务
struct VideoColorAdjuster {
    
    /// 应用颜色调整
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - adjustment: 颜色调整参数
    ///   - progressHandler: 进度回调
    static func adjust(
        inputURL: URL,
        outputURL: URL,
        adjustment: ColorAdjustment,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        // 构建滤镜链
        var filters: [String] = []
        
        // EQ 滤镜（亮度/对比度/饱和度/Gamma）
        let eqFilter = adjustment.toEQFilter()
        if !eqFilter.isEmpty {
            filters.append(eqFilter)
        }
        
        // Hue 滤镜（色调）
        if let hueFilter = adjustment.toHueFilter() {
            filters.append(hueFilter)
        }
        
        // 色温滤镜
        if let tempFilter = adjustment.toColorTemperatureFilter() {
            filters.append(tempFilter)
        }
        
        // 应用滤镜
        if !filters.isEmpty {
            let filterChain = filters.joined(separator: ",")
            arguments.append("-vf")
            arguments.append(filterChain)
        }
        
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
    
    /// 调整亮度
    static func adjustBrightness(
        inputURL: URL,
        outputURL: URL,
        brightness: Double,
        progressHandler: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws {
        var adjustment = ColorAdjustment()
        adjustment.brightness = brightness
        try await adjust(inputURL: inputURL, outputURL: outputURL, adjustment: adjustment, progressHandler: progressHandler)
    }
    
    /// 调整对比度
    static func adjustContrast(
        inputURL: URL,
        outputURL: URL,
        contrast: Double,
        progressHandler: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws {
        var adjustment = ColorAdjustment()
        adjustment.contrast = contrast
        try await adjust(inputURL: inputURL, outputURL: outputURL, adjustment: adjustment, progressHandler: progressHandler)
    }
    
    /// 调整饱和度
    static func adjustSaturation(
        inputURL: URL,
        outputURL: URL,
        saturation: Double,
        progressHandler: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws {
        var adjustment = ColorAdjustment()
        adjustment.saturation = saturation
        try await adjust(inputURL: inputURL, outputURL: outputURL, adjustment: adjustment, progressHandler: progressHandler)
    }
    
    /// 调整色温
    static func adjustColorTemperature(
        inputURL: URL,
        outputURL: URL,
        temperature: Double,
        progressHandler: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws {
        var adjustment = ColorAdjustment()
        adjustment.temperature = temperature
        try await adjust(inputURL: inputURL, outputURL: outputURL, adjustment: adjustment, progressHandler: progressHandler)
    }
    
    /// 应用 LUT 调色
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - lutFileURL: LUT 文件 URL（.cube 格式）
    ///   - progressHandler: 进度回调
    static func applyLUT(
        inputURL: URL,
        outputURL: URL,
        lutFileURL: URL,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(inputURL.path)
        
        // 应用 LUT
        arguments.append("-vf")
        arguments.append("lut3d='\(lutFileURL.path)'")
        
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
    
    // MARK: - 帧提取和预览相关方法
    
    /// 从视频中提取指定时间点的帧
    /// - Parameters:
    ///   - videoURL: 视频文件 URL
    ///   - timestamp: 时间点（秒）
    ///   - outputURL: 输出图片 URL
    /// - Returns: 提取的图片 URL
    static func extractFrame(
        from videoURL: URL,
        at timestamp: TimeInterval,
        outputURL: URL
    ) async throws -> URL {
        var arguments: [String] = []
        
        // 使用 -ss 参数定位到指定时间点
        arguments.append("-ss")
        arguments.append(String(format: "%.3f", timestamp))
        
        arguments.append("-i")
        arguments.append(videoURL.path)
        
        // 只提取一帧
        arguments.append("-vframes")
        arguments.append("1")
        
        // 高质量输出
        arguments.append("-q:v")
        arguments.append("2")
        
        arguments.append("-y")
        arguments.append(outputURL.path)
        
        try await FFmpegService.execute(
            arguments: arguments,
            progressHandler: { _, _ in }
        )
        
        return outputURL
    }
    
    /// 对图片应用颜色调整
    /// - Parameters:
    ///   - imageURL: 输入图片 URL
    ///   - outputURL: 输出图片 URL
    ///   - adjustment: 颜色调整参数
    static func applyColorAdjustmentToImage(
        imageURL: URL,
        outputURL: URL,
        adjustment: ColorAdjustment
    ) async throws {
        var arguments: [String] = []
        
        arguments.append("-i")
        arguments.append(imageURL.path)
        
        // 构建滤镜链
        var filters: [String] = []
        
        // EQ 滤镜（亮度/对比度/饱和度/Gamma）
        let eqFilter = adjustment.toEQFilter()
        if !eqFilter.isEmpty {
            filters.append(eqFilter)
        }
        
        // Hue 滤镜（色调）
        if let hueFilter = adjustment.toHueFilter() {
            filters.append(hueFilter)
        }
        
        // 色温滤镜
        if let tempFilter = adjustment.toColorTemperatureFilter() {
            filters.append(tempFilter)
        }
        
        // 应用滤镜
        if !filters.isEmpty {
            let filterChain = filters.joined(separator: ",")
            arguments.append("-vf")
            arguments.append(filterChain)
        }
        
        // 高质量输出
        arguments.append("-q:v")
        arguments.append("2")
        
        arguments.append("-y")
        arguments.append(outputURL.path)
        
        try await FFmpegService.execute(
            arguments: arguments,
            progressHandler: { _, _ in }
        )
    }
    
    /// 从视频中提取帧并应用颜色调整（用于预览，带缓存优化）
    /// - Parameters:
    ///   - videoURL: 视频文件 URL
    ///   - timestamp: 时间点（秒）
    ///   - adjustment: 颜色调整参数
    /// - Returns: (原始图片 NSImage, 调整后图片 NSImage)
    static func extractAndAdjustFrame(
        from videoURL: URL,
        at timestamp: TimeInterval,
        adjustment: ColorAdjustment
    ) async throws -> (original: NSImage, adjusted: NSImage) {
        // 尝试从缓存获取原始帧
        let originalImage: NSImage
        if let cachedImage = await VideoFrameCache.shared.getFrame(for: videoURL, at: timestamp) {
            originalImage = cachedImage
        } else {
            // 创建临时文件路径
            let tempDir = FileManager.default.temporaryDirectory
            let originalImageURL = tempDir.appendingPathComponent("frame_original_\(UUID().uuidString).jpg")
            
            // 提取原始帧
            _ = try await extractFrame(from: videoURL, at: timestamp, outputURL: originalImageURL)
            
            // 加载图片
            guard let extractedImage = NSImage(contentsOf: originalImageURL) else {
                throw NSError(domain: "VideoColorAdjuster", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "无法加载提取的图片"
                ])
            }
            
            // 缓存原始帧
            await VideoFrameCache.shared.setFrame(extractedImage, for: videoURL, at: timestamp)
            originalImage = extractedImage
            
            // 清理临时文件
            try? FileManager.default.removeItem(at: originalImageURL)
        }
        
        // 应用颜色调整（不缓存调整后的图片，因为调整参数可能频繁变化）
        let tempDir = FileManager.default.temporaryDirectory
        let tempOriginalURL = tempDir.appendingPathComponent("temp_original_\(UUID().uuidString).jpg")
        let adjustedImageURL = tempDir.appendingPathComponent("frame_adjusted_\(UUID().uuidString).jpg")
        
        // 保存原始图片到临时文件
        if let tiffData = originalImage.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
            try jpegData.write(to: tempOriginalURL)
        }
        
        // 应用颜色调整
        try await applyColorAdjustmentToImage(
            imageURL: tempOriginalURL,
            outputURL: adjustedImageURL,
            adjustment: adjustment
        )
        
        // 加载调整后的图片
        guard let adjustedImage = NSImage(contentsOf: adjustedImageURL) else {
            throw NSError(domain: "VideoColorAdjuster", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "无法加载调整后的图片"
            ])
        }
        
        // 清理临时文件
        try? FileManager.default.removeItem(at: tempOriginalURL)
        try? FileManager.default.removeItem(at: adjustedImageURL)
        
        return (originalImage, adjustedImage)
    }
}
