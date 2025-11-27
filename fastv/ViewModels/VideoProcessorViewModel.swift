//
//  VideoProcessorViewModel.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
class VideoProcessorViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var appState: AppState = .empty
    @Published var videoURL: URL? {
        didSet {
            // 同步更新 appState
            if let url = videoURL {
                appState = .singleVideo(url)
            } else if appState.isSingleVideo {
                appState = .empty
            }
        }
    }
    @Published var videoInfo: VideoInfo?
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var processingStatus: String = ""
    @Published var processingCompleted = false
    @Published var errorMessage: String?
    
    // 下载状态
    @Published var downloadState: DownloadState = .idle
    
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
    
    var selectedTranscriptLanguage: TranscriptLanguage {
        get { preferences.transcriptLanguage }
        set { preferences.transcriptLanguage = newValue }
    }
    
    var detectSceneChanges: Bool {
        get { preferences.detectSceneChanges }
        set { preferences.detectSceneChanges = newValue }
    }
    
    // 结果
    @Published var firstFrameImage: NSImage?
    @Published var lastFrameImage: NSImage?
    @Published var audioURL: URL?
    @Published var outputDirectory: URL?
    
    // MARK: - Computed Properties
    
    var hasAnyOptionSelected: Bool {
        return extractFirstFrame || extractLastFrame || extractAudio || detectSceneChanges
    }
    
    // 转录结果
    @Published var transcriptURL: URL?
    
    // 画面变更检测结果
    @Published var sceneChangePoints: [SceneChangePoint] = []
    @Published var sceneChangeReportURL: URL?
    
    // MARK: - Methods
    
    /// 加载视频文件
    func loadVideo(_ url: URL) {
        videoURL = url
        videoInfo = nil
        processingCompleted = false
        firstFrameImage = nil
        lastFrameImage = nil
        audioURL = nil
        errorMessage = nil
        
        // 保存上次打开的文件
        preferences.saveLastVideoURL(url)
        
        Task {
            await loadVideoInfo()
        }
    }
    
    /// 获取上次打开的文件 URL（不自动加载）
    func getLastVideoURL() -> URL? {
        guard let lastURL = preferences.getLastVideoURL(),
              FileManager.default.fileExists(atPath: lastURL.path) else {
            return nil
        }
        return lastURL
    }
    
    /// 加载多个视频文件
    func loadVideos(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        
        if urls.count == 1 {
            loadVideo(urls[0])
        } else {
            appState = .multipleVideos(urls)
        }
    }
    
    /// 视频列表 ViewModel（用于多视频模式）
    @Published var videoListViewModel: VideoListViewModel?
    
    /// 初始化视频列表 ViewModel
    func initializeVideoList() {
        if case .multipleVideos(let urls) = appState {
            let listViewModel = VideoListViewModel()
            listViewModel.addVideos(urls)
            videoListViewModel = listViewModel
        }
    }
    
    /// 加载视频信息
    private func loadVideoInfo() async {
        guard let videoURL = videoURL else { return }
        
        do {
            videoInfo = try await VideoInfoService.getVideoInfo(from: videoURL)
            // 使用自定义保存位置或默认位置
            if let customDir = preferences.getCustomOutputDirectory() {
                outputDirectory = customDir
            } else {
                outputDirectory = FileManager.default.defaultOutputDirectory(for: videoURL)
            }
            
            // 如果没有音频轨道，禁用音频提取选项
            if let videoInfo = videoInfo, videoInfo.audioTracks.isEmpty {
                preferences.extractAudio = false
            }
        } catch let error as VideoProcessingError {
            errorMessage = error.errorDescription ?? "加载视频信息失败"
        } catch {
            errorMessage = "加载视频信息失败: \(error.localizedDescription)"
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
        if let customDir = preferences.getCustomOutputDirectory() {
            panel.directoryURL = customDir
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            preferences.saveCustomOutputDirectory(url)
            outputDirectory = url
        }
    }
    
    /// 重置为默认保存位置（视频文件同目录）
    func resetToDefaultOutputDirectory() {
        guard let videoURL = videoURL else { return }
        preferences.saveCustomOutputDirectory(nil)
        outputDirectory = FileManager.default.defaultOutputDirectory(for: videoURL)
    }
    
    /// 开始处理
    func startProcessing() async {
        guard let videoURL = videoURL,
              let outputDirectory = outputDirectory else {
            errorMessage = "请先选择视频文件"
            return
        }
        
        guard hasAnyOptionSelected else {
            errorMessage = "请至少选择一项处理操作"
            return
        }
        
        isProcessing = true
        processingCompleted = false
        progress = 0.0
        errorMessage = nil
        
        do {
            let result = try await VideoProcessor.processVideo(
                videoURL: videoURL,
                extractFirstFrame: extractFirstFrame,
                extractLastFrame: extractLastFrame,
                extractAudio: extractAudio,
                extractTranscript: extractTranscript,
                detectSceneChanges: detectSceneChanges,
                audioFormat: selectedAudioFormat,
                transcriptLanguage: selectedTranscriptLanguage,
                outputDirectory: outputDirectory,
                imageFormat: preferences.imageFormat,
                imageMaxWidth: preferences.imageMaxWidth,
                imageMaxHeight: preferences.imageMaxHeight,
                imageCompressionEnabled: preferences.imageCompressionEnabled,
                imageCompressionQuality: preferences.imageCompressionQuality,
                progressHandler: { [weak self] progress, status in
                    Task { @MainActor in
                        self?.progress = progress
                        self?.processingStatus = status
                    }
                }
            )
            
            firstFrameImage = result.firstFrameImage
            lastFrameImage = result.lastFrameImage
            audioURL = result.audioURL
            transcriptURL = result.transcriptURL
            sceneChangePoints = result.sceneChangePoints
            sceneChangeReportURL = result.sceneChangeReportURL
            self.outputDirectory = result.outputDirectory
            processingCompleted = true
            
        } catch let error as VideoProcessingError {
            errorMessage = error.errorDescription ?? "处理失败"
        } catch {
            errorMessage = "处理失败: \(error.localizedDescription)"
        }
        
        isProcessing = false
    }
    
    /// 从 URL 下载视频
    func downloadVideo(from urlString: String) {
        guard !urlString.isEmpty else {
            errorMessage = "请输入有效的视频链接"
            return
        }
        
        downloadState = .fetchingInfo
        errorMessage = nil
        
        Task {
            do {
                let localURL = try await VideoDownloader.downloadVideo(from: urlString) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadState = .downloading(progress)
                    }
                }
                
                await MainActor.run {
                    downloadState = .completed(localURL)
                    // 下载完成后自动加载视频
                    loadVideo(localURL)
                }
            } catch {
                await MainActor.run {
                    downloadState = .failed(error)
                    if let error = error as? VideoProcessingError {
                        errorMessage = error.errorDescription
                    } else {
                        errorMessage = "下载失败: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    /// 重置状态（处理新文件）
    func reset() {
        videoURL = nil
        videoInfo = nil
        isProcessing = false
        progress = 0.0
        processingStatus = ""
        processingCompleted = false
        errorMessage = nil
        firstFrameImage = nil
        lastFrameImage = nil
        audioURL = nil
        transcriptURL = nil
        sceneChangePoints = []
        sceneChangeReportURL = nil
        outputDirectory = nil
        appState = .empty
        videoListViewModel = nil
        downloadState = .idle
    }
}

