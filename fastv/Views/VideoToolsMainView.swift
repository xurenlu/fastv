//
//  VideoToolsMainView.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// 视频工具主界面 - 包含所有视频处理功能的入口
struct VideoToolsMainView: View {
    @StateObject private var viewModel = VideoProcessorViewModel()
    @State private var selectedTool: VideoTool?
    
    enum VideoToolCategory: String, CaseIterable, Identifiable {
        case editing = "视频编辑"
        case effects = "特效处理"
        case extraction = "内容提取"
        case analysis = "智能分析"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .editing: return "film"
            case .effects: return "wand.and.stars"
            case .extraction: return "arrow.down.doc"
            case .analysis: return "brain.head.profile"
            }
        }
    }
    
    enum VideoTool: String, CaseIterable, Identifiable {
        // 视频编辑
        case formatConversion = "格式转换"
        case compression = "压缩调整"
        case transform = "裁剪旋转"
        case colorAdjustment = "颜色调整"
        
        // 特效处理
        case watermark = "水印Logo"
        case subtitle = "字幕处理"
        case blur = "模糊马赛克"
        case logoTracking = "Logo跟踪"
        case cartoon = "视频卡通化"
        
        // 内容提取
        case onlineVideoDownload = "在线视频下载"
        case extractFrames = "提取首尾帧"
        case extractAudio = "提取音频"
        case audioToText = "音频转文字"
        
        // 智能分析
        case sceneDetection = "场景变更检测"
        case aiSceneAnalysis = "AI场景分析"
        
        var id: String { rawValue }
        
        var category: VideoToolCategory {
            switch self {
            case .formatConversion, .compression, .transform, .colorAdjustment:
                return .editing
            case .watermark, .subtitle, .blur, .logoTracking, .cartoon:
                return .effects
            case .onlineVideoDownload, .extractFrames, .extractAudio, .audioToText:
                return .extraction
            case .sceneDetection, .aiSceneAnalysis:
                return .analysis
            }
        }
        
        var icon: String {
            switch self {
            case .formatConversion: return "arrow.triangle.2.circlepath"
            case .compression: return "arrow.down.circle"
            case .colorAdjustment: return "paintpalette.fill"
            case .watermark: return "text.badge.plus"
            case .subtitle: return "text.bubble"
            case .transform: return "crop.rotate"
            case .blur: return "eye.slash.fill"
            case .logoTracking: return "target"
            case .cartoon: return "wand.and.stars"
            case .onlineVideoDownload: return "arrow.down.circle.fill"
            case .extractFrames: return "photo.on.rectangle"
            case .extractAudio: return "waveform"
            case .audioToText: return "doc.text"
            case .sceneDetection: return "scissors"
            case .aiSceneAnalysis: return "sparkles"
            }
        }
        
        var description: String {
            switch self {
            case .formatConversion: return "MP4/MOV/AVI/MKV/WebM 格式互转"
            case .compression: return "分辨率、帧率、比特率调整"
            case .colorAdjustment: return "亮度、对比度、饱和度、色温"
            case .watermark: return "添加图片或文字水印"
            case .subtitle: return "烧录 SRT/ASS 字幕"
            case .transform: return "裁剪、缩放、旋转、翻转"
            case .blur: return "马赛克、高斯模糊、渐变抹除"
            case .logoTracking: return "智能跟踪并替换 Logo"
            case .cartoon: return "AI 视频风格迁移、动漫化"
            case .onlineVideoDownload: return "从抖音、YouTube等平台下载视频"
            case .extractFrames: return "提取视频第一帧和最后一帧"
            case .extractAudio: return "提取视频中的音频轨道"
            case .audioToText: return "将视频音频转写为文字稿"
            case .sceneDetection: return "检测视频中的场景变更点"
            case .aiSceneAnalysis: return "AI 智能分析视频场景内容"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // 左侧工具列表 - 按类别分组
            List(selection: $selectedTool) {
                ForEach(VideoToolCategory.allCases) { category in
                    Section {
                        ForEach(VideoTool.allCases.filter { $0.category == category }) { tool in
                            NavigationLink(value: tool) {
                                HStack(spacing: 10) {
                                    Image(systemName: tool.icon)
                                        .font(.system(size: 16))
                                        .foregroundStyle(.blue)
                                        .frame(width: 20)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tool.rawValue)
                                            .font(.system(size: 13, weight: .medium))
                                        
                                        Text(tool.description)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: category.icon)
                                .font(.system(size: 12))
                            Text(category.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("视频工具")
            .frame(minWidth: 160, idealWidth: 180, maxWidth: 200)
        } detail: {
            // 右侧内容区域
            Group {
                if let tool = selectedTool {
                    toolView(for: tool)
                } else {
                    welcomeView
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
    
    private var welcomeView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "video.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                
                Text("视频处理工具")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("选择左侧工具开始处理视频")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("支持的功能：")
                        .font(.headline)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], alignment: .leading, spacing: 12) {
                        ForEach(VideoTool.allCases) { tool in
                            HStack(spacing: 8) {
                                Image(systemName: tool.icon)
                                    .foregroundStyle(.blue)
                                Text(tool.rawValue)
                                    .font(.subheadline)
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                }
                .frame(maxWidth: 600, alignment: .leading)
            }
            .padding(.leading, 60)
            .padding(.top, 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    @ViewBuilder
    private func toolView(for tool: VideoTool) -> some View {
        // 在线视频下载工具不需要先选择视频文件
        if tool == .onlineVideoDownload {
            VideoOnlineDownloadView(viewModel: viewModel)
        } else if viewModel.videoURL == nil {
            VideoToolPlaceholderView(
                title: tool.rawValue,
                description: "请先选择视频文件",
                action: {
                    selectVideoFile()
                }
            )
        } else {
            switch tool {
            // 视频编辑
            case .formatConversion:
                VideoFormatConversionView(viewModel: viewModel)
            case .compression:
                VideoCompressionView(viewModel: viewModel)
            case .transform:
                VideoTransformView(viewModel: viewModel)
            case .colorAdjustment:
                VideoColorAdjustmentView(viewModel: viewModel)
            
            // 特效处理
            case .watermark:
                VideoWatermarkView(viewModel: viewModel)
            case .subtitle:
                VideoSubtitleView(viewModel: viewModel)
            case .blur:
                VideoBlurView(viewModel: viewModel)
            case .logoTracking:
                if let videoURL = viewModel.videoURL {
                    LogoAnnotationView(videoURL: videoURL)
                } else {
                    VideoToolPlaceholderView(
                        title: "Logo 跟踪",
                        description: "请先选择视频文件",
                        action: {
                            selectVideoFile()
                        }
                    )
                }
            case .cartoon:
                VideoCartoonView(viewModel: viewModel)
            
            // 内容提取
            case .onlineVideoDownload:
                VideoToolPlaceholderView(
                    title: "在线视频下载",
                    description: "功能开发中",
                    action: {
                        selectVideoFile()
                    }
                )
            case .extractFrames:
                VideoExtractFramesView(viewModel: viewModel)
            case .extractAudio:
                VideoExtractAudioView(viewModel: viewModel)
            case .audioToText:
                VideoAudioToTextView(viewModel: viewModel)
            
            // 智能分析
            case .sceneDetection:
                VideoSceneDetectionView(viewModel: viewModel)
            case .aiSceneAnalysis:
                VideoSceneAnalysisView()
            }
        }
    }
    
    private func selectVideoFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "选择视频文件"
        
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.loadVideo(url)
        }
    }
}

/// 视频工具占位视图（需要先选择视频）
struct VideoToolPlaceholderView: View {
    let title: String
    let description: String
    let action: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "video.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                
                Button(action: action) {
                    Label("选择视频文件", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.leading, 60)
            .padding(.top, 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    VideoToolsMainView()
}
