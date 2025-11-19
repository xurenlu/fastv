//
//  FFmpegHelper.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation

struct FFmpegHelper {
    /// 检查 ffmpeg 是否可用
    static func isAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // 如果 which 找到 ffmpeg，返回 true
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    /// 获取 ffmpeg 可执行文件路径
    static func ffmpegPath() -> String? {
        // 先尝试直接调用 ffmpeg
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !output.isEmpty && FileManager.default.fileExists(atPath: output) {
                    return output
                }
            }
        } catch {
            // 继续尝试其他路径
        }
        
        // 尝试常见路径
        let commonPaths = [
            "/usr/local/bin/ffmpeg",
            "/opt/homebrew/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    /// 使用 ffmpeg 提取音频并转换为指定格式
    /// - Parameters:
    ///   - videoURL: 视频文件 URL
    ///   - outputURL: 输出音频文件 URL
    ///   - format: 音频格式（目前支持 MP3）
    ///   - duration: 视频总时长（秒），用于计算进度
    ///   - progressHandler: 进度回调（0.0 - 1.0）
    /// - Throws: VideoProcessingError
    static func extractAudio(
        from videoURL: URL,
        to outputURL: URL,
        format: AudioFormat,
        duration: Double,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        guard let ffmpegPath = ffmpegPath() else {
            throw VideoProcessingError.exportFailed
        }
        
        // 检查并删除已存在的文件
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        
        // 构建 ffmpeg 命令参数
        var arguments: [String] = []
        
        // 输入文件
        arguments.append("-i")
        arguments.append(videoURL.path)
        
        // 音频编码设置
        switch format {
        case .mp3:
            // MP3 编码：使用 libmp3lame
            arguments.append("-acodec")
            arguments.append("libmp3lame")
            arguments.append("-ab")
            arguments.append("192k") // 比特率 192kbps
            arguments.append("-ar")
            arguments.append("44100") // 采样率 44.1kHz
            arguments.append("-ac")
            arguments.append("2") // 立体声
        case .wav:
            // WAV 编码：使用 PCM
            arguments.append("-acodec")
            arguments.append("pcm_s16le")
            arguments.append("-ar")
            arguments.append("44100")
            arguments.append("-ac")
            arguments.append("2")
        case .m4a:
            // M4A 编码：使用 AAC
            arguments.append("-acodec")
            arguments.append("aac")
            arguments.append("-ab")
            arguments.append("192k")
            arguments.append("-ar")
            arguments.append("44100")
            arguments.append("-ac")
            arguments.append("2")
        }
        
        // 覆盖输出文件
        arguments.append("-y")
        
        // 输出文件
        arguments.append(outputURL.path)
        
        process.arguments = arguments
        
        // 设置输出管道来捕获进度
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // 启动进程
        try process.run()
        
        // 读取错误输出（ffmpeg 将进度信息输出到 stderr）
        let errorHandle = errorPipe.fileHandleForReading
        
        // 监听进程完成和进度
        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "ffmpeg.progress")
            var buffer = ""
            
            // 读取错误输出（包含进度信息）
            errorHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    return
                }
                
                // 追加新数据到缓冲区
                if let newText = String(data: data, encoding: .utf8) {
                    buffer += newText
                    
                    // 按行处理，查找最新的进度信息
                    let lines = buffer.components(separatedBy: .newlines)
                    // 保留最后一行（可能不完整）
                    buffer = lines.last ?? ""
                    
                    // 处理完整的行
                    for line in lines.dropLast() {
                        // ffmpeg 进度格式：time=00:00:05.00 bitrate= 123.4kbits/s speed=1.2x
                        // 提取时间信息
                        if let timeRange = line.range(of: #"time=(\d{2}):(\d{2}):(\d{2})\.(\d{2})"#, options: .regularExpression) {
                            let timeStr = String(line[timeRange])
                            if let progress = parseFFmpegProgress(timeString: timeStr, totalDuration: duration) {
                                queue.async {
                                    progressHandler(progress)
                                }
                            }
                        }
                    }
                }
            }
            
            // 等待进程完成
            process.terminationHandler = { process in
                errorHandle.readabilityHandler = nil
                
                if process.terminationStatus == 0 {
                    // 检查输出文件是否存在
                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        queue.async {
                            progressHandler(1.0)
                            continuation.resume()
                        }
                    } else {
                        queue.async {
                            continuation.resume(throwing: VideoProcessingError.exportFailed)
                        }
                    }
                } else {
                    // 读取错误信息
                    let finalErrorData = errorHandle.readDataToEndOfFile()
                    let errorMessage = String(data: finalErrorData, encoding: .utf8) ?? "未知错误"
                    
                    queue.async {
                        continuation.resume(throwing: VideoProcessingError.exportFailed)
                    }
                }
            }
        }
    }
    
    /// 解析 ffmpeg 进度字符串
    /// - Parameters:
    ///   - timeString: 时间字符串，格式如 "time=00:01:23.45"
    ///   - totalDuration: 视频总时长（秒）
    /// - Returns: 进度值（0.0 - 1.0），如果无法解析则返回 nil
    private static func parseFFmpegProgress(timeString: String, totalDuration: Double) -> Double? {
        guard totalDuration > 0 else { return nil }
        
        // 提取时间值：time=00:01:23.45 -> 00:01:23.45
        guard let timeRange = timeString.range(of: #"(\d{2}):(\d{2}):(\d{2})\.(\d{2})"#, options: .regularExpression) else {
            return nil
        }
        
        let timeValue = String(timeString[timeRange])
        let components = timeValue.split(separator: ":")
        guard components.count == 3 else { return nil }
        
        // 解析小时、分钟、秒
        guard let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]) else {
            return nil
        }
        
        let currentSeconds = hours * 3600 + minutes * 60 + seconds
        let progress = min(currentSeconds / totalDuration, 1.0)
        
        return progress
    }
}

