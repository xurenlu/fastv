//
//  VideoTimelineSelector.swift
//  fastv
//
//  Created by rocky on 2025/12/25.
//

import SwiftUI

/// 视频时间轴选择器
/// 允许用户通过拖动或点击选择视频中的特定时间点
struct VideoTimelineSelector: View {
    let duration: TimeInterval
    @Binding var selectedTime: TimeInterval
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text("选择预览帧")
                    .font(.headline)
                Spacer()
                Text(formatTime(selectedTime))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.blue)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景轨道
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    // 已选择部分
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * CGFloat(selectedTime / duration), height: 8)
                    
                    // 滑块指示器
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.2), radius: 2)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .position(
                            x: geometry.size.width * CGFloat(selectedTime / duration),
                            y: 4
                        )
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let newTime = Double(value.location.x / geometry.size.width) * duration
                                    selectedTime = min(max(newTime, 0), duration)
                                }
                        )
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let newTime = Double(location.x / geometry.size.width) * duration
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTime = min(max(newTime, 0), duration)
                    }
                }
            }
            .frame(height: 20)
            
            // 时间标记
            HStack {
                Text(formatTime(0))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatTime(duration / 2))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatTime(duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Preview
#Preview {
    VStack {
        VideoTimelineSelector(
            duration: 300,
            selectedTime: .constant(150)
        )
        .frame(width: 500)
        
        VideoTimelineSelector(
            duration: 7200,
            selectedTime: .constant(3600)
        )
        .frame(width: 500)
    }
    .padding()
}

