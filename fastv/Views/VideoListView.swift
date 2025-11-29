//
//  VideoListView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoListView: View {
    @ObservedObject var viewModel: VideoListViewModel
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Button(action: addMoreVideos) {
                    Label("添加文件", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isProcessing)
                
                Button(action: {
                    viewModel.clear()
                }) {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.videoItems.isEmpty || viewModel.isProcessing)
                
                Spacer()
                
                Text("已选择 \(viewModel.selectedVideos.count) / \(viewModel.videoItems.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Button(action: { showSettings = true }) {
                    Label("设置", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background {
                Rectangle()
                    .fill(.regularMaterial)
            }
            
            Divider()
            
            // 视频列表
            if viewModel.videoItems.isEmpty {
                ContentUnavailableView(
                    "没有视频",
                    systemImage: "video.slash",
                    description: Text("拖拽视频文件到这里或点击\"添加文件\"按钮")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.videoItems) { item in
                            VideoItemRow(item: item, viewModel: viewModel)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .padding()
                }
            }
            
            Divider()
            
            // 底部操作栏
            VStack(spacing: 12) {
                // 处理选项
                Form {
                    Section {
                        ProcessingOptionsView(provider: viewModel)
                    } header: {
                        Text("处理选项")
                    }
                    
                    Section {
                        HStack {
                            Label("保存位置", systemImage: "folder")
                            Spacer()
                            if let outputDirectory = viewModel.customOutputDirectory ?? viewModel.preferences.getCustomOutputDirectory() {
                                Text(outputDirectory.lastPathComponent)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("默认（各视频文件同目录）")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                viewModel.selectOutputDirectory()
                            }) {
                                Label("选择位置", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isProcessing)
                            
                            if viewModel.preferences.useCustomOutputDirectory {
                                Button(action: {
                                    viewModel.resetToDefaultOutputDirectory()
                                }) {
                                    Label("使用默认", systemImage: "arrow.counterclockwise")
                                }
                                .buttonStyle(.borderless)
                                .disabled(viewModel.isProcessing)
                            }
                        }
                    } header: {
                        Text("保存位置")
                    }
                }
                .formStyle(.grouped)
                .frame(height: nil)
                
                // 批量处理按钮和进度
                VStack(spacing: 8) {
                    if viewModel.isProcessing {
                        VStack(spacing: 4) {
                            ProgressView(value: viewModel.overallProgress) {
                                Text("总体进度")
                                    .font(.subheadline)
                            }
                            Text("\(Int(viewModel.overallProgress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    
                    Button(action: {
                        Task {
                            await viewModel.startBatchProcessing()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if viewModel.isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(viewModel.isProcessing ? "处理中..." : "批量处理")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isProcessing || viewModel.selectedVideos.isEmpty || !viewModel.hasAnyOptionSelected)
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
            .padding()
            .background {
                Rectangle()
                    .fill(.regularMaterial)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .frame(minWidth: 800, idealWidth: 900, maxWidth: 1000, minHeight: 600, idealHeight: 700, maxHeight: 800)
        }
    }
    
    private func addMoreVideos() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .avi]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "添加视频文件"
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            if !urls.isEmpty {
                viewModel.addVideos(urls)
            }
        }
    }
}

struct VideoItemRow: View {
    @ObservedObject var item: VideoItem
    @ObservedObject var viewModel: VideoListViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // 选择框
            Toggle("", isOn: Binding(
                get: { item.isSelected },
                set: { _ in
                    withAnimation {
                        viewModel.toggleSelection(for: item)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .disabled(viewModel.isProcessing)
            
            // 预览图
            Group {
                if let previewImage = item.previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 80, height: 60)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                }
            }
            
            // 视频信息
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.body)
                    .lineLimit(1)
                
                if let videoInfo = item.videoInfo {
                    Text("\(videoInfo.durationString) · \(videoInfo.resolutionString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("加载中...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // 处理状态
                if case .processing = item.processingState {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(item.processingStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(item.progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } else if case .completed = item.processingState {
                    Label("已完成", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if case .failed = item.processingState {
                    Label("失败", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            Spacer()
            
            // 操作按钮
            HStack(spacing: 8) {
                if case .completed = item.processingState, let outputDirectory = item.outputDirectory {
                    Button(action: {
                        FileManager.default.revealInFinder(outputDirectory)
                    }) {
                        Label("打开", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("打开保存位置")
                }
                
                Button(action: {
                    withAnimation {
                        viewModel.removeVideo(item)
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isProcessing)
                .help("移除")
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        }
        .opacity(item.isSelected ? 1.0 : 0.6)
    }
}

#Preview {
    VideoListView(viewModel: VideoListViewModel())
        .frame(width: 800, height: 600)
}

