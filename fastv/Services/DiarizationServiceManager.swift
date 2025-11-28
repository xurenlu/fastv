//
//  DiarizationServiceManager.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import AppKit
import Darwin

/// 说话人分离服务管理器
/// 负责自动启动、监控和管理 Python 服务
@MainActor
class DiarizationServiceManager {
    static let shared = DiarizationServiceManager()
    
    private var serviceProcess: Process?
    private var isServiceRunning = false
    private let serviceURL = URL(string: "http://127.0.0.1:50001")!
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 2.0
    
    private init() {}
    
    /// 确保服务正在运行
    func ensureServiceRunning() async throws {
        // 如果服务已经在运行，检查健康状态
        if isServiceRunning {
            if await checkServiceHealth() {
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
        
        // 获取脚本路径
        guard let scriptPath = getServiceScriptPath() else {
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
        
        // 设置输出重定向（可选，用于调试）
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        
        // 启动进程
        do {
            try process.run()
            self.serviceProcess = process
            self.isServiceRunning = true
            
            print("✅ [DiarizationServiceManager] 服务进程已启动 (PID: \(process.processIdentifier))")
        } catch {
            print("❌ [DiarizationServiceManager] 启动服务失败: \(error)")
            throw DiarizationServiceError.startFailed(error.localizedDescription)
        }
    }
    
    /// 等待服务就绪
    private func waitForServiceReady() async throws {
        print("⏳ [DiarizationServiceManager] 等待服务就绪...")
        
        for attempt in 1...maxRetries {
            if await checkServiceHealth() {
                print("✅ [DiarizationServiceManager] 服务已就绪")
                return
            }
            
            if attempt < maxRetries {
                print("⏳ [DiarizationServiceManager] 服务未就绪，等待 \(retryDelay) 秒后重试 (\(attempt)/\(maxRetries))...")
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
        
        throw DiarizationServiceError.serviceNotReady("服务在 \(maxRetries) 次尝试后仍未就绪")
    }
    
    /// 检查服务健康状态
    private func checkServiceHealth() async -> Bool {
        guard let url = URL(string: "\(serviceURL)/health") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }
    
    /// 停止服务
    func stopService() {
        guard let process = serviceProcess, process.isRunning else {
            return
        }
        
        print("🛑 [DiarizationServiceManager] 停止服务...")
        process.terminate()
        
        // 等待进程结束（最多等待 5 秒）
        let timeout: TimeInterval = 5.0
        let startTime = Date()
        while process.isRunning && Date().timeIntervalSince(startTime) < timeout {
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // 如果还在运行，强制终止
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        
        serviceProcess = nil
        isServiceRunning = false
        print("✅ [DiarizationServiceManager] 服务已停止")
    }
    
    /// 获取服务脚本路径
    private func getServiceScriptPath() -> String? {
        // 尝试多个可能的路径
        let possiblePaths = [
            // 开发环境：项目根目录
            "\(FileManager.default.currentDirectoryPath)/SpeakerDiarization/start_diarization_service.sh",
            // 打包后：应用 Bundle 中
            Bundle.main.path(forResource: "start_diarization_service", ofType: "sh", inDirectory: "SpeakerDiarization"),
            // 打包后：应用支持目录
            {
                if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    return appSupport.appendingPathComponent("妙打/SpeakerDiarization/start_diarization_service.sh").path
                }
                return nil
            }()
        ]
        
        for path in possiblePaths {
            if let path = path, FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // 如果找不到，尝试从项目根目录查找
        if let projectRoot = findProjectRoot() {
            let scriptPath = "\(projectRoot)/SpeakerDiarization/start_diarization_service.sh"
            if FileManager.default.fileExists(atPath: scriptPath) {
                return scriptPath
            }
        }
        
        return nil
    }
    
    /// 查找项目根目录
    private func findProjectRoot() -> String? {
        var currentPath = FileManager.default.currentDirectoryPath
        
        // 向上查找，直到找到包含 SpeakerDiarization 目录的路径
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

