//
//  VideoPreviewView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import AVKit
import AppKit

struct VideoPreviewView: View {
    let videoURL: URL
    var onVideoDropped: (([URL]) -> Void)? = nil
    @State private var player: AVPlayer?
    @State private var previewImage: NSImage?
    @State private var isPlaying = false
    @State private var isLoadingPreview = true
    @State private var isTargeted = false
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // 预览图片或播放器
                if let previewImage = previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 400)
                        .background(Color.black)
                } else if isLoadingPreview {
                    ProgressView()
                        .frame(maxHeight: 400)
                } else {
                    Color.black
                        .frame(maxHeight: 400)
                }
                
                // 播放按钮覆盖层
                if !isLoadingPreview {
                    Button(action: togglePlayback) {
                        ZStack {
                            Circle()
                                .fill(.black.opacity(0.3))
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .buttonStyle(.plain)
                    .opacity(isPlaying ? 0 : 1)
                    .animation(.easeInOut, value: isPlaying)
                }
            }
            .frame(maxHeight: 400)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
            }
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.05))
            }
        }
        .onAppear {
            loadPreview()
        }
        .onChange(of: videoURL) { oldValue, newValue in
            // 当视频 URL 改变时，重新加载预览
            if oldValue != newValue {
                previewImage = nil
                isLoadingPreview = true
                player?.pause()
                player = nil
                loadPreview()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.1))
                    }
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let onVideoDropped = onVideoDropped else { return false }
        
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
                onVideoDropped(urls)
            }
        }
        
        return true
    }
    
    private func loadPreview() {
        Task {
            // 提取第一帧作为预览
            do {
                let image = try await FrameExtractor.extractFirstFrame(from: videoURL)
                await MainActor.run {
                    previewImage = image
                    isLoadingPreview = false
                }
            } catch {
                await MainActor.run {
                    isLoadingPreview = false
                }
            }
        }
    }
    
    private func togglePlayback() {
        // 点击预览图时，使用系统默认播放器打开视频
        NSWorkspace.shared.open(videoURL)
    }
}

// 使用 NSViewRepresentable 包装 AVPlayerView
struct AVPlayerViewWrapper: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = false
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

#Preview {
    VideoPreviewView(videoURL: URL(fileURLWithPath: "/path/to/video.mp4"))
        .frame(width: 600, height: 400)
}

