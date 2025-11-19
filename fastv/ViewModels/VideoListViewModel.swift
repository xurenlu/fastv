//
//  VideoListViewModel.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import SwiftUI
import Combine
import AppKit

@MainActor
class VideoListViewModel: ObservableObject {
    @Published var videoItems: [VideoItem] = []
    @Published var isProcessing = false
    @Published var overallProgress: Double = 0.0
    @Published var errorMessage: String?
    
    // 用户偏好
    @ObservedObject var preferences = UserPreferences.shared
    
    // 处理选项（从用户偏好同步）
    var extractFirstFrame: Bool {
        get { preferences.extractFirstFrame }
        set { preferences.extractFirstFrame = newValue }
    }
    
    var extractLastFrame: Bool {
        get { preferences.extractLastFrame }
        set { preferences.extractLastFrame = newValue }
    }
    
    var extractAudio: Bool {
        get { preferences.extractAudio }
        set { preferences.extractAudio = newValue }
    }
    
    var selectedAudioFormat: AudioFormat {
        get { preferences.audioFormat }
        set { preferences.audioFormat = newValue }
    }
    
    var extractTranscript: Bool {
        get { preferences.extractTranscript }
        set { preferences.extractTranscript = newValue }
    }
    
    var hasAnyOptionSelected: Bool {
        return extractFirstFrame || extractLastFrame || extractAudio
    }
    
    var selectedVideos: [VideoItem] {
        videoItems.filter { $0.isSelected }
    }
    
    /// 自定义保存位置（可选）
    @Published var customOutputDirectory: URL?
    
    // MARK: - Methods
    
    /// 添加视频
    func addVideos(_ urls: [URL]) {
        let newItems = urls.map { url in
            VideoItem(url: url, isSelected: true)
        }
        videoItems.append(contentsOf: newItems)
        
        // 异步加载视频信息和预览
        Task {
            await loadVideosInfo(newItems)
        }
    }
    
    /// 加载视频信息和预览
    private func loadVideosInfo(_ items: [VideoItem]) async {
        await withTaskGroup(of: Void.self) { group in
            for item in items {
                group.addTask {
                    await self.loadVideoInfo(for: item)
                }
                group.addTask {
                    await self.loadPreviewImage(for: item)
                }
            }
        }
    }
    
    /// 加载单个视频信息
    private func loadVideoInfo(for item: VideoItem) async {
        do {
            let videoInfo = try await VideoInfoService.getVideoInfo(from: item.url)
            await MainActor.run {
                item.videoInfo = videoInfo
            }
        } catch {
            // 静默失败，不影响其他视频
            print("Failed to load video info for \(item.url): \(error)")
        }
    }
    
    /// 加载预览图片
    private func loadPreviewImage(for item: VideoItem) async {
        do {
            let image = try await FrameExtractor.extractFirstFrame(from: item.url)
            await MainActor.run {
                item.previewImage = image
            }
        } catch {
            // 静默失败
            print("Failed to load preview for \(item.url): \(error)")
        }
    }
    
    /// 移除视频
    func removeVideo(_ item: VideoItem) {
        videoItems.removeAll { $0.id == item.id }
    }
    
    /// 切换选择状态
    func toggleSelection(for item: VideoItem) {
        item.isSelected.toggle()
    }
    
    /// 开始批量处理
    func startBatchProcessing() async {
        let selected = selectedVideos
        guard !selected.isEmpty else {
            errorMessage = "请至少选择一个视频"
            return
        }
        
        guard hasAnyOptionSelected else {
            errorMessage = "请至少选择一项处理操作"
            return
        }
        
        isProcessing = true
        overallProgress = 0.0
        errorMessage = nil
        
        // 重置所有视频的处理状态
        for item in selected {
            item.processingState = .processing
            item.progress = 0.0
        }
        
        // 并发处理所有视频
        await withTaskGroup(of: Void.self) { group in
            for (index, item) in selected.enumerated() {
                group.addTask {
                    await self.processVideo(item, index: index, total: selected.count)
                }
            }
        }
        
        isProcessing = false
    }
    
    /// 处理单个视频
    private func processVideo(_ item: VideoItem, index: Int, total: Int) async {
        // 使用自定义保存位置或默认位置
        let outputDirectory: URL
        if let customDir = customOutputDirectory ?? preferences.getCustomOutputDirectory() {
            outputDirectory = customDir
        } else {
            outputDirectory = FileManager.default.defaultOutputDirectory(for: item.url)
        }
        
        do {
            let result = try await VideoProcessor.processVideo(
                videoURL: item.url,
                extractFirstFrame: extractFirstFrame,
                extractLastFrame: extractLastFrame,
                extractAudio: extractAudio,
                extractTranscript: extractTranscript,
                audioFormat: selectedAudioFormat,
                outputDirectory: outputDirectory,
                imageFormat: preferences.imageFormat,
                imageMaxWidth: preferences.imageMaxWidth,
                imageMaxHeight: preferences.imageMaxHeight,
                imageCompressionEnabled: preferences.imageCompressionEnabled,
                imageCompressionQuality: preferences.imageCompressionQuality,
                progressHandler: { progress, status in
                    Task { @MainActor in
                        item.progress = progress
                        item.processingStatus = status
                        
                        // 更新总体进度
                        let baseProgress = Double(index) / Double(total)
                        let itemProgress = progress / Double(total)
                        self.overallProgress = baseProgress + itemProgress
                    }
                }
            )
            
            await MainActor.run {
                item.firstFrameImage = result.firstFrameImage
                item.lastFrameImage = result.lastFrameImage
                item.audioURL = result.audioURL
                item.outputDirectory = result.outputDirectory
                item.processingState = .completed
            }
            
        } catch {
            await MainActor.run {
                item.processingState = .failed(error)
                if let error = error as? VideoProcessingError {
                    self.errorMessage = "处理失败: \(error.errorDescription ?? "未知错误")"
                } else {
                    self.errorMessage = "处理失败: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// 选择保存位置
    func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = "选择保存位置"
        panel.prompt = "选择"
        
        // 如果有自定义目录，设置为起始目录
        if let customDir = customOutputDirectory ?? preferences.getCustomOutputDirectory() {
            panel.directoryURL = customDir
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            preferences.saveCustomOutputDirectory(url)
            customOutputDirectory = url
        }
    }
    
    /// 重置为默认保存位置（视频文件同目录）
    func resetToDefaultOutputDirectory() {
        preferences.saveCustomOutputDirectory(nil)
        customOutputDirectory = nil
    }
    
    /// 清空列表
    func clear() {
        videoItems.removeAll()
        isProcessing = false
        overallProgress = 0.0
    }
}

