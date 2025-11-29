//
//  MeetingRecordView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

/// 会议记录主视图
struct MeetingRecordView: View {
    @StateObject private var viewModel = MeetingRecordViewModel()
    @ObservedObject private var recordManager = MeetingRecordManager.shared
    @State private var selectedRecord: MeetingRecord?
    @State private var showDetail = false
    
    // 缓存总时长计算
    private var totalDuration: Double {
        recordManager.totalDuration()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部：录音控制区域
            VStack(spacing: 16) {
                // 波形显示（仅在录音时显示）
                if viewModel.isRecording {
                    InlineWaveformView(
                        audioLevel: viewModel.audioLevel,
                        isActive: viewModel.isRecording
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // 录音按钮和状态
                HStack(spacing: 20) {
                    // 录音按钮
                    Button(action: {
                        if viewModel.isRecording {
                            viewModel.stopRecording()
                        } else {
                            viewModel.startRecording()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "record.circle.fill")
                                .font(.system(size: 32))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.isRecording ? "停止录音" : "开始录音")
                                    .font(.headline)
                                
                                if viewModel.isRecording {
                                    Text(formatDuration(viewModel.recordingDuration))
                                        .font(.subheadline)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("点击开始记录会议")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .foregroundStyle(viewModel.isRecording ? .red : .blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 24)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(viewModel.isRecording ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(viewModel.isRecording ? Color.red : Color.blue, lineWidth: 2)
                                }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isProcessing)
                    
                    // 取消按钮（仅在录音中显示）
                    if viewModel.isRecording {
                        Button(action: {
                            viewModel.cancelRecording()
                        }) {
                            Label("取消", systemImage: "xmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // 实时转写内容显示(录音中)
                if viewModel.isRecording && !viewModel.realtimeTranscript.isEmpty {
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
                
                // 处理状态提示
                if viewModel.isProcessing {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            ProgressView(value: viewModel.processingProgress)
                                .progressViewStyle(.linear)
                                .frame(maxWidth: 300)
                            
                            Text("\(Int(viewModel.processingProgress * 100))%")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40)
                        }
                        
                        HStack(spacing: 8) {
                            if let stage = viewModel.processingStage {
                                Text(stage.rawValue)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if viewModel.canCancelProcessing {
                                Button(action: {
                                    viewModel.cancelProcessing()
                                }) {
                                    Label("取消", systemImage: "xmark.circle")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.blue.opacity(0.1))
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
            
            // 中部：会议记录列表
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("会议记录")
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
                            Text("暂无会议记录")
                                .font(.system(size: 20, weight: .semibold))
                        } icon: {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                    } description: {
                        VStack(spacing: 8) {
                            Text("点击上方按钮开始记录会议")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(recordManager.records) { record in
                                MeetingRecordRow(record: record)
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
        .navigationTitle("会议记录")
        .sheet(item: $selectedRecord) { record in
            NavigationStack {
                MeetingRecordDetailViewWrapper(record: record)
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

/// 包装器视图，用于处理 MeetingRecord 的绑定
struct MeetingRecordDetailViewWrapper: View {
    let record: MeetingRecord
    @State private var mutableRecord: MeetingRecord
    @State private var hasChanges = false
    
    init(record: MeetingRecord) {
        self.record = record
        self._mutableRecord = State(initialValue: record)
    }
    
    var body: some View {
        MeetingRecordDetailView(record: $mutableRecord)
            .onChange(of: mutableRecord) { oldValue, newValue in
                // 只在真正有变化时更新
                checkForChanges(oldValue: oldValue, newValue: newValue)
            }
            .onDisappear {
                // 关闭时才保存，避免频繁更新
                if hasChanges {
                    MeetingRecordManager.shared.update(mutableRecord)
                }
            }
    }
    
    private func checkForChanges(oldValue: MeetingRecord, newValue: MeetingRecord) {
        // 确保是同一个记录
        guard oldValue.id == newValue.id else { return }
        
        // 检查各个字段是否有变化
        let titleChanged = oldValue.title != newValue.title
        let textChanged = oldValue.correctedText != newValue.correctedText
        let summaryChanged = oldValue.summary != newValue.summary
        let actionItemsChanged = oldValue.actionItems != newValue.actionItems
        
        // 如果有任何变化，标记为已更改
        if titleChanged || textChanged || summaryChanged || actionItemsChanged {
            hasChanges = true
        }
    }
}

#Preview {
    MeetingRecordView()
}

