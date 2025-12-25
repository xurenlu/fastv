//
//  ImageComparisonSlider.swift
//  fastv
//
//  Created by rocky on 2025/12/25.
//

import SwiftUI

/// 图片对比滑块视图
/// 支持左右拖动滑块查看调整前后的对比效果
struct ImageComparisonSlider: View {
    let originalImage: NSImage?
    let adjustedImage: NSImage?
    
    @State private var sliderPosition: CGFloat = 0.5
    @State private var isDragging = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景
                Color.black.opacity(0.1)
                
                if let original = originalImage, let adjusted = adjustedImage {
                    // 调整后的图片（完整显示）
                    Image(nsImage: adjusted)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    
                    // 原始图片（通过遮罩只显示左侧部分）
                    Image(nsImage: original)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .mask(
                            Rectangle()
                                .frame(width: geometry.size.width * sliderPosition)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                    
                    // 分割线和滑块
                    VStack(spacing: 0) {
                        // 垂直分割线
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 3)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                        
                        // 滑块手柄
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 40, height: 40)
                                .shadow(color: .black.opacity(0.3), radius: 4)
                            
                            HStack(spacing: 2) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 10, weight: .bold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.gray)
                        }
                        .offset(y: -20)
                        
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 3)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                    }
                    .frame(height: geometry.size.height)
                    .position(x: geometry.size.width * sliderPosition, y: geometry.size.height / 2)
                    
                    // 标签
                    HStack {
                        // 原图标签
                        Text("原图")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .padding(8)
                        
                        Spacer()
                        
                        // 调整后标签
                        Text("调整后")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .padding(8)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    // 占位符
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("等待加载预览图片...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let newPosition = value.location.x / geometry.size.width
                        sliderPosition = min(max(newPosition, 0), 1)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onTapGesture { location in
                withAnimation(.easeInOut(duration: 0.2)) {
                    let newPosition = location.x / geometry.size.width
                    sliderPosition = min(max(newPosition, 0), 1)
                }
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview
#Preview {
    ImageComparisonSlider(
        originalImage: nil,
        adjustedImage: nil
    )
    .frame(width: 600, height: 400)
    .padding()
}

