//
//  DiarizationServiceManager.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import AppKit
import Darwin
import Combine

/// 服务状态
enum DiarizationServiceStatus {
    case stopped
    case starting
    case running
    case error(String)
}

/// 说话人分离服务管理器
/// 负责自动启动、监控和管理 Python 服务
/// 
/// @deprecated 此功能已废弃。说话人分离服务现在需要用户自行部署，Mac app 通过配置的服务地址调用。
/// 请使用独立部署的 Python 服务，并通过 UserPreferences.diarizationServiceURL 配置服务地址。
@available(*, deprecated, message: "说话人分离服务现在需要用户自行部署，请使用独立部署的 Python 服务")
@MainActor
class DiarizationServiceManager: ObservableObject {
    static let shared = DiarizationServiceManager()
    
    private var serviceProcess: Process?
    @Published private(set) var status: DiarizationServiceStatus = .stopped
    @Published private(set) var isModelLoaded: Bool = false
    private let serviceURL = URL(string: "http://127.0.0.1:50001")!
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 2.0
    private var healthCheckTask: Task<Void, Never>?
    
    private init() {
        // 启动定期健康检查
        startHealthCheck()
    }
    
    /// 服务是否正在运行
    var isServiceRunning: Bool {
        if case .running = status {
            return true
        }
        return false
    }
    
    /// 手动启动服务（公开方法）
    func startServiceManually() async throws {
        if isServiceRunning {
            return
        }
        
        status = .starting
        try await startService()
        try await waitForServiceReady()
    }
    
    /// 手动停止服务（公开方法）
    func stopServiceManually() {
        stopService()
    }
    
    /// 确保服务正在运行（内部方法，用于自动启动）
    func ensureServiceRunning() async throws {
        // 如果服务已经在运行，检查健康状态
        if isServiceRunning {
            let (isHealthy, modelLoaded) = await checkServiceHealth()
            if isHealthy {
                isModelLoaded = modelLoaded
                return
            }
        }
        
        // 停止旧进程（如果有）
        stopService()
        
        // 启动服务
        try await startService()
        
        // 等待服务就绪
        try await waitForServiceReady()
    }
    
    /// 启动服务
    private func startService() async throws {
        print("🚀 [DiarizationServiceManager] 启动说话人分离服务...")
        status = .starting
        
        // 获取脚本路径
        guard let scriptPath = getServiceScriptPath() else {
            let errorMsg = "找不到说话人分离服务脚本。请确保 SpeakerDiarization/start_diarization_service.sh 文件存在。"
            print("❌ [DiarizationServiceManager] \(errorMsg)")
            status = .error(errorMsg)
            throw DiarizationServiceError.scriptNotFound
        }
        
        // 创建进程
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        
        // 设置环境变量
        var environment = ProcessInfo.processInfo.environment
        // 设置代理（如果需要）
        environment["https_proxy"] = "http://127.0.0.1:7890"
        environment["http_proxy"] = "http://127.0.0.1:7890"
        environment["all_proxy"] = "socks5://127.0.0.1:7890"
        process.environment = environment
        
        // 设置输出重定向（用于调试和错误诊断）
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // 异步读取输出（用于调试）
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        
        // 设置非阻塞读取
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    print("📝 [DiarizationService] \(output)", terminator: "")
                }
            }
        }
        
        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let error = String(data: data, encoding: .utf8) {
                    print("❌ [DiarizationService] \(error)", terminator: "")
                }
            }
        }
        
        // 启动进程
        do {
            try process.run()
            self.serviceProcess = process
            status = .starting
            
            print("✅ [DiarizationServiceManager] 服务进程已启动 (PID: \(process.processIdentifier))")
            print("📝 [DiarizationServiceManager] 脚本路径: \(scriptPath)")
            
            // 等待一小段时间，检查进程是否立即退出
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
            
            if !process.isRunning {
                // 读取剩余的错误输出
                let errorData = errorHandle.readDataToEndOfFile()
                let outputData = outputHandle.readDataToEndOfFile()
                
                var errorMessage = "服务进程已退出"
                if let errorStr = String(data: errorData, encoding: .utf8), !errorStr.isEmpty {
                    errorMessage += ": \(errorStr)"
                } else if let outputStr = String(data: outputData, encoding: .utf8), !outputStr.isEmpty {
                    errorMessage += ": \(outputStr)"
                }
                
                print("❌ [DiarizationServiceManager] \(errorMessage)")
                status = .error(errorMessage)
                throw DiarizationServiceError.startFailed(errorMessage)
            }
        } catch {
            print("❌ [DiarizationServiceManager] 启动服务失败: \(error)")
            status = .error(error.localizedDescription)
            throw DiarizationServiceError.startFailed(error.localizedDescription)
        }
    }
    
    /// 等待服务就绪
    private func waitForServiceReady() async throws {
        print("⏳ [DiarizationServiceManager] 等待服务就绪...")
        
        // 首次启动可能需要更长时间（下载模型等），增加重试次数和等待时间
        let extendedMaxRetries = 10 // 增加到 10 次
        let extendedRetryDelay: TimeInterval = 3.0 // 增加到 3 秒
        
        for attempt in 1...extendedMaxRetries {
            // 检查进程是否还在运行
            if let process = serviceProcess, !process.isRunning {
                let errorMsg = "服务进程已退出（可能在启动过程中出错）"
                print("❌ [DiarizationServiceManager] \(errorMsg)")
                status = .error(errorMsg)
                throw DiarizationServiceError.serviceNotReady(errorMsg)
            }
            
            let (isHealthy, modelLoaded) = await checkServiceHealth()
            if isHealthy {
                print("✅ [DiarizationServiceManager] 服务已就绪")
                status = .running
                isModelLoaded = modelLoaded
                return
            }
            
            if attempt < extendedMaxRetries {
                print("⏳ [DiarizationServiceManager] 服务未就绪，等待 \(extendedRetryDelay) 秒后重试 (\(attempt)/\(extendedMaxRetries))...")
                if attempt <= 3 {
                    print("💡 [DiarizationServiceManager] 提示：首次启动可能需要下载模型（约 500MB），请耐心等待...")
                }
                try await Task.sleep(nanoseconds: UInt64(extendedRetryDelay * 1_000_000_000))
            }
        }
        
        // 检查进程状态
        if let process = serviceProcess, process.isRunning {
            status = .error("服务进程在运行但无法连接（可能端口被占用或服务启动失败）")
        } else {
            status = .error("服务进程已退出")
        }
        throw DiarizationServiceError.serviceNotReady("服务在 \(extendedMaxRetries) 次尝试后仍未就绪")
    }
    
    /// 检查服务健康状态
    private func checkServiceHealth() async -> (Bool, Bool) {
        guard let url = URL(string: "\(serviceURL)/health") else {
            return (false, false)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, false)
            }
            
            if httpResponse.statusCode == 200 {
                // 解析响应，检查模型是否已加载
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let modelLoaded = json["model_loaded"] as? Bool {
                    return (true, modelLoaded)
                }
                return (true, false)
            }
            return (false, false)
        } catch {
            return (false, false)
        }
    }
    
    /// 启动定期健康检查
    private func startHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 每5秒检查一次
                
                if case .running = status {
                    let (isHealthy, modelLoaded) = await checkServiceHealth()
                    if !isHealthy {
                        status = .stopped
                        isModelLoaded = false
                    } else {
                        isModelLoaded = modelLoaded
                    }
                }
            }
        }
    }
    
    /// 停止服务
    func stopService() {
        guard let process = serviceProcess, process.isRunning else {
            status = .stopped
            isModelLoaded = false
            return
        }
        
        print("🛑 [DiarizationServiceManager] 停止服务...")
        status = .stopped
        process.terminate()
        
        // 等待进程结束（最多等待 5 秒）
        // 使用异步方式等待，避免阻塞线程
        let timeout: TimeInterval = 5.0
        
        // 使用 RunLoop 而不是 Thread.sleep，避免阻塞
        let runLoop = RunLoop.current
        let timeoutDate = Date(timeIntervalSinceNow: timeout)
        
        while process.isRunning && Date() < timeoutDate {
            runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
        
        // 如果还在运行，强制终止
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        
        serviceProcess = nil
        isModelLoaded = false
        print("✅ [DiarizationServiceManager] 服务已停止")
    }
    
    /// 获取服务脚本路径
    private func getServiceScriptPath() -> String? {
        var candidatePaths: [(String, String)] = [] // (路径, 描述)
        
        // 1. 从 Bundle 中查找（打包后的应用）
        if let bundlePath = Bundle.main.path(forResource: "start_diarization_service", ofType: "sh", inDirectory: "SpeakerDiarization") {
            candidatePaths.append((bundlePath, "Bundle 资源目录"))
        } else {
            candidatePaths.append(("Bundle.main.path(forResource:...) 返回 nil", "Bundle 资源目录（未找到）"))
        }
        
        // 2. 从 Bundle 的 resourceURL 查找
        if let resourceURL = Bundle.main.resourceURL {
            let scriptURL = resourceURL.appendingPathComponent("SpeakerDiarization/start_diarization_service.sh")
            candidatePaths.append((scriptURL.path, "Bundle resourceURL"))
        } else {
            candidatePaths.append(("Bundle.main.resourceURL 为 nil", "Bundle resourceURL（未找到）"))
        }
        
        // 3. 从可执行文件路径向上查找（开发环境）
        if let executablePath = Bundle.main.executablePath {
            var currentPath = (executablePath as NSString).deletingLastPathComponent
            // 向上查找最多 10 层
            for level in 0..<10 {
                let testPath = "\(currentPath)/SpeakerDiarization/start_diarization_service.sh"
                candidatePaths.append((testPath, "可执行文件路径向上 \(level) 层"))
                if FileManager.default.fileExists(atPath: testPath) {
                    break
                }
                let parent = (currentPath as NSString).deletingLastPathComponent
                if parent == currentPath {
                    break
                }
                currentPath = parent
            }
        } else {
            candidatePaths.append(("Bundle.main.executablePath 为 nil", "可执行文件路径（未找到）"))
        }
        
        // 4. 从当前工作目录查找（开发环境）
        let currentDirPath = "\(FileManager.default.currentDirectoryPath)/SpeakerDiarization/start_diarization_service.sh"
        candidatePaths.append((currentDirPath, "当前工作目录"))
        
        // 5. 从项目根目录查找（使用 findProjectRoot）
        if let projectRoot = findProjectRoot() {
            let scriptPath = "\(projectRoot)/SpeakerDiarization/start_diarization_service.sh"
            candidatePaths.append((scriptPath, "项目根目录"))
        } else {
            candidatePaths.append(("findProjectRoot() 返回 nil", "项目根目录（未找到）"))
        }
        
        // 6. 从应用支持目录查找
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "fastv"
            let scriptPath = appSupport.appendingPathComponent("\(appName)/SpeakerDiarization/start_diarization_service.sh").path
            candidatePaths.append((scriptPath, "应用支持目录"))
        }
        
        // 7. 从主目录查找（开发环境备用方案）
        let homePath = NSHomeDirectory()
        let homeScriptPath = "\(homePath)/Sites/fastv/SpeakerDiarization/start_diarization_service.sh"
        candidatePaths.append((homeScriptPath, "主目录备用路径"))
        
        // 打印所有尝试的路径（用于调试）
        print("🔍 [DiarizationServiceManager] 查找脚本路径，尝试了以下路径：")
        for (index, (path, description)) in candidatePaths.enumerated() {
            let exists = FileManager.default.fileExists(atPath: path)
            print("  \(index + 1). [\(description)] \(path) \(exists ? "✅" : "❌")")
        }
        
        // 返回第一个存在的路径
        if let foundPath = candidatePaths.first(where: { FileManager.default.fileExists(atPath: $0.0) })?.0 {
            print("✅ [DiarizationServiceManager] 找到脚本: \(foundPath)")
            return foundPath
        }
        
        print("❌ [DiarizationServiceManager] 未找到脚本文件")
        print("💡 [DiarizationServiceManager] 提示：请确保 SpeakerDiarization/start_diarization_service.sh 文件存在")
        return nil
    }
    
    /// 查找项目根目录
    private func findProjectRoot() -> String? {
        // 方法1: 从当前工作目录向上查找
        var currentPath = FileManager.default.currentDirectoryPath
        for _ in 0..<10 {
            let testPath = "\(currentPath)/SpeakerDiarization"
            if FileManager.default.fileExists(atPath: testPath) {
                return currentPath
            }
            
            let parent = (currentPath as NSString).deletingLastPathComponent
            if parent == currentPath {
                break
            }
            currentPath = parent
        }
        
        // 方法2: 从可执行文件路径向上查找
        if let executablePath = Bundle.main.executablePath {
            var currentPath = (executablePath as NSString).deletingLastPathComponent
            for _ in 0..<10 {
                let testPath = "\(currentPath)/SpeakerDiarization"
                if FileManager.default.fileExists(atPath: testPath) {
                    return currentPath
                }
                
                let parent = (currentPath as NSString).deletingLastPathComponent
                if parent == currentPath {
                    break
                }
                currentPath = parent
            }
        }
        
        // 方法3: 检查常见的开发路径
        let commonPaths = [
            NSHomeDirectory() + "/Sites/fastv",
            NSHomeDirectory() + "/Developer/fastv",
            "/Users/\(NSUserName())/Sites/fastv"
        ]
        
        for path in commonPaths {
            let testPath = "\(path)/SpeakerDiarization"
            if FileManager.default.fileExists(atPath: testPath) {
                return path
            }
        }
        
        return nil
    }
}

/// 服务管理器错误
enum DiarizationServiceError: LocalizedError {
    case scriptNotFound
    case startFailed(String)
    case serviceNotReady(String)
    
    var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            return "找不到说话人分离服务脚本"
        case .startFailed(let message):
            return "启动服务失败: \(message)"
        case .serviceNotReady(let message):
            return "服务未就绪: \(message)"
        }
    }
}

