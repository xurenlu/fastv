import XCTest
@testable import musetype

@MainActor
final class InputExperienceTests: XCTestCase {
    func testAITriggersRespectOffAndShortcutModes() {
        XCTAssertFalse(VoiceAITrigger.off.shouldProcess(isAIShortcut: true))
        XCTAssertFalse(VoiceAITrigger.off.shouldProcess(isAIShortcut: false))
        XCTAssertFalse(VoiceAITrigger.shortcut.shouldProcess(isAIShortcut: false))
        XCTAssertTrue(VoiceAITrigger.shortcut.shouldProcess(isAIShortcut: true))
        XCTAssertTrue(VoiceAITrigger.always.shouldProcess(isAIShortcut: false))
    }

    func testUpgradePreservesDedicatedShortcutAndNewUsersStartOff() {
        let name = "InputExperienceTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(InputExperiencePreferences(defaults: defaults).aiTrigger, .off)
        defaults.set(true, forKey: "hasCompletedOnboarding")
        XCTAssertEqual(InputExperiencePreferences(defaults: defaults).aiTrigger, .off)
        defaults.removeObject(forKey: "voiceAITrigger") // 模拟从未写入新字段的旧版本。
        let settings = InputExperiencePreferences(defaults: defaults)
        XCTAssertEqual(settings.aiTrigger, .shortcut)
        XCTAssertFalse(settings.retainAudio)
        settings.aiTrigger = .off
        XCTAssertEqual(InputExperiencePreferences(defaults: defaults).aiTrigger, .off)
    }

    func testDisablingRetentionRevokesPreviouslyStartedSessionEvenAfterReenable() {
        let name = "InputExperienceTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = InputExperiencePreferences(defaults: defaults)
        settings.retainAudio = true
        let consent = settings.consentGeneration
        settings.retainAudio = false
        settings.retainAudio = true
        XCTAssertNotEqual(consent, settings.consentGeneration)
    }

    func testQuotaRetainsNewestAndCountsMetadata() {
        var old = VoiceEvaluationRecord()
        old.date = Date(timeIntervalSince1970: 1)
        old.audioBytes = 100
        var newest = VoiceEvaluationRecord()
        newest.date = Date(timeIntervalSince1970: 2)
        newest.audioBytes = 100
        XCTAssertEqual(VoiceEvaluationMetrics.retainedIDs([old, newest], countLimit: 1, byteLimit: 10000), [newest.id])
        XCTAssertTrue(VoiceEvaluationMetrics.retainedIDs([newest], countLimit: 500, byteLimit: 100).isEmpty)
    }

    func testFiveHundredBoundary() {
        let records = (0..<501).map { index in
            var record = VoiceEvaluationRecord()
            record.date = Date(timeIntervalSince1970: Double(index))
            return record
        }
        let ids = VoiceEvaluationMetrics.retainedIDs(records, countLimit: 500, byteLimit: 5_000_000_000)
        XCTAssertEqual(ids.count, 500)
        XCTAssertFalse(ids.contains(records[0].id))
        XCTAssertTrue(ids.contains(records[500].id))
    }

    func testCharacterErrorRateNeedsReferenceAndPreservesUnicode() {
        XCTAssertNil(VoiceEvaluationMetrics.characterErrorRate(recognized: "你好", reference: ""))
        XCTAssertEqual(VoiceEvaluationMetrics.characterErrorRate(recognized: "你好", reference: "您好"), 0.5)
        XCTAssertEqual(VoiceEvaluationMetrics.characterErrorRate(recognized: "👩🏽‍💻好", reference: "👩🏽‍💻好"), 0)
        XCTAssertEqual(VoiceEvaluationMetrics.characterErrorRate(recognized: "", reference: "你好"), 1)
    }

    func testArchiveRoundTripKeepsRawTranscriptAndDeletesAudioTogether() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = VoiceEvaluationRepository(directory: directory)
        var record = VoiceEvaluationRecord()
        record.rawText = "原始"
        record.finalText = "改写"
        let wav = VoiceEvaluationSession.wav(pcm: Data(repeating: 0, count: 320), sampleRate: 16000, channels: 1)
        try await repository.save(record, wav: wav, policy: .recent500)
        let records = try await repository.records()
        XCTAssertEqual(records.first?.rawText, "原始")
        XCTAssertEqual(records.first?.finalText, "改写")
        XCTAssertEqual(records.first?.audioBytes, Int64(wav.count))
        record.referenceText = "参考"
        try await repository.update(record)
        try await repository.remove(record.id)
        let after = try await repository.records()
        XCTAssertTrue(after.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(record.id.uuidString).path))
    }

    func testWaveHeaderEncodesPCMFormatAndLength() {
        let wav = VoiceEvaluationSession.wav(pcm: Data(repeating: 0, count: 320), sampleRate: 16000, channels: 1)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .utf8), "RIFF")
        XCTAssertEqual(String(data: wav.subdata(in: 8..<12), encoding: .utf8), "WAVE")
        XCTAssertEqual(wav.count, 364)
        XCTAssertEqual(Array(wav[24..<28]), [0x80, 0x3e, 0, 0])
    }
}
