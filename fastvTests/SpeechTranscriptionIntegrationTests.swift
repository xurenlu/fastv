//
//  SpeechTranscriptionIntegrationTests.swift
//  fastvTests
//
//  真机端到端识别验证：跑的是 App 自己的完整链路（kaldi-native-fbank → LFR → CMVN →
//  ONNX Runtime → CTC 解码），而不是任何离线复现。
//
//  换 int8 加速版模型时必须过这一关：离线用 Python 复现的特征证明不了 App 的 fbank
//  实现在量化模型上同样稳。
//
//  依赖两个外部条件，缺任一条自动跳过（CI 与普通开发机默认跳过）：
//  - 本机已安装语音模型（`~/Library/Application Support/<应用名>/Models/sensevoice-small/`）；
//  - 环境变量 `QECHO_ASR_FIXTURE_DIR` 指向一个目录，内含 16kHz 单声道 wav 与同名 .txt 参考文本。
//
//  跑法（xcodebuild 不会把 shell 环境透传给测试进程，必须加 TEST_RUNNER_ 前缀）：
//    TEST_RUNNER_QECHO_ASR_FIXTURE_DIR=/path/to/fixtures bash scripts/run_unit_tests.sh
//

import Testing
import Foundation
@testable import musetype

@Suite("语音识别端到端", .serialized)
struct SpeechTranscriptionIntegrationTests {

    /// 参考文本与识别结果的字符错误率上限。
    /// TTS 合成的普通话在 SenseVoice 上本来就有几个百分点的错字（例如「调大」听成「掉大」），
    /// 这里卡的是「模型没坏」，不是「模型完美」。
    private static let maxCharacterErrorRate = 0.06

    private struct Fixture {
        let name: String
        let recording: VoiceRecording
        let reference: String
    }

    /// 读取 16kHz 单声道 Int16 wav，转成语音输入实际使用的 `VoiceRecording`。
    /// 按 RIFF 块遍历找 data 块，不假定固定的 44 字节头（afconvert 会写额外块）。
    private static func loadRecording(from url: URL) throws -> VoiceRecording? {
        let data = try Data(contentsOf: url)
        guard data.count > 12,
              data[0..<4].elementsEqual(Array("RIFF".utf8)),
              data[8..<12].elementsEqual(Array("WAVE".utf8)) else {
            return nil
        }
        var offset = 12
        var sampleRate: Double = 16000
        var channels = 1
        while offset + 8 <= data.count {
            let chunkID = data[offset..<(offset + 4)]
            let chunkSize = Int(data[(offset + 4)..<(offset + 8)].withUnsafeBytes {
                $0.loadUnaligned(as: UInt32.self).littleEndian
            })
            let bodyStart = offset + 8
            guard bodyStart + chunkSize <= data.count else { break }
            if chunkID.elementsEqual(Array("fmt ".utf8)), chunkSize >= 16 {
                let body = data[bodyStart..<(bodyStart + chunkSize)]
                channels = Int(body[body.startIndex + 2..<body.startIndex + 4].withUnsafeBytes {
                    $0.loadUnaligned(as: UInt16.self).littleEndian
                })
                sampleRate = Double(body[body.startIndex + 4..<body.startIndex + 8].withUnsafeBytes {
                    $0.loadUnaligned(as: UInt32.self).littleEndian
                })
            } else if chunkID.elementsEqual(Array("data".utf8)) {
                let pcm = Data(data[bodyStart..<(bodyStart + chunkSize)])
                return VoiceRecording(pcmData: pcm, sampleRate: sampleRate, channelCount: channels)
            }
            offset = bodyStart + chunkSize + (chunkSize % 2)
        }
        return nil
    }

    /// 素材目录：没配就说明这台机器不跑这条集成测试。
    private static var fixtureDirectory: String? {
        let directory = ProcessInfo.processInfo.environment["QECHO_ASR_FIXTURE_DIR"]
        guard let directory, !directory.isEmpty else { return nil }
        return directory
    }

    /// 只有「配了素材目录」且「本机装了模型」时才启用，其余情况整条测试跳过而不是失败。
    static var isEnabled: Bool {
        fixtureDirectory != nil && SpeechModelLocator.hasAnyModel()
    }

    private static func loadFixtures() throws -> [Fixture] {
        guard let directory = fixtureDirectory else {
            return []
        }
        let directoryURL = URL(fileURLWithPath: directory)
        let entries = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        return try entries
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { audioURL in
                let referenceURL = audioURL.deletingPathExtension().appendingPathExtension("txt")
                guard let reference = try? String(contentsOf: referenceURL, encoding: .utf8),
                      let recording = try loadRecording(from: audioURL) else { return nil }
                return Fixture(
                    name: audioURL.lastPathComponent,
                    recording: recording,
                    reference: reference.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
    }

    /// 去掉标点与空白，只比内容——标点由模型另行判定，不该算进错字率。
    private static func normalized(_ text: String) -> String {
        let dropped = CharacterSet(charactersIn: " \t\n，。、？！：；,.?!:;\"'“”‘’()（）")
        return text.unicodeScalars.filter { !dropped.contains($0) }.map(String.init).joined().lowercased()
    }

    private static func editDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        var previous = Array(0...rhs.count)
        for (i, left) in lhs.enumerated() {
            var current = [i + 1]
            for (j, right) in rhs.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (left == right ? 0 : 1)))
            }
            previous = current
        }
        return previous[rhs.count]
    }

    @Test(
        "已安装的模型能在 App 自己的管线上跑通，且错字率在阈值内",
        .enabled(if: SpeechTranscriptionIntegrationTests.isEnabled, "未配置素材目录或本机没装模型")
    )
    func transcribesFixturesWithInstalledModel() async throws {
        let fixtures = try Self.loadFixtures()
        try #require(!fixtures.isEmpty, "素材目录里没有成对的 wav + txt")

        let variant = SpeechModelLocator.resolvedVariant()
        print("🧪 [ASR 集成测试] 使用变体: \(variant?.rawValue ?? "无")，线程数: \(ONNXRuntimeWrapper.recommendedIntraOpThreadCount())")

        // 先把模型加载与预热做掉，让计时只反映「用户松键后真正要等的那段」
        _ = await SpeechTranscriptionModel.shared.preload()

        var totalErrors = 0
        var totalCharacters = 0
        var elapsedTimes: [Double] = []
        for fixture in fixtures {
            // 走 transcribe(recording:)，也就是语音输入真正用的内存录音路径；
            // transcribe(audioURL:) 会多一次 AVAsset 转码，不代表用户的等待。
            let start = CFAbsoluteTimeGetCurrent()
            let transcript = try await SpeechTranscriber.transcribe(
                recording: fixture.recording,
                language: .zh,
                enableCTCDeduplication: false
            )
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            elapsedTimes.append(elapsed)

            let hypothesis = Array(Self.normalized(transcript))
            let reference = Array(Self.normalized(fixture.reference))
            let errors = Self.editDistance(hypothesis, reference)
            totalErrors += errors
            totalCharacters += reference.count

            let audioSeconds = fixture.recording.durationSeconds
            print(String(
                format: "🧪 [ASR 集成测试] %@  语音 %.1fs  识别 %.3fs  实时率 %.2f  错字 %d/%d  → %@",
                fixture.name, audioSeconds, elapsed, elapsed / max(audioSeconds, 0.001),
                errors, reference.count, transcript
            ))
            #expect(!transcript.isEmpty, "\(fixture.name) 识别结果为空")
        }

        let sorted = elapsedTimes.sorted()
        print(String(format: "🧪 [ASR 集成测试] 识别耗时中位数 %.3fs，最慢 %.3fs",
                     sorted[sorted.count / 2], sorted.last ?? 0))

        let characterErrorRate = Double(totalErrors) / Double(max(1, totalCharacters))
        print(String(format: "🧪 [ASR 集成测试] 总字错率 %.2f%%（阈值 %.2f%%）",
                     characterErrorRate * 100, Self.maxCharacterErrorRate * 100))
        #expect(characterErrorRate <= Self.maxCharacterErrorRate)
    }
}
