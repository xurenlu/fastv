//
//  KaldiFbankWrapper.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation

final class KaldiFbankWrapper {
    static let shared = KaldiFbankWrapper()
    
    private let handle: KaldiFbankHandle?
    
    private init() {
        handle = KaldiFbankCreate(
            16_000,
            80,
            25.0,
            10.0,
            "hamming",
            1.0,
            true
        )
        
        #if DEBUG
        if handle == nil {
            print("KaldiFbankWrapper: 无法创建 Kaldi FBank 句柄")
        } else {
            print("KaldiFbankWrapper: Kaldi FBank 初始化成功")
        }
        #endif
    }
    
    deinit {
        if let handle = handle {
            KaldiFbankDestroy(handle)
        }
    }
    
    func compute(samples: [Float]) throws -> [[Float]] {
        guard let handle = handle else {
            throw VideoProcessingError.transcriptionFailed("Kaldi FBank 未初始化")
        }
        
        var outBuffer: UnsafeMutablePointer<Float>?
        var numFrames: Int32 = 0
        var featureDim: Int32 = 0
        
        let status = samples.withUnsafeBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else {
                return -1
            }
            return KaldiFbankCompute(
                handle,
                baseAddress,
                Int32(buffer.count),
                &outBuffer,
                &numFrames,
                &featureDim
            )
        }
        
        guard status == 0 else {
            if let outBuffer = outBuffer {
                KaldiFbankFreeBuffer(outBuffer)
            }
            throw VideoProcessingError.transcriptionFailed("Kaldi FBank 计算失败: status=\(status)")
        }
        
        guard let buffer = outBuffer else {
            return []
        }
        
        let frameCount = Int(numFrames)
        let dim = Int(featureDim)
        var features: [[Float]] = []
        features.reserveCapacity(frameCount)
        
        for frameIndex in 0..<frameCount {
            let start = frameIndex * dim
            let frame = Array(UnsafeBufferPointer(start: buffer + start, count: dim))
            features.append(frame)
        }
        
        KaldiFbankFreeBuffer(buffer)
        
        return features
    }
}

