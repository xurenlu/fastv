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
    
    private let timelineHeight: CGFloat = 80  // 增加高度以容纳截图
    private let markerHeight: CGFloat = 60  // 增加标记高度
    private let thumbnailSize: CGFloat = 50  // 缩略图大小
    
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
                
                // 变更点列表（带截图预览）
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
                .frame(maxHeight: 300)
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
        
        return VStack(spacing: 4) {
            // 悬停时显示大图预览
            if hoveredPoint?.id == point.id, let thumbnailImage = point.thumbnailImage {
                VStack(spacing: 6) {
                    Image(nsImage: thumbnailImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 200, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 8)
                    
                    VStack(spacing: 2) {
                        Text(point.timeString)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(String(format: "差异: %.1f%%", point.changeIntensity * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 8)
                }
                .offset(y: -timelineHeight / 2 - 180)
            }
            
            // 标记线
            Rectangle()
                .fill(Color.blue)
                .frame(width: 2)
                .frame(height: timelineHeight)
            
            // 截图缩略图（如果有）
            if let thumbnailImage = point.thumbnailImage {
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.blue, lineWidth: 2)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 4)
                    .offset(y: -timelineHeight / 2)
            } else {
                // 没有截图时显示标记点
                Circle()
                    .fill(Color.blue)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 2)
                    .offset(y: -timelineHeight / 2)
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
                // 截图缩略图
                if let thumbnailImage = point.thumbnailImage {
                    Image(nsImage: thumbnailImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 45)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                        }
                } else {
                    // 占位符
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 60, height: 45)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
                
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

