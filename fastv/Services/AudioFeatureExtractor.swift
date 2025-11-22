//
//  AudioFeatureExtractor.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AVFoundation
import Accelerate

/// 音频特征提取器：提取 Mel 频谱特征
struct AudioFeatureExtractor {
    // 配置参数（从 config.yaml 读取）
    private static let sampleRate: Double = 16000
    private static let nMelBands: Int = 80
    private static let frameLength: Int = 25  // 毫秒
    private static let frameShift: Int = 10   // 毫秒
    private static let lfrM: Int = 7
    private static let lfrN: Int = 6
    
    /// 提取 Mel 频谱特征
    /// - Parameter audioURL: 音频文件 URL（16kHz 单声道 WAV）
    /// - Parameter cmvnURL: Global CMVN 文件 URL (am.mvn)
    /// - Returns: 特征矩阵 [[Float]]，每行是一帧，每列是一个 Mel 频带
    static func extractMelFeatures(from audioURL: URL, cmvnURL: URL? = nil) async throws -> [[Float]] {
        let audioData = try await loadAudioData(from: audioURL)
        return try processSamples(audioData, cmvnURL: cmvnURL)
    }
    
    static func extractMelFeatures(from recording: VoiceRecording, cmvnURL: URL? = nil) async throws -> [[Float]] {
        guard recording.channelCount == 1 else {
            throw VideoProcessingError.transcriptionFailed("仅支持单声道录音")
        }
        guard abs(recording.sampleRate - sampleRate) < 1 else {
            throw VideoProcessingError.transcriptionFailed("录音采样率需为16kHz")
        }
        let samples = recording.normalizedSamples()
        return try processSamples(samples, cmvnURL: cmvnURL)
    }
    
    private static func processSamples(_ audioData: [Float], cmvnURL: URL?) throws -> [[Float]] {
        // 2. 计算 Mel 频谱图（优先使用 Kaldi 原生实现）
        var melFeatures: [[Float]]
        do {
            melFeatures = try computeKaldiFbankFeatures(audioData: audioData)
        } catch {
            #if DEBUG
            print("Kaldi FBank 提取失败，使用 Swift 备选实现: \(error)")
            #endif
            melFeatures = try computeMelSpectrogram(audioData: audioData)
        }
        
        // 3. 应用 LFR (Low Frame Rate)
        if lfrM > 1 || lfrN > 1 {
            #if DEBUG
            print("应用 LFR: m=\(lfrM), n=\(lfrN), 原始维度=\(melFeatures.first?.count ?? 0), 帧数=\(melFeatures.count)")
            #endif
            melFeatures = applyLFR(features: melFeatures, lfrM: lfrM, lfrN: lfrN)
            #if DEBUG
            print("LFR 完成: 新维度=\(melFeatures.first?.count ?? 0), 新帧数=\(melFeatures.count)")
            #endif
        }
        
        // 4. 应用 Global CMVN
        if let cmvnURL = cmvnURL {
            #if DEBUG
            print("应用 Global CMVN: \(cmvnURL.path)")
            #endif
            let (means, vars) = try loadCMVN(from: cmvnURL)
            melFeatures = applyGlobalCMVN(features: melFeatures, means: means, vars: vars)
        }
        
        return melFeatures
    }
    
    /// 加载音频数据
    private static func loadAudioData(from audioURL: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: audioURL)
        
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw VideoProcessingError.noAudioTrack
        }
        
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        guard reader.canAdd(audioOutput) else {
            throw VideoProcessingError.transcriptionFailed("无法添加音频输出")
        }
        reader.add(audioOutput)
        
        guard reader.startReading() else {
            throw VideoProcessingError.transcriptionFailed("无法开始读取音频: \(reader.error?.localizedDescription ?? "未知错误")")
        }
        
        var audioSamples: [Float] = []
        
        while let sampleBuffer = audioOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }
            
            var length: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>? = nil
            let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            
            guard status == noErr, let data = dataPointer else {
                continue
            }
            
            // 修复：使用 withMemoryRebound 的正确方式，并在闭包内处理数据
            let sampleCount = length / 2
            let floatSamples = data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { int16Ptr -> [Float] in
                let buffer = UnsafeBufferPointer(start: int16Ptr, count: sampleCount)
                // 调试：检查前几个样本值
                #if DEBUG
                if audioSamples.isEmpty && sampleCount > 0 {
                    print("Buffer 前10个 Int16 值: \(buffer.prefix(10).map { $0 })")
                }
                #endif
                return buffer.map { Float($0) / 32768.0 }
            }
            
            audioSamples.append(contentsOf: floatSamples)
        }
        
        #if DEBUG
        let duration = Double(audioSamples.count) / sampleRate
        print("加载音频文件: \(audioURL.path)")
        print("音频格式 ID: \(outputSettings[AVFormatIDKey] as? UInt32 ?? 0)")
        print("音频加载完成: 总样本数=\(audioSamples.count), 时长=\(String(format: "%.2f", duration))秒")
        
        let minVal = audioSamples.min() ?? 0
        let maxVal = audioSamples.max() ?? 0
        let avgVal = audioSamples.reduce(0, +) / Float(audioSamples.count)
        let rms = sqrt(audioSamples.map { $0 * $0 }.reduce(0, +) / Float(audioSamples.count))
        print("音频样本统计: min=\(minVal), max=\(maxVal), avg=\(avgVal), RMS=\(rms)")
        print("音频数据统计: 样本数=\(audioSamples.count), min=\(minVal), max=\(maxVal), avg=\(avgVal)")
        #endif
        
        return audioSamples
    }
    
    /// 使用 Kaldi 原生库计算 FBank 特征
    private static func computeKaldiFbankFeatures(audioData: [Float]) throws -> [[Float]] {
        guard !audioData.isEmpty else {
            return []
        }
        
        let features = try KaldiFbankWrapper.shared.compute(samples: audioData)
        
        // 验证特征数据
        guard !features.isEmpty else {
            throw VideoProcessingError.transcriptionFailed("Kaldi FBank 返回空特征")
        }
        
        let featureDim = features[0].count
        guard featureDim > 0 else {
            throw VideoProcessingError.transcriptionFailed("Kaldi FBank 特征维度为 0")
        }
        
        // 检查所有帧的维度是否一致
        for (index, frame) in features.enumerated() {
            guard frame.count == featureDim else {
                throw VideoProcessingError.transcriptionFailed("Kaldi FBank 特征维度不一致: 帧 \(index) 维度为 \(frame.count)，期望 \(featureDim)")
            }
            
            // 检查 NaN 和 Inf
            for (valueIndex, value) in frame.enumerated() {
                if value.isNaN {
                    throw VideoProcessingError.transcriptionFailed("Kaldi FBank 特征包含 NaN: 帧 \(index), 维度 \(valueIndex)")
                }
                if value.isInfinite {
                    throw VideoProcessingError.transcriptionFailed("Kaldi FBank 特征包含 Inf: 帧 \(index), 维度 \(valueIndex), 值=\(value)")
                }
            }
        }
        
        #if DEBUG
        if let firstFrame = features.first {
            let minVal = firstFrame.min() ?? 0
            let maxVal = firstFrame.max() ?? 0
            let avgVal = firstFrame.reduce(0, +) / Float(firstFrame.count)
            print("Kaldi FBank 第一帧统计: min=\(minVal), max=\(maxVal), avg=\(avgVal)")
            
            // 检查特征值范围是否合理（FBank 特征通常在 -50 到 50 之间）
            if abs(minVal) > 100 || abs(maxVal) > 100 {
                print("警告：Kaldi FBank 特征值范围异常: min=\(minVal), max=\(maxVal)")
            }
        }
        print("Kaldi FBank 特征: 帧数=\(features.count), 维度=\(features.first?.count ?? 0)")
        #endif
        
        return features
    }
    
    /// 计算 Mel 频谱图（Swift 备选实现）
    private static func computeMelSpectrogram(audioData: [Float]) throws -> [[Float]] {
        let frameSize = Int(Double(frameLength) / 1000.0 * sampleRate)  // 样本数
        let hopSize = Int(Double(frameShift) / 1000.0 * sampleRate)      // 样本数
        
        #if DEBUG
        print("帧大小: \(frameSize) 样本, 跳跃大小: \(hopSize) 样本")
        #endif
        
        // 关键：Python 代码中，waveform 从 librosa.load 加载后范围是 [-1, 1]
        // 然后乘以 (1 << 15) = 32768，变成 [-32768, 32768] 的 Float 值
        // kaldi_native_fbank 期望这个范围的输入
        // 我们在 Swift 中也需要做同样的缩放，以匹配 Python 的行为
        let scaledAudioData = audioData.map { $0 * 32768.0 }
        
        #if DEBUG
        print("缩放后音频数据统计: min=\(scaledAudioData.min() ?? 0), max=\(scaledAudioData.max() ?? 0), avg=\(scaledAudioData.reduce(0, +) / Float(scaledAudioData.count))")
        print("缩放后音频数据前10个样本: \(scaledAudioData.prefix(10))")
        #endif
        
        // 创建 FFT 设置
        let fftSize = nextPowerOfTwo(frameSize)
        let log2n = vDSP_Length(log2(Double(fftSize)))
        
        // 创建窗口函数 (Hamming)
        var window = [Float](repeating: 0, count: frameSize)
        for i in 0..<frameSize {
            // Hamming 窗口: w(n) = 0.54 - 0.46 * cos(2πn / (N-1))
            let n = Double(i)
            let N = Double(frameSize - 1)
            window[i] = Float(0.54 - 0.46 * cos(2.0 * Double.pi * n / N))
        }
        
        // 创建 Mel 滤波器组
        let melFilters = createMelFilterBank(fftSize: fftSize, nMelBands: nMelBands, sampleRate: sampleRate)
        
        var features: [[Float]] = []
        var offset = 0
        
        #if DEBUG
        var frameCount = 0
        print("音频数据前10个样本: \(audioData.prefix(10))")
        
        // 找到第一个非静音帧的位置
        var firstNonSilentOffset = 0
        let silenceThreshold: Float = 0.01
        for i in stride(from: 0, to: scaledAudioData.count - frameSize, by: hopSize) {
            let frame = Array(scaledAudioData[i..<i + frameSize])
            let frameRMS = sqrt(frame.map { $0 * $0 }.reduce(0, +) / Float(frame.count))
            if frameRMS > silenceThreshold {
                firstNonSilentOffset = i
                break
            }
        }
        print("第一个非静音帧位置: offset=\(firstNonSilentOffset), 样本数=\(firstNonSilentOffset)")
        #endif
        
        while offset + frameSize <= scaledAudioData.count {
            // 提取帧
            let frame = Array(scaledAudioData[offset..<offset + frameSize])
            
            // 应用窗口
            var windowedFrame = frame
            vDSP_vmul(frame, 1, window, 1, &windowedFrame, 1, vDSP_Length(frameSize))
            
            #if DEBUG
            if frameCount == 0 {
                print("第一帧原始数据前10个样本: \(frame.prefix(10))")
                print("第一帧窗口化后前10个样本: \(windowedFrame.prefix(10))")
                print("窗口函数前10个值: \(window.prefix(10))")
                let frameMin = windowedFrame.min() ?? 0
                let frameMax = windowedFrame.max() ?? 0
                let frameAvg = windowedFrame.reduce(0, +) / Float(windowedFrame.count)
                let frameRMS = sqrt(windowedFrame.map { $0 * $0 }.reduce(0, +) / Float(windowedFrame.count))
                print("窗口化后帧统计: min=\(frameMin), max=\(frameMax), avg=\(frameAvg), RMS=\(frameRMS)")
            }
            // 检查第一个非静音帧
            if offset == firstNonSilentOffset && firstNonSilentOffset > 0 {
                let frameRMS = sqrt(windowedFrame.map { $0 * $0 }.reduce(0, +) / Float(windowedFrame.count))
                print("第一个非静音帧 (offset=\(offset)): RMS=\(frameRMS)")
            }
            #endif
            
            // FFT - 使用 vDSP_fft_zrip 进行实数 FFT
            guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
                throw VideoProcessingError.transcriptionFailed("无法创建 FFT 设置")
            }
            
            // 准备输入数据：零填充到 fftSize
            var inputBuffer = [Float](repeating: 0, count: fftSize)
            for i in 0..<windowedFrame.count {
                inputBuffer[i] = windowedFrame[i]
            }
            
            // FFT 输出缓冲区 (复数分离格式)
            var realParts = [Float](repeating: 0, count: fftSize/2)
            var imagParts = [Float](repeating: 0, count: fftSize/2)
            
            // 将输入数据打包到 splitComplex (Even-Odd Split)
            inputBuffer.withUnsafeBufferPointer { inputPtr in
                inputPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize/2) { complexPtr in
                    realParts.withUnsafeMutableBufferPointer { realBuffer in
                        imagParts.withUnsafeMutableBufferPointer { imagBuffer in
                            var splitComplex = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize/2))
                        }
                    }
                }
            }
            
            // 计算功率谱（在闭包外部定义）
            var powerSpectrum = [Float](repeating: 0, count: fftSize/2 + 1)
            var melSpectrum = [Float](repeating: 0, count: nMelBands)
            var logResult = [Float](repeating: 0, count: nMelBands)
            
            // 执行实数 FFT
            realParts.withUnsafeMutableBufferPointer { realBuffer in
                imagParts.withUnsafeMutableBufferPointer { imagBuffer in
                    var splitComplex = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                    
                    // 缩放结果 (vDSP_fft_zrip 结果放大了 2 倍)
                    var scale: Float = 0.5
                    vDSP_vsmul(splitComplex.realp, 1, &scale, splitComplex.realp, 1, vDSP_Length(fftSize/2))
                    vDSP_vsmul(splitComplex.imagp, 1, &scale, splitComplex.imagp, 1, vDSP_Length(fftSize/2))
                    
                    // 处理 DC 和 Nyquist
                    let dc = splitComplex.realp[0]
                    let nyquist = splitComplex.imagp[0]
                    powerSpectrum[0] = dc * dc
                    powerSpectrum[fftSize/2] = nyquist * nyquist
                    
                    // 处理其他频率分量
                    splitComplex.imagp[0] = 0 // 重置 Nyquist 位置为 0 以便批量计算
                    
                    var tempSpectrum = [Float](repeating: 0, count: fftSize/2)
                    vDSP_zvmags(&splitComplex, 1, &tempSpectrum, 1, vDSP_Length(fftSize/2))
                    
                    for i in 1..<fftSize/2 {
                        powerSpectrum[i] = tempSpectrum[i]
                    }
                }
            }
            
            vDSP_destroy_fftsetup(fftSetup)
            
            #if DEBUG
            if frameCount == 0 {
                let maxVal = powerSpectrum.max() ?? 0
                print("功率谱统计: min=\(powerSpectrum.min() ?? 0), max=\(maxVal), avg=\(powerSpectrum.reduce(0, +) / Float(powerSpectrum.count))")
                if maxVal == 0 {
                    print("警告：功率谱全为 0！检查 FFT 输入")
                    print("FFT 输入示例 (前10): \(inputBuffer.prefix(10))")
                }
            }
            #endif
            
            // 应用 Mel 滤波器组
            // 滤波器长度通常是 fftSize / 2 + 1
            for (i, filter) in melFilters.enumerated() {
                var sum: Float = 0
                // 注意：这里使用前 fftSize / 2 + 1 个点
                vDSP_dotpr(powerSpectrum, 1, filter, 1, &sum, vDSP_Length(fftSize / 2 + 1))
                melSpectrum[i] = sum
            }
            
            #if DEBUG
            if frameCount == 0 {
                print("Mel 频谱统计: min=\(melSpectrum.min() ?? 0), max=\(melSpectrum.max() ?? 0), avg=\(melSpectrum.reduce(0, +) / Float(melSpectrum.count))")
            }
            #endif
            
            // 对数变换
            // Kaldi Fbank 通常使用自然对数 (Natural Log)
            // 我们的波形已经缩放了 32768，所以能量值会很大
            // log(energy) 大约在 20 左右是合理的
            var logMelSpectrum = melSpectrum
            for i in 0..<nMelBands {
                // 避免 log(0)，使用一个小的 epsilon
                // 注意：Kaldi 默认 energy_floor 是 0.0 (在 Python 代码中显式设置)
                // 但数值计算中我们还是需要避免 -inf
                logMelSpectrum[i] = max(logMelSpectrum[i], Float(1e-10))
            }
            
            // 使用自然对数 (ln)
            var count = Int32(nMelBands)
            var input = logMelSpectrum
            logResult = logMelSpectrum
            vvlogf(&logResult, &input, &count)
            
            // 注意：不再乘以 10。Kaldi Fbank 输出通常是自然对数能量，不是 dB (10*log10)
            
            #if DEBUG
            if frameCount == 0 {
                print("对数 Mel 频谱统计 (Natural Log): min=\(logResult.min() ?? 0), max=\(logResult.max() ?? 0), avg=\(logResult.reduce(0, +) / Float(logResult.count))")
            }
            frameCount += 1
            #endif
            
            features.append(logResult)
            offset += hopSize
        }
        
        #if DEBUG
        print("特征提取完成: 总帧数=\(features.count), 每帧维度=\(features.first?.count ?? 0)")
        if !features.isEmpty {
            let allValues = features.flatMap { $0 }
            let minVal = allValues.min() ?? 0
            let maxVal = allValues.max() ?? 0
            let avgVal = allValues.reduce(0, +) / Float(allValues.count)
            print("最终特征统计: min=\(minVal), max=\(maxVal), avg=\(avgVal)")
        }
        #endif
        
        return features
    }
    
    /// 创建 Mel 滤波器组
    private static func createMelFilterBank(fftSize: Int, nMelBands: Int, sampleRate: Double) -> [[Float]] {
        let nyquist = sampleRate / 2.0
        let melMax = 2595 * log10(1 + nyquist / 700)
        
        var filters: [[Float]] = []
        
        for i in 0..<nMelBands {
            let melLow = melMax * Double(i) / Double(nMelBands)
            let melHigh = melMax * Double(i + 1) / Double(nMelBands)
            
            let freqLow = 700 * (exp(melLow / 2595) - 1)
            let freqHigh = 700 * (exp(melHigh / 2595) - 1)
            
            let binLow = Int(freqLow * Double(fftSize) / sampleRate)
            let binHigh = Int(freqHigh * Double(fftSize) / sampleRate)
            
            var filter = [Float](repeating: 0, count: fftSize / 2 + 1)
            
            for bin in binLow..<binHigh {
                if bin >= 0 && bin < fftSize / 2 + 1 {
                    let weight: Float
                    if bin < (binLow + binHigh) / 2 {
                        weight = Float(2.0 * Double(bin - binLow) / Double(binHigh - binLow))
                    } else {
                        weight = Float(2.0 * Double(binHigh - bin) / Double(binHigh - binLow))
                    }
                    filter[bin] = weight
                }
            }
            
            filters.append(filter)
        }
        
        return filters
    }
    
    /// 应用 LFR (Low Frame Rate)
    /// 参考 Python 官方实现：SenseVoice/utils/frontend.py
    private static func applyLFR(features: [[Float]], lfrM: Int, lfrN: Int) -> [[Float]] {
        guard !features.isEmpty else { return features }
        
        let featureDim = features[0].count
        var T = features.count
        
        // Python 逻辑：T_lfr = ceil(T / lfr_n)，在添加 padding 之前计算
        let T_lfr = Int(ceil(Double(T) / Double(lfrN)))
        
        // 左填充：复制第一帧 (lfr_m - 1) // 2 次
        let leftPadCount = (lfrM - 1) / 2
        var paddedFeatures: [[Float]] = []
        
        // 添加左填充
        for _ in 0..<leftPadCount {
            paddedFeatures.append(features[0])
        }
        // 添加原始特征
        paddedFeatures.append(contentsOf: features)
        
        // 更新 T（添加 padding 后）
        T = T + leftPadCount
        
        // 创建输出数组
        var lfrFeatures: [[Float]] = []
        
        for i in 0..<T_lfr {
            // Python 逻辑：if lfr_m <= T - i * lfr_n:
            if lfrM <= T - i * lfrN {
                // 正常情况：取 lfrM 个连续帧并 reshape
                var concatenated = [Float](repeating: 0, count: featureDim * lfrM)
                for j in 0..<lfrM {
                    let sourceIndex = i * lfrN + j
                    let startIdx = j * featureDim
                    concatenated.replaceSubrange(startIdx..<startIdx + featureDim, with: paddedFeatures[sourceIndex])
                }
                lfrFeatures.append(concatenated)
            } else {
                // 处理最后一帧的 padding
                // Python: num_padding = lfr_m - (T - i * lfr_n)
                let numPadding = lfrM - (T - i * lfrN)
                
                // Python: frame = inputs[i * lfr_n :].reshape(-1)
                var frame: [Float] = []
                for idx in (i * lfrN)..<T {
                    frame.append(contentsOf: paddedFeatures[idx])
                }
                
                // Python: for _ in range(num_padding): frame = np.hstack((frame, inputs[-1]))
                let lastFrame = paddedFeatures[T - 1]
                for _ in 0..<numPadding {
                    frame.append(contentsOf: lastFrame)
                }
                
                lfrFeatures.append(frame)
            }
        }
        
        return lfrFeatures
    }
    
    /// 加载 CMVN 文件 (am.mvn)
    private static func loadCMVN(from url: URL) throws -> (means: [Float], vars: [Float]) {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var means: [Float] = []
        var vars: [Float] = []
        
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("<AddShift>") {
                // 读取下一行 <LearnRateCoef> ... [ ... ]
                // 有时候数据可能在同一行，或者多行。根据文件内容样例，数据在一行 [ ... ]
                // 内容样例: <LearnRateCoef> 0 [ -8.311879 ... ]
                // 需要找到包含 '[' 的行（可能是当前行或下一行）
                var dataLine = line
                if !dataLine.contains("[") {
                    if i + 1 < lines.count {
                        dataLine = lines[i+1]
                        i += 1
                    }
                }
                
                if let startRange = dataLine.range(of: "["), let endRange = dataLine.range(of: "]", range: startRange.upperBound..<dataLine.endIndex) {
                    let dataString = String(dataLine[startRange.upperBound..<endRange.lowerBound])
                    means = dataString.split(separator: " ").compactMap { Float($0) }
                }
            } else if line.hasPrefix("<Rescale>") {
                var dataLine = line
                if !dataLine.contains("[") {
                    if i + 1 < lines.count {
                        dataLine = lines[i+1]
                        i += 1
                    }
                }
                
                if let startRange = dataLine.range(of: "["), let endRange = dataLine.range(of: "]", range: startRange.upperBound..<dataLine.endIndex) {
                    let dataString = String(dataLine[startRange.upperBound..<endRange.lowerBound])
                    vars = dataString.split(separator: " ").compactMap { Float($0) }
                }
            }
            i += 1
        }
        
        guard !means.isEmpty, !vars.isEmpty else {
            throw VideoProcessingError.transcriptionFailed("解析 CMVN 文件失败或文件为空")
        }
        
        #if DEBUG
        print("加载 CMVN 成功: 维度=\(means.count)")
        print("CMVN Means 前10个值: \(means.prefix(10))")
        print("CMVN Means 统计: min=\(means.min() ?? 0), max=\(means.max() ?? 0), avg=\(means.reduce(0, +) / Float(means.count))")
        print("CMVN Vars 前10个值: \(vars.prefix(10))")
        print("CMVN Vars 统计: min=\(vars.min() ?? 0), max=\(vars.max() ?? 0), avg=\(vars.reduce(0, +) / Float(vars.count))")
        #endif
        
        return (means, vars)
    }
    
    /// 应用 Global CMVN
    /// Python 逻辑: (inputs + means) * vars
    private static func applyGlobalCMVN(features: [[Float]], means: [Float], vars: [Float]) -> [[Float]] {
        guard !features.isEmpty else { return features }
        let dim = features[0].count
        guard means.count == dim, vars.count == dim else {
            print("警告：CMVN 维度不匹配 (特征=\(dim), CMVN=\(means.count))，跳过 CMVN")
            return features
        }
        
        var normalizedFeatures = features
        for i in 0..<features.count {
            var frame = features[i]
            // frame = frame + means
            vDSP_vadd(frame, 1, means, 1, &frame, 1, vDSP_Length(dim))
            // frame = frame * vars
            vDSP_vmul(frame, 1, vars, 1, &frame, 1, vDSP_Length(dim))
            normalizedFeatures[i] = frame
        }
        
        #if DEBUG
        if !normalizedFeatures.isEmpty {
            let firstFrame = normalizedFeatures[0]
            let minVal = firstFrame.min() ?? 0
            let maxVal = firstFrame.max() ?? 0
            let avgVal = firstFrame.reduce(0, +) / Float(firstFrame.count)
            print("CMVN 后第一帧统计: min=\(minVal), max=\(maxVal), avg=\(avgVal)")
            }
        #endif
        
        return normalizedFeatures
    }
    
    /// 计算下一个 2 的幂
    private static func nextPowerOfTwo(_ n: Int) -> Int {
        var power = 1
        while power < n {
            power *= 2
        }
        return power
    }
    
    /// 计算以 10 为底的对数
    private static func log10(_ x: Double) -> Double {
        return log(x) / log(10.0)
    }
}

