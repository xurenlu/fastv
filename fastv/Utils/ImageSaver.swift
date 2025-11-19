//
//  ImageSaver.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import AppKit
import Foundation
import ImageIO
import CoreGraphics

struct ImageSaver {
    /// 保存图片到指定路径
    static func save(
        _ image: NSImage,
        to url: URL,
        format: ImageFormat = .png,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil,
        compressionEnabled: Bool = true,
        compressionQuality: Double = 0.8
    ) throws {
        var processedImage = image
        
        // 应用尺寸限制
        if let maxWidth = maxWidth, let maxHeight = maxHeight {
            processedImage = resizeImage(image, maxWidth: maxWidth, maxHeight: maxHeight)
        }
        
        // 使用 ImageIO 进行压缩
        if compressionEnabled {
            try saveWithCompression(processedImage, to: url, format: format, quality: compressionQuality)
        } else {
            guard let imageData = imageData(from: processedImage, format: format) else {
                throw VideoProcessingError.fileSaveFailed
            }
            try imageData.write(to: url)
        }
    }
    
    /// 调整图片尺寸（保持宽高比）
    private static func resizeImage(_ image: NSImage, maxWidth: Int, maxHeight: Int) -> NSImage {
        let currentSize = image.size
        let aspectRatio = currentSize.width / currentSize.height
        
        var newWidth = CGFloat(maxWidth)
        var newHeight = CGFloat(maxHeight)
        
        // 根据宽高比调整尺寸
        if currentSize.width > currentSize.height {
            // 横向图片
            newHeight = newWidth / aspectRatio
            if newHeight > CGFloat(maxHeight) {
                newHeight = CGFloat(maxHeight)
                newWidth = newHeight * aspectRatio
            }
        } else {
            // 纵向图片
            newWidth = newHeight * aspectRatio
            if newWidth > CGFloat(maxWidth) {
                newWidth = CGFloat(maxWidth)
                newHeight = newWidth / aspectRatio
            }
        }
        
        // 如果图片已经小于限制，不进行缩放
        if currentSize.width <= newWidth && currentSize.height <= newHeight {
            return image
        }
        
        let resizedImage = NSImage(size: NSSize(width: newWidth, height: newHeight))
        resizedImage.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight),
                   from: NSRect(x: 0, y: 0, width: currentSize.width, height: currentSize.height),
                   operation: .sourceOver,
                   fraction: 1.0)
        resizedImage.unlockFocus()
        
        return resizedImage
    }
    
    /// 使用 ImageIO 进行压缩保存
    private static func saveWithCompression(
        _ image: NSImage,
        to url: URL,
        format: ImageFormat,
        quality: Double
    ) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw VideoProcessingError.fileSaveFailed
        }
        
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType, 1, nil) else {
            throw VideoProcessingError.fileSaveFailed
        }
        
        var options: [CFString: Any] = [:]
        
        switch format {
        case .png:
            // PNG 使用无损压缩
            // 使用优化选项来减小文件大小
            options[kCGImageDestinationOptimizeColorForSharing] = true
            // 对于 PNG，quality 参数可以用于控制压缩级别（通过 ImageIO 的内部优化）
            // 这里我们使用默认的 PNG 压缩
        case .jpg:
            // JPEG 使用有损压缩
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }
        
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw VideoProcessingError.fileSaveFailed
        }
    }
    
    /// 从 NSImage 生成图片数据（备用方法）
    private static func imageData(from image: NSImage, format: ImageFormat) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        switch format {
        case .png:
            return bitmapImage.representation(using: .png, properties: [:])
        case .jpg:
            return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        }
    }
}

enum ImageFormat: String, CaseIterable {
    case png = "PNG"
    case jpg = "JPEG"
    
    var fileExtension: String {
        switch self {
        case .png:
            return "png"
        case .jpg:
            return "jpg"
        }
    }
    
    var utType: CFString {
        switch self {
        case .png:
            return kUTTypePNG
        case .jpg:
            return kUTTypeJPEG
        }
    }
    
    var displayName: String {
        return rawValue
    }
}

