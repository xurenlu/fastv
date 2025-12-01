//
//  ExpenseView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI

struct ExpenseView: View {
    @StateObject private var viewModel = ExpenseViewModel()
    @ObservedObject private var store = ExpenseStore.shared
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 输入区域
            inputSection
            
            Divider()
            
            // 视图模式切换工具栏
            viewModeToolbar
            
            Divider()
            
            // 内容视图
            if store.items.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
        .navigationTitle("记账")
        .sheet(item: $viewModel.editingItem) { item in
            EditExpenseItemView(item: item, viewModel: viewModel)
        }
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        switch viewModel.viewMode {
        case .list:
            ExpenseListView(viewModel: viewModel)
        case .chart:
            ExpenseChartView(viewModel: viewModel)
        case .calendar:
            ExpenseCalendarView(viewModel: viewModel)
        }
    }
    
    // MARK: - View Mode Toolbar
    
    private var viewModeToolbar: some View {
        HStack(spacing: 12) {
            // 模式切换
            Picker("", selection: $viewModel.viewMode) {
                ForEach(ExpenseViewMode.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            
            Spacer()
            
            // 类型筛选
            Picker("类型", selection: Binding(
                get: { viewModel.selectedType },
                set: { viewModel.selectedType = $0 }
            )) {
                Text("全部").tag(nil as ExpenseType?)
                ForEach(ExpenseType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type as ExpenseType?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
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
        VStack(alignment: .leading, spacing: 12) {
            // 提示信息
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                
                Text("选择图片后，请输入文字说明或使用语音输入，然后点击分析按钮。分析时会同时考虑图片内容和您的文字说明。")
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
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    TextField("输入记账内容或语音说话...", text: $viewModel.inputText, axis: .vertical)
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
                    
                    // 图片选择按钮
                    Button(action: {
                        viewModel.selectReceiptImage()
                    }) {
                        Image(systemName: "photo.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isProcessingAI)
                    .help("选择票据图片（可多选）")
                    
                    // AI 解析按钮
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
                    .disabled(viewModel.isProcessingAI || (viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.selectedImages.isEmpty))
                    .help("AI 分析")
                }
                
                // 选中的图片预览
                if !viewModel.selectedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.selectedImages, id: \.id) { imageItem in
                                ImagePreview(imageData: imageItem.data, onDelete: {
                                    viewModel.removeSelectedImage(id: imageItem.id)
                                })
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(height: 100)
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
                Text("暂无记账")
                    .font(.system(size: 20, weight: .semibold))
            } icon: {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        } description: {
            VStack(spacing: 8) {
                Text("可以通过文字、语音或上传票据图片来记账")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Image Preview

struct ImagePreview: View {
    let imageData: Data
    let onDelete: () -> Void
    @State private var nsImage: NSImage?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let nsImage = nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    }
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .overlay {
                        ProgressView()
                    }
            }
            
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white)
                    .background {
                        Circle()
                            .fill(Color.black.opacity(0.5))
                    }
            }
            .buttonStyle(.plain)
            .padding(4)
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        Task {
            if let image = NSImage(data: imageData) {
                await MainActor.run {
                    self.nsImage = image
                }
            }
        }
    }
}

#Preview {
    ExpenseView()
}

