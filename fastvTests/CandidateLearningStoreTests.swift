//
//  CandidateLearningStoreTests.swift
//  fastvTests
//
//  候选采用率统计的聚合与动态词频开关解耦测试。
//

import XCTest
@testable import musetype

final class CandidateLearningStoreTests: XCTestCase {

    func testRecordsCandidateAndPositionAdoptionRates() throws {
        var statistics = CandidateLearningStatistics()
        let firstDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-28T10:00:00Z")
        )
        let secondDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-28T10:01:00Z")
        )

        statistics.recordSelection(
            schemaId: IMESchema.pinyin.rawValue,
            inputCode: "shuru",
            candidates: ["输入", "驶入", "书如"],
            selectedIndex: 1,
            pageNumber: 0,
            dynamicRankingEnabled: false,
            source: .keyboard,
            at: firstDate
        )
        statistics.recordSelection(
            schemaId: IMESchema.pinyin.rawValue,
            inputCode: "shuru",
            candidates: ["输入", "驶入", "书如"],
            selectedIndex: 0,
            pageNumber: 0,
            dynamicRankingEnabled: true,
            source: .mouse,
            at: secondDate
        )

        XCTAssertEqual(statistics.totalSelections, 2)
        XCTAssertEqual(statistics.selectionsWithDynamicRanking, 1)
        XCTAssertEqual(statistics.selectionsWithoutDynamicRanking, 1)
        XCTAssertEqual(statistics.keyboardSelections, 1)
        XCTAssertEqual(statistics.mouseSelections, 1)

        let inputMetric = try XCTUnwrap(
            statistics.candidates.values.first { $0.candidate == "输入" }
        )
        XCTAssertEqual(inputMetric.resolvedMenuAppearances, 2)
        XCTAssertEqual(inputMetric.selections, 1)
        XCTAssertEqual(inputMetric.adoptionRate, 0.5, accuracy: 0.0001)

        let firstPosition = try XCTUnwrap(statistics.positions["0:0"])
        XCTAssertEqual(firstPosition.resolvedMenuAppearances, 2)
        XCTAssertEqual(firstPosition.selections, 1)
        XCTAssertEqual(firstPosition.adoptionRate, 0.5, accuracy: 0.0001)
    }

    func testInvalidSelectionDoesNotRecordAnything() {
        var statistics = CandidateLearningStatistics()
        statistics.recordSelection(
            schemaId: IMESchema.mixed.rawValue,
            inputCode: "abc",
            candidates: ["阿", "吧"],
            selectedIndex: 9,
            pageNumber: 0,
            dynamicRankingEnabled: false,
            source: .keyboard
        )

        XCTAssertEqual(statistics, CandidateLearningStatistics())
    }

    func testStatisticsRoundTripPreservesDisabledDynamicRankingLearning() throws {
        var statistics = CandidateLearningStatistics()
        let fixedDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-28T10:02:00Z")
        )
        statistics.recordSelection(
            schemaId: IMESchema.wubi.rawValue,
            inputCode: "wqvb",
            candidates: ["输入", "输出"],
            selectedIndex: 0,
            pageNumber: 0,
            dynamicRankingEnabled: false,
            source: .keyboard,
            at: fixedDate
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(statistics)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertEqual(try decoder.decode(CandidateLearningStatistics.self, from: data), statistics)
    }

    func testStorePersistsSelectionToConfiguredLocalFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("candidate-learning.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CandidateLearningStore(fileURL: fileURL)

        store.recordSelection(
            schemaId: IMESchema.mixed.rawValue,
            inputCode: "khk",
            candidates: ["中", "忠"],
            selectedIndex: 1,
            pageNumber: 0,
            dynamicRankingEnabled: false,
            source: .keyboard
        )
        store.flush()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let saved = try decoder.decode(
            CandidateLearningStatistics.self,
            from: Data(contentsOf: fileURL)
        )
        XCTAssertEqual(saved.totalSelections, 1)
        XCTAssertEqual(saved.selectionsWithoutDynamicRanking, 1)
        XCTAssertEqual(
            saved.candidates.values.first { $0.candidate == "忠" }?.adoptionRate,
            1
        )
    }
}
