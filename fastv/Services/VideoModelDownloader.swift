//
//  VideoModelDownloader.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import Foundation
import Combine

/// 视频处理 AI 模型信息
struct VideoModelInfo: Equatable {
    let id: String
    let name: String
    let fileName: String
    let description: String
    let downloadURL: String // Hugging Face 或其他源 URL
    let expectedSize: Int64 // 预期文件大小（字节）
    let modelType: VideoModelType
    
    enum VideoModelType: Equatable {
        case yolo // YOLOv8 物体检测
        case faceDetection // SCRFD 人脸检测
    }
}

/// 视频模型下载器
@MainActor
class VideoModelDownloader: ObservableObject {
    static let shared = VideoModelDownloader()
    
    // 支持的模型列表
    static let availableModels: [VideoModelInfo] = [
        VideoModelInfo(
            id: "yolov8n",
            name: "YOLOv8n",
            fileName: "yolov8n.onnx",
            description: "YOLOv8 Nano - 物体检测模型（6MB）",
            downloadURL: "https://huggingface.co/onnx/models/resolve/main/yolov8n.onnx",
            expectedSize: 6_000_000, // 约 6MB
            modelType: .yolo
        ),
        VideoModelInfo(
            id: "scrfd_10g",
            name: "SCRFD 10G",
            fileName: "scrfd_10g_bnkps.onnx",
            description: "SCRFD 人脸检测模型（16MB）",
            downloadURL: "https://huggingface.co/onnx/models/resolve/main/scrfd_10g_bnkps.onnx",
            expectedSize: 16_000_000, // 约 16MB
            modelType: .faceDetection
        )
    ]
    
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatus: String = ""
    @Published var downloadSpeed: String = ""
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var currentModel: VideoModelInfo?
    @Published var error: Error?
    
    private var downloadTask: URLSessionDownloadTask?
    private var speedTimer: Timer?
    private var lastDownloadedBytes: Int64 = 0
    private var lastSpeedCheckTime: Date = Date()
    
    private init() {}
    
    /// 下载指定的模型
    func downloadModel(_ model: VideoModelInfo, progressHandler: @escaping (Double, String, String) -> Void) async throws {
        isDownloading = true
        downloadProgress = 0.0
        downloadStatus = "准备下载 \(model.name)..."
        downloadSpeed = ""
        downloadedBytes = 0
        totalBytes = 0
        error = nil
        currentModel = model
        
        defer {
            isDownloading = false
            speedTimer?.invalidate()
            speedTimer = nil
            currentModel = nil
        }
        
        guard let url = URL(string: model.downloadURL) else {
            throw VideoModelDownloadError.invalidURL
        }
        
        // 获取模型目录
        let modelDir = getModelDirectory(for: model)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        
        let destinationURL = modelDir.appendingPathComponent(model.fileName)
        
        // 检查文件是否已存在且大小正确
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: destinationURL.path),
               let fileSize = attributes[.size] as? Int64 {
                let tolerance: Int64 = 1024 * 1024 // 允许 1MB 误差
                
                if abs(fileSize - model.expectedSize) <= tolerance || fileSize >= model.expectedSize * 9 / 10 {
                    downloadStatus = "\(model.name) 已存在"
                    downloadProgress = 1.0
                    updateModelPath(model, path: destinationURL.path)
                    return
                } else {
                    // 文件存在但大小不正确，删除并重新下载
                    try? FileManager.default.removeItem(at: destinationURL)
                }
            }
        }
        
        downloadStatus = "正在下载 \(model.name)..."
        
        // 获取 Hugging Face Token（如果设置了）
        let preferences = UserPreferences.shared
        let token = preferences.huggingFaceToken.isEmpty ? nil : preferences.huggingFaceToken
        
        do {
            // 创建下载任务
            let (localURL, _) = try await downloadFileWithProgress(
                from: url,
                to: destinationURL,
                token: token,
                progressHandler: { [weak self] fileProgress, speed in
                    guard let self = self else { return }
                    Task { @MainActor in
                        self.downloadProgress = fileProgress
                        let percent = Int(fileProgress * 100)
                        self.downloadStatus = "正在下载 \(model.name)... \(percent)%"
                        self.downloadSpeed = speed
                        progressHandler(fileProgress, self.downloadStatus, speed)
                    }
                }
            )
            
            // 移动文件到目标位置
            let destinationDir = destinationURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: destinationDir.path) {
                try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            }
            
            guard FileManager.default.fileExists(atPath: localURL.path) else {
                throw VideoModelDownloadError.downloadFailed("临时文件未找到")
            }
            
            // 更新状态：正在处理文件
            downloadProgress = 0.99
            downloadStatus = "正在处理文件..."
            downloadSpeed = ""
            
            // 在后台线程执行文件移动
            try await Task.detached(priority: .userInitiated) {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: localURL, to: destinationURL)
            }.value
            
            // 更新模型路径
            updateModelPath(model, path: destinationURL.path)
            
            // 成功
            downloadProgress = 1.0
            downloadStatus = "\(model.name) 下载完成"
            downloadSpeed = ""
            
        } catch {
            downloadStatus = "下载失败: \(error.localizedDescription)"
            throw VideoModelDownloadError.downloadFailed(error.localizedDescription)
        }
    }
    
    /// 下载文件（带进度和速度）
    private func downloadFileWithProgress(
        from url: URL,
        to destinationURL: URL,
        token: String? = nil,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> (URL, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let tempDir = FileManager.default.temporaryDirectory
            let tempFileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("onnx")
            
            let delegate = VideoDownloadTaskDelegate(
                destinationURL: destinationURL,
                tempFileURL: tempFileURL,
                progress: { [weak self] progress, _ in
                    guard let self = self else { return }
                    Task { @MainActor in
                        progressHandler(progress, self.downloadSpeed)
                    }
                },
                completion: { result in
                    Task { @MainActor in
                        continuation.resume(with: result)
                    }
                }
            )
            
            // 创建 URLRequest 以支持自定义请求头
            var request = URLRequest(url: url)
            
            // 如果提供了 token，添加到请求头
            if let token = token, !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30.0
            configuration.timeoutIntervalForResource = 3600.0
            configuration.waitsForConnectivity = true
            
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: request)
            downloadTask = task
            
            // 初始化速度跟踪
            lastDownloadedBytes = 0
            lastSpeedCheckTime = Date()
            
            // 启动速度计时器
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
                        self.downloadedBytes = currentBytes
                        self.totalBytes = delegate.totalBytesExpected
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
    private func getModelDirectory(for model: VideoModelInfo) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("fastv")
        return appDir.appendingPathComponent("Models/video/\(model.id)")
    }
    
    /// 更新模型路径到 UserPreferences
    private func updateModelPath(_ model: VideoModelInfo, path: String) {
        let preferences = UserPreferences.shared
        switch model.modelType {
        case .yolo:
            preferences.videoYoloModelPath = path
        case .faceDetection:
            preferences.videoFaceModelPath = path
        }
        
        // 检查是否所有模型都已下载
        checkAllModelsDownloaded()
    }
    
    /// 检查所有模型是否已下载
    private func checkAllModelsDownloaded() {
        let preferences = UserPreferences.shared
        let allDownloaded = !preferences.videoYoloModelPath.isEmpty && !preferences.videoFaceModelPath.isEmpty
        preferences.isVideoModelsDownloaded = allDownloaded
    }
    
    /// 检查模型文件是否存在
    func checkModelExists(_ model: VideoModelInfo) -> Bool {
        let modelDir = getModelDirectory(for: model)
        let modelFileURL = modelDir.appendingPathComponent(model.fileName)
        return FileManager.default.fileExists(atPath: modelFileURL.path)
    }
    
    /// 获取模型文件路径
    func getModelPath(_ model: VideoModelInfo) -> URL? {
        let preferences = UserPreferences.shared
        let path: String
        
        switch model.modelType {
        case .yolo:
            path = preferences.videoYoloModelPath
        case .faceDetection:
            path = preferences.videoFaceModelPath
        }
        
        if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        
        // 如果用户未指定路径，检查默认位置
        let modelDir = getModelDirectory(for: model)
        let modelFileURL = modelDir.appendingPathComponent(model.fileName)
        if FileManager.default.fileExists(atPath: modelFileURL.path) {
            return modelFileURL
        }
        
        return nil
    }
}

/// 下载任务代理
class VideoDownloadTaskDelegate: NSObject, URLSessionDownloadDelegate {
    var totalBytesWritten: Int64 = 0
    var totalBytesExpected: Int64 = 0
    var progressHandler: ((Double, String) -> Void)?
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
        DispatchQueue.main.async { [weak self] in
            self?.progressHandler?(progress, "")
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let httpResponse = downloadTask.response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            guard (200...299).contains(statusCode) else {
                let errorMessage = "HTTP错误 \(statusCode)"
                DispatchQueue.main.async { [weak self] in
                    self?.completionHandler?(.failure(VideoModelDownloadError.downloadFailed(errorMessage)))
                }
                return
            }
        }
        
        guard FileManager.default.fileExists(atPath: location.path) else {
            DispatchQueue.main.async { [weak self] in
                self?.completionHandler?(.failure(VideoModelDownloadError.downloadFailed("临时文件未找到")))
            }
            return
        }
        
        do {
            let finalTempFileURL = self.tempFileURL
            if FileManager.default.fileExists(atPath: finalTempFileURL.path) {
                try FileManager.default.removeItem(at: finalTempFileURL)
            }
            
            try FileManager.default.copyItem(at: location, to: finalTempFileURL)
            
            if let response = downloadTask.response {
                DispatchQueue.main.async { [weak self] in
                    self?.completionHandler?(.success((finalTempFileURL, response)))
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.completionHandler?(.failure(VideoModelDownloadError.downloadFailed("下载失败")))
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.completionHandler?(.failure(VideoModelDownloadError.downloadFailed(error.localizedDescription)))
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError
            var errorMessage = error.localizedDescription
            
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorTimedOut:
                    errorMessage = "下载超时，请检查网络连接"
                case NSURLErrorNotConnectedToInternet:
                    errorMessage = "网络连接失败，请检查网络设置"
                case NSURLErrorNetworkConnectionLost:
                    errorMessage = "网络连接中断"
                default:
                    break
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.completionHandler?(.failure(VideoModelDownloadError.downloadFailed(errorMessage)))
            }
        }
    }
}

/// 视频模型下载错误
enum VideoModelDownloadError: LocalizedError {
    case invalidURL
    case downloadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的下载 URL"
        case .downloadFailed(let message):
            return "下载失败: \(message)"
        }
    }
}
