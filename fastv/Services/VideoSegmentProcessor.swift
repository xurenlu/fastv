//
//  VideoSegmentProcessor.swift
//  fastv
//
//  Created by AI Assistant on 2025/12/25.
//  视频分段并行处理服务
//

import Foundation
import AVFoundation

/// 视频分段并行处理器
struct VideoSegmentProcessor {
    
    /// 分段信息
    struct Segment {
        let index: Int
        let startTime: Double
        let duration: Double
        let inputURL: URL
        let outputURL: URL
    }
    
    /// 处理进度信息
    struct ProcessProgress {
        let totalSegments: Int
        let completedSegments: Int
        let currentProgress: Double
        let overallProgress: Double
        let status: String
    }
    
    /// 分段并行处理视频
    /// - Parameters:
    ///   - inputURL: 输入视频文件 URL
    ///   - outputURL: 输出视频文件 URL
    ///   - segmentDuration: 每段时长（秒）
    ///   - maxConcurrentTasks: 最大并发任务数
    ///   - processSegment: 处理单个片段的闭包
    ///   - progressHandler: 进度回调
    static func processInParallel(
        inputURL: URL,
        outputURL: URL,
        segmentDuration: Double = 30.0,
        maxConcurrentTasks: Int = 4,
        processSegment: @escaping (URL, URL) async throws -> Void,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        let startTime = Date()
        
        await MainActor.run {
            progressHandler(0.0, "正在分析视频...")
        }
        
        // 1. 获取视频信息
        let videoInfo = try await VideoInfoService.getVideoInfo(from: inputURL)
        let totalDuration = videoInfo.duration
        
        // 计算分段数量
        let segmentCount = Int(ceil(totalDuration / segmentDuration))
        
        guard segmentCount > 0 else {
            throw NSError(domain: "VideoSegmentProcessor", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "视频时长无效"])
        }
        
        print("📊 [VideoSegmentProcessor] 视频时长: \(totalDuration)秒, 分段数: \(segmentCount), 每段: \(segmentDuration)秒")
        
        await MainActor.run {
            progressHandler(0.05, "准备分段处理（共 \(segmentCount) 段）...")
        }
        
        // 2. 创建临时目录
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fastv_segments_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            // 清理临时文件
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // 3. 生成分段信息
        var segments: [Segment] = []
        for i in 0..<segmentCount {
            let start = Double(i) * segmentDuration
            let duration = min(segmentDuration, totalDuration - start)
            
            let segmentInput = tempDir.appendingPathComponent("segment_\(i)_input.mp4")
            let segmentOutput = tempDir.appendingPathComponent("segment_\(i)_output.mp4")
            
            segments.append(Segment(
                index: i,
                startTime: start,
                duration: duration,
                inputURL: segmentInput,
                outputURL: segmentOutput
            ))
        }
        
        // 4. 切分视频
        await MainActor.run {
            progressHandler(0.1, "正在切分视频...")
        }
        
        try await splitVideo(inputURL: inputURL, segments: segments)
        
        await MainActor.run {
            progressHandler(0.2, "视频切分完成，开始并行处理...")
        }
        
        // 5. 并行处理各片段
        let completedCount = Atomic(value: 0)
        let segmentProgress = Atomic(value: [Int: Double]())
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            var activeTaskCount = 0
            var nextSegmentIndex = 0
            
            // 启动初始任务
            while activeTaskCount < maxConcurrentTasks && nextSegmentIndex < segments.count {
                let segment = segments[nextSegmentIndex]
                nextSegmentIndex += 1
                activeTaskCount += 1
                
                group.addTask {
                    try await processSegmentWithProgress(
                        segment: segment,
                        processSegment: processSegment,
                        onProgress: { progress in
                            segmentProgress.modify { dict in
                                var newDict = dict
                                newDict[segment.index] = progress
                                return newDict
                            }
                            
                            // 计算总进度
                            let completed = completedCount.value
                            let currentSegmentProgress = segmentProgress.value.values.reduce(0.0, +)
                            let overallProgress = 0.2 + 0.7 * (Double(completed) + currentSegmentProgress) / Double(segments.count)
                            
                            Task { @MainActor in
                                progressHandler(overallProgress, "正在处理片段 \(completed + 1)/\(segments.count)...")
                            }
                        }
                    )
                    
                    completedCount.modify { $0 + 1 }
                    segmentProgress.modify { dict in
                        var newDict = dict
                        newDict.removeValue(forKey: segment.index)
                        return newDict
                    }
                }
            }
            
            // 等待任务完成并启动新任务
            for try await _ in group {
                activeTaskCount -= 1
                
                // 如果还有待处理的片段，启动新任务
                if nextSegmentIndex < segments.count {
                    let segment = segments[nextSegmentIndex]
                    nextSegmentIndex += 1
                    activeTaskCount += 1
                    
                    group.addTask {
                        try await processSegmentWithProgress(
                            segment: segment,
                            processSegment: processSegment,
                            onProgress: { progress in
                                segmentProgress.modify { dict in
                                    var newDict = dict
                                    newDict[segment.index] = progress
                                    return newDict
                                }
                                
                                let completed = completedCount.value
                                let currentSegmentProgress = segmentProgress.value.values.reduce(0.0, +)
                                let overallProgress = 0.2 + 0.7 * (Double(completed) + currentSegmentProgress) / Double(segments.count)
                                
                                Task { @MainActor in
                                    progressHandler(overallProgress, "正在处理片段 \(completed + 1)/\(segments.count)...")
                                }
                            }
                        )
                        
                        completedCount.modify { $0 + 1 }
                        segmentProgress.modify { dict in
                            var newDict = dict
                            newDict.removeValue(forKey: segment.index)
                            return newDict
                        }
                    }
                }
            }
        }
        
        await MainActor.run {
            progressHandler(0.9, "正在合并视频片段...")
        }
        
        // 6. 合并处理后的片段
        try await mergeSegments(segments: segments, outputURL: outputURL)
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ [VideoSegmentProcessor] 处理完成，耗时: \(String(format: "%.1f", elapsed))秒")
        
        await MainActor.run {
            progressHandler(1.0, "视频处理完成！")
        }
    }
    
    /// 切分视频为多个片段
    private static func splitVideo(inputURL: URL, segments: [Segment]) async throws {
        // 使用 FFmpeg 切分视频（不重新编码，速度快）
        for segment in segments {
            var arguments: [String] = []
            arguments.append("-y")
            
            // 精确定位到指定时间点
            arguments.append("-ss")
            arguments.append(String(format: "%.3f", segment.startTime))
            
            arguments.append("-i")
            arguments.append(inputURL.path)
            
            // 指定输出时长
            arguments.append("-t")
            arguments.append(String(format: "%.3f", segment.duration))
            
            // 复制编码（不重新编码）
            arguments.append("-c")
            arguments.append("copy")
            
            // 避免负时间戳，使用 make_zero 模式
            arguments.append("-avoid_negative_ts")
            arguments.append("make_zero")
            
            // 重置时间戳为从 0 开始
            arguments.append("-fflags")
            arguments.append("+genpts")
            
            arguments.append(segment.inputURL.path)
            
            _ = try await FFmpegService.execute(arguments: arguments)
            
            // 验证切分后的片段时长
            do {
                let segmentInfo = try await VideoInfoService.getVideoInfo(from: segment.inputURL)
                let actualDuration = segmentInfo.duration
                let expectedDuration = segment.duration
                let durationDiff = abs(actualDuration - expectedDuration)
                
                print("✂️ [VideoSegmentProcessor] 切分片段 \(segment.index): \(String(format: "%.2f", segment.startTime))s - \(String(format: "%.2f", segment.startTime + segment.duration))s")
                print("   实际时长: \(String(format: "%.2f", actualDuration))s, 预期: \(String(format: "%.2f", expectedDuration))s, 差异: \(String(format: "%.3f", durationDiff))s")
                
                if durationDiff > 0.5 {
                    print("⚠️ [VideoSegmentProcessor] 警告：片段 \(segment.index) 时长差异较大: \(String(format: "%.3f", durationDiff))秒")
                }
            } catch {
                print("⚠️ [VideoSegmentProcessor] 无法验证片段 \(segment.index) 时长: \(error)")
            }
        }
    }
    
    /// 处理单个片段并报告进度
    private static func processSegmentWithProgress(
        segment: Segment,
        processSegment: @escaping (URL, URL) async throws -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        print("🔄 [VideoSegmentProcessor] 开始处理片段 \(segment.index)")
        
        // 调用用户提供的处理函数
        try await processSegment(segment.inputURL, segment.outputURL)
        
        print("✅ [VideoSegmentProcessor] 完成处理片段 \(segment.index)")
        onProgress(1.0)
    }
    
    /// 合并视频片段
    private static func mergeSegments(segments: [Segment], outputURL: URL) async throws {
        // 创建 concat 文件列表
        let concatListURL = segments[0].outputURL.deletingLastPathComponent()
            .appendingPathComponent("concat_list.txt")
        
        var concatContent = ""
        var totalExpectedDuration: Double = 0
        for segment in segments.sorted(by: { $0.index < $1.index }) {
            concatContent += "file '\(segment.outputURL.path)'\n"
            totalExpectedDuration += segment.duration
            
            // 验证片段是否存在
            guard FileManager.default.fileExists(atPath: segment.outputURL.path) else {
                throw NSError(domain: "VideoSegmentProcessor", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "片段文件不存在: \(segment.outputURL.path)"])
            }
        }
        
        print("📊 [VideoSegmentProcessor] 预期总时长: \(String(format: "%.2f", totalExpectedDuration))秒")
        
        try concatContent.write(to: concatListURL, atomically: true, encoding: .utf8)
        
        // 使用 concat demuxer 合并
        var arguments: [String] = []
        arguments.append("-y")
        arguments.append("-f")
        arguments.append("concat")
        arguments.append("-safe")
        arguments.append("0")
        arguments.append("-i")
        arguments.append(concatListURL.path)
        
        // 重新生成时间戳，避免时间戳不连续导致的问题
        arguments.append("-fflags")
        arguments.append("+genpts")
        
        // 复制编码（不重新编码）
        arguments.append("-c")
        arguments.append("copy")
        
        // 避免负时间戳
        arguments.append("-avoid_negative_ts")
        arguments.append("make_zero")
        
        arguments.append(outputURL.path)
        
        _ = try await FFmpegService.execute(arguments: arguments)
        
        // 验证输出文件的时长
        do {
            let outputInfo = try await VideoInfoService.getVideoInfo(from: outputURL)
            let actualDuration = outputInfo.duration
            let durationDiff = abs(actualDuration - totalExpectedDuration)
            
            print("🔗 [VideoSegmentProcessor] 合并完成: \(outputURL.path)")
            print("📊 [VideoSegmentProcessor] 实际时长: \(String(format: "%.2f", actualDuration))秒")
            print("📊 [VideoSegmentProcessor] 时长差异: \(String(format: "%.2f", durationDiff))秒")
            
            // 如果时长差异超过 1 秒，发出警告
            if durationDiff > 1.0 {
                print("⚠️ [VideoSegmentProcessor] 警告：合并后视频时长与预期不符！差异: \(String(format: "%.2f", durationDiff))秒")
            }
        } catch {
            print("⚠️ [VideoSegmentProcessor] 无法验证输出视频时长: \(error)")
        }
    }
}

/// 线程安全的原子值包装器
private class Atomic<T> {
    private var _value: T
    private let lock = NSLock()
    
    var value: T {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    
    init(value: T) {
        self._value = value
    }
    
    func modify(_ transform: (T) -> T) {
        lock.lock()
        defer { lock.unlock() }
        _value = transform(_value)
    }
}

