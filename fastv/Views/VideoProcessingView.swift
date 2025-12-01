//
//  VideoProcessingView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoProcessingView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @State private var showLastVideoBanner = false
    @State private var seekToTime: TimeInterval?
    
    var body: some View {
        VStack(spacing: 0) {
            // 上次打开视频横幅提示
            if showLastVideoBanner, let lastURL = viewModel.getLastVideoURL() {
                LastVideoBannerView(
                    lastVideoURL: lastURL,
                    onOpen: {
                        viewModel.loadVideo(lastURL)
                        showLastVideoBanner = false
                    },
                    onDismiss: {
                        showLastVideoBanner = false
                    }
                )
            }
            
            // 主内容区域
            Group {
                if viewModel.appState.isEmpty {
                    DropZoneView(viewModel: viewModel)
                } else if viewModel.appState.isSingleVideo {
                    processingView
                } else {
                    // 多视频列表视图
                    if let listViewModel = viewModel.videoListViewModel {
                        VideoListView(viewModel: listViewModel)
                    } else {
                        ProgressView("加载中...")
                            .onAppear {
                                viewModel.initializeVideoList()
                            }
                    }
                }
            }
        }
        .navigationTitle("视频处理")
        .onAppear {
            // 检查是否有上次打开的文件，显示横幅提示
            if viewModel.getLastVideoURL() != nil {
                showLastVideoBanner = true
            }
        }
    }
    
    private func selectVideoFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .avi]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "选择视频文件"
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            if !urls.isEmpty {
                viewModel.loadVideos(urls)
                showLastVideoBanner = false
            }
        }
    }
    
    private var processingView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 视频预览
                if let videoURL = viewModel.videoURL {
                    VideoPreviewView(
                        videoURL: videoURL,
                        onVideoDropped: { urls in
                            viewModel.loadVideos(urls)
                        },
                        seekToTime: $seekToTime
                    )
                }
                
                // 视频信息
                if let videoInfo = viewModel.videoInfo {
                    VideoInfoCard(videoInfo: videoInfo)
                }
                
                // 操作栏
                HStack(spacing: 12) {
                    Button(action: selectVideoFiles) {
                        Label("切换文件", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button(action: {
                        Task {
                            await viewModel.startProcessing()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if viewModel.isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(viewModel.isProcessing ? "处理中..." : "开始处理")
                        }
                        .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isProcessing || !viewModel.hasAnyOptionSelected)
                    .keyboardShortcut(.return, modifiers: [])
                }
                
                // 处理选项
                Form {
                    Section {
                        ProcessingOptionsView(videoInfo: viewModel.videoInfo)
                    } header: {
                        Text("处理选项")
                    }
                    
                    Section {
                        HStack {
                            Label("保存位置", systemImage: "folder")
                            Spacer()
                            if let outputDirectory = viewModel.outputDirectory {
                                Text(outputDirectory.lastPathComponent)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("默认（视频文件同目录）")
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
                            
                            if viewModel.preferences.useCustomOutputDirectory {
                                Button(action: {
                                    viewModel.resetToDefaultOutputDirectory()
                                }) {
                                    Label("使用默认", systemImage: "arrow.counterclockwise")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    } header: {
                        Text("保存位置")
                    }
                }
                .formStyle(.grouped)
                
                // 处理进度
                if viewModel.isProcessing {
                    ProcessingProgressView(
                        progress: viewModel.progress,
                        status: viewModel.processingStatus
                    )
                }
                
                // 结果预览
                if viewModel.processingCompleted {
                    ResultCard(
                        firstFrameImage: viewModel.firstFrameImage,
                        lastFrameImage: viewModel.lastFrameImage,
                        audioURL: viewModel.audioURL,
                        transcriptURL: viewModel.transcriptURL,
                        outputDirectory: viewModel.outputDirectory
                    )
                    
                    // 画面变更检测结果
                    if !viewModel.sceneChangePoints.isEmpty, let videoInfo = viewModel.videoInfo {
                        VideoTimelineView(
                            duration: videoInfo.duration,
                            changePoints: viewModel.sceneChangePoints,
                            onSeekToTime: { time in
                                // 设置跳转时间，触发视频预览跳转
                                seekToTime = time
                            }
                        )
                    }
                    
                    // 操作按钮
                    HStack(spacing: 12) {
                        Button(action: {
                            viewModel.reset()
                        }) {
                            Label("处理新文件", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                        
                        if let outputDirectory = viewModel.outputDirectory {
                            Button(action: {
                                FileManager.default.revealInFinder(outputDirectory)
                            }) {
                                Label("打开保存位置", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

