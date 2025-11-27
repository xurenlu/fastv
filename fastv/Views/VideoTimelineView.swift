//
//  VideoTimelineView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

struct VideoTimelineView: View {
    let duration: TimeInterval  // 视频总时长（秒）
    let changePoints: [SceneChangePoint]  // 变更点列表
    let onSeekToTime: ((TimeInterval) -> Void)?  // 点击跳转回调
    
    @State private var hoveredPoint: SceneChangePoint?
    @State private var scale: Double = 1.0  // 缩放比例
    
    private let timelineHeight: CGFloat = 60
    private let markerHeight: CGFloat = 40
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack {
                Label("画面变更检测", systemImage: "waveform.path")
                    .font(.headline)
                
                Spacer()
                
                if !changePoints.isEmpty {
                    Text("发现 \(changePoints.count) 个变更点")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            if changePoints.isEmpty {
                Text("未检测到画面变更")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                // 时间轴
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // 时间轴背景
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: timelineHeight)
                        
                        // 时间刻度
                        timelineMarkers(in: geometry)
                        
                        // 变更点标记
                        ForEach(changePoints) { point in
                            changePointMarker(point: point, in: geometry)
                        }
                    }
                }
                .frame(height: timelineHeight + markerHeight)
                
                // 变更点列表
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(changePoints) { point in
                            ChangePointRow(point: point) {
                                onSeekToTime?(point.timestamp)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        }
    }
    
    /// 绘制时间刻度
    private func timelineMarkers(in geometry: GeometryProxy) -> some View {
        let width = geometry.size.width
        let durationMinutes = Int(duration) / 60
        let durationSeconds = Int(duration) % 60
        
        // 计算合适的刻度间隔
        let totalSeconds = duration
        let markerCount = min(10, max(5, Int(totalSeconds / 10))) // 每10秒一个标记，最多10个
        let interval = totalSeconds / Double(markerCount)
        
        return ZStack {
            ForEach(0...markerCount, id: \.self) { index in
                let time = Double(index) * interval
                let position = CGFloat(time / duration) * width
                
                VStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1, height: 8)
                    
                    Text(formatTime(time))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .position(x: position, y: timelineHeight / 2)
            }
        }
    }
    
    /// 绘制变更点标记
    private func changePointMarker(point: SceneChangePoint, in geometry: GeometryProxy) -> some View {
        let width = geometry.size.width
        let position = CGFloat(point.timestamp / duration) * width
        
        return VStack(spacing: 0) {
            // 标记线
            Rectangle()
                .fill(Color.blue)
                .frame(width: 2)
                .frame(height: timelineHeight)
            
            // 标记点
            Circle()
                .fill(Color.blue)
                .frame(width: 12, height: 12)
                .overlay {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.2), radius: 2)
                .offset(y: -timelineHeight / 2)
            
            // 悬停时显示详情
            if hoveredPoint?.id == point.id {
                VStack(spacing: 4) {
                    Text(point.timeString)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(String(format: "差异: %.1f%%", point.changeIntensity * 100))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 4)
                }
                .offset(y: -timelineHeight / 2 - 30)
            }
        }
        .position(x: position, y: timelineHeight / 2)
        .onTapGesture {
            onSeekToTime?(point.timestamp)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredPoint = hovering ? point : nil
            }
        }
    }
    
    /// 格式化时间显示
    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
}

/// 变更点行视图
struct ChangePointRow: View {
    let point: SceneChangePoint
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 时间戳
                Text(point.timeString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.blue)
                    .frame(width: 80, alignment: .leading)
                
                // 变更强度指示器
                HStack(spacing: 4) {
                    ForEach(0..<5) { index in
                        Circle()
                            .fill(index < Int(point.changeIntensity * 5) ? Color.blue : Color.secondary.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }
                
                // 描述
                Text(point.description)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // 跳转图标
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.05))
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VideoTimelineView(
        duration: 120,
        changePoints: [
            SceneChangePoint(timestamp: 7.0, frameNumber: 210, changeIntensity: 0.45, description: "第7秒：从室内切到室外"),
            SceneChangePoint(timestamp: 21.0, frameNumber: 630, changeIntensity: 0.38, description: "第21秒：从一个人变成两个人"),
            SceneChangePoint(timestamp: 45.5, frameNumber: 1365, changeIntensity: 0.52, description: "第45.5秒：画面大幅变更")
        ],
        onSeekToTime: { time in
            print("跳转到: \(time)秒")
        }
    )
    .padding()
    .frame(width: 600)
}

