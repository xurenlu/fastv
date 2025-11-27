//
//  AudioFormat.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AVFoundation

enum AudioFormat: String, CaseIterable {
    case m4a = "M4A"
    case mp3 = "MP3"
    case wav = "WAV"
    
    var fileExtension: String {
        switch self {
        case .m4a:
            return "m4a"
        case .mp3:
            return "mp3"
        case .wav:
            return "wav"
        }
    }
    
    var exportPreset: String {
        switch self {
        case .m4a:
            return AVAssetExportPresetAppleM4A
        case .mp3:
            return AVAssetExportPresetPassthrough
        case .wav:
            return AVAssetExportPresetPassthrough
        }
    }
    
    var fileType: AVFileType {
        switch self {
        case .m4a:
            return .m4a
        case .mp3:
            // AVAssetWriter 不支持 MP3，使用 M4A (AAC) 作为替代
            return .m4a
        case .wav:
            return .wav
        }
    }
    
    /// 音频编码设置（用于 AVAssetWriter）
    var audioSettings: [String: Any] {
        switch self {
        case .m4a, .mp3:
            // 使用 AAC 编码（MP3 实际上会导出为 AAC/M4A 格式）
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]
        case .wav:
            // WAV 使用 PCM 编码
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }
    }
    
    var displayName: String {
        return rawValue
    }
}

