//
//  fastvTests.swift
//  fastvTests
//
//  Created by rocky on 2025/11/19.
//

import Testing
@testable import fastv

struct fastvTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    /// 与 ChatManager 加载会话消息时的解析策略一致：非法 UUID 键应跳过，避免强制解包崩溃
    @Test func messageStorage_skipsInvalidUUIDKeys() {
        let input: [String: [String]] = [
            "not-a-uuid": ["x"],
            "550E8400-E29B-41D4-A716-446655440000": ["y"],
        ]
        let parsed = Dictionary(uniqueKeysWithValues: input.compactMap { key, value -> (UUID, [String])? in
            guard let uuid = UUID(uuidString: key) else { return nil }
            return (uuid, value)
        })
        #expect(parsed.count == 1)
        #expect(parsed.values.first?.first == "y")
    }

}
