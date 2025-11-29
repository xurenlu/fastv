//
//  InlineWaveformView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

/// 内嵌波形显示视图 - 用于在界面中显示实时音频波形
struct InlineWaveformView: View {
    let audioLevel: Float
    let isActive: Bool
    
    @State private var barHeights: [CGFloat] = Array(repeating: 0.1, count: 20)
    private let barCount = 20
    private let minBarHeight: CGFloat = 0.1
    private let maxBarHeight: CGFloat = 1.0
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    
    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let availableWidth = totalWidth - CGFloat(barCount - 1) * barSpacing
            let calculatedBarWidth = min(barWidth, availableWidth / CGFloat(barCount))
            
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: calculatedBarWidth / 2, style: .continuous)
                        .fill(barGradient(for: barHeights[index]))
                        .frame(width: calculatedBarWidth, height: barHeights[index] * geometry.size.height)
                        .shadow(color: barShadowColor(for: barHeights[index]), radius: barHeights[index] * 3, x: 0, y: 0)
                        .animation(
                            .spring(response: 0.15, dampingFraction: 0.7)
                            .delay(Double(index) * 0.01),
                            value: barHeights[index]
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.blue.opacity(0.3),
                                        Color.purple.opacity(0.2)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1
                            )
                    }
            }
        }
        .frame(height: 50)
        .onChange(of: audioLevel) { _, newLevel in
            updateBars(with: newLevel)
        }
        .onChange(of: isActive) { _, newActive in
            if !newActive {
                resetBars()
            }
        }
        .onAppear {
            if isActive {
                updateBars(with: audioLevel)
            }
        }
    }
    
    /// 根据音量大小生成渐变色
    private func barGradient(for height: CGFloat) -> LinearGradient {
        let normalizedHeight = min(max(height, minBarHeight), maxBarHeight)
        
        // 根据高度决定颜色
        let colors: [Color]
        if normalizedHeight < 0.3 {
            // 低音量：蓝色系
            colors = [
                Color.blue.opacity(0.9),
                Color.cyan.opacity(0.7),
                Color.blue.opacity(0.5)
            ]
        } else if normalizedHeight < 0.7 {
            // 中音量：绿色/黄色系
            colors = [
                Color.green.opacity(0.9),
                Color.yellow.opacity(0.7),
                Color.green.opacity(0.5)
            ]
        } else {
            // 高音量：红色/橙色系
            colors = [
                Color.red.opacity(0.9),
                Color.orange.opacity(0.8),
                Color.red.opacity(0.6)
            ]
        }
        
        return LinearGradient(
            colors: colors,
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    /// 根据高度生成阴影颜色
    private func barShadowColor(for height: CGFloat) -> Color {
        let normalizedHeight = min(max(height, minBarHeight), maxBarHeight)
        
        if normalizedHeight < 0.3 {
            return Color.blue.opacity(0.3)
        } else if normalizedHeight < 0.7 {
            return Color.green.opacity(0.4)
        } else {
            return Color.red.opacity(0.5)
        }
    }
    
    /// 更新波形条高度
    private func updateBars(with level: Float) {
        guard isActive else { return }
        
        let normalizedLevel = min(max(level, 0.0), 1.0)
        
        // 创建基于音频电平的波形模式
        // 中间高，两边低，模拟真实的音频频谱
        for i in 0..<barCount {
            let centerIndex = barCount / 2
            let distanceFromCenter = abs(i - centerIndex)
            let maxDistance = CGFloat(centerIndex)
            
            // 基础高度：根据距离中心的距离衰减
            let distanceFactor = 1.0 - (CGFloat(distanceFromCenter) / maxDistance) * 0.5
            
            // 添加一些随机变化，模拟真实频谱
            let randomVariation = CGFloat.random(in: -0.1...0.1)
            
            // 计算最终高度
            let baseHeight = CGFloat(normalizedLevel) * distanceFactor + randomVariation
            let finalHeight = min(max(baseHeight, minBarHeight), maxBarHeight)
            
            // 平滑更新
            barHeights[i] = finalHeight
        }
    }
    
    /// 重置波形条
    private func resetBars() {
        barHeights = Array(repeating: minBarHeight, count: barCount)
    }
}

#Preview {
    VStack {
        InlineWaveformView(audioLevel: 0.5, isActive: true)
            .padding()
        
        InlineWaveformView(audioLevel: 0.8, isActive: true)
            .padding()
        
        InlineWaveformView(audioLevel: 0.2, isActive: true)
            .padding()
    }
    .frame(width: 400)
}
