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
    @Binding var seekToTime: TimeInterval?
    @State private var player: AVPlayer?
    @State private var previewImage: NSImage?
    @State private var isPlaying = false
    @State private var isLoadingPreview = true
    @State private var isTargeted = false
    @State private var showPlayer = false
    
    init(videoURL: URL, onVideoDropped: (([URL]) -> Void)? = nil, seekToTime: Binding<TimeInterval?> = .constant(nil)) {
        self.videoURL = videoURL
        self.onVideoDropped = onVideoDropped
        self._seekToTime = seekToTime
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if showPlayer, let player = player {
                    // 显示视频播放器
                    AVPlayerViewWrapper(player: player)
                        .frame(maxHeight: 400)
                        .background(Color.black)
                } else if let previewImage = previewImage {
                    // 显示预览图片
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
                
                // 播放按钮覆盖层（仅在显示预览图时显示）
                if !showPlayer && !isLoadingPreview {
                    Button(action: togglePlayback) {
                        ZStack {
                            Circle()
                                .fill(.black.opacity(0.3))
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .buttonStyle(.plain)
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
                showPlayer = false
                player?.pause()
                player = nil
                seekToTime = nil  // 清除跳转请求
                loadPreview()
            }
        }
        .onChange(of: seekToTime) { oldValue, newValue in
            // 当需要跳转时间时
            if let time = newValue {
                performSeek(time)
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
        // 点击预览图时，初始化播放器并开始播放
        if player == nil {
            initializePlayer()
        }
        showPlayer = true
        
        if let player = player {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
        }
    }
    
    private func initializePlayer() {
        let newPlayer = AVPlayer(url: videoURL)
        player = newPlayer
        
        // 监听播放状态
        newPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak newPlayer] time in
            if let player = newPlayer {
                self.isPlaying = player.rate > 0
            }
        }
    }
    
    private func performSeek(_ time: TimeInterval) {
        // 如果播放器未初始化，先初始化
        if player == nil {
            initializePlayer()
            showPlayer = true
        }
        
        guard let player = player else {
            // 如果播放器还未准备好，延迟跳转
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                performSeek(time)
            }
            return
        }
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime) { [weak player] completed in
            if completed {
                // 跳转成功后，如果播放器未播放，则开始播放
                if player?.rate == 0 {
                    player?.play()
                    isPlaying = true
                }
            }
        }
        
        // 清除跳转请求（通过设置 binding 为 nil）
        DispatchQueue.main.async {
            seekToTime = nil
        }
    }
}

// 使用 NSViewRepresentable 包装 AVPlayerView
struct AVPlayerViewWrapper: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = false
        return view
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

#Preview {
    VideoPreviewView(
        videoURL: URL(fileURLWithPath: "/path/to/video.mp4"),
        seekToTime: .constant(nil)
    )
    .frame(width: 600, height: 400)
}

