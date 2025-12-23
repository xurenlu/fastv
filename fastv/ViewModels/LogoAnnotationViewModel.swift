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
    
    private var asset: AVAsset?
    private var videoTrack: AVAssetTrack?
    private var frameExtractor: AVAssetImageGenerator?
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    
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
        asset = AVAsset(url: url)
        
        Task {
            await setupVideo()
        }
    }
    
    private func setupVideo() async {
        guard let asset = asset else { return }
        
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            videoTrack = tracks.first
            
            if let videoTrack = videoTrack {
                frameExtractor = AVAssetImageGenerator(asset: asset)
                frameExtractor?.appliesPreferredTrackTransform = true
                frameExtractor?.requestedTimeToleranceBefore = .zero
                frameExtractor?.requestedTimeToleranceAfter = .zero
                
                // 设置播放器
                playerItem = AVPlayerItem(asset: asset)
                player = AVPlayer(playerItem: playerItem)
                
                // 加载第一帧
                await loadFrame(at: 0)
            }
        } catch {
            print("加载视频失败: \(error)")
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
        guard let frameExtractor = frameExtractor else { return }
        
        let time = CMTime(seconds: timestamp, preferredTimescale: 600)
        
        do {
            let cgImage = try await frameExtractor.image(at: time).image
            currentFrameImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            currentTimestamp = timestamp
            
            if let videoTrack = videoTrack {
                let frameRate = videoTrack.nominalFrameRate
                currentFrameNumber = Int(timestamp * Double(frameRate))
            }
        } catch {
            print("加载帧失败: \(error)")
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
    }
}
