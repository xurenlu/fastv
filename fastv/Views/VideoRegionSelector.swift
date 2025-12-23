//
//  VideoRegionSelector.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI
import AppKit

/// 通用的视频区域结构（用于区域选择器）
struct VideoRegion: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}

extension VideoRegion {
    init(_ blurRegion: BlurRegion) {
        self.x = blurRegion.x
        self.y = blurRegion.y
        self.width = blurRegion.width
        self.height = blurRegion.height
    }
    
    init(_ cropRegion: CropRegion) {
        self.x = cropRegion.x
        self.y = cropRegion.y
        self.width = cropRegion.width
        self.height = cropRegion.height
    }
    
    func toBlurRegion() -> BlurRegion {
        return BlurRegion(x: x, y: y, width: width, height: height)
    }
    
    func toCropRegion() -> CropRegion {
        return CropRegion(x: x, y: y, width: width, height: height)
    }
}

/// 视频区域选择器
/// 支持在预览图上用鼠标框选矩形区域
struct VideoRegionSelector: View {
    /// 预览图片
    let previewImage: NSImage
    /// 视频的实际尺寸
    let videoSize: CGSize
    /// 选中区域（视频坐标系）
    @Binding var selectedRegion: VideoRegion
    /// 是否启用选择
    var enabled: Bool = true
    
    @State private var dragStart: CGPoint?
    @State private var currentDrag: CGPoint?
    @State private var displayRect: CGRect = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 预览图片，根据视频尺寸保持宽高比
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(videoSize.width / videoSize.height, contentMode: .fit)
                
                // 选择区域覆盖层
                if enabled && displayRect.width > 0 && displayRect.height > 0 {
                    Rectangle()
                        .fill(Color.blue.opacity(0.2))
                        .border(Color.blue, width: 2)
                        .frame(width: displayRect.width, height: displayRect.height)
                        .position(
                            x: displayRect.midX,
                            y: displayRect.midY
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard enabled else { return }
                        let location = value.location
                        
                        if dragStart == nil {
                            dragStart = location
                        }
                        currentDrag = location
                        updateDisplayRect(start: dragStart!, end: location, geometry: geometry)
                    }
                    .onEnded { value in
                        guard enabled, let start = dragStart, let end = currentDrag else { return }
                        updateDisplayRect(start: start, end: end, geometry: geometry)
                        updateSelectedRegion(displayRect: displayRect, geometry: geometry)
                        dragStart = nil
                        currentDrag = nil
                    }
            )
            .onAppear {
                updateDisplayRectFromRegion(geometry: geometry)
            }
            .onChange(of: selectedRegion) { _, _ in
                updateDisplayRectFromRegion(geometry: geometry)
            }
        }
    }
    
    /// 从显示坐标更新显示矩形
    private func updateDisplayRect(start: CGPoint, end: CGPoint, geometry: GeometryProxy) {
        let imageAspect = videoSize.width / videoSize.height
        let viewAspect = geometry.size.width / geometry.size.height
        
        var imageRect: CGRect
        var imageSize: CGSize
        
        // 计算图片在视图中的实际显示区域
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
        
        // 将拖拽坐标限制在图片区域内
        let clampedStart = CGPoint(
            x: max(imageRect.minX, min(imageRect.maxX, start.x)),
            y: max(imageRect.minY, min(imageRect.maxY, start.y))
        )
        let clampedEnd = CGPoint(
            x: max(imageRect.minX, min(imageRect.maxX, end.x)),
            y: max(imageRect.minY, min(imageRect.maxY, end.y))
        )
        
        // 计算矩形
        let rect = CGRect(
            x: min(clampedStart.x, clampedEnd.x),
            y: min(clampedStart.y, clampedEnd.y),
            width: abs(clampedEnd.x - clampedStart.x),
            height: abs(clampedEnd.y - clampedStart.y)
        )
        
        displayRect = rect.intersection(imageRect)
    }
    
    /// 从选中区域更新显示矩形
    private func updateDisplayRectFromRegion(geometry: GeometryProxy) {
        guard selectedRegion.width > 0 && selectedRegion.height > 0 else {
            displayRect = .zero
            return
        }
        
        let imageAspect = videoSize.width / videoSize.height
        let viewAspect = geometry.size.width / geometry.size.height
        
        var imageRect: CGRect
        var imageSize: CGSize
        
        // 计算图片在视图中的实际显示区域
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
        
        // 将视频坐标转换为显示坐标
        let scaleX = imageSize.width / videoSize.width
        let scaleY = imageSize.height / videoSize.height
        
        let displayX = CGFloat(selectedRegion.x) * scaleX + imageRect.minX
        let displayY = CGFloat(selectedRegion.y) * scaleY + imageRect.minY
        let displayWidth = CGFloat(selectedRegion.width) * scaleX
        let displayHeight = CGFloat(selectedRegion.height) * scaleY
        
        displayRect = CGRect(
            x: displayX,
            y: displayY,
            width: displayWidth,
            height: displayHeight
        )
    }
    
    /// 将显示矩形转换为视频坐标系并更新选中区域
    private func updateSelectedRegion(displayRect: CGRect, geometry: GeometryProxy) {
        let imageAspect = videoSize.width / videoSize.height
        let viewAspect = geometry.size.width / geometry.size.height
        
        var imageRect: CGRect
        var imageSize: CGSize
        
        // 计算图片在视图中的实际显示区域
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
        
        // 将显示坐标转换为视频坐标
        let scaleX = videoSize.width / imageSize.width
        let scaleY = videoSize.height / imageSize.height
        
        let videoX = Int((displayRect.minX - imageRect.minX) * scaleX)
        let videoY = Int((displayRect.minY - imageRect.minY) * scaleY)
        let videoWidth = Int(displayRect.width * scaleX)
        let videoHeight = Int(displayRect.height * scaleY)
        
        // 确保坐标在有效范围内
        let clampedX = max(0, min(videoX, Int(videoSize.width)))
        let clampedY = max(0, min(videoY, Int(videoSize.height)))
        let clampedWidth = max(1, min(videoWidth, Int(videoSize.width) - clampedX))
        let clampedHeight = max(1, min(videoHeight, Int(videoSize.height) - clampedY))
        
        selectedRegion = VideoRegion(
            x: clampedX,
            y: clampedY,
            width: clampedWidth,
            height: clampedHeight
        )
    }
}

