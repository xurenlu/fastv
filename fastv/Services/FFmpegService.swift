//
//  FFmpegService.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import Foundation
import Combine

/// FFmpeg 服务 - 封装 FFmpeg 命令执行
struct FFmpegService {
    
    // MARK: - FFmpeg 检测
    
    /// 检测 FFmpeg 是否可用
    /// - Returns: (是否可用, 版本信息, 可执行文件路径)
    static func checkFFmpegAvailable() -> (available: Bool, version: String?, path: String?) {
        let preferences = UserPreferences.shared
        
        // 如果用户指定了路径，优先使用
        if !preferences.ffmpegPath.isEmpty {
            let customPath = preferences.ffmpegPath
            if FileManager.default.fileExists(atPath: customPath) {
                if let version = getFFmpegVersion(at: customPath) {
                    return (true, version, customPath)
                }
            }
        }
        
        // 尝试从 PATH 环境变量查找
        if let systemPath = findFFmpegInPATH() {
            if let version = getFFmpegVersion(at: systemPath) {
                return (true, version, systemPath)
            }
        }
        
        // 尝试常见安装路径
        let commonPaths = [
            "/usr/local/bin/ffmpeg",
            "/opt/homebrew/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                if let version = getFFmpegVersion(at: path) {
                    return (true, version, path)
                }
            }
        }
        
        return (false, nil, nil)
    }
    
    /// 从 PATH 环境变量查找 FFmpeg
    private static func findFFmpegInPATH() -> String? {
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = ["ffmpeg"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // 忽略错误
        }
        
        return nil
    }
    
    /// 获取 FFmpeg 版本信息
    private static func getFFmpegVersion(at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    // 提取版本号（第一行通常包含版本信息）
                    let lines = output.components(separatedBy: .newlines)
                    if let firstLine = lines.first, firstLine.contains("ffmpeg version") {
                        // 提取版本号，例如 "ffmpeg version 6.1.1"
                        let components = firstLine.components(separatedBy: " ")
                        if let versionIndex = components.firstIndex(of: "version"), versionIndex + 1 < components.count {
                            return components[versionIndex + 1]
                        }
                        return firstLine
                    }
                    // 如果没有找到版本信息，返回第一行
                    if let firstLine = lines.first {
                        return firstLine
                    }
                }
            }
        } catch {
            // 忽略错误
        }
        
        return nil
    }
    
    // MARK: - FFmpeg 命令执行
    
    /// 执行 FFmpeg 命令（兼容旧接口）
    /// - Parameters:
    ///   - arguments: FFmpeg 参数（不包含 ffmpeg 本身）
    ///   - progressHandler: 进度回调（0.0-1.0）
    ///   - outputHandler: 输出日志回调
    /// - Returns: 执行结果
    static func execute(
        arguments: [String],
        progressHandler: @escaping (Double, String) -> Void = { _, _ in },
        outputHandler: @escaping (String) -> Void = { _ in }
    ) async throws -> ProcessResult {
        return try await execute(
            arguments: arguments,
            totalDuration: nil,
            progressHandler: progressHandler,
            outputHandler: outputHandler
        )
    }
    
    /// 执行 FFmpeg 命令（带总时长，用于计算真实进度）
    /// - Parameters:
    ///   - arguments: FFmpeg 参数（不包含 ffmpeg 本身）
    ///   - totalDuration: 视频总时长（秒），用于计算进度百分比
    ///   - progressHandler: 进度回调（0.0-1.0, 状态描述）
    ///   - outputHandler: 输出日志回调
    /// - Returns: 执行结果
    static func execute(
        arguments: [String],
        totalDuration: TimeInterval?,
        progressHandler: @escaping (Double, String) -> Void = { _, _ in },
        outputHandler: @escaping (String) -> Void = { _ in }
    ) async throws -> ProcessResult {
        // 在后台线程执行，避免阻塞主线程
        return try await Task.detached(priority: .userInitiated) {
            let checkResult = checkFFmpegAvailable()
            guard checkResult.available, let ffmpegPath = checkResult.path else {
                throw FFmpegError.ffmpegNotFound
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = arguments
            
            // 设置环境变量（如果需要）
            let environment = ProcessInfo.processInfo.environment
            process.environment = environment
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            // 创建进度解析任务
            let progressTask = Task {
                await parseProgress(
                    from: errorPipe,
                    totalDuration: totalDuration,
                    progressHandler: progressHandler,
                    outputHandler: outputHandler
                )
            }
            
            do {
                try process.run()
                
                // 等待进程完成（在后台线程执行，不会阻塞主线程）
                process.waitUntilExit()
                
                // 取消进度解析任务
                progressTask.cancel()
                
                // 读取输出
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                
                if process.terminationStatus != 0 {
                    throw FFmpegError.executionFailed(
                        code: Int(process.terminationStatus),
                        message: errorOutput.isEmpty ? output : errorOutput
                    )
                }
                
                // 完成时发送 100% 进度
                await MainActor.run {
                    progressHandler(1.0, "处理完成")
                }
                
                return ProcessResult(
                    exitCode: Int(process.terminationStatus),
                    output: output,
                    errorOutput: errorOutput
                )
            } catch {
                progressTask.cancel()
                throw error
            }
        }.value
    }
    
    /// 解析 FFmpeg 进度输出
    /// - Parameters:
    ///   - pipe: FFmpeg 的 stderr 管道
    ///   - totalDuration: 视频总时长（秒），用于计算进度百分比
    ///   - progressHandler: 进度回调
    ///   - outputHandler: 输出日志回调
    private static func parseProgress(
        from pipe: Pipe,
        totalDuration: TimeInterval?,
        progressHandler: @escaping (Double, String) -> Void,
        outputHandler: @escaping (String) -> Void
    ) async {
        let fileHandle = pipe.fileHandleForReading
        
        // 在后台线程持续读取输出
        await Task.detached(priority: .userInitiated) {
            var buffer = Data()
            
            while !Task.isCancelled {
                // 使用同步方式读取可用数据
                let availableData = fileHandle.availableData
                if availableData.isEmpty {
                    // 如果没有数据，等待一小段时间
                    try? await Task.sleep(nanoseconds: VideoToolsConstants.progressUpdateInterval)
                    continue
                }
                
                buffer.append(availableData)
                
                // 按行处理数据（FFmpeg 使用 \r 更新同一行）
                if let text = String(data: buffer, encoding: .utf8) {
                    // FFmpeg 输出使用 \r 来更新进度行，需要同时处理 \r 和 \n
                    let lines = text.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
                    
                    // 保留最后一行（可能不完整）
                    if lines.count > 1 {
                        buffer = lines.last?.data(using: .utf8) ?? Data()
                        
                        // 处理完整的行
                        for i in 0..<(lines.count - 1) {
                            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                            if !line.isEmpty {
                                await MainActor.run {
                                    outputHandler(line)
                                    
                                    // 解析进度（FFmpeg 进度格式：frame= 1234 fps=30 ... time=00:00:05.00 bitrate=1234.5kbits/s speed=1.2x）
                                    if line.contains("time=") {
                                        // 提取时间信息并计算进度
                                        if let currentTime = parseTimeFromLine(line) {
                                            var progress = 0.0
                                            var statusMessage = ""
                                            
                                            // 如果有总时长，计算百分比
                                            if let total = totalDuration, total > 0 {
                                                progress = min(currentTime / total, 0.99) // 最大 99%，留给完成状态
                                                let percentage = Int(progress * 100)
                                                statusMessage = "处理中: \(percentage)%"
                                            } else {
                                                // 没有总时长，显示已处理时间
                                                statusMessage = "已处理: \(formatDuration(currentTime))"
                                            }
                                            
                                            // 提取速度信息
                                            if let speed = parseSpeedFromLine(line) {
                                                if let total = totalDuration, total > 0 {
                                                    let remaining = (total - currentTime) / speed
                                                    statusMessage += " | 速度: \(String(format: "%.1f", speed))x | 剩余: \(formatDuration(remaining))"
                                                } else {
                                                    statusMessage += " | 速度: \(String(format: "%.1f", speed))x"
                                                }
                                            }
                                            
                                            progressHandler(progress, statusMessage)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        // 只有一行，可能不完整，保留在 buffer 中
                        buffer = availableData
                    }
                }
            }
        }.value
    }
    
    /// 从 FFmpeg 输出行解析当前时间
    /// - Parameter line: FFmpeg 输出行，格式如 "time=00:01:23.45"
    /// - Returns: 时间（秒）
    private static func parseTimeFromLine(_ line: String) -> TimeInterval? {
        // 匹配 time=HH:MM:SS.ms 或 time=HH:MM:SS
        let pattern = #"time=(\d{2}):(\d{2}):(\d{2})(?:\.(\d{2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        
        guard let hoursRange = Range(match.range(at: 1), in: line),
              let minutesRange = Range(match.range(at: 2), in: line),
              let secondsRange = Range(match.range(at: 3), in: line) else {
            return nil
        }
        
        let hours = Double(line[hoursRange]) ?? 0
        let minutes = Double(line[minutesRange]) ?? 0
        let seconds = Double(line[secondsRange]) ?? 0
        
        var milliseconds: Double = 0
        if match.range(at: 4).location != NSNotFound,
           let msRange = Range(match.range(at: 4), in: line) {
            milliseconds = (Double(line[msRange]) ?? 0) / 100.0
        }
        
        return hours * 3600 + minutes * 60 + seconds + milliseconds
    }
    
    /// 从 FFmpeg 输出行解析处理速度
    /// - Parameter line: FFmpeg 输出行，格式如 "speed=1.23x"
    /// - Returns: 速度倍数
    private static func parseSpeedFromLine(_ line: String) -> Double? {
        let pattern = #"speed=\s*([\d.]+)x"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
              let speedRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return Double(line[speedRange])
    }
    
    /// 格式化时长为可读字符串
    /// - Parameter duration: 时长（秒）
    /// - Returns: 格式化的字符串，如 "01:23:45" 或 "23:45"
    private static func formatDuration(_ duration: TimeInterval) -> String {
        guard duration.isFinite && duration >= 0 else { return "--:--" }
        
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    // MARK: - 便捷方法
    
    /// 获取 FFmpeg 可执行路径
    static func getFFmpegPath() -> String? {
        let result = checkFFmpegAvailable()
        return result.path
    }
    
    /// 设置自定义 FFmpeg 路径
    static func setCustomFFmpegPath(_ path: String) {
        UserPreferences.shared.ffmpegPath = path
    }
}

// MARK: - 错误类型

enum FFmpegError: LocalizedError {
    case ffmpegNotFound
    case executionFailed(code: Int, message: String)
    case invalidArguments
    
    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "未找到 FFmpeg。请先安装 FFmpeg（例如：brew install ffmpeg）"
        case .executionFailed(let code, let message):
            return "FFmpeg 执行失败（退出码：\(code)）\n\(message)"
        case .invalidArguments:
            return "FFmpeg 参数无效"
        }
    }
}

// MARK: - 结果类型

struct ProcessResult {
    let exitCode: Int
    let output: String
    let errorOutput: String
}
