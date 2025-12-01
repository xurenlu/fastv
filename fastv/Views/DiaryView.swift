//
//  DiaryView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI

struct DiaryView: View {
    @StateObject private var viewModel = DiaryViewModel()
    @ObservedObject private var store = DiaryStore.shared
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 输入区域
            inputSection
            
            Divider()
            
            // 日记列表
            if store.entries.isEmpty {
                emptyStateView
            } else {
                diaryListView
            }
        }
        .navigationTitle("日记")
    }
    
    // MARK: - Input Section
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 提示信息
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                
                Text("可以直接输入文字，或使用语音输入")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.1))
            }
            
            // 输入框和按钮
            HStack(spacing: 12) {
                TextField("输入日记内容或语音说话...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...8)
                    .frame(minHeight: 60)
                    .focused($isInputFocused)
                    .onSubmit {
                        Task {
                            await viewModel.processWithAI()
                        }
                    }
                
                // 语音录制按钮
                Button(action: {
                    if viewModel.isRecording {
                        Task {
                            await viewModel.stopVoiceRecording()
                        }
                    } else {
                        viewModel.startVoiceRecording()
                    }
                }) {
                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.isRecording ? .red : .blue)
                }
                .buttonStyle(.plain)
                .help(viewModel.isRecording ? "停止录音" : "开始录音")
                
                // AI 分析按钮
                Button(action: {
                    Task {
                        await viewModel.processWithAI()
                    }
                }) {
                    if viewModel.isProcessingAI {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isProcessingAI || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("AI 分析")
            }
            
            // 消息提示
            if let errorMessage = viewModel.aiErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.red.opacity(0.1))
                }
            }
            
            if let successMessage = viewModel.aiSuccessMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(successMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.green.opacity(0.1))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label {
                Text("暂无日记")
                    .font(.system(size: 20, weight: .semibold))
            } icon: {
                Image(systemName: "book.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        } description: {
            VStack(spacing: 8) {
                Text("可以通过文字或语音添加日记")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Diary List
    
    private var diaryListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.entries) { entry in
                    DiaryRow(entry: entry, viewModel: viewModel)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Diary Row

struct DiaryRow: View {
    let entry: DiaryEntry
    @ObservedObject var viewModel: DiaryViewModel
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题和日期
            HStack {
                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(formatDate(entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // 内容
            Text(entry.content)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            
            // 心情和摘要
            HStack(spacing: 12) {
                if let mood = entry.mood {
                    Label(mood.displayName, systemImage: mood.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let summary = entry.aiSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            // AI 情绪分析
            if let moodAnalysis = entry.aiMoodAnalysis {
                Text(moodAnalysis)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.blue.opacity(0.1))
                    }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
                .overlay {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    }
                }
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: {
                    viewModel.deleteEntry(entry)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    DiaryView()
}

