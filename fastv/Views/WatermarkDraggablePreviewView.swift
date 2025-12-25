//
//  WatermarkDraggablePreviewView.swift
//  fastv
//
//  Created by rocky on 2025/12/23.
//

import SwiftUI
import AppKit
import CoreText

/// 可拖动和调整大小的水印预览视图
struct WatermarkDraggablePreviewView: View {
    let previewImage: NSImage?
    let videoSize: CGSize?
    let watermarkType: WatermarkType
    let watermarkImageURL: URL?
    let watermarkText: String
    let fontSize: Int
    let opacity: Double
    let fontURL: URL?
    
    @Binding var customPosition: CGPoint? // 自定义位置（视频坐标系，nil 表示使用预设位置）
    @Binding var customSize: CGSize? // 自定义大小（视频坐标系，nil 表示使用默认大小）
    @Binding var position: WatermarkPosition // 预设位置（当 customPosition 为 nil 时使用）
    
    @State private var watermarkImage: NSImage?
    @State private var isLoadingWatermarkImage = false
    @State private var currentTimestamp: Date = Date()
    @State private var timestampTimer: Timer?
    
    // 拖动状态
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartPosition: CGPoint = .zero
    
    // 调整大小状态
    @State private var isResizing = false
    @State private var resizeStartSize: CGSize = .zero
    @State private var resizeStartPoint: CGPoint = .zero
    @State private var resizeCorner: ResizeCorner = .none
    
    // 旋转和颜色相关
    let textColor: Color
    let rotationMode: RotationMode?
    let fixedRotationAngle: Double
    let smoothRotationSpeed: Double
    let randomRotationRange: (min: Double, max: Double)?
    let enableRandomMovement: Bool
    
    @State private var previewRotation: Double = 0.0
    @State private var movementTimer: Timer?
    
    enum WatermarkType {
        case image
        case text
        case timestamp
    }
    
    enum ResizeCorner {
        case none
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }
    
    init(
        previewImage: NSImage?,
        videoSize: CGSize?,
        watermarkType: WatermarkType,
        watermarkImageURL: URL? = nil,
        watermarkText: String = "",
        fontSize: Int = 24,
        opacity: Double = 1.0,
        fontURL: URL? = nil,
        textColor: Color = .white,
        rotationMode: RotationMode? = nil,
        fixedRotationAngle: Double = 0.0,
        smoothRotationSpeed: Double = 10.0,
        randomRotationRange: (min: Double, max: Double)? = nil,
        enableRandomMovement: Bool = false,
        customPosition: Binding<CGPoint?> = .constant(nil),
        customSize: Binding<CGSize?> = .constant(nil),
        position: Binding<WatermarkPosition> = .constant(.bottomRight)
    ) {
        self.previewImage = previewImage
        self.videoSize = videoSize
        self.watermarkType = watermarkType
        self.watermarkImageURL = watermarkImageURL
        self.watermarkText = watermarkText
        self.fontSize = fontSize
        self.opacity = opacity
        self.fontURL = fontURL
        self.textColor = textColor
        self.rotationMode = rotationMode
        self.fixedRotationAngle = fixedRotationAngle
        self.smoothRotationSpeed = smoothRotationSpeed
        self.randomRotationRange = randomRotationRange
        self.enableRandomMovement = enableRandomMovement
        self._customPosition = customPosition
        self._customSize = customSize
        self._position = position
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
            
            if watermarkType == .timestamp {
                startTimestampTimer()
            }
            
            // 启动旋转和移动定时器
            startRotationTimer()
        }
        .onChange(of: watermarkType) { oldValue, newValue in
            if newValue == .timestamp {
                startTimestampTimer()
            } else {
                stopTimestampTimer()
            }
            
            if newValue == .image, let url = watermarkImageURL {
                loadWatermarkImage(from: url)
            }
        }
        .onDisappear {
            stopTimestampTimer()
            stopRotationTimer()
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
        
        // 计算水印在预览图中的位置（显示坐标系）
        let watermarkRect = calculateWatermarkRect(
            videoSize: videoSize,
            imageSize: imageSize,
            imageRect: imageRect
        )
        
        // 显示水印
        if watermarkRect.width > 0 && watermarkRect.height > 0 {
            ZStack {
                // 水印内容
                watermarkContent(rect: watermarkRect)
                
                // 拖动和调整大小的控制框
                if watermarkType == .image {
                    watermarkControlFrame(
                        rect: watermarkRect,
                        imageRect: imageRect,
                        imageSize: imageSize,
                        videoSize: videoSize,
                        geometry: geometry
                    )
                }
            }
        }
    }
    
    // 水印内容
    @ViewBuilder
    private func watermarkContent(rect: CGRect) -> some View {
        switch watermarkType {
        case .image:
            if let watermarkImage = watermarkImage {
                Image(nsImage: watermarkImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: rect.width, height: rect.height)
                        .opacity(opacity)
                        .position(x: rect.midX, y: rect.midY)
            } else {
                EmptyView()
            }
        case .text:
            if !watermarkText.isEmpty, let videoSize = videoSize {
                // 计算缩放后的字体大小
                let scaledFontSize = calculateScaledFontSize(
                    originalSize: CGFloat(fontSize),
                    videoSize: videoSize,
                    displayRect: rect
                )
                
                // 计算当前旋转角度
                let currentRotation: Double = {
                    if let mode = rotationMode {
                        switch mode {
                        case .fixed:
                            return fixedRotationAngle
                        case .smooth:
                            // 使用当前时间计算旋转角度
                            return (Date().timeIntervalSince1970 * smoothRotationSpeed).truncatingRemainder(dividingBy: 360)
                        case .random:
                            return previewRotation
                        }
                    } else {
                        return 0
                    }
                }()
                
                Text(watermarkText)
                    .font(resolveFont(size: scaledFontSize))
                    .foregroundStyle(textColor)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1)
                    .padding(6)
                    .background {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.black.opacity(0.5))
                    }
                    .rotationEffect(.degrees(currentRotation))
                    .frame(minWidth: rect.width, minHeight: rect.height, alignment: .leading)
                    .opacity(opacity)
                    .position(x: rect.midX, y: rect.midY)
            } else {
                EmptyView()
            }
        case .timestamp:
            if let videoSize = videoSize {
                // 计算缩放后的字体大小
                let scaledFontSize = calculateScaledFontSize(
                    originalSize: CGFloat(fontSize),
                    videoSize: videoSize,
                    displayRect: rect
                )
                
                // 计算当前旋转角度
                let currentRotation: Double = {
                    if let mode = rotationMode {
                        switch mode {
                        case .fixed:
                            return fixedRotationAngle
                        case .smooth:
                            return (Date().timeIntervalSince1970 * smoothRotationSpeed).truncatingRemainder(dividingBy: 360)
                        case .random:
                            return previewRotation
                        }
                    } else {
                        return 0
                    }
                }()
                
                Text(formatTimestamp(currentTimestamp))
                    .font(resolveFont(size: scaledFontSize))
                    .foregroundStyle(textColor)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1)
                    .padding(6)
                    .background {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.black.opacity(0.5))
                    }
                    .rotationEffect(.degrees(currentRotation))
                    .frame(minWidth: rect.width, minHeight: rect.height, alignment: .leading)
                    .opacity(opacity)
                    .position(x: rect.midX, y: rect.midY)
            } else {
                EmptyView()
            }
        }
    }
    
    // 水印控制框（用于拖动和调整大小）
    @ViewBuilder
    private func watermarkControlFrame(
        rect: CGRect,
        imageRect: CGRect,
        imageSize: CGSize,
        videoSize: CGSize,
        geometry: GeometryProxy
    ) -> some View {
        // 控制框边框
        Rectangle()
            .strokeBorder(Color.blue, lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .opacity(isDragging || isResizing ? 1.0 : 0.5)
        
        // 调整大小的控制点（四个角）
        let cornerSize: CGFloat = 12
        let corners: [(CGPoint, ResizeCorner)] = [
            (CGPoint(x: rect.minX, y: rect.minY), .topLeft),
            (CGPoint(x: rect.maxX, y: rect.minY), .topRight),
            (CGPoint(x: rect.minX, y: rect.maxY), .bottomLeft),
            (CGPoint(x: rect.maxX, y: rect.maxY), .bottomRight)
        ]
        
        ForEach(0..<corners.count, id: \.self) { index in
            let (point, corner) = corners[index]
            Circle()
                .fill(Color.blue)
                .frame(width: cornerSize, height: cornerSize)
                .position(x: point.x, y: point.y)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isResizing {
                                isResizing = true
                                resizeCorner = corner
                                resizeStartSize = rect.size
                                resizeStartPoint = value.location
                            }
                            
                            handleResize(
                                startSize: resizeStartSize,
                                startPoint: resizeStartPoint,
                                currentPoint: value.location,
                                corner: resizeCorner,
                                imageRect: imageRect,
                                imageSize: imageSize,
                                videoSize: videoSize
                            )
                        }
                        .onEnded { _ in
                            isResizing = false
                            resizeCorner = .none
                        }
                )
        }
        
        // 拖动整个水印
        Rectangle()
            .fill(Color.clear)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartPosition = rect.origin
                        }
                        
                        let newX = dragStartPosition.x + value.translation.width
                        let newY = dragStartPosition.y + value.translation.height
                        
                        handleDrag(
                            newPosition: CGPoint(x: newX, y: newY),
                            watermarkSize: rect.size,
                            imageRect: imageRect,
                            imageSize: imageSize,
                            videoSize: videoSize
                        )
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
    
    // 处理拖动
    private func handleDrag(
        newPosition: CGPoint,
        watermarkSize: CGSize,
        imageRect: CGRect,
        imageSize: CGSize,
        videoSize: CGSize
    ) {
        // 限制在图片区域内
        let minX = imageRect.minX
        let minY = imageRect.minY
        let maxX = imageRect.maxX - watermarkSize.width
        let maxY = imageRect.maxY - watermarkSize.height
        
        let clampedX = max(minX, min(maxX, newPosition.x))
        let clampedY = max(minY, min(maxY, newPosition.y))
        
        // 转换为视频坐标系
        let scaleX = videoSize.width / imageSize.width
        let scaleY = videoSize.height / imageSize.height
        
        let videoX = (clampedX - imageRect.minX) * scaleX
        let videoY = (clampedY - imageRect.minY) * scaleY
        
        customPosition = CGPoint(x: videoX, y: videoY)
    }
    
    // 处理调整大小
    private func handleResize(
        startSize: CGSize,
        startPoint: CGPoint,
        currentPoint: CGPoint,
        corner: ResizeCorner,
        imageRect: CGRect,
        imageSize: CGSize,
        videoSize: CGSize
    ) {
        let deltaX = currentPoint.x - startPoint.x
        let deltaY = currentPoint.y - startPoint.y
        
        var newWidth = startSize.width
        var newHeight = startSize.height
        
        switch corner {
        case .topLeft:
            newWidth = startSize.width - deltaX
            newHeight = startSize.height - deltaY
        case .topRight:
            newWidth = startSize.width + deltaX
            newHeight = startSize.height - deltaY
        case .bottomLeft:
            newWidth = startSize.width - deltaX
            newHeight = startSize.height + deltaY
        case .bottomRight:
            newWidth = startSize.width + deltaX
            newHeight = startSize.height + deltaY
        case .none:
            return
        }
        
        // 限制最小和最大尺寸
        let minSize: CGFloat = 20
        let maxSize = min(imageSize.width, imageSize.height) * 0.5
        
        newWidth = max(minSize, min(maxSize, newWidth))
        newHeight = max(minSize, min(maxSize, newHeight))
        
        // 转换为视频坐标系
        let scaleX = videoSize.width / imageSize.width
        let scaleY = videoSize.height / imageSize.height
        
        let videoWidth = newWidth * scaleX
        let videoHeight = newHeight * scaleY
        
        customSize = CGSize(width: videoWidth, height: videoHeight)
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
            imageSize = CGSize(width: geometry.size.width, height: geometry.size.width / imageAspect)
            imageRect = CGRect(
                x: 0,
                y: (geometry.size.height - imageSize.height) / 2,
                width: imageSize.width,
                height: imageSize.height
            )
        } else {
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
        let scaleX = imageSize.width / videoSize.width
        let scaleY = imageSize.height / videoSize.height
        
        // 计算水印尺寸（视频坐标系）
        let watermarkSize: CGSize
        if let customSize = customSize {
            watermarkSize = customSize
        } else {
            watermarkSize = calculateDefaultWatermarkSize(videoSize: videoSize)
        }
        
        // 计算水印位置（视频坐标系）
        let videoPosition: CGPoint
        if let customPos = customPosition {
            videoPosition = customPos
        } else {
            videoPosition = calculateDefaultWatermarkPosition(
                videoSize: videoSize,
                watermarkSize: watermarkSize
            )
        }
        
        // 转换为预览图坐标系
        let displayX = imageRect.minX + videoPosition.x * scaleX
        let displayY = imageRect.minY + videoPosition.y * scaleY
        let displayWidth = watermarkSize.width * scaleX
        let displayHeight = watermarkSize.height * scaleY
        
        return CGRect(
            x: displayX,
            y: displayY,
            width: displayWidth,
            height: displayHeight
        )
    }
    
    // 计算默认水印尺寸
    private func calculateDefaultWatermarkSize(videoSize: CGSize) -> CGSize {
        switch watermarkType {
        case .image:
            if let watermarkImage = watermarkImage {
                let imageSize = watermarkImage.size
                // 限制最大尺寸为视频宽度的 15%（之前是 20%，现在更小）
                let maxWidth = videoSize.width * 0.15
                let maxHeight = videoSize.height * 0.15
                let aspectRatio = imageSize.width / imageSize.height
                
                if imageSize.width > maxWidth || imageSize.height > maxHeight {
                    if imageSize.width / maxWidth > imageSize.height / maxHeight {
                        return CGSize(width: maxWidth, height: maxWidth / aspectRatio)
                    } else {
                        return CGSize(width: maxHeight * aspectRatio, height: maxHeight)
                    }
                } else {
                    return imageSize
                }
            } else {
                return CGSize(width: videoSize.width * 0.1, height: videoSize.height * 0.1)
            }
        case .text, .timestamp:
            let text = watermarkType == .text ? watermarkText : formatTimestamp(currentTimestamp)
            let charWidth = CGFloat(fontSize) * 0.6
            let estimatedWidth = CGFloat(text.count) * charWidth + 12
            let estimatedHeight = CGFloat(fontSize) * 1.5 + 12
            return CGSize(width: min(estimatedWidth, videoSize.width * 0.4), height: estimatedHeight)
        }
    }
    
    // 计算默认水印位置
    private func calculateDefaultWatermarkPosition(
        videoSize: CGSize,
        watermarkSize: CGSize
    ) -> CGPoint {
        let margin: CGFloat = 20
        
        switch position {
        case .topLeft:
            return CGPoint(x: margin, y: margin)
        case .topCenter:
            return CGPoint(x: (videoSize.width - watermarkSize.width) / 2, y: margin)
        case .topRight:
            return CGPoint(x: videoSize.width - watermarkSize.width - margin, y: margin)
        case .middleLeft:
            return CGPoint(x: margin, y: (videoSize.height - watermarkSize.height) / 2)
        case .center:
            return CGPoint(x: (videoSize.width - watermarkSize.width) / 2, y: (videoSize.height - watermarkSize.height) / 2)
        case .middleRight:
            return CGPoint(x: videoSize.width - watermarkSize.width - margin, y: (videoSize.height - watermarkSize.height) / 2)
        case .bottomLeft:
            return CGPoint(x: margin, y: videoSize.height - watermarkSize.height - margin)
        case .bottomCenter:
            return CGPoint(x: (videoSize.width - watermarkSize.width) / 2, y: videoSize.height - watermarkSize.height - margin)
        case .bottomRight:
            return CGPoint(x: videoSize.width - watermarkSize.width - margin, y: videoSize.height - watermarkSize.height - margin)
        }
    }
    
    // 加载水印图片
    private func loadWatermarkImage(from url: URL) {
        isLoadingWatermarkImage = true
        
        Task.detached(priority: .userInitiated) {
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
    
    // 计算缩放后的字体大小
    private func calculateScaledFontSize(
        originalSize: CGFloat,
        videoSize: CGSize,
        displayRect: CGRect
    ) -> CGFloat {
        // 计算预览区域相对于原始视频的缩放比例
        let scaleX = displayRect.width / videoSize.width
        let scaleY = displayRect.height / videoSize.height
        let scale = min(scaleX, scaleY)
        
        // 返回缩放后的字体大小，确保预览与实际效果一致
        return originalSize * scale
    }
    
    // 解析字体：优先使用传入字体文件，否则系统默认
    private func resolveFont(size: CGFloat) -> Font {
        guard let fontURL = fontURL else {
            return .system(size: size, weight: .medium)
        }
        
        if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
           let first = descriptors.first {
            let ctFont = CTFontCreateWithFontDescriptor(first, size, nil)
            let name = CTFontCopyPostScriptName(ctFont) as String
            let nsFont = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: .medium)
            return Font(nsFont)
        }
        
        return .system(size: size, weight: .medium)
    }
    
    // 启动时间戳定时器
    private func startTimestampTimer() {
        stopTimestampTimer()
        
        timestampTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            currentTimestamp = Date()
        }
    }
    
    // 停止时间戳定时器
    private func stopTimestampTimer() {
        timestampTimer?.invalidate()
        timestampTimer = nil
    }
    
    // 启动旋转定时器
    private func startRotationTimer() {
        stopRotationTimer()
        
        guard let rotationMode = rotationMode else {
            previewRotation = fixedRotationAngle
            return
        }
        
        switch rotationMode {
        case .smooth:
            // 缓慢旋转：每帧更新
            movementTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { _ in
                previewRotation = (Date().timeIntervalSince1970 * smoothRotationSpeed).truncatingRemainder(dividingBy: 360)
            }
            
        case .random:
            // 随机旋转：配合位置变化
            if enableRandomMovement, let range = randomRotationRange {
                previewRotation = Double.random(in: range.min...range.max)
                movementTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                    previewRotation = Double.random(in: range.min...range.max)
                }
            } else {
                previewRotation = fixedRotationAngle
            }
            
        case .fixed:
            previewRotation = fixedRotationAngle
            break
        }
    }
    
    // 停止旋转定时器
    private func stopRotationTimer() {
        movementTimer?.invalidate()
        movementTimer = nil
    }
}

