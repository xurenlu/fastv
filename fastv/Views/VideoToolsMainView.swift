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
    
    enum VideoTool: String, CaseIterable, Identifiable {
        case formatConversion = "格式转换"
        case compression = "压缩调整"
        case colorAdjustment = "颜色调整"
        case watermark = "水印Logo"
        case subtitle = "字幕处理"
        case transform = "裁剪旋转"
        case blur = "模糊马赛克"
        case logoTracking = "Logo跟踪"
        
        var id: String { rawValue }
        
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
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // 左侧工具列表
            List(selection: $selectedTool) {
                Section("视频处理工具") {
                    ForEach(VideoTool.allCases) { tool in
                        NavigationLink(value: tool) {
                            HStack(spacing: 12) {
                                Image(systemName: tool.icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tool.rawValue)
                                        .font(.headline)
                                    
                                    Text(tool.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("视频工具")
            .frame(minWidth: 250, idealWidth: 280)
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
        VStack(spacing: 24) {
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
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
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
            .padding()
            .frame(maxWidth: 600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func toolView(for tool: VideoTool) -> some View {
        if viewModel.videoURL == nil {
            VideoToolPlaceholderView(
                title: tool.rawValue,
                description: "请先选择视频文件",
                action: {
                    selectVideoFile()
                }
            )
        } else {
            switch tool {
            case .formatConversion:
                VideoFormatConversionView(viewModel: viewModel)
            case .compression:
                VideoCompressionView(viewModel: viewModel)
            case .colorAdjustment:
                VideoColorAdjustmentView(viewModel: viewModel)
            case .watermark:
                VideoWatermarkView(viewModel: viewModel)
            case .subtitle:
                VideoSubtitleView(viewModel: viewModel)
            case .transform:
                VideoTransformView(viewModel: viewModel)
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
        VStack(spacing: 20) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    VideoToolsMainView()
}
