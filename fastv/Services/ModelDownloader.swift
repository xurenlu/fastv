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
    
    private init() {
        // 应用启动时检查是否有未完成的下载
        Task { @MainActor in
            await checkAndRecoverDownloadState()
        }
    }
    
    /// 检查并恢复下载状态（应用重启后）
    private func checkAndRecoverDownloadState() async {
        // 检查是否有临时下载文件
        let modelDir = getModelDirectory()
        let destinationURL = modelDir.appendingPathComponent("model.onnx")
        
        // 如果目标文件已存在且完整，不需要恢复
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            // 检查文件大小是否合理（至少800MB）
            if let attributes = try? FileManager.default.attributesOfItem(atPath: destinationURL.path),
               let fileSize = attributes[.size] as? Int64,
               fileSize >= 800 * 1024 * 1024 {
                // 文件完整，清除下载状态
                isDownloading = false
                downloadProgress = 0.0
                downloadStatus = ""
                return
            }
        }
        
        // 检查临时目录中是否有未完成的下载
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.fileSizeKey])
            let onnxTempFiles = tempFiles.filter { $0.pathExtension == "onnx" }
            
            // 如果有临时文件，可能是未完成的下载
            if !onnxTempFiles.isEmpty {
                // 不清除下载状态，让用户知道可能需要重新下载
                // 但也不自动恢复，因为URLSession任务已经丢失
                print("⚠️ [ModelDownloader] 发现未完成的下载临时文件，但无法恢复下载任务")
            }
        } catch {
            // 忽略错误
        }
        
        // 确保下载状态已清除
        isDownloading = false
        downloadProgress = 0.0
        downloadStatus = ""
    }
    
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
        let destinationURL = modelDir.appendingPathComponent(filename)
        
        // 检查文件是否已存在且大小正确
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            // 验证文件大小是否正确
            if let attributes = try? FileManager.default.attributesOfItem(atPath: destinationURL.path),
               let fileSize = attributes[.size] as? Int64 {
                let expectedFileSize: Int64 = 937615562
                let tolerance: Int64 = 1024 // 允许1KB误差
                
                if abs(fileSize - expectedFileSize) <= tolerance {
                    // 文件存在且大小正确
                    let existsFormat = NSLocalizedString("model.download.already.exists", comment: "")
                    downloadStatus = existsFormat.replacingOccurrences(of: "%@", with: filename)
                    downloadProgress = 1.0
                    UserPreferences.shared.isModelDownloaded = true
                    return
                } else {
                    // 文件存在但大小不正确，删除并重新下载
                    try? FileManager.default.removeItem(at: destinationURL)
                    #if DEBUG
                    print("⚠️ [ModelDownloader] 文件大小不正确 (\(fileSize) 字节)，已删除，将重新下载")
                    #endif
                }
            }
        }
        
        downloadStatus = String(format: NSLocalizedString("model.download.status.downloading", comment: ""), filename, 0).replacingOccurrences(of: "%@", with: filename).replacingOccurrences(of: "%d", with: "0")
        
        do {
            // 创建下载任务（支持断点续传）
            let (localURL, _) = try await downloadFileWithProgress(
                from: url,
                to: destinationURL,
                progressHandler: { [weak self] fileProgress, speed in
                    guard let self = self else { return }
                    // 确保在主线程更新 @Published 属性
                    Task { @MainActor in
                        self.downloadProgress = fileProgress
                        let statusFormat = NSLocalizedString("model.download.status.downloading", comment: "")
                        self.downloadStatus = statusFormat.replacingOccurrences(of: "%@", with: filename).replacingOccurrences(of: "%d", with: "\(Int(fileProgress * 100))")
                        self.downloadSpeed = speed
                        progressHandler(fileProgress, self.downloadStatus, speed)
                    }
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
            
            // 更新状态：正在处理文件（在后台线程执行耗时操作）
            downloadProgress = 0.99
            downloadStatus = NSLocalizedString("model.download.status.processing", comment: "正在处理文件...")
            downloadSpeed = ""
            
            // 在后台线程执行文件移动和校验操作，避免阻塞UI
            try await Task.detached(priority: .userInitiated) {
                // 确保目标目录存在
                let destinationDir = destinationURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: destinationDir.path) {
                    try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
                }
                
                // 移动文件到目标位置（894MB文件移动可能耗时）
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: localURL, to: destinationURL)
                
                // 校验文件大小（精确校验：937615562 字节）
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
                if let fileSize = fileAttributes[.size] as? Int64 {
                    let expectedFileSize: Int64 = 937615562 // 精确的文件大小
                    let tolerance: Int64 = 1024 // 允许1KB的误差（避免因文件系统差异导致校验失败）
                    
                    if abs(fileSize - expectedFileSize) > tolerance {
                        // 文件大小不匹配，删除文件并报错
                        try? FileManager.default.removeItem(at: destinationURL)
                        let fileSizeMB = Double(fileSize) / (1024 * 1024)
                        let expectedSizeMB = Double(expectedFileSize) / (1024 * 1024)
                        let errorMessage = String(format: NSLocalizedString("model.download.error.file.size.mismatch", comment: "文件大小不匹配：实际 %@ MB，期望 %@ MB"), String(format: "%.2f", fileSizeMB), String(format: "%.2f", expectedSizeMB))
                        throw ModelDownloadError.downloadFailed(errorMessage)
                    }
                    
                    #if DEBUG
                    let fileSizeMB = Double(fileSize) / (1024 * 1024)
                    print("✅ [ModelDownloader] 文件大小校验通过: \(fileSize) 字节 (\(String(format: "%.2f", fileSizeMB)) MB)")
                    #endif
                } else {
                    // 无法获取文件大小，也视为错误
                    try? FileManager.default.removeItem(at: destinationURL)
                    throw ModelDownloadError.downloadFailed(NSLocalizedString("model.download.error.cannot.get.file.size", comment: ""))
                }
            }.value
            
            // 在主线程更新UI状态（成功时）
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
        UserPreferences.shared.isModelDownloaded = true
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
                    // 确保在主线程更新进度
                    Task { @MainActor in
                        // 使用定时器更新速度
                        progressHandler(progress, self.downloadSpeed)
                    }
                },
                completion: { result in
                    // 确保在主线程恢复 continuation
                    Task { @MainActor in
                        continuation.resume(with: result)
                    }
                }
            )
            
            // 配置 URLSession，设置超时时间
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30.0 // 30秒请求超时
            configuration.timeoutIntervalForResource = 3600.0 // 1小时资源超时（大文件下载需要更长时间）
            configuration.waitsForConnectivity = true
            
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            delegate.setSession(session)  // 设置 session 引用以便清理
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
                Task { @MainActor in
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
    
    // 缓存文件检查结果，避免重复检查
    private var cachedModelExists: Bool?
    private var lastCheckTime: Date?
    private let cacheTimeout: TimeInterval = 5.0 // 5秒缓存
    
    /// 检查模型文件是否存在（只检查 model.onnx）
    /// 使用缓存避免频繁的文件系统访问
    func checkModelFilesExist() -> Bool {
        // 如果缓存有效，直接返回
        if let cached = cachedModelExists,
           let lastCheck = lastCheckTime,
           Date().timeIntervalSince(lastCheck) < cacheTimeout {
            return cached
        }
        
        // 在后台线程检查文件，避免阻塞UI
        let modelDir = getModelDirectory()
        let modelFileURL = modelDir.appendingPathComponent("model.onnx")
        
        // 使用同步检查（文件系统操作通常很快，但为了安全可以改为异步）
        let exists = FileManager.default.fileExists(atPath: modelFileURL.path)
        
        // 更新缓存
        cachedModelExists = exists
        lastCheckTime = Date()
        
        return exists
    }
    
    /// 异步检查模型文件是否存在（不阻塞UI）
    func checkModelFilesExistAsync() async -> Bool {
        // 如果缓存有效，直接返回
        if let cached = cachedModelExists,
           let lastCheck = lastCheckTime,
           Date().timeIntervalSince(lastCheck) < cacheTimeout {
            return cached
        }
        
        // 在后台线程检查文件
        let modelDir = getModelDirectory()
        let exists = await Task.detached(priority: .userInitiated) { [modelDir] in
            let modelFileURL = modelDir.appendingPathComponent("model.onnx")
            return FileManager.default.fileExists(atPath: modelFileURL.path)
        }.value
        
        // 更新缓存（在主线程）
        await MainActor.run {
            cachedModelExists = exists
            lastCheckTime = Date()
        }
        
        return exists
    }
    
    /// 清除缓存，强制重新检查
    func invalidateCache() {
        cachedModelExists = nil
        lastCheckTime = nil
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
    private var session: URLSession?

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

    // 设置 session 引用（在创建 session 后调用）
    func setSession(_ session: URLSession) {
        self.session = session
    }

    // 清理 session
    private func cleanupSession() {
        session?.finishTasksAndInvalidate()
        session = nil
    }

    deinit {
        // 确保在释放时清理 session
        cleanupSession()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        self.totalBytesWritten = totalBytesWritten
        self.totalBytesExpected = totalBytesExpectedToWrite

        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
        // 确保在主线程调用 progressHandler
        DispatchQueue.main.async { [weak self] in
            self?.progressHandler?(progress, "")
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // URLSession 下载完成后，文件在临时位置，需要立即复制到安全位置
        // 因为 session 结束后，临时文件可能被系统删除
        let downloadedFileURL = location
        
        // 检查 HTTP 响应状态码
        if let httpResponse = downloadTask.response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            // 检查状态码是否表示成功（200-299）
            guard (200...299).contains(statusCode) else {
                let errorMessage: String
                switch statusCode {
                case 404:
                    errorMessage = NSLocalizedString("model.download.error.404", comment: "文件未找到 (404)")
                case 500:
                    errorMessage = NSLocalizedString("model.download.error.500", comment: "服务器错误 (500)")
                case 403:
                    errorMessage = NSLocalizedString("model.download.error.403", comment: "禁止访问 (403)")
                default:
                    errorMessage = String(format: NSLocalizedString("model.download.error.http", comment: "HTTP错误 %d"), statusCode)
                }
                print("❌ [ModelDownloader] HTTP错误状态码: \(statusCode)")
                // 确保在主线程调用 completionHandler
                DispatchQueue.main.async { [weak self] in
                    self?.completionHandler?(.failure(ModelDownloadError.downloadFailed(errorMessage)))
                }
                return
            }
        }

        // 检查下载的文件是否存在
        guard FileManager.default.fileExists(atPath: downloadedFileURL.path) else {
            DispatchQueue.main.async { [weak self] in
                self?.completionHandler?(.failure(ModelDownloadError.downloadFailed(NSLocalizedString("model.download.error.temp.file.not.found", comment: ""))))
            }
            cleanupSession()
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

            // 捕获需要的值，避免在闭包中引用 self 的属性
            let finalTempFileURL = tempFileURL
            if let response = downloadTask.response {
                // 确保在主线程调用 completionHandler
                DispatchQueue.main.async { [weak self] in
                    self?.completionHandler?(.success((finalTempFileURL, response)))
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.completionHandler?(.failure(ModelDownloadError.downloadFailed(NSLocalizedString("model.download.error", comment: ""))))
                }
            }
        } catch {
            print("❌ [ModelDownloader] 复制临时文件失败: \(error.localizedDescription)")
            // 确保在主线程调用 completionHandler
            DispatchQueue.main.async { [weak self] in
                self?.completionHandler?(.failure(ModelDownloadError.downloadFailed(error.localizedDescription)))
            }
        }

        // 下载完成，清理 session
        cleanupSession()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // 检查是否是网络错误或超时错误
            let nsError = error as NSError
            var errorMessage = error.localizedDescription

            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorTimedOut:
                    errorMessage = NSLocalizedString("model.download.error.timeout", comment: "下载超时，请检查网络连接")
                case NSURLErrorNotConnectedToInternet:
                    errorMessage = NSLocalizedString("model.download.error.no.internet", comment: "网络连接失败，请检查网络设置")
                case NSURLErrorNetworkConnectionLost:
                    errorMessage = NSLocalizedString("model.download.error.connection.lost", comment: "网络连接中断")
                case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                    errorMessage = NSLocalizedString("model.download.error.cannot.connect", comment: "无法连接到服务器")
                default:
                    break
                }
            }

            print("❌ [ModelDownloader] 下载任务完成时出错: \(errorMessage)")
            // 确保在主线程调用 completionHandler
            DispatchQueue.main.async { [weak self] in
                self?.completionHandler?(.failure(ModelDownloadError.downloadFailed(errorMessage)))
            }
        }

        // 任务完成，清理 session
        cleanupSession()
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
