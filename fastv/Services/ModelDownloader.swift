//
//  ModelDownloader.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import Combine

/// 模型下载器
@MainActor
class ModelDownloader: ObservableObject {
    static let shared = ModelDownloader()
    
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatus: String = ""
    @Published var downloadSpeed: String = ""
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var error: Error?
    
    private var downloadTask: URLSessionDownloadTask?
    private var speedTimer: Timer?
    private var lastDownloadedBytes: Int64 = 0
    private var lastSpeedCheckTime: Date = Date()
    
    private init() {}
    
    /// 下载模型文件（支持断点续传和速度显示）
    func downloadModel(baseURL: String, progressHandler: @escaping (Double, String, String) -> Void) async throws {
        isDownloading = true
        downloadProgress = 0.0
        downloadStatus = NSLocalizedString("model.download.status.preparing", comment: "")
        downloadSpeed = ""
        downloadedBytes = 0
        totalBytes = 0
        error = nil
        
        defer {
            isDownloading = false
            speedTimer?.invalidate()
            speedTimer = nil
        }
        
        guard let url = URL(string: baseURL) else {
            throw ModelDownloadError.invalidURL
        }
        
        // 获取模型目录
        let modelDir = getModelDirectory()
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        
        // 只下载 model.onnx 文件（894MB）
        let filename = "model.onnx"
        let fileSizeMB = 894.0
        let destinationURL = modelDir.appendingPathComponent(filename)
        
        // 检查文件是否已存在
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let existsFormat = NSLocalizedString("model.download.already.exists", comment: "")
            downloadStatus = existsFormat.replacingOccurrences(of: "%@", with: filename)
            downloadProgress = 1.0
            UserPreferences.shared.modelDownloaded = true
            return
        }
        
        downloadStatus = String(format: NSLocalizedString("model.download.status.downloading", comment: ""), filename, 0).replacingOccurrences(of: "%@", with: filename).replacingOccurrences(of: "%d", with: "0")
        
        do {
            // 创建下载任务（支持断点续传）
            let (localURL, _) = try await downloadFileWithProgress(
                from: url,
                to: destinationURL,
                progressHandler: { [weak self] fileProgress, speed in
                    guard let self = self else { return }
                    self.downloadProgress = fileProgress
                    let statusFormat = NSLocalizedString("model.download.status.downloading", comment: "")
                    self.downloadStatus = statusFormat.replacingOccurrences(of: "%@", with: filename).replacingOccurrences(of: "%d", with: "\(Int(fileProgress * 100))")
                    self.downloadSpeed = speed
                    progressHandler(fileProgress, self.downloadStatus, speed)
                }
            )
            
            // 确保目标目录存在
            let destinationDir = destinationURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: destinationDir.path) {
                try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            }
            
            // 检查临时文件是否存在
            guard FileManager.default.fileExists(atPath: localURL.path) else {
                throw ModelDownloadError.downloadFailed(NSLocalizedString("model.download.error.temp.file.not.found", comment: ""))
            }
            
            // 移动文件到目标位置
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: localURL, to: destinationURL)
            
            downloadProgress = 1.0
            let completeFormat = NSLocalizedString("model.download.status.complete", comment: "")
            downloadStatus = completeFormat.replacingOccurrences(of: "%@", with: filename)
        } catch {
            let failedFormat = NSLocalizedString("model.download.status.failed", comment: "")
            downloadStatus = failedFormat.replacingOccurrences(of: "%@", with: filename).replacingOccurrences(of: "%@", with: error.localizedDescription)
            throw ModelDownloadError.downloadFailed(error.localizedDescription)
        }
        
        downloadProgress = 1.0
        downloadStatus = NSLocalizedString("model.download.status.all.complete", comment: "")
        downloadSpeed = ""
        
        // 标记模型已下载
        UserPreferences.shared.modelDownloaded = true
    }
    
    /// 下载文件（带进度和速度）
    private func downloadFileWithProgress(
        from url: URL,
        to destinationURL: URL,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> (URL, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            // 创建一个临时文件路径用于保存下载的文件
            let tempDir = FileManager.default.temporaryDirectory
            let tempFileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("onnx")
            
            let delegate = DownloadTaskDelegate(
                destinationURL: destinationURL,
                tempFileURL: tempFileURL,
                progress: { [weak self] progress, _ in
                    guard let self = self else { return }
                    // 使用定时器更新速度
                    progressHandler(progress, self.downloadSpeed)
                },
                completion: { result in
                    continuation.resume(with: result)
                }
            )
            
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            downloadTask = task
            
            // 初始化速度跟踪
            lastDownloadedBytes = 0
            lastSpeedCheckTime = Date()
            
            // 启动速度计时器（在主线程）
            speedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                let now = Date()
                let timeInterval = now.timeIntervalSince(self.lastSpeedCheckTime)
                if timeInterval > 0 {
                    let currentBytes = delegate.totalBytesWritten
                    let bytesDiff = currentBytes - self.lastDownloadedBytes
                    let speed = Double(bytesDiff) / timeInterval
                    let speedString = self.formatSpeed(bytesPerSecond: speed)
                    self.downloadSpeed = speedString
                    self.lastDownloadedBytes = currentBytes
                    self.lastSpeedCheckTime = now
                }
            }
            RunLoop.main.add(speedTimer!, forMode: .common)
            
            task.resume()
        }
    }
    
    /// 格式化速度
    private func formatSpeed(bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        } else if bytesPerSecond >= 1_000 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1_000)
        } else {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }
    
    /// 取消下载
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        speedTimer?.invalidate()
        speedTimer = nil
    }
    
    /// 获取模型目录
    private func getModelDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent(NSLocalizedString("app.name", comment: ""))
        return appDir.appendingPathComponent("Models/sensevoice-small")
    }
    
    /// 检查模型文件是否存在（只检查 model.onnx）
    func checkModelFilesExist() -> Bool {
        let modelDir = getModelDirectory()
        let modelFileURL = modelDir.appendingPathComponent("model.onnx")
        return FileManager.default.fileExists(atPath: modelFileURL.path)
    }
}

/// 下载任务代理
class DownloadTaskDelegate: NSObject, URLSessionDownloadDelegate {
    var totalBytesWritten: Int64 = 0
    var totalBytesExpected: Int64 = 0
    var progressHandler: ((Double, String) -> Void)?
    var speedUpdateHandler: ((String) -> Void)?
    var completionHandler: ((Result<(URL, URLResponse), Error>) -> Void)?
    
    private let destinationURL: URL
    private let tempFileURL: URL
    
    init(
        destinationURL: URL,
        tempFileURL: URL,
        progress: @escaping (Double, String) -> Void,
        completion: @escaping (Result<(URL, URLResponse), Error>) -> Void
    ) {
        self.destinationURL = destinationURL
        self.tempFileURL = tempFileURL
        self.progressHandler = progress
        self.completionHandler = completion
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        self.totalBytesWritten = totalBytesWritten
        self.totalBytesExpected = totalBytesExpectedToWrite
        
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
        progressHandler?(progress, "")
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // URLSession 下载完成后，文件在临时位置，需要立即复制到安全位置
        // 因为 session 结束后，临时文件可能被系统删除
        let downloadedFileURL = location
        
        // 检查下载的文件是否存在
        guard FileManager.default.fileExists(atPath: downloadedFileURL.path) else {
            completionHandler?(.failure(ModelDownloadError.downloadFailed(NSLocalizedString("model.download.error.temp.file.not.found", comment: ""))))
            return
        }
        
        do {
            // 将下载的文件复制到临时位置（避免被系统删除）
            // 删除已存在的临时文件（如果有）
            if FileManager.default.fileExists(atPath: tempFileURL.path) {
                try FileManager.default.removeItem(at: tempFileURL)
            }
            
            // 复制文件到临时位置
            try FileManager.default.copyItem(at: downloadedFileURL, to: tempFileURL)
            
            if let response = downloadTask.response {
                completionHandler?(.success((tempFileURL, response)))
            } else {
                completionHandler?(.failure(ModelDownloadError.downloadFailed(NSLocalizedString("model.download.error", comment: ""))))
            }
        } catch {
            print("❌ [ModelDownloader] 复制临时文件失败: \(error.localizedDescription)")
            completionHandler?(.failure(ModelDownloadError.downloadFailed(error.localizedDescription)))
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completionHandler?(.failure(error))
        }
    }
}

/// 模型下载错误
enum ModelDownloadError: LocalizedError {
    case invalidURL
    case downloadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("model.download.error.invalid.url", comment: "")
        case .downloadFailed(let message):
            let errorFormat = NSLocalizedString("model.download.error", comment: "")
            return errorFormat.replacingOccurrences(of: "%@", with: message)
        }
    }
}
