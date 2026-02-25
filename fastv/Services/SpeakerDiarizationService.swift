//
//  SpeakerDiarizationService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation

/// 说话人片段
struct SpeakerSegment: Codable {
    let start: TimeInterval
    let end: TimeInterval
    let speaker: String
    let duration: TimeInterval
    
    enum CodingKeys: String, CodingKey {
        case start, end, speaker, duration
    }
}

/// 说话人分离响应
struct DiarizationResponse: Codable {
    let success: Bool
    let segments: [SpeakerSegment]
    let speakerCount: Int
    let totalSegments: Int
    
    enum CodingKeys: String, CodingKey {
        case success, segments
        case speakerCount = "speaker_count"
        case totalSegments = "total_segments"
    }
}

/// 说话人分离服务
@MainActor
class SpeakerDiarizationService {
    static let shared = SpeakerDiarizationService()
    
    private var apiEndpoint: String {
        UserPreferences.shared.diarizationServiceURL
    }
    private let preferences = UserPreferences.shared
    
    private init() {
        // 服务地址从 UserPreferences 读取
    }
    
    /// 对音频文件进行说话人分离
    /// - Parameters:
    ///   - audioURL: 音频文件 URL
    ///   - minSpeakers: 最小说话人数量（可选）
    ///   - maxSpeakers: 最大说话人数量（可选）
    /// - Returns: 说话人片段列表
    func diarize(
        audioURL: URL,
        minSpeakers: Int? = nil,
        maxSpeakers: Int? = nil
    ) async throws -> [SpeakerSegment] {
        print("🎤 [SpeakerDiarization] 开始说话人分离: \(audioURL.lastPathComponent)")
        print("🎤 [SpeakerDiarization] 服务地址: \(apiEndpoint)")
        
        // 验证服务地址格式
        guard let serviceURL = URL(string: apiEndpoint) else {
            throw DiarizationError.invalidEndpoint
        }
        
        // 准备 multipart/form-data 请求
        let boundary = UUID().uuidString
        guard let requestURL = URL(string: "\(apiEndpoint)/api/v1/diarization") else {
            throw DiarizationError.invalidEndpoint
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300 // 5 分钟超时（说话人分离可能需要较长时间）
        
        // 构建请求体
        var body = Data()
        
        // 添加文件
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: audioURL))
        body.append("\r\n".data(using: .utf8)!)
        
        // 添加可选参数
        if let minSpeakers = minSpeakers {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"min_speakers\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(minSpeakers)\r\n".data(using: .utf8)!)
        }
        
        if let maxSpeakers = maxSpeakers {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"max_speakers\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(maxSpeakers)\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        print("🎤 [SpeakerDiarization] 发送请求到服务...")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiarizationError.invalidResponse
        }
        
        print("🎤 [SpeakerDiarization] 收到响应，状态码: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [SpeakerDiarization] 请求失败: \(errorMessage)")
            throw DiarizationError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        // 解析响应
        let decoder = JSONDecoder()
        let diarizationResponse = try decoder.decode(DiarizationResponse.self, from: data)
        
        guard diarizationResponse.success else {
            throw DiarizationError.processingFailed("说话人分离处理失败")
        }
        
        print("✅ [SpeakerDiarization] 说话人分离完成，识别到 \(diarizationResponse.speakerCount) 个说话人，共 \(diarizationResponse.totalSegments) 个片段")
        
        return diarizationResponse.segments
    }
    
    /// 测试服务连接
    func testConnection() async throws -> Bool {
        print("🎤 [SpeakerDiarization] 测试服务连接: \(apiEndpoint)")
        
        // 验证服务地址格式
        guard let serviceURL = URL(string: apiEndpoint) else {
            throw DiarizationError.invalidEndpoint
        }
        
        guard let url = URL(string: "\(apiEndpoint)/health") else {
            throw DiarizationError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiarizationError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            return false
        }
        
        // 解析响应
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = json["status"] as? String {
            return status == "healthy"
        }
        
        return false
    }
}

/// 说话人分离错误
enum DiarizationError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case requestFailed(Int, String)
    case processingFailed(String)
    case serviceNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "无效的服务端点地址"
        case .invalidResponse:
            return "无效的响应格式"
        case .requestFailed(let code, let message):
            return "请求失败 (状态码: \(code)): \(message)"
        case .processingFailed(let message):
            return "处理失败: \(message)"
        case .serviceNotAvailable:
            return "说话人分离服务不可用，请检查服务是否正在运行"
        }
    }
}

