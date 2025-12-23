//
//  LogoAnnotation.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import Foundation
import AppKit

/// Logo 标注点
struct LogoAnnotation: Codable, Identifiable {
    let id: UUID
    let frameNumber: Int
    let timestamp: TimeInterval
    let boundingBox: CGRect
    var imageData: Data? // 该帧的截图数据（用于模板匹配）
    
    init(
        id: UUID = UUID(),
        frameNumber: Int,
        timestamp: TimeInterval,
        boundingBox: CGRect,
        image: NSImage? = nil
    ) {
        self.id = id
        self.frameNumber = frameNumber
        self.timestamp = timestamp
        self.boundingBox = boundingBox
        
        // 将 NSImage 转换为 Data
        if let image = image,
           let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            self.imageData = pngData
        } else {
            self.imageData = nil
        }
    }
    
    /// 从 Data 恢复 NSImage
    var image: NSImage? {
        guard let imageData = imageData else { return nil }
        return NSImage(data: imageData)
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id
        case frameNumber
        case timestamp
        case boundingBoxX
        case boundingBoxY
        case boundingBoxWidth
        case boundingBoxHeight
        case imageData
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        frameNumber = try container.decode(Int.self, forKey: .frameNumber)
        timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        
        let x = try container.decode(CGFloat.self, forKey: .boundingBoxX)
        let y = try container.decode(CGFloat.self, forKey: .boundingBoxY)
        let width = try container.decode(CGFloat.self, forKey: .boundingBoxWidth)
        let height = try container.decode(CGFloat.self, forKey: .boundingBoxHeight)
        boundingBox = CGRect(x: x, y: y, width: width, height: height)
        
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(frameNumber, forKey: .frameNumber)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(boundingBox.origin.x, forKey: .boundingBoxX)
        try container.encode(boundingBox.origin.y, forKey: .boundingBoxY)
        try container.encode(boundingBox.width, forKey: .boundingBoxWidth)
        try container.encode(boundingBox.height, forKey: .boundingBoxHeight)
        try container.encodeIfPresent(imageData, forKey: .imageData)
    }
}

/// Logo 跟踪结果
struct LogoTrackingResult: Codable {
    var frameNumber: Int
    var timestamp: TimeInterval
    var boundingBox: CGRect
    var confidence: Double // 跟踪置信度 (0.0 - 1.0)
    var trackingMethod: TrackingMethod // 使用的跟踪方法
    
    init(frameNumber: Int, timestamp: TimeInterval, boundingBox: CGRect, confidence: Double, trackingMethod: TrackingMethod) {
        self.frameNumber = frameNumber
        self.timestamp = timestamp
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.trackingMethod = trackingMethod
    }
    
    enum CodingKeys: String, CodingKey {
        case frameNumber
        case timestamp
        case boundingBoxX
        case boundingBoxY
        case boundingBoxWidth
        case boundingBoxHeight
        case confidence
        case trackingMethod
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frameNumber = try container.decode(Int.self, forKey: .frameNumber)
        timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        
        let x = try container.decode(CGFloat.self, forKey: .boundingBoxX)
        let y = try container.decode(CGFloat.self, forKey: .boundingBoxY)
        let width = try container.decode(CGFloat.self, forKey: .boundingBoxWidth)
        let height = try container.decode(CGFloat.self, forKey: .boundingBoxHeight)
        boundingBox = CGRect(x: x, y: y, width: width, height: height)
        
        confidence = try container.decode(Double.self, forKey: .confidence)
        trackingMethod = try container.decode(TrackingMethod.self, forKey: .trackingMethod)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frameNumber, forKey: .frameNumber)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(boundingBox.origin.x, forKey: .boundingBoxX)
        try container.encode(boundingBox.origin.y, forKey: .boundingBoxY)
        try container.encode(boundingBox.width, forKey: .boundingBoxWidth)
        try container.encode(boundingBox.height, forKey: .boundingBoxHeight)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(trackingMethod, forKey: .trackingMethod)
    }
}

/// 跟踪方法
enum TrackingMethod: String, Codable {
    case templateMatching = "template_matching"
    case opticalFlow = "optical_flow"
    case hybrid = "hybrid"
    case interpolation = "interpolation"
}

/// Logo 跟踪配置
struct LogoTrackingConfig: Codable {
    let annotations: [LogoAnnotation] // 用户标注的关键帧
    let replacementLogoURL: URL // 替换用的新 Logo
    let trackingMethod: TrackingMethod
    let interpolationEnabled: Bool // 是否在关键帧之间插值
    let templateMatchingThreshold: Double // 模板匹配阈值 (0.0 - 1.0)
    let opticalFlowWindowSize: Int // 光流窗口大小
    let minConfidence: Double // 最小置信度阈值
    
    init(
        annotations: [LogoAnnotation],
        replacementLogoURL: URL,
        trackingMethod: TrackingMethod = .hybrid,
        interpolationEnabled: Bool = true,
        templateMatchingThreshold: Double = 0.7,
        opticalFlowWindowSize: Int = 15,
        minConfidence: Double = 0.5
    ) {
        self.annotations = annotations
        self.replacementLogoURL = replacementLogoURL
        self.trackingMethod = trackingMethod
        self.interpolationEnabled = interpolationEnabled
        self.templateMatchingThreshold = templateMatchingThreshold
        self.opticalFlowWindowSize = opticalFlowWindowSize
        self.minConfidence = minConfidence
    }
    
    enum CodingKeys: String, CodingKey {
        case annotations
        case replacementLogoURL
        case trackingMethod
        case interpolationEnabled
        case templateMatchingThreshold
        case opticalFlowWindowSize
        case minConfidence
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        annotations = try container.decode([LogoAnnotation].self, forKey: .annotations)
        let urlString = try container.decode(String.self, forKey: .replacementLogoURL)
        replacementLogoURL = URL(fileURLWithPath: urlString)
        trackingMethod = try container.decode(TrackingMethod.self, forKey: .trackingMethod)
        interpolationEnabled = try container.decode(Bool.self, forKey: .interpolationEnabled)
        templateMatchingThreshold = try container.decode(Double.self, forKey: .templateMatchingThreshold)
        opticalFlowWindowSize = try container.decode(Int.self, forKey: .opticalFlowWindowSize)
        minConfidence = try container.decode(Double.self, forKey: .minConfidence)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(annotations, forKey: .annotations)
        try container.encode(replacementLogoURL.path, forKey: .replacementLogoURL)
        try container.encode(trackingMethod, forKey: .trackingMethod)
        try container.encode(interpolationEnabled, forKey: .interpolationEnabled)
        try container.encode(templateMatchingThreshold, forKey: .templateMatchingThreshold)
        try container.encode(opticalFlowWindowSize, forKey: .opticalFlowWindowSize)
        try container.encode(minConfidence, forKey: .minConfidence)
    }
}
