//
//  AudioExtractor.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AVFoundation

struct AudioExtractor {
    /// 提取音频
    /// - Returns: 实际创建的文件 URL（可能与传入的 outputURL 不同，例如 MP3 在 ffmpeg 不可用时会导出为 M4A）
    static func extractAudio(
        from videoURL: URL,
        to outputURL: URL,
        format: AudioFormat,
        progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        let asset = AVAsset(url: videoURL)
        
        // 检查是否有音频轨道
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw VideoProcessingError.noAudioTrack
        }
        
        // 创建可编辑的组合
        let composition = AVMutableComposition()
        guard let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoProcessingError.compositionFailed
        }
        
        // 插入音频轨道
        let duration = try await asset.load(.duration)
        try compositionAudioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: audioTrack,
            at: .zero
        )
        
        // M4A 格式可以使用 AVAssetExportSession
        if format == .m4a {
            try await exportWithExportSession(
                composition: composition,
                outputURL: outputURL,
                progressHandler: progressHandler
            )
            return outputURL
        } else {
            // MP3 和 WAV 需要使用 AVAssetReader/Writer
            // MP3 实际会导出为 M4A 格式（因为 AVFoundation 不支持 MP3）
            var actualOutputURL = outputURL
            if format == .mp3 {
                // 将扩展名改为 m4a
                let urlWithoutExtension = outputURL.deletingPathExtension()
                actualOutputURL = urlWithoutExtension.appendingPathExtension("m4a")
            }
            
            try await exportWithReaderWriter(
                composition: composition,
                compositionAudioTrack: compositionAudioTrack,
                outputURL: actualOutputURL,
                format: format,
                progressHandler: progressHandler
            )
            return actualOutputURL
        }
    }
    
    /// 使用 AVAssetExportSession 导出 M4A
    private static func exportWithExportSession(
        composition: AVAsset,
        outputURL: URL,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw VideoProcessingError.exportFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        // 监听导出进度
        let progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                progressHandler(Double(exportSession.progress))
                
                if exportSession.status == .completed || exportSession.status == .failed || exportSession.status == .cancelled {
                    break
                }
            }
        }
        
        defer {
            progressTask.cancel()
        }
        
        await exportSession.export()
        
        if let error = exportSession.error {
            throw VideoProcessingError.unknown(error)
        }
        
        // 确保导出成功
        guard exportSession.status == .completed else {
            throw VideoProcessingError.exportFailed
        }
    }
    
    /// 使用 AVAssetReader/Writer 导出 MP3 或 WAV
    private static func exportWithReaderWriter(
        composition: AVAsset,
        compositionAudioTrack: AVMutableCompositionTrack,
        outputURL: URL,
        format: AudioFormat,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        // 检查并删除已存在的文件
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // 获取音频格式设置
        let audioSettings = format.audioSettings
        
        // 创建 Reader
        let reader = try AVAssetReader(asset: composition)
        let audioOutput = AVAssetReaderAudioMixOutput(
            audioTracks: [compositionAudioTrack],
            audioSettings: nil
        )
        
        guard reader.canAdd(audioOutput) else {
            throw VideoProcessingError.exportFailed
        }
        reader.add(audioOutput)
        
        // 创建 Writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: format.fileType)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        
        guard writer.canAdd(audioInput) else {
            throw VideoProcessingError.exportFailed
        }
        writer.add(audioInput)
        
        // 开始转换
        guard reader.startReading() else {
            throw VideoProcessingError.exportFailed
        }
        
        guard writer.startWriting() else {
            throw VideoProcessingError.exportFailed
        }
        
        writer.startSession(atSourceTime: .zero)
        
        // 获取总时长用于进度计算
        let duration = try await composition.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        
        // 处理音频数据
        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "audio.extraction")
            var processedSeconds: Double = 0
            
            audioInput.requestMediaDataWhenReady(on: queue) {
                while audioInput.isReadyForMoreMediaData {
                    guard let sampleBuffer = audioOutput.copyNextSampleBuffer() else {
                        audioInput.markAsFinished()
                        writer.finishWriting {
                            if let error = writer.error {
                                continuation.resume(throwing: VideoProcessingError.unknown(error))
                            } else {
                                continuation.resume()
                            }
                        }
                        return
                    }
                    
                    // 更新进度
                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    processedSeconds = CMTimeGetSeconds(presentationTime)
                    if totalSeconds > 0 {
                        let progress = min(processedSeconds / totalSeconds, 1.0)
                        progressHandler(progress)
                    }
                    
                    if !audioInput.append(sampleBuffer) {
                        audioInput.markAsFinished()
                        writer.finishWriting {
                            if let error = writer.error {
                                continuation.resume(throwing: VideoProcessingError.unknown(error))
                            } else {
                                continuation.resume()
                            }
                        }
                        return
                    }
                }
            }
        }
    }
}

