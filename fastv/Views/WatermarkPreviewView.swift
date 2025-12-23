//
//  WatermarkPreviewView.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI
import AppKit

/// 水印预览视图
/// 在视频预览图上叠加显示水印效果
struct WatermarkPreviewView: View {
    let previewImage: NSImage?
    let videoSize: CGSize?
    let watermarkType: WatermarkType
    let watermarkImageURL: URL?
    let watermarkText: String
    let position: WatermarkPosition
    let fontSize: Int
    let opacity: Double
    let margin: CGFloat
    
    @State private var watermarkImage: NSImage?
    @State private var isLoadingWatermarkImage = false
    @State private var currentTimestamp: Date = Date()
    @State private var timestampTimer: Timer?
    
    enum WatermarkType {
        case image
        case text
        case timestamp
    }
    
    init(
        previewImage: NSImage?,
        videoSize: CGSize?,
        watermarkType: WatermarkType,
        watermarkImageURL: URL? = nil,
        watermarkText: String = "",
        position: WatermarkPosition = .bottomRight,
        fontSize: Int = 24,
        opacity: Double = 1.0,
        margin: CGFloat = 20
    ) {
        self.previewImage = previewImage
        self.videoSize = videoSize
        self.watermarkType = watermarkType
        self.watermarkImageURL = watermarkImageURL
        self.watermarkText = watermarkText
        self.position = position
        self.fontSize = fontSize
        self.opacity = opacity
        self.margin = margin
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // 背景预览图
                if let previewImage = previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(calculatedAspectRatio, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Color.black
                }
                
                // 水印层
                if let previewImage = previewImage, let videoSize = videoSize {
                    watermarkOverlay(
                        previewImage: previewImage,
                        videoSize: videoSize,
                        geometry: geometry
                    )
                }
            }
        }
        .onChange(of: watermarkImageURL) { oldValue, newValue in
            if let url = newValue {
                loadWatermarkImage(from: url)
            } else {
                watermarkImage = nil
            }
        }
        .onAppear {
            if let url = watermarkImageURL {
                loadWatermarkImage(from: url)
            }
            
            // 如果是时间戳类型，每秒更新一次
            if watermarkType == .timestamp {
                startTimestampTimer()
            }
        }
        .onChange(of: watermarkType) { oldValue, newValue in
            if newValue == .timestamp {
                startTimestampTimer()
            } else {
                stopTimestampTimer()
            }
            
            // 当类型改变时，如果之前有图片，重新加载
            if newValue == .image, let url = watermarkImageURL {
                loadWatermarkImage(from: url)
            }
        }
        .onDisappear {
            stopTimestampTimer()
        }
    }
    
    // 计算宽高比
    private var calculatedAspectRatio: CGFloat? {
        if let size = videoSize, size.width > 0 && size.height > 0 {
            return size.width / size.height
        }
        return nil
    }
    
    // 水印覆盖层
    @ViewBuilder
    private func watermarkOverlay(
        previewImage: NSImage,
        videoSize: CGSize,
        geometry: GeometryProxy
    ) -> some View {
        // 计算预览图在视图中的实际显示区域和尺寸
        let (imageRect, imageSize) = calculateImageDisplayRect(
            videoSize: videoSize,
            geometry: geometry
        )
        
        // 计算水印在预览图中的位置（视频坐标系）
        let watermarkRect = calculateWatermarkRect(
            videoSize: videoSize,
            imageSize: imageSize,
            imageRect: imageRect
        )
        
        // 显示水印
        if watermarkRect.width > 0 && watermarkRect.height > 0 {
            Group {
                switch watermarkType {
                case .image:
                    if let watermarkImage = watermarkImage {
                        Image(nsImage: watermarkImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: watermarkRect.width, height: watermarkRect.height)
                            .opacity(opacity)
                    }
                case .text:
                    if !watermarkText.isEmpty {
                        Text(watermarkText)
                            .font(.system(size: CGFloat(fontSize), weight: .medium))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1)
                            .padding(6)
                            .background {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.black.opacity(0.5))
                            }
                            .frame(minWidth: watermarkRect.width, minHeight: watermarkRect.height)
                            .opacity(opacity)
                    }
                case .timestamp:
                    Text(formatTimestamp(currentTimestamp))
                        .font(.system(size: CGFloat(fontSize), weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1)
                        .padding(6)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.black.opacity(0.5))
                        }
                        .frame(minWidth: watermarkRect.width, minHeight: watermarkRect.height)
                        .opacity(opacity)
                }
            }
            .position(
                x: watermarkRect.midX,
                y: watermarkRect.midY
            )
        }
    }
    
    // 计算预览图在视图中的显示区域
    private func calculateImageDisplayRect(
        videoSize: CGSize,
        geometry: GeometryProxy
    ) -> (rect: CGRect, size: CGSize) {
        let imageAspect = videoSize.width / videoSize.height
        let viewAspect = geometry.size.width / geometry.size.height
        
        var imageRect: CGRect
        var imageSize: CGSize
        
        if imageAspect > viewAspect {
            // 图片更宽，以宽度为准
            imageSize = CGSize(width: geometry.size.width, height: geometry.size.width / imageAspect)
            imageRect = CGRect(
                x: 0,
                y: (geometry.size.height - imageSize.height) / 2,
                width: imageSize.width,
                height: imageSize.height
            )
        } else {
            // 图片更高，以高度为准
            imageSize = CGSize(width: geometry.size.height * imageAspect, height: geometry.size.height)
            imageRect = CGRect(
                x: (geometry.size.width - imageSize.width) / 2,
                y: 0,
                width: imageSize.width,
                height: imageSize.height
            )
        }
        
        return (imageRect, imageSize)
    }
    
    // 计算水印在预览图中的位置
    private func calculateWatermarkRect(
        videoSize: CGSize,
        imageSize: CGSize,
        imageRect: CGRect
    ) -> CGRect {
        // 计算缩放比例
        let scaleX = imageSize.width / videoSize.width
        let scaleY = imageSize.height / videoSize.height
        
        // 根据水印类型计算水印尺寸（视频坐标系）
        let watermarkSize: CGSize
        switch watermarkType {
        case .image:
            if let watermarkImage = watermarkImage {
                let imageSize = watermarkImage.size
                // 限制最大尺寸为视频宽度的 20%
                let maxWidth = videoSize.width * 0.2
                let maxHeight = videoSize.height * 0.2
                let aspectRatio = imageSize.width / imageSize.height
                
                if imageSize.width > maxWidth || imageSize.height > maxHeight {
                    if imageSize.width / maxWidth > imageSize.height / maxHeight {
                        watermarkSize = CGSize(width: maxWidth, height: maxWidth / aspectRatio)
                    } else {
                        watermarkSize = CGSize(width: maxHeight * aspectRatio, height: maxHeight)
                    }
                } else {
                    watermarkSize = imageSize
                }
            } else {
                return .zero
            }
        case .text, .timestamp:
            // 文字水印尺寸估算（实际会根据内容调整）
            let text = watermarkType == .text ? watermarkText : formatTimestamp(currentTimestamp)
            // 更准确的文字宽度估算（考虑中文字符）
            let charWidth = CGFloat(fontSize) * 0.6
            let estimatedWidth = CGFloat(text.count) * charWidth + 8 // 加上 padding
            let estimatedHeight = CGFloat(fontSize) * 1.5 + 8 // 加上 padding
            watermarkSize = CGSize(width: min(estimatedWidth, videoSize.width * 0.4), height: estimatedHeight)
        }
        
        // 根据位置计算水印在视频坐标系中的位置
        let videoX: CGFloat
        let videoY: CGFloat
        
        switch position {
        case .topLeft:
            videoX = margin
            videoY = margin
        case .topCenter:
            videoX = (videoSize.width - watermarkSize.width) / 2
            videoY = margin
        case .topRight:
            videoX = videoSize.width - watermarkSize.width - margin
            videoY = margin
        case .middleLeft:
            videoX = margin
            videoY = (videoSize.height - watermarkSize.height) / 2
        case .center:
            videoX = (videoSize.width - watermarkSize.width) / 2
            videoY = (videoSize.height - watermarkSize.height) / 2
        case .middleRight:
            videoX = videoSize.width - watermarkSize.width - margin
            videoY = (videoSize.height - watermarkSize.height) / 2
        case .bottomLeft:
            videoX = margin
            videoY = videoSize.height - watermarkSize.height - margin
        case .bottomCenter:
            videoX = (videoSize.width - watermarkSize.width) / 2
            videoY = videoSize.height - watermarkSize.height - margin
        case .bottomRight:
            videoX = videoSize.width - watermarkSize.width - margin
            videoY = videoSize.height - watermarkSize.height - margin
        }
        
        // 转换为预览图坐标系
        let displayX = imageRect.minX + videoX * scaleX
        let displayY = imageRect.minY + videoY * scaleY
        let displayWidth = watermarkSize.width * scaleX
        let displayHeight = watermarkSize.height * scaleY
        
        return CGRect(
            x: displayX,
            y: displayY,
            width: displayWidth,
            height: displayHeight
        )
    }
    
    // 加载水印图片（异步，不阻塞 UI）
    private func loadWatermarkImage(from url: URL) {
        isLoadingWatermarkImage = true
        
        Task.detached(priority: .userInitiated) {
            // 在后台线程加载图片
            let image = NSImage(contentsOf: url)
            
            await MainActor.run {
                watermarkImage = image
                isLoadingWatermarkImage = false
            }
        }
    }
    
    // 格式化时间戳
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    // 启动时间戳定时器
    private func startTimestampTimer() {
        stopTimestampTimer() // 先停止之前的定时器
        
        timestampTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            currentTimestamp = Date()
        }
    }
    
    // 停止时间戳定时器
    private func stopTimestampTimer() {
        timestampTimer?.invalidate()
        timestampTimer = nil
    }
}

#Preview {
    WatermarkPreviewView(
        previewImage: nil,
        videoSize: CGSize(width: 1920, height: 1080),
        watermarkType: .text,
        watermarkText: "测试水印",
        position: .bottomRight,
        fontSize: 24,
        opacity: 0.8
    )
    .frame(width: 600, height: 400)
}

