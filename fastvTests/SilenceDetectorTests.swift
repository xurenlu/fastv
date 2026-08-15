//
//  SilenceDetectorTests.swift
//  fastvTests
//
//  覆盖静音检测的峰值衰减与相对/绝对静音时长区分。
//  背景：峰值只增不减时，一次重音会把相对阈值长期抬高，把整句话从中间切碎，
//  碎片单独送 ASR 导致识别质量下降。
//

import Testing
import Foundation
@testable import musetype

@Suite("SilenceDetector")
@MainActor
struct SilenceDetectorTests {

    /// 构造一个只看单帧、不做滑动平均的检测器，便于精确断言阈值行为
    private func makeDetector(peakDecayFactor: Float) -> SilenceDetector {
        let detector = SilenceDetector()
        detector.windowSize = 1
        detector.silenceThreshold = 0.01
        detector.relativeThreshold = 0.25
        detector.peakDecayFactor = peakDecayFactor
        detector.minimumSilenceDuration = 60  // 足够长，避免测试期间真的触发切段回调
        return detector
    }

    @Test("峰值衰减后，正常音量不再被误判为静音")
    func peakDecayRecoversFromLoudSpike() {
        let detector = makeDetector(peakDecayFactor: 0.9)

        // 一次重音把峰值拉到 0.6，相对阈值 = 0.6 * 0.25 = 0.15
        detector.processAudioLevel(0.6)
        #expect(detector.isSilent == false)

        // 随后以 0.1 的正常音量继续说话：初期确实低于相对阈值，被判为静音
        detector.processAudioLevel(0.1)
        #expect(detector.isSilent == true)

        // 峰值持续回落后，同样的 0.1 应重新被认作说话
        for _ in 0..<5 {
            detector.processAudioLevel(0.1)
        }
        #expect(detector.isSilent == false)
    }

    @Test("峰值不衰减时，重音后的正常音量会被一直误判为静音（回归对照）")
    func withoutDecayLoudSpikeKeepsFalseSilence() {
        let detector = makeDetector(peakDecayFactor: 1.0)

        detector.processAudioLevel(0.6)
        for _ in 0..<10 {
            detector.processAudioLevel(0.1)
        }
        // 这正是修复前的行为：0.1 永远低于 0.6 * 0.25，句子被从中间切开
        #expect(detector.isSilent == true)
    }

    @Test("真正的静音（低于绝对阈值）仍然立即进入静音状态")
    func absoluteSilenceStillDetected() {
        let detector = makeDetector(peakDecayFactor: 0.98)

        detector.processAudioLevel(0.3)
        #expect(detector.isSilent == false)

        detector.processAudioLevel(0.001)
        #expect(detector.isSilent == true)
    }

    @Test("语音恢复后峰值与静音状态被重置")
    func speechRecoveryResetsState() {
        let detector = makeDetector(peakDecayFactor: 0.98)

        detector.processAudioLevel(0.5)
        detector.processAudioLevel(0.001)
        #expect(detector.isSilent == true)

        // 恢复说话
        detector.processAudioLevel(0.4)
        #expect(detector.isSilent == false)
        #expect(detector.currentSilenceDuration == 0)
    }

    @Test("相对下降触发的静音需要更长持续时长才切段")
    func relativeSilenceRequiresLongerDuration() async throws {
        let detector = makeDetector(peakDecayFactor: 1.0)  // 关掉衰减，稳定维持相对静音
        detector.minimumSilenceDuration = 0.2
        detector.relativeSilenceDurationMultiplier = 3.0   // 相对静音需 0.6 秒

        final class Recorder { var durations: [TimeInterval] = [] }
        let recorder = Recorder()
        detector.onSilenceDetected = { recorder.durations.append($0) }

        detector.processAudioLevel(0.6)
        detector.processAudioLevel(0.1)  // 进入相对静音

        // 0.35 秒：已超过绝对静音所需的 0.2 秒，但未达相对静音所需的 0.6 秒
        try await Task.sleep(nanoseconds: 350_000_000)
        detector.processAudioLevel(0.1)
        #expect(recorder.durations.isEmpty)

        // 累计超过 0.6 秒后应触发
        try await Task.sleep(nanoseconds: 350_000_000)
        detector.processAudioLevel(0.1)
        #expect(recorder.durations.count == 1)
    }
}
