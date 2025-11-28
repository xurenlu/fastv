//
//  LiveTranscriptionView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI
import AppKit

/// 直播转录主视图
struct LiveTranscriptionView: View {
    @StateObject private var viewModel = LiveTranscriptionViewModel()
    @ObservedObject private var recordManager = LiveTranscriptionManager.shared
    @State private var selectedRecord: LiveTranscriptionRecord?
    @State private var showDetail = false
    
    // 缓存总时长计算
    private var totalDuration: Double {
        recordManager.totalDuration()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部：转录控制区域
            VStack(spacing: 16) {
                // 转录按钮和状态
                HStack(spacing: 20) {
                    // 转录按钮
                    Button(action: {
                        if viewModel.isTranscribing {
                            viewModel.stopTranscribing()
                        } else {
                            viewModel.startTranscribing()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: viewModel.isTranscribing ? "stop.circle.fill" : "record.circle.fill")
                                .font(.system(size: 32))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.isTranscribing ? "停止转录" : "开始转录")
                                    .font(.headline)
                                
                                if viewModel.isTranscribing {
                                    Text(formatDuration(viewModel.transcribingDuration))
                                        .font(.subheadline)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("点击开始实时转录系统音频")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .foregroundStyle(viewModel.isTranscribing ? .red : .blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 24)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(viewModel.isTranscribing ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(viewModel.isTranscribing ? Color.red : Color.blue, lineWidth: 2)
                                }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // 取消按钮（仅在转录中显示）
                    if viewModel.isTranscribing {
                        Button(action: {
                            viewModel.cancelTranscribing()
                        }) {
                            Label("取消", systemImage: "xmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // 实时转写内容显示(转录中)
                if viewModel.isTranscribing {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)
                            
                            Text("实时转写")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if !viewModel.transcriptionProgress.isEmpty {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text(viewModel.transcriptionProgress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        
                        if !viewModel.realtimeTranscript.isEmpty {
                            ScrollView {
                                Text(viewModel.realtimeTranscript)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .frame(maxHeight: 150)
                            .background {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(NSColor.textBackgroundColor))
                            }
                        } else {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("正在转写中...")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .frame(height: 50)
                            .background {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(NSColor.textBackgroundColor))
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.blue.opacity(0.05))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                            }
                    }
                }
                
                // 错误提示
                if let errorMessage = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.1))
                    }
                }
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 中部：转录记录列表
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("转录记录")
                            .font(.system(size: 17, weight: .semibold))
                        
                        if !recordManager.records.isEmpty {
                            Text("\(recordManager.records.count) 条记录")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // 统计信息
                    if !recordManager.records.isEmpty {
                        HStack(spacing: 20) {
                            Label(formatTotalDuration(totalDuration), systemImage: "clock")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                Divider()
                
                // 记录列表
                if recordManager.records.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("暂无转录记录")
                                .font(.system(size: 20, weight: .semibold))
                        } icon: {
                            Image(systemName: "waveform.circle")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                    } description: {
                        VStack(spacing: 8) {
                            Text("点击上方按钮开始实时转录")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(recordManager.records) { record in
                                LiveTranscriptionRecordRow(record: record)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .onTapGesture {
                                        selectedRecord = record
                                        showDetail = true
                                    }
                                
                                Divider()
                                    .padding(.horizontal, 20)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .navigationTitle("直播转录")
        .sheet(item: $selectedRecord) { record in
            NavigationStack {
                LiveTranscriptionDetailView(record: record)
            }
            .frame(minWidth: 600, minHeight: 500)
        }
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func formatTotalDuration(_ duration: Double) -> String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        } else if minutes > 0 {
            return "\(minutes)分钟"
        } else {
            return "0分钟"
        }
    }
}

/// 直播转录记录行视图
struct LiveTranscriptionRecordRow: View {
    let record: LiveTranscriptionRecord
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题和状态
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(record.title)
                            .font(.headline)
                            .lineLimit(1)
                        
                        if record.isOptimizing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        }
                    }
                    
                    // 摘要或全文预览
                    if let summary = record.summary, !isExpanded {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else if !record.displayText.isEmpty {
                        Text(record.displayText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                    } else {
                        Text("无转录内容")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                    
                    // 元信息
                    HStack(spacing: 12) {
                        Label(record.formattedDate, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Label(record.formattedDuration, systemImage: "timer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if record.characterCount > 0 {
                            Label("\(record.characterCount) 字", systemImage: "text.alignleft")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        // 展开/收起按钮
                        if !record.displayText.isEmpty && record.displayText.count > 100 {
                            Button(action: {
                                withAnimation {
                                    isExpanded.toggle()
                                }
                            }) {
                                Label(isExpanded ? "收起" : "展开", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Spacer()
            }
        }
        .contentShape(Rectangle())
    }
}

/// 直播转录详情视图
struct LiveTranscriptionDetailView: View {
    let record: LiveTranscriptionRecord
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题和元信息
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 16) {
                        Label(record.formattedDate, systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Label(record.formattedDuration, systemImage: "timer")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        if record.characterCount > 0 {
                            Label("\(record.characterCount) 字", systemImage: "text.alignleft")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Divider()
                
                // 转录文本
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("转录文本")
                            .font(.headline)
                        
                        if record.isOptimizing {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("AI优化中...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if record.optimizedTranscript != nil {
                            Label("已优化", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    
                    if !record.displayText.isEmpty {
                        Text(record.displayText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(NSColor.textBackgroundColor))
                            }
                    } else {
                        Text("无转录内容")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .italic()
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(NSColor.textBackgroundColor))
                            }
                    }
                    
                    // 显示摘要（如果有）
                    if let summary = record.summary, !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("摘要")
                                .font(.headline)
                            
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(NSColor.textBackgroundColor).opacity(0.5))
                                }
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("转录详情")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(record.displayText, forType: .string)
                }) {
                    Label("复制文本", systemImage: "doc.on.doc")
                }
            }
        }
    }
}

#Preview {
    LiveTranscriptionView()
}

