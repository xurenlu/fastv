//
//  SpeechModelVariantTests.swift
//  fastvTests
//
//  覆盖 2.5.0-rc6 的识别提速改造里最容易改错的几处约定：
//  1. 加速版与标准版必须落在不同文件名，否则升级会把老模型覆盖成半个文件；
//  2. 下载地址迁移只能动历史默认值，用户自己填过的地址不许改；
//  3. 下载地址要能反推出目标变体，否则会拿 int8 的期望大小去校验 fp32 文件、必然失败；
//  4. intra-op 线程数只用性能核——8 线程 + 自旋正是本次性能问题的元凶。
//

import Testing
import Foundation
@testable import musetype

@Suite("语音模型变体")
struct SpeechModelVariantTests {

    // MARK: - 变体本身

    @Test("默认分发加速版 int8")
    func preferredVariantIsInt8() {
        #expect(SpeechModelVariant.preferred == .int8)
        #expect(SpeechModelVariant.resolutionOrder.first == .int8)
    }

    @Test("两个变体文件名不同，升级不会覆盖老模型")
    func variantsUseDistinctFileNames() {
        #expect(SpeechModelVariant.int8.fileName == "model.int8.onnx")
        #expect(SpeechModelVariant.float32.fileName == "model.onnx")
        let names = Set(SpeechModelVariant.allCases.map(\.fileName))
        #expect(names.count == SpeechModelVariant.allCases.count)
    }

    @Test("官方下载地址与期望体积对得上")
    func officialURLsAndSizes() {
        #expect(SpeechModelVariant.int8.officialDownloadURL == "https://img.niuwoai.com/models/sensevoice-small/model.int8.onnx")
        #expect(SpeechModelVariant.float32.officialDownloadURL == "https://img.niuwoai.com/models/sensevoice-small/model.onnx")
        #expect(SpeechModelVariant.int8.expectedByteSize == 241_216_270)
        #expect(SpeechModelVariant.float32.expectedByteSize == 937_615_562)
        // 加速版必须明显更小，否则说明地址或体积配错了
        #expect(SpeechModelVariant.int8.expectedByteSize < SpeechModelVariant.float32.expectedByteSize / 2)
    }

    @Test("展示体积按 MB 取整")
    func approximateMegabytes() {
        #expect(SpeechModelVariant.int8.approximateMegabytes == 230)
        #expect(SpeechModelVariant.float32.approximateMegabytes == 894)
    }

    // MARK: - 文件大小校验

    @Test("文件大小校验允许 1KB 误差，超出即判定不完整")
    func sizeValidationTolerance() {
        let exact = SpeechModelVariant.int8.expectedByteSize
        #expect(SpeechModelLocator.matchesExpectedSize(.int8, byteSize: exact))
        #expect(SpeechModelLocator.matchesExpectedSize(.int8, byteSize: exact - 1024))
        #expect(SpeechModelLocator.matchesExpectedSize(.int8, byteSize: exact + 1024))
        #expect(!SpeechModelLocator.matchesExpectedSize(.int8, byteSize: exact - 1025))
        #expect(!SpeechModelLocator.matchesExpectedSize(.int8, byteSize: 0))
        // 拿 fp32 的体积去校验 int8 必须失败，反之亦然
        #expect(!SpeechModelLocator.matchesExpectedSize(.int8, byteSize: SpeechModelVariant.float32.expectedByteSize))
        #expect(!SpeechModelLocator.matchesExpectedSize(.float32, byteSize: SpeechModelVariant.int8.expectedByteSize))
    }

    // MARK: - 下载地址迁移

    @Test("没存过地址时用官方加速版地址")
    func migrationFromNil() {
        #expect(SpeechModelLocator.migratedDownloadURL(from: nil) == SpeechModelVariant.int8.officialDownloadURL)
        #expect(SpeechModelLocator.migratedDownloadURL(from: "") == SpeechModelVariant.int8.officialDownloadURL)
    }

    @Test("历史默认地址被迁移到加速版")
    func migrationFromLegacyDefault() {
        for legacy in SpeechModelVariant.legacyDefaultDownloadURLs {
            #expect(SpeechModelLocator.migratedDownloadURL(from: legacy) == SpeechModelVariant.int8.officialDownloadURL)
        }
    }

    @Test("用户自己填过的地址不许被迁移覆盖")
    func migrationKeepsCustomURL() {
        let custom = "https://mirror.example.com/my-sensevoice.onnx"
        #expect(SpeechModelLocator.migratedDownloadURL(from: custom) == custom)
    }

    @Test("已经是加速版地址时迁移是幂等的")
    func migrationIsIdempotent() {
        let current = SpeechModelVariant.int8.officialDownloadURL
        let once = SpeechModelLocator.migratedDownloadURL(from: current)
        #expect(once == current)
        #expect(SpeechModelLocator.migratedDownloadURL(from: once) == current)
    }

    // MARK: - 由下载地址反推变体

    @Test("官方地址能反推出对应变体")
    func variantFromOfficialURL() {
        #expect(SpeechModelLocator.variant(forDownloadURL: SpeechModelVariant.int8.officialDownloadURL) == .int8)
        #expect(SpeechModelLocator.variant(forDownloadURL: SpeechModelVariant.float32.officialDownloadURL) == .float32)
    }

    @Test("历史默认地址下的是 fp32，不能按加速版校验体积")
    func variantFromLegacyURL() {
        for legacy in SpeechModelVariant.legacyDefaultDownloadURLs {
            #expect(SpeechModelLocator.variant(forDownloadURL: legacy) == .float32)
        }
    }

    @Test("自定义镜像按文件名判断，判断不出来才落到默认变体")
    func variantFromCustomURL() {
        #expect(SpeechModelLocator.variant(forDownloadURL: "https://mirror.example.com/models/model.onnx") == .float32)
        #expect(SpeechModelLocator.variant(forDownloadURL: "https://mirror.example.com/models/model.int8.onnx") == .int8)
        #expect(SpeechModelLocator.variant(forDownloadURL: "https://mirror.example.com/whatever.bin") == .preferred)
    }

    // MARK: - 模型路径

    @Test("两个变体落在同一目录下的不同文件")
    func fileURLsShareDirectory() {
        let int8URL = SpeechModelLocator.fileURL(for: .int8)
        let fp32URL = SpeechModelLocator.fileURL(for: .float32)
        #expect(int8URL.deletingLastPathComponent() == SpeechModelLocator.modelDirectory())
        #expect(fp32URL.deletingLastPathComponent() == SpeechModelLocator.modelDirectory())
        #expect(int8URL != fp32URL)
        #expect(SpeechModelLocator.modelDirectory().path.hasSuffix("Models/sensevoice-small"))
    }
}

@Suite("ONNX 推理线程配置")
struct ONNXThreadConfigurationTests {

    @Test("intra-op 线程数只用性能核，且夹在 2~8 之间")
    func threadCountStaysWithinPerformanceCores() {
        let threads = ONNXRuntimeWrapper.recommendedIntraOpThreadCount()
        #expect(threads >= 2)
        #expect(threads <= 8)
        // 旧实现是 max(4, 逻辑核数)，在 Apple Silicon 上会把能效核也拉进线程池。
        // 新实现绝不该超过逻辑核数。
        #expect(threads <= ProcessInfo.processInfo.activeProcessorCount)
    }

    @Test("Apple Silicon 上不超过性能核数")
    func threadCountMatchesPerformanceCoreCount() throws {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let ok = sysctlbyname("hw.perflevel0.physicalcpu", &value, &size, nil, 0) == 0 && value > 0
        try #require(ok, "非 Apple Silicon 机器跳过")
        #expect(ONNXRuntimeWrapper.recommendedIntraOpThreadCount() == min(8, max(2, Int(value))))
    }
}
