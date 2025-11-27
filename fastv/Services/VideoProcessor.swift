//
//  VideoProcessor.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AppKit

/// 视频处理主服务（协调各子服务）
struct VideoProcessor {
    /// 处理视频：提取帧和音频
    static func processVideo(
        videoURL: URL,
        extractFirstFrame: Bool,
        extractLastFrame: Bool,
        extractAudio: Bool,
        extractTranscript: Bool,
        detectSceneChanges: Bool,
        audioFormat: AudioFormat,
        transcriptLanguage: TranscriptLanguage = .auto,
        outputDirectory: URL,
        imageFormat: ImageFormat,
        imageMaxWidth: Int?,
        imageMaxHeight: Int?,
        imageCompressionEnabled: Bool,
        imageCompressionQuality: Double,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> ProcessingResult {
        // 获取安全作用域资源访问权限（如果 URL 是通过文件选择器选择的）
        let hasVideoAccess = videoURL.startAccessingSecurityScopedResource()
        let hasOutputAccess = outputDirectory.startAccessingSecurityScopedResource()
        defer {
            if hasVideoAccess {
                videoURL.stopAccessingSecurityScopedResource()
            }
            if hasOutputAccess {
                outputDirectory.stopAccessingSecurityScopedResource()
            }
        }
        
        var firstFrameImage: NSImage?
        var lastFrameImage: NSImage?
        var audioURL: URL?
        var transcriptURL: URL?
        var sceneChangePoints: [SceneChangePoint] = []
        var sceneChangeReportURL: URL?
        
        let fileManager = FileManager.default
        let baseName = videoURL.deletingPathExtension().lastPathComponent
        
        // 计算进度分配
        var progressWeight: Double = 0.0
        if extractFirstFrame { progressWeight += 0.15 }
        if extractLastFrame { progressWeight += 0.15 }
        if extractAudio { progressWeight += 0.3 }
        if extractTranscript { progressWeight += 0.2 }
        if detectSceneChanges { progressWeight += 0.2 }
        
        var currentProgress: Double = 0.0
        
        // 提取第一帧
        if extractFirstFrame {
            progressHandler(currentProgress, "正在提取第一帧...")
            firstFrameImage = try await FrameExtractor.extractFirstFrame(from: videoURL)
            
            // 保存第一帧
            let fileName = fileManager.uniqueFileName(
                at: outputDirectory,
                baseName: "\(baseName)_第一帧",
                extension: imageFormat.fileExtension
            )
            let outputURL = outputDirectory.appendingPathComponent(fileName)
            try ImageSaver.save(
                firstFrameImage!,
                to: outputURL,
                format: imageFormat,
                maxWidth: imageMaxWidth,
                maxHeight: imageMaxHeight,
                compressionEnabled: imageCompressionEnabled,
                compressionQuality: imageCompressionQuality
            )
            currentProgress += 0.15
        }
        
        // 提取最后一帧
        if extractLastFrame {
            progressHandler(currentProgress, "正在提取最后一帧...")
            lastFrameImage = try await FrameExtractor.extractLastFrame(from: videoURL)
            
            // 保存最后一帧
            let fileName = fileManager.uniqueFileName(
                at: outputDirectory,
                baseName: "\(baseName)_最后一帧",
                extension: imageFormat.fileExtension
            )
            let outputURL = outputDirectory.appendingPathComponent(fileName)
            try ImageSaver.save(
                lastFrameImage!,
                to: outputURL,
                format: imageFormat,
                maxWidth: imageMaxWidth,
                maxHeight: imageMaxHeight,
                compressionEnabled: imageCompressionEnabled,
                compressionQuality: imageCompressionQuality
            )
            currentProgress += 0.15
        }
        
        // 提取音频
        if extractAudio {
            progressHandler(currentProgress, "正在提取音频...")
            let fileName = fileManager.uniqueFileName(
                at: outputDirectory,
                baseName: "\(baseName)_音频",
                extension: audioFormat.fileExtension
            )
            let outputURL = outputDirectory.appendingPathComponent(fileName)
            
            let audioProgressStart = currentProgress
            let audioProgressRange = extractTranscript ? 0.2 : 0.3
            
            let actualAudioURL = try await AudioExtractor.extractAudio(
                from: videoURL,
                to: outputURL,
                format: audioFormat
            ) { progress in
                let overallProgress = audioProgressStart + (progress * audioProgressRange)
                progressHandler(overallProgress, "正在提取音频... \(Int(progress * 100))%")
            }
            
            audioURL = actualAudioURL
            currentProgress += audioProgressRange
            
            // 提取文本稿（需要先有音频）
            if extractTranscript, let audioURL = audioURL {
                progressHandler(currentProgress, "正在转写语音...")
                let transcript = try await SpeechTranscriber.transcribe(audioURL: audioURL, language: transcriptLanguage)
                
                // 保存转录文本
                let transcriptFileName = fileManager.uniqueFileName(
                    at: outputDirectory,
                    baseName: "\(baseName)_文本稿",
                    extension: "txt"
                )
                let transcriptOutputURL = outputDirectory.appendingPathComponent(transcriptFileName)
                try transcript.write(to: transcriptOutputURL, atomically: true, encoding: .utf8)
                
                transcriptURL = transcriptOutputURL
                currentProgress += 0.2
            }
        }
        
        // 检测画面变更
        if detectSceneChanges {
            progressHandler(currentProgress, "正在检测画面变更...")
            let detectionStart = currentProgress
            let detectionRange = 0.2
            
            sceneChangePoints = try await SceneChangeDetector.detectSceneChanges(
                from: videoURL,
                sampleRate: 1.0,
                threshold: 0.3
            ) { detectionProgress, status in
                let overallProgress = detectionStart + (detectionProgress * detectionRange)
                progressHandler(overallProgress, status)
            }
            
            // 保存变更检测报告
            if !sceneChangePoints.isEmpty {
                let reportFileName = fileManager.uniqueFileName(
                    at: outputDirectory,
                    baseName: "\(baseName)_画面变更检测",
                    extension: "json"
                )
                let reportOutputURL = outputDirectory.appendingPathComponent(reportFileName)
                
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let reportData = try encoder.encode(sceneChangePoints)
                try reportData.write(to: reportOutputURL)
                
                sceneChangeReportURL = reportOutputURL
            }
            
            currentProgress += detectionRange
        }
        
        progressHandler(1.0, "处理完成")
        
        return ProcessingResult(
            firstFrameImage: firstFrameImage,
            lastFrameImage: lastFrameImage,
            audioURL: audioURL,
            transcriptURL: transcriptURL,
            sceneChangePoints: sceneChangePoints,
            sceneChangeReportURL: sceneChangeReportURL,
            outputDirectory: outputDirectory
        )
    }
}

struct ProcessingResult {
    let firstFrameImage: NSImage?
    let lastFrameImage: NSImage?
    let audioURL: URL?
    let transcriptURL: URL?
    let sceneChangePoints: [SceneChangePoint]
    let sceneChangeReportURL: URL?
    let outputDirectory: URL
}

