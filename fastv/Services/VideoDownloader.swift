//
//  VideoDownloader.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation

struct VideoDownloader {
    private static let apiURL = "https://auto-download-all-in-one.p.rapidapi.com/v1/social/autolink"
    private static let apiKey = "ab3c2f3997msha432a77d1e1afcdp1e54a7jsn791459b838a3"
    private static let apiHost = "auto-download-all-in-one.p.rapidapi.com"
    
    /// 从视频网站 URL 下载视频
    /// - Parameters:
    ///   - url: 视频网站 URL（如抖音、快手等）
    ///   - progressHandler: 下载进度回调 (0.0 - 1.0)
    /// - Returns: 下载后的本地视频文件 URL
    static func downloadVideo(
        from url: String,
        progressHandler: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        // 1. 调用 API 获取视频信息
        let videoInfo = try await getVideoInfo(from: url)
        
        // 2. 选择最佳质量的视频
        guard let videoURL = selectBestVideo(from: videoInfo) else {
            throw VideoProcessingError.downloadFailed("未找到可用的视频")
        }
        
        // 3. 下载视频到临时目录
        let localURL = try await downloadFile(
            from: videoURL,
            progressHandler: progressHandler
        )
        
        return localURL
    }
    
    /// 获取视频信息
    private static func getVideoInfo(from url: String) async throws -> VideoInfoResponse {
        guard let requestURL = URL(string: apiURL) else {
            throw VideoProcessingError.downloadFailed("无效的 API URL")
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-rapidapi-key")
        request.setValue(apiHost, forHTTPHeaderField: "x-rapidapi-host")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ["url": url]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VideoProcessingError.downloadFailed("无效的响应")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw VideoProcessingError.downloadFailed("API 请求失败: \(httpResponse.statusCode)")
        }
        
        let decoder = JSONDecoder()
        let videoInfo = try decoder.decode(VideoInfoResponse.self, from: data)
        
        guard !videoInfo.medias.isEmpty else {
            throw VideoProcessingError.downloadFailed("未找到视频媒体")
        }
        
        return videoInfo
    }
    
    /// 选择最佳质量的视频
    private static func selectBestVideo(from info: VideoInfoResponse) -> String? {
        let videos = info.medias.filter { $0.type == "video" }
        guard !videos.isEmpty else { return nil }
        
        // 优先选择分辨率最高的视频
        let sortedVideos = videos.sorted { video1, video2 in
            let width1 = video1.width ?? 0
            let width2 = video2.width ?? 0
            if width1 != width2 {
                return width1 > width2
            }
            // 如果宽度相同，比较带宽
            let bandwidth1 = video1.bandwidth ?? 0
            let bandwidth2 = video2.bandwidth ?? 0
            return bandwidth1 > bandwidth2
        }
        
        return sortedVideos.first?.url
    }
    
    /// 下载文件
    private static func downloadFile(
        from urlString: String,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw VideoProcessingError.downloadFailed("无效的视频 URL")
        }
        
        // 创建临时文件
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".mp4"
        let tempURL = tempDir.appendingPathComponent(fileName)
        
        // 先创建空文件
        FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
        
        // 下载文件
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw VideoProcessingError.downloadFailed("下载失败")
        }
        
        let contentLength = httpResponse.expectedContentLength
        let totalBytes = contentLength > 0 ? contentLength : nil
        
        // 创建文件并写入数据
        var fileHandle: FileHandle?
        do {
            fileHandle = try FileHandle(forWritingTo: tempURL)
        } catch {
            throw VideoProcessingError.downloadFailed("无法创建临时文件: \(error.localizedDescription)")
        }
        
        defer {
            try? fileHandle?.close()
        }
        
        guard let fileHandle = fileHandle else {
            throw VideoProcessingError.downloadFailed("无法创建文件句柄")
        }
        
        var downloadedBytes: Int64 = 0
        var buffer = Data()
        let bufferSize = 64 * 1024 // 64KB 缓冲区
        
        for try await byte in asyncBytes {
            buffer.append(byte)
            
            // 当缓冲区达到一定大小时，批量写入
            if buffer.count >= bufferSize {
                try fileHandle.write(contentsOf: buffer)
                downloadedBytes += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                
                if let totalBytes = totalBytes, totalBytes > 0 {
                    let progress = Double(downloadedBytes) / Double(totalBytes)
                    await MainActor.run {
                        progressHandler(min(progress, 1.0))
                    }
                }
            }
        }
        
        // 写入剩余数据
        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
            downloadedBytes += Int64(buffer.count)
        }
        
        // 确保进度完成
        await MainActor.run {
            progressHandler(1.0)
        }
        
        return tempURL
    }
}

// MARK: - API Response Models

struct VideoInfoResponse: Codable {
    let medias: [MediaInfo]
    let thumbnail: String?
    let title: String?
    let author: String?
    let duration: Int?
}

struct MediaInfo: Codable {
    let type: String
    let url: String
    let width: Int?
    let height: Int?
    let bandwidth: Int?
    let quality: String?
}

