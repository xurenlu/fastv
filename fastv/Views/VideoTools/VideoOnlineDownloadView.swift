//
//  VideoOnlineDownloadView.swift
//  fastv
//
//  Created by rocky on 2025/12/25.
//

import SwiftUI
import Combine

/// 在线视频下载视图
struct VideoOnlineDownloadView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @State private var urlInput: String = ""
    @State private var errorMessage: String?
    
    private var isDownloading: Bool {
        if case .fetchingInfo = viewModel.downloadState { return true }
        if case .downloading = viewModel.downloadState { return true }
        return false
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 标题和描述
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("在线视频下载")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("从各大视频平台下载视频到本地")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text("支持抖音、快手、B站、YouTube、微博、Twitter、Instagram、TikTok 等主流视频平台")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 60)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 20)
                
                // URL 输入区域
                VStack(alignment: .leading, spacing: 16) {
                    Text("视频链接")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        TextField("粘贴视频链接", text: $urlInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                downloadFromURL()
                            }
                            .disabled(isDownloading)
                        
                        Button(action: downloadFromURL) {
                            if case .fetchingInfo = viewModel.downloadState {
                                ProgressView()
                                    .controlSize(.small)
                            } else if case .downloading = viewModel.downloadState {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("下载", systemImage: "arrow.down.circle.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(urlInput.isEmpty || isDownloading)
                        .help("开始下载视频")
                    }
                    
                    // 支持的平台提示
                    VStack(alignment: .leading, spacing: 8) {
                        Label("支持的平台", systemImage: "checkmark.seal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading, spacing: 8) {
                            ForEach(["抖音", "快手", "B站", "YouTube", "微博", "Twitter", "Instagram", "TikTok"], id: \.self) { platform in
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.green)
                                    Text(platform)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                
                // 下载状态显示
                if case .fetchingInfo = viewModel.downloadState {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("正在获取视频信息...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                } else if case .downloading(let progress) = viewModel.downloadState {
                    VStack(spacing: 12) {
                        ProgressView(value: progress)
                            .frame(maxWidth: .infinity)
                        
                        Text("正在下载视频... \(Int(progress * 100))%")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                } else if case .completed(let url) = viewModel.downloadState {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.green)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("下载完成")
                                    .font(.headline)
                                
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                NSWorkspace.shared.selectFile(
                                    url.path,
                                    inFileViewerRootedAtPath: url.deletingLastPathComponent().path
                                )
                            }) {
                                Label("在 Finder 中显示", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Text("视频已成功下载到本地，可以继续使用其他工具进行处理")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // 错误信息
                if let errorMessage = errorMessage ?? viewModel.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("下载失败")
                                .font(.headline)
                        }
                        
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // 下载的视频预览（如果已加载）
                if let videoURL = viewModel.videoURL {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("已下载的视频")
                            .font(.headline)
                        
                        VideoPreviewView(
                            videoURL: videoURL,
                            onVideoDropped: { urls in
                                if let url = urls.first {
                                    viewModel.loadVideo(url)
                                }
                            },
                            seekToTime: .constant(nil)
                        )
                        
                        if let videoInfo = viewModel.videoInfo {
                            VideoInfoCard(videoInfo: videoInfo)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: 800)
        }
        .navigationTitle("在线视频下载")
        .onReceive(viewModel.$downloadState) { state in
            // 清除错误信息当状态改变时
            if case .failed = state {
                // 错误信息会通过 viewModel.errorMessage 显示
            } else {
                errorMessage = nil
            }
            
            // 下载完成后，清除URL输入
            if case .completed = state {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    urlInput = ""
                }
            }
        }
    }
    
    private func downloadFromURL() {
        guard !urlInput.isEmpty else { return }
        
        // 清除之前的错误信息
        errorMessage = nil
        viewModel.errorMessage = nil
        
        // 开始下载
        viewModel.downloadVideo(from: urlInput)
    }
}

#Preview {
    VideoOnlineDownloadView(viewModel: VideoProcessorViewModel())
}

