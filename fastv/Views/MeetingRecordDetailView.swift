//
//  MeetingRecordDetailView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI
import AppKit

/// 会议记录详情视图
struct MeetingRecordDetailView: View {
    @ObservedObject var recordManager = MeetingRecordManager.shared
    @Binding var record: MeetingRecord
    @State private var isEditingTitle = false
    @State private var editedTitle: String = ""
    @State private var showOriginalText = false
    @State private var showSummary = true
    @State private var completedActionItems: Set<Int> = []
    @State private var showDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题区域
                VStack(alignment: .leading, spacing: 12) {
                    if isEditingTitle {
                        TextField("会议标题", text: $editedTitle)
                            .textFieldStyle(.roundedBorder)
                            .font(.title2)
                            .onSubmit {
                                saveTitle()
                            }
                            .onAppear {
                                editedTitle = record.title
                            }
                    } else {
                        HStack {
                            Text(record.title.isEmpty ? "未命名会议" : record.title)
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Button(action: {
                                editedTitle = record.title
                                isEditingTitle = true
                            }) {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // 元信息
                    HStack(spacing: 16) {
                        Label(record.formattedDate, systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Label(record.formattedDuration, systemImage: "timer")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        if !record.correctedText.isEmpty {
                            Label("\(record.characterCount)字", systemImage: "text.alignleft")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // AI 修正后的文本（主要显示）
                if !record.correctedText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("会议内容")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button(action: {
                                copyToPasteboard(record.correctedText)
                            }) {
                                Label("复制", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Text(record.correctedText)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.secondary.opacity(0.1))
                            }
                    }
                }
                
                // 原始文本（可查看）
                if !record.originalText.isEmpty && record.originalText != record.correctedText {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: {
                            withAnimation {
                                showOriginalText.toggle()
                            }
                        }) {
                            HStack {
                                Text("原始转录文本")
                                    .font(.headline)
                                
                                Spacer()
                                
                                Image(systemName: showOriginalText ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        if showOriginalText {
                            Text(record.originalText)
                                .font(.body)
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.secondary.opacity(0.05))
                                }
                        }
                    }
                }
                
                // 摘要
                if !record.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: {
                            withAnimation {
                                showSummary.toggle()
                            }
                        }) {
                            HStack {
                                Text("会议摘要")
                                    .font(.headline)
                                
                                Spacer()
                                
                                Image(systemName: showSummary ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        if showSummary {
                            Text(record.summary)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.blue.opacity(0.1))
                                }
                        }
                    }
                }
                
                // 待办事项
                if !record.actionItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("待办事项")
                                .font(.headline)
                            
                            Spacer()
                            
                            Text("\(completedActionItems.count)/\(record.actionItems.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(record.actionItems.enumerated()), id: \.offset) { index, item in
                                HStack(alignment: .top, spacing: 8) {
                                    Button(action: {
                                        if completedActionItems.contains(index) {
                                            completedActionItems.remove(index)
                                        } else {
                                            completedActionItems.insert(index)
                                        }
                                    }) {
                                        Image(systemName: completedActionItems.contains(index) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(completedActionItems.contains(index) ? .green : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Text(item)
                                        .font(.body)
                                        .strikethrough(completedActionItems.contains(index))
                                        .foregroundStyle(completedActionItems.contains(index) ? .secondary : .primary)
                                        .textSelection(.enabled)
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.orange.opacity(0.1))
                        }
                    }
                }
                
                // 操作按钮
                HStack(spacing: 12) {
                    Button(action: {
                        copyToPasteboard(record.correctedText.isEmpty ? record.originalText : record.correctedText)
                    }) {
                        Label("复制内容", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        Label("删除", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .navigationTitle("会议详情")
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                recordManager.remove(record)
                dismiss()
            }
        } message: {
            Text("确定要删除这条会议记录吗？此操作无法撤销。")
        }
        .onAppear {
            // 初始化已完成事项（这里可以从记录中读取，如果需要持久化）
        }
    }
    
    private func saveTitle() {
        var updatedRecord = record
        updatedRecord.title = editedTitle.isEmpty ? MeetingRecord.generateDefaultTitle() : editedTitle
        recordManager.update(updatedRecord)
        record = updatedRecord
        isEditingTitle = false
    }
    
    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

#Preview {
    NavigationStack {
        MeetingRecordDetailView(
            record: .constant(
                MeetingRecord(
                    title: "产品规划会议",
                    originalText: "原始转录文本内容",
                    correctedText: "今天讨论了产品的下一步规划，包括新功能的开发和用户体验的优化。",
                    summary: "讨论了产品规划和用户体验优化，确定了下一步的开发重点。",
                    actionItems: ["完成新功能设计", "优化用户界面", "准备用户测试"],
                    duration: 1800
                )
            )
        )
    }
}

