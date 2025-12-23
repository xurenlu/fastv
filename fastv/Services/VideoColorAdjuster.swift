//
//  VideoColorAdjuster.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import Foundation

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
}
