//
//  DropZoneView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @State private var isTargeted = false
    @State private var urlInput: String = ""
    
    var body: some View {
        VStack(spacing: 24) {
            iconSection
            urlInputSection
            Divider()
                .padding(.horizontal, 40)
            buttonSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .background(backgroundView)
        .padding(32)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private var iconSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08))
                    .frame(width: 100, height: 100)
                
                Image(systemName: isTargeted ? "arrow.down.doc.fill" : "video.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                    .symbolEffect(.bounce, value: isTargeted)
            }
            
            VStack(spacing: 6) {
                Text(isTargeted ? "松开以添加视频" : "拖拽视频文件到这里")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text("支持 MP4、MOV、AVI、MKV、FLV 等格式")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var urlInputSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField("粘贴视频链接（抖音、快手、B站等）", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        downloadFromURL()
                    }
                
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
                .disabled(urlInput.isEmpty || isDownloading)
                .help("从链接下载视频")
            }
            .frame(maxWidth: 500)
            
            // 下载进度显示
            if case .downloading(let progress) = viewModel.downloadState {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .frame(maxWidth: 500)
                    Text("下载中... \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if case .fetchingInfo = viewModel.downloadState {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在获取视频信息...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text("支持抖音、快手、B站、微博、Twitter、Instagram、TikTok 等平台")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
    
    private var buttonSection: some View {
        VStack(spacing: 10) {
            Button(action: selectVideoFile) {
                Label("选择文件", systemImage: "folder")
                    .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: [.command])
            
            if let lastURL = viewModel.preferences.getLastVideoURL(),
               FileManager.default.fileExists(atPath: lastURL.path) {
                Button(action: {
                    viewModel.loadVideo(lastURL)
                }) {
                    Label("打开上次的文件", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
    }
    
    private var isDownloading: Bool {
        if case .fetchingInfo = viewModel.downloadState { return true }
        if case .downloading = viewModel.downloadState { return true }
        return false
    }
    
    private func downloadFromURL() {
        guard !urlInput.isEmpty else { return }
        viewModel.downloadVideo(from: urlInput)
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
            }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                urls.append(url)
            }
        }
        
        group.notify(queue: .main) {
            if !urls.isEmpty {
                viewModel.loadVideos(urls)
            }
        }
        
        return true
    }
    
    private func selectVideoFile() {
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
            }
        }
    }
}

#Preview {
    DropZoneView(viewModel: VideoProcessorViewModel())
}
