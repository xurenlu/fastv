//
//  VideoCartoonizerService.swift
//  fastv
//
//  Created for Video Cartoonization
//

import Foundation
import AppKit
import CoreGraphics
import AVFoundation
import Combine

/// 卡通风格枚举
enum CartoonStyle: String, CaseIterable, Identifiable {
    case shinkai = "新海诚 (Shinkai)"
    case hayao = "宫崎骏 (Hayao)"
    case paprika = "今敏 (Paprika)"
    case whitebox = "白盒 (White-box)"
    
    var id: String { self.rawValue }
    
    var modelName: String {
        switch self {
        case .shinkai: return "Shinkai_53.onnx"
        case .hayao: return "Hayao_64.onnx"
        case .paprika: return "Paprika_54.onnx"
        case .whitebox: return "whitebox.onnx"
        }
    }
}

/// 视频卡通化服务
/// 负责加载模型并对视频进行风格迁移
class VideoCartoonizerService: ObservableObject {
    static let shared = VideoCartoonizerService()
    
    private let onnxWrapper = ONNXRuntimeWrapper()
    private var currentLoadedStyle: CartoonStyle?
    
    // 模型输入尺寸 (AnimeGANv2 常用 512x512，但也支持动态尺寸，这里先固定以简化处理)
    // 注意：如果是动态尺寸模型，可以传入原图尺寸（需为32倍数）
    private let inputWidth = 512
    private let inputHeight = 512
    
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = ""
    
    private init() {}
    
    /// 检查模型是否存在
    func isModelAvailable(for style: CartoonStyle) -> Bool {
        let modelPath = getModelPath(for: style)
        return FileManager.default.fileExists(atPath: modelPath)
    }
    
    /// 获取模型路径
    private func getModelPath(for style: CartoonStyle) -> String {
        let resourcesURL = Bundle.main.resourceURL ?? URL(fileURLWithPath: "/Users/rocky/Sites/fastv/fastv/Resources")
        let modelDir = resourcesURL.appendingPathComponent("Models/Cartoon")
        return modelDir.appendingPathComponent(style.modelName).path
    }
    
    /// 加载模型
    private func loadModel(style: CartoonStyle) throws {
        if currentLoadedStyle == style { return }
        
        let path = getModelPath(for: style)
        try onnxWrapper.loadModel(from: path)
        currentLoadedStyle = style
    }
    
    /// 处理单帧图片
    func processImage(_ image: NSImage, style: CartoonStyle) async throws -> NSImage {
        try loadModel(style: style)
        
        // 1. 预处理: Resize -> NCHW -> [-1, 1]
        guard let inputData = preprocess(image: image, width: inputWidth, height: inputHeight) else {
            throw VideoProcessingError.transcriptionFailed("图片预处理失败")
        }
        
        // 2. 推理
        let inputShape = [1, 3, inputHeight, inputWidth]
        let outputShape = [1, 3, inputHeight, inputWidth] // 假设输出尺寸一致
        
        let outputData = try onnxWrapper.runImageInference(
            inputData: inputData,
            inputShape: inputShape,
            outputShape: outputShape
        )
        
        // 3. 后处理: [-1, 1] -> NCHW -> NSImage
        guard let resultImage = postprocess(data: outputData, width: inputWidth, height: inputHeight) else {
            throw VideoProcessingError.transcriptionFailed("图片后处理失败")
        }
        
        return resultImage
    }
    
    /// 预处理: NSImage -> [Float] (NCHW format, range [-1, 1])
    private func preprocess(image: NSImage, width: Int, height: Int) -> [Float]? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        // 创建上下文并绘制（缩放）
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let buffer = context.data else { return nil }
        let pixelBuffer = buffer.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        // 转换为 NCHW 格式，并归一化到 [-1, 1]
        // AnimeGANv2 expect input in [-1, 1]
        var floatArray = [Float](repeating: 0, count: 3 * width * height)
        let count = width * height
        
        for i in 0..<count {
            let offset = i * 4
            let r = Float(pixelBuffer[offset])
            let g = Float(pixelBuffer[offset + 1])
            let b = Float(pixelBuffer[offset + 2])
            
            // Normalize to [-1, 1]: (x / 127.5) - 1.0
            floatArray[i] = (r / 127.5) - 1.0             // R channel
            floatArray[count + i] = (g / 127.5) - 1.0     // G channel
            floatArray[count * 2 + i] = (b / 127.5) - 1.0 // B channel
        }
        
        return floatArray
    }
    
    /// 后处理: [Float] -> NSImage
    private func postprocess(data: [Float], width: Int, height: Int) -> NSImage? {
        let count = width * height
        var pixelData = [UInt8](repeating: 0, count: count * 4)
        
        for i in 0..<count {
            // Denormalize from [-1, 1] to [0, 255]
            // x = (y + 1.0) * 127.5
            let r = min(max(Int((data[i] + 1.0) * 127.5), 0), 255)
            let g = min(max(Int((data[count + i] + 1.0) * 127.5), 0), 255)
            let b = min(max(Int((data[count * 2 + i] + 1.0) * 127.5), 0), 255)
            
            let offset = i * 4
            pixelData[offset] = UInt8(r)
            pixelData[offset + 1] = UInt8(g)
            pixelData[offset + 2] = UInt8(b)
            pixelData[offset + 3] = 255 // Alpha
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let provider = CGDataProvider(data: Data(pixelData) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}
