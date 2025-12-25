//
//  LogoAnnotationViewModel.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import Foundation
import SwiftUI
import AppKit
import AVFoundation
import Combine

@MainActor
class LogoAnnotationViewModel: ObservableObject {
    @Published var videoURL: URL?
    @Published var currentFrameNumber: Int = 0
    @Published var currentTimestamp: TimeInterval = 0
    @Published var currentFrameImage: NSImage?
    @Published var annotations: [LogoAnnotation] = []
    @Published var selectedAnnotation: LogoAnnotation?
    @Published var isPlaying = false
    @Published var isSelectingRegion = false
    @Published var selectionRect: CGRect = .zero
    @Published var selectionStartPoint: CGPoint = .zero
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var asset: AVURLAsset?
    private var videoTrack: AVAssetTrack?
    private var frameExtractor: AVAssetImageGenerator?
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var hasSecurityAccess = false
    private var securityScopedURL: URL?
    
    var totalFrames: Int {
        guard let asset = asset,
              let videoTrack = videoTrack else { return 0 }
        
        let duration = asset.duration.seconds
        let frameRate = videoTrack.nominalFrameRate
        return Int(duration * Double(frameRate))
    }
    
    var duration: TimeInterval {
        return asset?.duration.seconds ?? 0
    }
    
    var frameRate: Double {
        return Double(videoTrack?.nominalFrameRate ?? 30.0)
    }
    
    init(videoURL: URL? = nil) {
        self.videoURL = videoURL
        if let url = videoURL {
            loadVideo(url)
        }
    }
    
    func loadVideo(_ url: URL) {
        videoURL = url
        isLoading = true
        errorMessage = nil
        currentFrameImage = nil
        
        // 标准化 URL
        let normalizedURL = normalizeFileURL(url)
        
        // 获取安全作用域访问权限
        hasSecurityAccess = normalizedURL.startAccessingSecurityScopedResource()
        securityScopedURL = normalizedURL
        
        // 使用 AVURLAsset
        asset = AVURLAsset(url: normalizedURL)
        
        Task {
            await setupVideo()
        }
    }
    
    /// 标准化文件 URL，正确处理特殊字符（中文、冒号、加号等）
    private func normalizeFileURL(_ url: URL) -> URL {
        // 保留安全作用域信息，避免用 fileURLWithPath 重新构造
        guard url.isFileURL else { return url }
        if let resolved = (url as NSURL).resolvingSymlinksInPath {
            return resolved
        }
        return url
    }
    
    /// 带超时的异步操作
    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw VideoLoadError.timeout
            }
            
            guard let result = try await group.next() else {
                throw VideoLoadError.timeout
            }
            
            group.cancelAll()
            return result
        }
    }
    
    private func setupVideo() async {
        guard let asset = asset else {
            await MainActor.run {
                isLoading = false
                errorMessage = "视频资源无效"
            }
            return
        }
        
        do {
            // 使用超时机制加载视频轨道（30秒超时）
            let tracks = try await withTimeout(seconds: 30) {
                try await asset.loadTracks(withMediaType: .video)
            }
            
            guard let firstTrack = tracks.first else {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "视频中没有视频轨道"
                }
                return
            }
            
            videoTrack = firstTrack
            
            frameExtractor = AVAssetImageGenerator(asset: asset)
            frameExtractor?.appliesPreferredTrackTransform = true
            frameExtractor?.requestedTimeToleranceBefore = .zero
            frameExtractor?.requestedTimeToleranceAfter = .zero
            
            // 设置播放器
            playerItem = AVPlayerItem(asset: asset)
            player = AVPlayer(playerItem: playerItem)
            
            // 加载第一帧（10秒超时）
            try await withTimeout(seconds: 10) {
                await self.loadFrame(at: 0)
            }
            
            // 加载成功
            await MainActor.run {
                isLoading = false
            }
        } catch let error as VideoLoadError {
            await MainActor.run {
                isLoading = false
                errorMessage = error.errorDescription ?? "加载视频失败"
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = "加载视频失败: \(error.localizedDescription)"
            }
        }
    }
    
    func loadFrame(at frameNumber: Int) async {
        guard let videoTrack = videoTrack,
              let frameExtractor = frameExtractor else { return }
        
        let frameRate = videoTrack.nominalFrameRate
        let timestamp = Double(frameNumber) / Double(frameRate)
        
        await loadFrame(at: timestamp)
    }
    
    func loadFrame(at timestamp: TimeInterval) async {
        guard let frameExtractor = frameExtractor else {
            await MainActor.run {
                errorMessage = "帧提取器未初始化"
            }
            return
        }
        
        let time = CMTime(seconds: timestamp, preferredTimescale: 600)
        
        do {
            // 使用超时机制加载帧（5秒超时）
            let cgImage = try await withTimeout(seconds: 5) {
                try await frameExtractor.image(at: time).image
            }
            
            currentFrameImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            currentTimestamp = timestamp
            
            if let videoTrack = videoTrack {
                let frameRate = videoTrack.nominalFrameRate
                currentFrameNumber = Int(timestamp * Double(frameRate))
            }
            
            // 清除错误信息（如果之前有的话）
            if errorMessage != nil {
                errorMessage = nil
            }
        } catch let error as VideoLoadError {
            await MainActor.run {
                errorMessage = error.errorDescription ?? "加载帧失败"
            }
        } catch {
            await MainActor.run {
                errorMessage = "加载帧失败: \(error.localizedDescription)"
            }
        }
    }
    
    func nextFrame() {
        guard currentFrameNumber < totalFrames - 1 else { return }
        Task {
            await loadFrame(at: currentFrameNumber + 1)
        }
    }
    
    func previousFrame() {
        guard currentFrameNumber > 0 else { return }
        Task {
            await loadFrame(at: currentFrameNumber - 1)
        }
    }
    
    func startSelection(at point: CGPoint, in viewSize: CGSize) {
        isSelectingRegion = true
        selectionStartPoint = point
        selectionRect = CGRect(origin: point, size: .zero)
    }
    
    func updateSelection(to point: CGPoint, in viewSize: CGSize) {
        guard isSelectingRegion else { return }
        
        let minX = min(selectionStartPoint.x, point.x)
        let maxX = max(selectionStartPoint.x, point.x)
        let minY = min(selectionStartPoint.y, point.y)
        let maxY = max(selectionStartPoint.y, point.y)
        
        selectionRect = CGRect(
            x: max(0, minX),
            y: max(0, minY),
            width: min(viewSize.width, maxX) - max(0, minX),
            height: min(viewSize.height, maxY) - max(0, minY)
        )
    }
    
    func endSelection() {
        isSelectingRegion = false
    }
    
    func addAnnotation(boundingBox: CGRect) {
        guard let currentImage = currentFrameImage else { return }
        
        let annotation = LogoAnnotation(
            frameNumber: currentFrameNumber,
            timestamp: currentTimestamp,
            boundingBox: boundingBox,
            image: currentImage
        )
        
        annotations.append(annotation)
        annotations.sort { $0.frameNumber < $1.frameNumber }
    }
    
    func deleteAnnotation(_ annotation: LogoAnnotation) {
        annotations.removeAll { $0.id == annotation.id }
        if selectedAnnotation?.id == annotation.id {
            selectedAnnotation = nil
        }
    }
    
    func updateAnnotation(_ annotation: LogoAnnotation, boundingBox: CGRect) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }),
              let currentImage = currentFrameImage else { return }
        
        let updated = LogoAnnotation(
            id: annotation.id,
            frameNumber: annotation.frameNumber,
            timestamp: annotation.timestamp,
            boundingBox: boundingBox,
            image: currentImage
        )
        
        annotations[index] = updated
        if selectedAnnotation?.id == annotation.id {
            selectedAnnotation = updated
        }
    }
    
    func selectAnnotation(_ annotation: LogoAnnotation) {
        selectedAnnotation = annotation
        Task {
            await loadFrame(at: annotation.frameNumber)
        }
    }
    
    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        
        // 释放安全作用域访问
        if hasSecurityAccess, let url = securityScopedURL {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

// MARK: - 错误类型

enum VideoLoadError: LocalizedError {
    case timeout
    case noVideoTrack
    case invalidResource
    
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "视频加载超时，请检查文件是否损坏或过大"
        case .noVideoTrack:
            return "视频中没有视频轨道"
        case .invalidResource:
            return "视频资源无效"
        }
    }
}
