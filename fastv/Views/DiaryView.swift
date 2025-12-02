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
            
            // 心情筛选
            MoodFilterView(viewModel: viewModel)
            
            Divider()
            
            // 视图模式切换工具栏
            viewModeToolbar
            
            Divider()
            
            // 内容视图
            if store.entries.isEmpty && viewModel.viewMode == .list && viewModel.selectedMood == nil && !viewModel.showNormalOnly {
                emptyStateView
            } else {
                contentView
            }
        }
        .navigationTitle("日记")
        .sheet(item: $viewModel.editingEntry) { entry in
            EditDiaryEntryView(entry: entry, viewModel: viewModel)
        }
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        switch viewModel.viewMode {
        case .list:
            diaryListView
        case .calendar:
            DiaryCalendarView(viewModel: viewModel)
        }
    }
    
    // MARK: - View Mode Toolbar
    
    private var viewModeToolbar: some View {
        HStack(spacing: 12) {
            // 模式切换
            Picker("", selection: $viewModel.viewMode) {
                ForEach(DiaryViewMode.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.regularMaterial)
        }
    }
    
    // MARK: - Input Section
    
    private var inputSection: some View {
        VStack(spacing: 16) {
            // 输入框和按钮 - 重新设计
            HStack(spacing: 16) {
                // 输入框区域
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        // 输入框
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(
                                            isInputFocused ? Color.accentColor.opacity(0.5) : Color.clear,
                                            lineWidth: 2
                                        )
                                }
                            
                            TextField("记录今天的心情和想法...", text: $viewModel.inputText, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 15))
                                .padding(12)
                                .focused($isInputFocused)
                                .onSubmit {
                                    Task {
                                        await viewModel.processWithAI()
                                    }
                                }
                        }
                        .frame(minHeight: 50, maxHeight: 120)
                        
                        // 操作按钮组
                        VStack(spacing: 12) {
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
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: viewModel.isRecording ? [.red, .red.opacity(0.8)] : [.blue, .blue.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 50, height: 50)
                                        .shadow(color: (viewModel.isRecording ? Color.red : Color.blue).opacity(0.3), radius: viewModel.isRecording ? 8 : 4, y: 4)
                                    
                                    Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(viewModel.isRecording ? "停止录音" : "开始录音")
                            
                            // AI 分析按钮
                            Button(action: {
                                Task {
                                    await viewModel.processWithAI()
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [.purple, .pink],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 50, height: 50)
                                        .shadow(color: Color.purple.opacity(0.3), radius: 4, y: 4)
                                    
                                    if viewModel.isProcessingAI {
                                        ProgressView()
                                            .tint(.white)
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isProcessingAI || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help("AI 分析")
                        }
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
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.green.opacity(0.1))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
        }
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
            LazyVStack(spacing: 16) {
                // 筛选提示
                if viewModel.selectedMood != nil || viewModel.showNormalOnly || !viewModel.searchText.isEmpty {
                    HStack {
                        HStack(spacing: 8) {
                            if viewModel.showNormalOnly {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(.secondary)
                            } else if let mood = viewModel.selectedMood {
                                Image(systemName: mood.icon)
                                    .foregroundStyle(mood.color)
                            }
                            if !viewModel.searchText.isEmpty {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                            }
                            Text("筛选中")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation {
                                viewModel.clearFilters()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text("清除")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
                
                // 日记列表
                if viewModel.entries.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("没有找到日记")
                                .font(.system(size: 18, weight: .semibold))
                        } icon: {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                    } description: {
                        Text("尝试调整筛选条件")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    ForEach(viewModel.entries) { entry in
                        DiaryRow(entry: entry, viewModel: viewModel)
                            .padding(.horizontal, 24)
                    }
                }
            }
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Diary Row

struct DiaryRow: View {
    let entry: DiaryEntry
    @ObservedObject var viewModel: DiaryViewModel
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部：心情标签和日期
            HStack(spacing: 12) {
                if let mood = entry.mood {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: mood.gradientColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 24, height: 24)
                            
                            Image(systemName: mood.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        
                        Text(mood.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(mood.color)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(mood.color.opacity(0.1))
                    }
                }
                
                Spacer()
                
                Text(formatDate(entry.date))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // 标题
            Text(entry.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            
            // 内容
            Text(entry.content)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            
            // 底部信息
            HStack(spacing: 12) {
                if let summary = entry.aiSummary {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.blue.opacity(0.1))
                    }
                }
                
                if let moodAnalysis = entry.aiMoodAnalysis {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 10))
                            .foregroundStyle(.purple)
                        Text(moodAnalysis)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.purple.opacity(0.1))
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: isHovered ? 12 : 8, y: isHovered ? 6 : 4)
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: {
                    viewModel.deleteEntry(entry)
                }) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background {
                            Circle()
                                .fill(Color.red)
                        }
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            viewModel.showEditEntry(entry)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return "今天 " + formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return "昨天 " + formatter.string(from: date)
        } else {
            formatter.dateFormat = "M月d日 HH:mm"
            return formatter.string(from: date)
        }
    }
}

#Preview {
    DiaryView()
}

