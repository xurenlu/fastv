//
//  MeetingRecordRow.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

/// 会议记录列表项组件
struct MeetingRecordRow: View {
    let record: MeetingRecord
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 左侧：图标和状态
            VStack(spacing: 4) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 32)
                
                if !record.actionItems.isEmpty {
                    Text("\(record.actionItems.count)")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            Capsule()
                                .fill(.red)
                        }
                }
            }
            
            // 中间：内容
            VStack(alignment: .leading, spacing: 6) {
                // 标题
                Text(record.title.isEmpty ? "未命名会议" : record.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                // 时间和时长
                HStack(spacing: 12) {
                    Label(record.formattedDate, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label(record.formattedDuration, systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if !record.correctedText.isEmpty {
                        Label("\(record.characterCount)字", systemImage: "text.alignleft")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 摘要预览
                if !record.summary.isEmpty {
                    Text(record.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                } else if !record.correctedText.isEmpty {
                    Text(record.correctedText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
                
                // 代办事项预览
                if !record.actionItems.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        
                        Text("\(record.actionItems.count)项待办")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .padding(.top, 2)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    MeetingRecordRow(
        record: MeetingRecord(
            title: "产品规划会议",
            originalText: "原始文本",
            correctedText: "今天讨论了产品的下一步规划，包括新功能的开发和用户体验的优化。",
            summary: "讨论了产品规划和用户体验优化",
            actionItems: ["完成新功能设计", "优化用户界面"],
            duration: 1800
        )
    )
    .padding()
}

