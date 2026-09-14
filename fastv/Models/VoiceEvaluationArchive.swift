import AVFoundation
import Combine
import Foundation

nonisolated struct VoiceEvaluationRecord: Identifiable, Codable, Sendable {
    var id = UUID()
    var date = Date()
    var rawText = ""
    var correctedText = ""
    var finalText = ""
    var referenceText = ""
    var status = "captured"
    var model = ""
    var language = ""
    var appVersion = ""
    var aiModel: String?
    var duration: Double = 0
    var recognitionSeconds: Double = 0
    var audioBytes: Int64 = 0
}

nonisolated enum VoiceEvaluationMetrics {
    /// 原样比较 Unicode 字符，不把 AI 输出当作参考，也不隐藏标点差异。
    static func characterErrorRate(recognized: String, reference: String) -> Double? {
        let expected = Array(reference)
        guard !expected.isEmpty else { return nil }
        let actual = Array(recognized)
        var previous = Array(0...expected.count)
        for (i, character) in actual.enumerated() {
            var row = [i + 1] + Array(repeating: 0, count: expected.count)
            for j in expected.indices {
                row[j + 1] = min(row[j] + 1, previous[j + 1] + 1,
                                 previous[j] + (character == expected[j] ? 0 : 1))
            }
            previous = row
        }
        return Double(previous[expected.count]) / Double(expected.count)
    }

    static func retainedIDs(_ records: [VoiceEvaluationRecord], countLimit: Int, byteLimit: Int64) -> Set<UUID> {
        var bytes: Int64 = 0
        var ids = Set<UUID>()
        for record in records.sorted(by: { $0.date > $1.date }) {
            let size = record.audioBytes + Int64((try? JSONEncoder().encode(record).count) ?? 0)
            guard ids.count < countLimit, size <= byteLimit - bytes else { break }
            ids.insert(record.id)
            bytes += size
        }
        return ids
    }
}

/// 每条素材自包含：WAV + JSON；原子目录提交，不让中断产生半条可见记录。
actor VoiceEvaluationRepository {
    let directory: URL
    init(directory: URL) { self.directory = directory }

    func records() throws -> [VoiceEvaluationRecord] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var result: [VoiceEvaluationRecord] = []
        for url in urls where UUID(uuidString: url.lastPathComponent) != nil {
            guard let data = try? Data(contentsOf: url.appendingPathComponent("record.json")),
                  let record = try? JSONDecoder().decode(VoiceEvaluationRecord.self, from: data) else {
                // 启动时忽略并清理中断留下的孤立素材目录，不能让一条坏记录阻塞整个评估库。
                try? FileManager.default.removeItem(at: url)
                continue
            }
            result.append(record)
        }
        return result.sorted { $0.date > $1.date }
    }

    func save(_ record: VoiceEvaluationRecord, wav: Data, policy: AudioRetentionPolicy) throws {
        guard Int64(wav.count) <= AudioRetentionPolicy.byteLimit else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".pending-" + record.id.uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try wav.write(to: temporary.appendingPathComponent("audio.wav"), options: .atomic)
        var stored = record
        stored.audioBytes = Int64(wav.count)
        try JSONEncoder().encode(stored).write(to: temporary.appendingPathComponent("record.json"), options: .atomic)
        try FileManager.default.moveItem(at: temporary, to: directory.appendingPathComponent(record.id.uuidString))
        try trim(policy: policy)
    }

    func update(_ record: VoiceEvaluationRecord) throws {
        let url = directory.appendingPathComponent(record.id.uuidString).appendingPathComponent("record.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var stored = try JSONDecoder().decode(VoiceEvaluationRecord.self, from: Data(contentsOf: url))
        stored.referenceText = record.referenceText
        try JSONEncoder().encode(stored).write(to: url, options: .atomic)
    }

    func remove(_ id: UUID) throws {
        let url = directory.appendingPathComponent(id.uuidString)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    func trim(policy: AudioRetentionPolicy) throws {
        let items = try records()
        let retained = VoiceEvaluationMetrics.retainedIDs(items, countLimit: policy.countLimit, byteLimit: AudioRetentionPolicy.byteLimit)
        for item in items where !retained.contains(item.id) { try remove(item.id) }
    }
}

@MainActor
final class VoiceEvaluationArchive: ObservableObject {
    static let shared = VoiceEvaluationArchive()
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("QEcho/VoiceEvaluation", isDirectory: true)
    private let repository = VoiceEvaluationRepository(directory: directory)
    @Published private(set) var records: [VoiceEvaluationRecord] = []
    @Published var errorMessage: String?

    func refresh() async {
        do { records = try await repository.records() }
        catch { errorMessage = error.localizedDescription }
    }

    func save(_ record: VoiceEvaluationRecord, wav: Data, consent: Int) async {
        let preferences = InputExperiencePreferences.shared
        guard preferences.retainAudio, preferences.consentGeneration == consent else { return }
        do {
            try await repository.save(record, wav: wav, policy: preferences.retention)
            if !preferences.retainAudio || preferences.consentGeneration != consent {
                try await repository.remove(record.id)
            }
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func update(_ record: VoiceEvaluationRecord) async {
        do {
            try await repository.update(record)
            try await repository.trim(policy: InputExperiencePreferences.shared.retention)
            await refresh()
        }
        catch { errorMessage = error.localizedDescription }
    }

    func remove(_ id: UUID) async {
        do { try await repository.remove(id); await refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func clear() async {
        InputExperiencePreferences.shared.invalidatePendingRecordings()
        do {
            for record in try await repository.records() { try await repository.remove(record.id) }
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func trim() async {
        do { try await repository.trim(policy: InputExperiencePreferences.shared.retention); await refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func audioURL(_ record: VoiceEvaluationRecord) -> URL {
        Self.directory.appendingPathComponent(record.id.uuidString).appendingPathComponent("audio.wav")
    }
}

/// 仅在用户同意留存时创建。保存送入识别器的音频和未改写的识别结果。
@MainActor
final class VoiceEvaluationSession {
    let consent = InputExperiencePreferences.shared.consentGeneration
    var record = VoiceEvaluationRecord()
    private var pcm = Data()
    private var sampleRate: Double = 16000
    private var channels = 1
    private var oversized = false

    init() {
        record.model = SpeechModelLocator.resolvedVariant()?.rawValue ?? "unavailable"
        record.language = UserPreferences.shared.voiceInputLanguage
        record.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    func append(_ audio: VoiceRecording) {
        guard InputExperiencePreferences.shared.retainAudio,
              consent == InputExperiencePreferences.shared.consentGeneration else { pcm.removeAll(); return }
        guard !oversized else { return }
        // 防止为留存额外保留无限 PCM。超过单次 128 MB 时跳过，正常识别不受影响。
        guard pcm.count + audio.pcmData.count <= 128 * 1024 * 1024 else {
            oversized = true; pcm.removeAll()
            VoiceEvaluationArchive.shared.errorMessage = NSLocalizedString("experience.audio.tooLarge", comment: "")
            return
        }
        sampleRate = audio.sampleRate
        channels = audio.channelCount
        pcm.append(audio.pcmData)
        record.duration += audio.durationSeconds
    }

    func finish() {
        guard !pcm.isEmpty, !oversized else { return }
        if record.status == "captured" { record.status = record.rawText.isEmpty ? "empty" : "recognized" }
        let wav = Self.wav(pcm: pcm, sampleRate: Int(sampleRate), channels: channels)
        record.audioBytes = Int64(wav.count)
        let snapshot = record
        Task { await VoiceEvaluationArchive.shared.save(snapshot, wav: wav, consent: consent) }
    }

    static func wav(pcm: Data, sampleRate: Int, channels: Int) -> Data {
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ number: T) {
            var value = number.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        append(UInt32(pcm.count + 36)); data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(channels))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * channels * 2))
        append(UInt16(channels * 2)); append(UInt16(16))
        data.append(Data("data".utf8)); append(UInt32(pcm.count)); data.append(pcm)
        return data
    }
}
