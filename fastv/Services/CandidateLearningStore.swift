//
//  CandidateLearningStore.swift
//  fastv
//
//  独立于 Rime 动态词频开关的候选采用率记录。
//  数据只写入本机 QechoIME 用户数据目录，不上传。
//

import Foundation

enum CandidateSelectionSource: String, Codable {
    case keyboard
    case mouse
}

struct CandidateLearningMetric: Codable, Equatable {
    let schemaId: String
    let inputCode: String
    let candidate: String
    var resolvedMenuAppearances: Int
    var selections: Int
    var adoptionRate: Double
    var lastPresentedAt: Date
    var lastSelectedAt: Date?
}

struct CandidatePositionMetric: Codable, Equatable {
    let pageNumber: Int
    let indexOnPage: Int
    var resolvedMenuAppearances: Int
    var selections: Int
    var adoptionRate: Double
}

struct CandidateLearningStatistics: Codable, Equatable {
    static let currentVersion = 1
    static let maximumCandidateMetrics = 20_000

    var version = currentVersion
    var totalSelections = 0
    var selectionsWithDynamicRanking = 0
    var selectionsWithoutDynamicRanking = 0
    var keyboardSelections = 0
    var mouseSelections = 0
    var candidates: [String: CandidateLearningMetric] = [:]
    var positions: [String: CandidatePositionMetric] = [:]

    mutating func recordSelection(
        schemaId: String,
        inputCode: String,
        candidates visibleCandidates: [String],
        selectedIndex: Int,
        pageNumber: Int,
        dynamicRankingEnabled: Bool,
        source: CandidateSelectionSource,
        at date: Date = Date()
    ) {
        guard visibleCandidates.indices.contains(selectedIndex) else { return }

        totalSelections += 1
        if dynamicRankingEnabled {
            selectionsWithDynamicRanking += 1
        } else {
            selectionsWithoutDynamicRanking += 1
        }
        switch source {
        case .keyboard:
            keyboardSelections += 1
        case .mouse:
            mouseSelections += 1
        }

        for (index, candidate) in visibleCandidates.enumerated() {
            let key = Self.candidateKey(
                schemaId: schemaId,
                inputCode: inputCode,
                candidate: candidate
            )
            var metric = candidates[key] ?? CandidateLearningMetric(
                schemaId: schemaId,
                inputCode: inputCode,
                candidate: candidate,
                resolvedMenuAppearances: 0,
                selections: 0,
                adoptionRate: 0,
                lastPresentedAt: date,
                lastSelectedAt: nil
            )
            metric.resolvedMenuAppearances += 1
            metric.lastPresentedAt = date
            if index == selectedIndex {
                metric.selections += 1
                metric.lastSelectedAt = date
            }
            metric.adoptionRate = Double(metric.selections)
                / Double(metric.resolvedMenuAppearances)
            candidates[key] = metric

            let positionKey = Self.positionKey(pageNumber: pageNumber, indexOnPage: index)
            var position = positions[positionKey] ?? CandidatePositionMetric(
                pageNumber: pageNumber,
                indexOnPage: index,
                resolvedMenuAppearances: 0,
                selections: 0,
                adoptionRate: 0
            )
            position.resolvedMenuAppearances += 1
            if index == selectedIndex {
                position.selections += 1
            }
            position.adoptionRate = Double(position.selections)
                / Double(position.resolvedMenuAppearances)
            positions[positionKey] = position
        }

        pruneCandidateMetricsIfNeeded()
    }

    private mutating func pruneCandidateMetricsIfNeeded() {
        let overflow = candidates.count - Self.maximumCandidateMetrics
        guard overflow > 0 else { return }
        let oldestKeys = candidates
            .sorted { $0.value.lastPresentedAt < $1.value.lastPresentedAt }
            .prefix(overflow)
            .map(\.key)
        for key in oldestKeys {
            candidates.removeValue(forKey: key)
        }
    }

    private static func candidateKey(
        schemaId: String,
        inputCode: String,
        candidate: String
    ) -> String {
        [schemaId, inputCode, candidate]
            .map { Data($0.utf8).base64EncodedString() }
            .joined(separator: ".")
    }

    private static func positionKey(pageNumber: Int, indexOnPage: Int) -> String {
        "\(pageNumber):\(indexOnPage)"
    }
}

final class CandidateLearningStore {
    static let shared = CandidateLearningStore()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.17push.qecho-ime.candidate-learning")
    private var statistics: CandidateLearningStatistics
    private var saveGeneration = 0
    private var isDirty = false

    init(
        fileURL: URL = InputMethodBridgeContract.imeUserDataDirectory()
            .appendingPathComponent(InputMethodBridgeContract.candidateLearningFileName)
    ) {
        self.fileURL = fileURL
        statistics = Self.load(from: fileURL)
    }

    func recordSelection(
        schemaId: String,
        inputCode: String,
        candidates: [String],
        selectedIndex: Int,
        pageNumber: Int,
        dynamicRankingEnabled: Bool,
        source: CandidateSelectionSource
    ) {
        queue.async { [self] in
            statistics.recordSelection(
                schemaId: schemaId,
                inputCode: inputCode,
                candidates: candidates,
                selectedIndex: selectedIndex,
                pageNumber: pageNumber,
                dynamicRankingEnabled: dynamicRankingEnabled,
                source: source
            )
            isDirty = true
            saveGeneration += 1
            let scheduledGeneration = saveGeneration
            queue.asyncAfter(deadline: .now() + 0.75) { [self] in
                guard scheduledGeneration == saveGeneration, isDirty else { return }
                persist()
            }
        }
    }

    /// 确保退出输入上下文前，已排队的采用记录全部落盘。
    func flush() {
        queue.sync {
            guard isDirty else { return }
            persist()
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(statistics).write(to: fileURL, options: .atomic)
            isDirty = false
        } catch {
            NSLog("QechoIME: 候选采用率写入失败 \(error.localizedDescription)")
        }
    }

    private static func load(from fileURL: URL) -> CandidateLearningStatistics {
        guard let data = try? Data(contentsOf: fileURL) else {
            return CandidateLearningStatistics()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let saved = try? decoder.decode(CandidateLearningStatistics.self, from: data),
              saved.version <= CandidateLearningStatistics.currentVersion else {
            return CandidateLearningStatistics()
        }
        return saved
    }
}
