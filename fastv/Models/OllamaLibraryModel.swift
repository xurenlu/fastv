//
//  OllamaLibraryModel.swift
//  fastv
//
//  Ollama 模型库：可下载的模型列表及大小（近似值，来自 ollama.com/library）
//

import Foundation

/// Ollama 模型信息（已下载或可下载）
struct OllamaModelInfo: Identifiable {
    let id: String
    let name: String
    /// 模型大小（字节），未下载时为近似值
    let sizeBytes: Int64
    /// 是否已下载到本地
    let isDownloaded: Bool
    /// 参数量描述，如 "2B"、"7B"
    let parameterSize: String?
    
    /// 格式化的大小显示
    var formattedSize: String {
        formatBytes(sizeBytes)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }
}

/// Ollama 官方库中常用模型及近似大小（字节）
/// 来源：ollama.com/library，大小为 :latest 标签的典型值
enum OllamaLibrary {
    /// 常用模型列表：(name, sizeBytes, parameterSize)
    static let popularModels: [(name: String, sizeBytes: Int64, parameterSize: String)] = [
        // 小模型 - 适合语音优化、快速响应
        ("gemma2:2b", 1_573_000_000, "2B"),
        ("deepseek-r1:1.5b", 1_200_000_000, "1.5B"),
        ("gemma3:1b", 1_100_000_000, "1B"),
        ("qwen2.5:1.5b", 1_100_000_000, "1.5B"),
        ("llama3.2:1b", 1_300_000_000, "1B"),
        ("phi4:mini", 1_500_000_000, "~2B"),
        ("smollm2:360m", 400_000_000, "360M"),
        ("tinyllama", 637_000_000, "1.1B"),
        // 中等模型
        ("llama3.2:3b", 2_000_000_000, "3B"),
        ("qwen2.5:3b", 2_000_000_000, "3B"),
        ("phi3:mini", 2_000_000_000, "3.8B"),
        ("gemma2:9b", 5_500_000_000, "9B"),
        ("mistral:7b", 4_100_000_000, "7B"),
        ("llama3.1:8b", 4_700_000_000, "8B"),
        ("qwen2.5:7b", 4_700_000_000, "7B"),
        ("deepseek-r1:7b", 4_500_000_000, "7B"),
        ("phi4", 4_500_000_000, "8B"),
        ("gemma3:4b", 2_500_000_000, "4B"),
        // 大模型
        ("qwen2.5:14b", 9_000_000_000, "14B"),
        ("llama3.1:70b", 40_000_000_000, "70B"),
        ("qwen2.5:32b", 20_000_000_000, "32B"),
        // 视觉/多模态
        ("llava:7b", 4_500_000_000, "7B"),
        ("llava:13b", 8_000_000_000, "13B"),
        ("qwen2.5-vl:7b", 4_700_000_000, "7B"),
    ]
    
    /// 获取可下载的模型列表（排除已下载的）
    static func availableModels(excludingDownloaded downloadedNames: Set<String>) -> [OllamaModelInfo] {
        popularModels
            .filter { !downloadedNames.contains(normalizeName($0.name)) }
            .map { OllamaModelInfo(
                id: $0.name,
                name: $0.name,
                sizeBytes: $0.sizeBytes,
                isDownloaded: false,
                parameterSize: $0.parameterSize
            )}
    }
    
    /// 模型名可能带 :tag，统一比较时去掉 tag 比较 base name
    private static func normalizeName(_ name: String) -> String {
        name.lowercased()
    }
    
    /// 检查给定名称是否在库中
    static func isInLibrary(_ name: String) -> Bool {
        let normalized = normalizeName(name)
        return popularModels.contains { normalizeName($0.name) == normalized }
    }
    
    /// 根据名称获取库中的模型信息
    static func getLibraryInfo(for name: String) -> OllamaModelInfo? {
        guard let match = popularModels.first(where: { normalizeName($0.name) == normalizeName(name) }) else {
            return nil
        }
        return OllamaModelInfo(
            id: match.name,
            name: match.name,
            sizeBytes: match.sizeBytes,
            isDownloaded: false,
            parameterSize: match.parameterSize
        )
    }
}
