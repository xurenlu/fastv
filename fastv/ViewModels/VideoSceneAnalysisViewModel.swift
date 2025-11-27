//
//  VideoSceneAnalysisViewModel.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
class VideoSceneAnalysisViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var videoURL: URL?
    @Published var videoInfo: VideoInfo?
    @Published var isAnalyzing = false
    @Published var progress: Double = 0.0
    @Published var analysisStatus: String = ""
    @Published var errorMessage: String?
    
    // 分析结果
    @Published var sceneChangePoints: [SceneChangePoint] = []
    
    // 分析模式
    enum AnalysisMode: String, CaseIterable {
        case traditional = "传统方法"
        case aiPowered = "AI智能分析"
        case hybrid = "混合模式"
        
        var description: String {
            switch self {
            case .traditional:
                return "基于像素差异的快速分析"
            case .aiPowered:
                return "AI理解语义变化，更智能"
            case .hybrid:
                return "传统方法+AI优化"
            }
        }
    }
    
    @Published var analysisMode: AnalysisMode = .traditional
    
    // 分析参数（传统方法）
    @Published var threshold: Double = 0.3  // 变更阈值
    @Published var extractThumbnails: Bool = true  // 是否提取截图
    
    // 分析间隔设置
    enum AnalysisIntervalMode: String, CaseIterable {
        case timeBased = "时间间隔"
        case frameBased = "帧数间隔"
    }
    
    @Published var intervalMode: AnalysisIntervalMode = .timeBased
    @Published var timeInterval: Double = 0.1  // 时间间隔（秒）
    @Published var frameSkip: Int = 10  // 跳帧数（每N帧分析一次）
    
    // AI 分析参数
    @Published var visionModel: String = "llava:7b"  // 视觉模型
    @Published var textModel: String = "deepseek-r1:1.5b"  // 文本模型
    @Published var frameInterval: Double = 2.0  // 帧分析间隔（秒，AI分析用）
    @Published var audioSegmentDuration: Double = 5.0  // 音频分段时长（秒）
    
    // MARK: - Methods
    
    /// 加载视频文件
    func loadVideo(_ url: URL) {
        videoURL = url
        videoInfo = nil
        sceneChangePoints = []
        errorMessage = nil
        
        Task {
            await loadVideoInfo()
        }
    }
    
    /// 加载视频信息
    private func loadVideoInfo() async {
        guard let videoURL = videoURL else { return }
        
        do {
            videoInfo = try await VideoInfoService.getVideoInfo(from: videoURL)
        } catch let error as VideoProcessingError {
            errorMessage = error.errorDescription ?? "加载视频信息失败"
        } catch {
            errorMessage = "加载视频信息失败: \(error.localizedDescription)"
        }
    }
    
    /// 开始场景分析
    func startAnalysis() async {
        guard let videoURL = videoURL,
              let videoInfo = videoInfo else {
            errorMessage = "请先选择视频文件"
            return
        }
        
        isAnalyzing = true
        progress = 0.0
        analysisStatus = ""
        errorMessage = nil
        sceneChangePoints = []
        
        let preferences = UserPreferences.shared
        
        do {
            switch analysisMode {
            case .traditional:
                // 传统像素差异分析
                let points = try await SceneChangeDetector.detectSceneChanges(
                    from: videoURL,
                    frameRate: videoInfo.frameRate,
                    threshold: threshold,
                    extractThumbnails: extractThumbnails,
                    analysisInterval: intervalMode == .timeBased ? timeInterval : nil,
                    frameSkip: intervalMode == .frameBased ? frameSkip : nil,
                    progressHandler: { [weak self] progress, status in
                        Task { @MainActor in
                            self?.progress = progress
                            self?.analysisStatus = status
                        }
                    }
                )
                sceneChangePoints = points
                
            case .aiPowered:
                // AI 智能分析
                guard !preferences.aiAPIEndpoint.isEmpty else {
                    errorMessage = "请先在设置中配置 AI API 端点"
                    isAnalyzing = false
                    return
                }
                
                let aiPoints = try await AISceneAnalyzer.analyzeSceneChanges(
                    from: videoURL,
                    frameRate: videoInfo.frameRate,
                    visionModel: visionModel,
                    textModel: textModel,
                    endpoint: preferences.aiAPIEndpoint,
                    apiToken: preferences.aiAPIToken.isEmpty ? nil : preferences.aiAPIToken,
                    frameInterval: frameInterval,
                    audioSegmentDuration: audioSegmentDuration,
                    extractThumbnails: extractThumbnails,
                    progressHandler: { [weak self] progress, status in
                        Task { @MainActor in
                            self?.progress = progress
                            self?.analysisStatus = status
                        }
                    }
                )
                
                // 转换为 SceneChangePoint
                sceneChangePoints = aiPoints.map { aiPoint in
                    SceneChangePoint(
                        timestamp: aiPoint.timestamp,
                        frameNumber: aiPoint.frameNumber,
                        changeIntensity: aiPoint.confidence,
                        description: aiPoint.semanticDescription,
                        thumbnailImage: aiPoint.thumbnailImage
                    )
                }
                
            case .hybrid:
                // 混合模式：先用传统方法快速筛选，再用AI优化
                progressHandler(0.0, "第一步：传统方法快速筛选...")
                let traditionalPoints = try await SceneChangeDetector.detectSceneChanges(
                    from: videoURL,
                    frameRate: videoInfo.frameRate,
                    threshold: threshold * 0.7,  // 更低的阈值以获取更多候选点
                    extractThumbnails: false,  // 先不提取截图
                    analysisInterval: intervalMode == .timeBased ? timeInterval : nil,
                    frameSkip: intervalMode == .frameBased ? frameSkip : nil,
                    progressHandler: { [weak self] progress, status in
                        Task { @MainActor in
                            self?.progress = progress * 0.4
                            self?.analysisStatus = "第一步: \(status)"
                        }
                    }
                )
                
                // 第二步：用AI分析候选点
                if !traditionalPoints.isEmpty && !preferences.aiAPIEndpoint.isEmpty {
                    progressHandler(0.4, "第二步：AI深度分析候选点...")
                    // 简化版：只分析前几个候选点
                    let candidatePoints = Array(traditionalPoints.prefix(min(10, traditionalPoints.count)))
                    
                    var aiRefinedPoints: [SceneChangePoint] = []
                    for (index, point) in candidatePoints.enumerated() {
                        let progress = 0.4 + (Double(index) / Double(candidatePoints.count)) * 0.5
                        progressHandler(progress, "AI分析候选点 \(index + 1)/\(candidatePoints.count)...")
                        
                        // 提取该时间点的帧
                        if let frameImage = try? await FrameExtractor.extractFrame(at: point.timestamp, from: videoURL) {
                            // 使用AI分析
                            if let description = try? await OllamaService.shared.analyzeImage(
                                image: frameImage,
                                prompt: "请描述这张图片中的场景和主要变化。",
                                endpoint: preferences.aiAPIEndpoint,
                                model: visionModel,
                                apiToken: preferences.aiAPIToken.isEmpty ? nil : preferences.aiAPIToken,
                                timeout: 15.0
                            ) {
                                let refinedPoint = SceneChangePoint(
                                    timestamp: point.timestamp,
                                    frameNumber: point.frameNumber,
                                    changeIntensity: point.changeIntensity,
                                    description: "AI分析: \(description)",
                                    thumbnailImage: extractThumbnails ? frameImage : nil
                                )
                                aiRefinedPoints.append(refinedPoint)
                            } else {
                                // AI分析失败，使用原始点
                                aiRefinedPoints.append(point)
                            }
                        } else {
                            aiRefinedPoints.append(point)
                        }
                    }
                    
                    sceneChangePoints = aiRefinedPoints
                } else {
                    sceneChangePoints = traditionalPoints
                }
            }
            
        } catch let error as VideoProcessingError {
            errorMessage = error.errorDescription ?? "分析失败"
        } catch {
            errorMessage = "分析失败: \(error.localizedDescription)"
        }
        
        isAnalyzing = false
    }
    
    private func progressHandler(_ progress: Double, _ status: String) {
        self.progress = progress
        self.analysisStatus = status
    }
    
    /// 导出关键帧图片
    func exportKeyFrames() async {
        guard !sceneChangePoints.isEmpty else {
            errorMessage = "没有可导出的关键帧"
            return
        }
        
        // 让用户选择保存文件夹
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择保存位置"
        panel.title = "选择保存关键帧图片的文件夹"
        panel.message = "请选择一个文件夹来保存所有关键帧图片"
        
        guard panel.runModal() == .OK, let outputDirectory = panel.url else {
            return
        }
        
        isAnalyzing = true
        progress = 0.0
        analysisStatus = "正在导出关键帧图片..."
        errorMessage = nil
        
        do {
            let fileManager = FileManager.default
            var exportedCount = 0
            let totalCount = sceneChangePoints.count
            
            for (index, point) in sceneChangePoints.enumerated() {
                let progress = Double(index) / Double(totalCount)
                let timestamp = point.timestamp
                let minutes = Int(timestamp) / 60
                let seconds = Int(timestamp) % 60
                let milliseconds = Int((timestamp.truncatingRemainder(dividingBy: 1)) * 100)
                
                analysisStatus = "正在导出第 \(index + 1)/\(totalCount) 帧..."
                
                // 生成文件名：时间戳_帧号.png
                // 格式：MM分SS秒MS_帧N.png 或 SS秒MS_帧N.png
                let baseFileName: String
                if minutes > 0 {
                    baseFileName = String(format: "%02d分%02d秒%02d_帧%d", minutes, seconds, milliseconds, point.frameNumber)
                } else {
                    baseFileName = String(format: "%02d秒%02d_帧%d", seconds, milliseconds, point.frameNumber)
                }
                
                // 确保文件名唯一（如果已存在，添加序号）
                let uniqueFileName = fileManager.uniqueFileName(
                    at: outputDirectory,
                    baseName: baseFileName,
                    extension: "png"
                )
                let finalURL = outputDirectory.appendingPathComponent(uniqueFileName)
                
                // 如果关键点有截图，直接保存
                if let thumbnailImage = point.thumbnailImage {
                    try ImageSaver.save(
                        thumbnailImage,
                        to: finalURL,
                        format: .png,
                        maxWidth: nil,
                        maxHeight: nil,
                        compressionEnabled: false,
                        compressionQuality: 1.0
                    )
                    exportedCount += 1
                } else {
                    // 如果没有截图，从视频中提取
                    if let videoURL = videoURL {
                        let frameImage = try await FrameExtractor.extractFrame(at: point.timestamp, from: videoURL)
                        try ImageSaver.save(
                            frameImage,
                            to: finalURL,
                            format: .png,
                            maxWidth: nil,
                            maxHeight: nil,
                            compressionEnabled: false,
                            compressionQuality: 1.0
                        )
                        exportedCount += 1
                    }
                }
            }
            
            analysisStatus = "导出完成！已保存 \(exportedCount) 张图片"
            progress = 1.0
            
            // 打开文件夹
            NSWorkspace.shared.open(outputDirectory)
            
        } catch {
            errorMessage = "导出失败: \(error.localizedDescription)"
        }
        
        isAnalyzing = false
    }
    
    /// 清除当前视频信息
    func clearCurrentVideo() {
        videoURL = nil
        videoInfo = nil
        sceneChangePoints = []
        errorMessage = nil
        analysisStatus = ""
        progress = 0.0
    }
    
    /// 从在线视频URL下载并加载视频
    func downloadAndLoadVideo(from urlString: String) async {
        guard !urlString.isEmpty else {
            errorMessage = "请输入视频URL"
            return
        }
        
        // 验证URL格式
        guard URL(string: urlString) != nil else {
            errorMessage = "无效的URL格式"
            return
        }
        
        isAnalyzing = true
        progress = 0.0
        analysisStatus = "正在下载视频..."
        errorMessage = nil
        
        do {
            // 下载视频
            let downloadedURL = try await VideoDownloader.downloadVideo(from: urlString) { [weak self] downloadProgress in
                Task { @MainActor in
                    self?.progress = downloadProgress * 0.8  // 下载占80%进度
                    self?.analysisStatus = "正在下载视频... \(Int(downloadProgress * 100))%"
                }
            }
            
            // 加载视频信息
            analysisStatus = "正在加载视频信息..."
            progress = 0.9
            
            // 加载视频
            loadVideo(downloadedURL)
            
            // 等待视频信息加载完成
            while videoInfo == nil && errorMessage == nil {
                try await Task.sleep(nanoseconds: 100_000_000) // 等待0.1秒
            }
            
            if videoInfo != nil {
                analysisStatus = "视频下载并加载完成"
                progress = 1.0
            }
            
        } catch let error as VideoProcessingError {
            errorMessage = error.errorDescription ?? "下载失败"
        } catch {
            errorMessage = "下载失败: \(error.localizedDescription)"
        }
        
        isAnalyzing = false
    }
    
    /// 重置状态
    func reset() {
        videoURL = nil
        videoInfo = nil
        isAnalyzing = false
        progress = 0.0
        analysisStatus = ""
        errorMessage = nil
        sceneChangePoints = []
    }
    
    /// 选择视频文件
    func selectVideoFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .avi]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "选择视频文件"
        
        if panel.runModal() == .OK, let url = panel.url {
            loadVideo(url)
        }
    }
}

