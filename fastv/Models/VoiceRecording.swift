//
//  VoiceRecording.swift
//  fastv
//
//  Created by rocky on 2025/11/21.
//

import Foundation

/// 内存中的录音数据（16-bit PCM）
struct VoiceRecording {
    let pcmData: Data
    let sampleRate: Double
    let channelCount: Int

    /// 音频时长（秒）
    var durationSeconds: TimeInterval {
        guard sampleRate > 0, channelCount > 0 else { return 0 }
        let bytesPerSample = MemoryLayout<Int16>.size
        let totalSamples = pcmData.count / bytesPerSample
        return Double(totalSamples) / (sampleRate * Double(channelCount))
    }

    func normalizedSamples() -> [Float] {
        guard !pcmData.isEmpty else { return [] }
        let sampleCount = pcmData.count / MemoryLayout<Int16>.size
        var floats = [Float](repeating: 0, count: sampleCount)
        pcmData.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            let int16Ptr = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                floats[i] = Float(int16Ptr[i]) / Float(Int16.max)
            }
        }
        return floats
    }
}


