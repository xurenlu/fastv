//
//  OllamaLocalModelTests.swift
//  fastvTests
//
//  覆盖本地 Ollama 模型（gemma4 等）做语音修正的两处硬约束：
//  1. 请求必须关思考模式——实测 gemma4:e4b-it-qat 开思考热调用 20.9s、关掉后 1.6s；
//  2. Ollama 的历史 5 秒超时必须被迁移抬升，否则本地模型光冷加载就超时，AI 校正永远失败。
//

import Testing
import Foundation
@testable import musetype

@Suite("Ollama 本地模型")
@MainActor
struct OllamaLocalModelTests {

    private func makeOllamaProfile(model: String = "gemma4:e4b-it-qat") -> AIServiceProfile {
        AIServiceProfile(name: "本地 Ollama", protocolType: .ollama, defaultModel: model)
    }

    @Test("Ollama 原生请求体关闭思考模式")
    func ollamaRequestDisablesThinking() {
        let body = AIServiceAdapter.shared.buildRequestBody(
            for: makeOllamaProfile(),
            messages: [["role": "user", "content": "今天下午三点开会"]],
            systemPrompt: "你是语音转写校正助手"
        )
        #expect(body[OllamaRequestDefaults.thinkingKey] as? Bool == false)
        #expect(body["stream"] as? Bool == false)
        #expect(body["model"] as? String == "gemma4:e4b-it-qat")
    }

    @Test("非 Ollama 协议不带 think 字段，避免污染 OpenAI 兼容服务")
    func nonOllamaRequestHasNoThinkingFlag() {
        let profile = AIServiceProfile(
            name: "OpenAI",
            protocolType: .openAI,
            apiKey: "sk-test",
            defaultModel: "gpt-4o-mini"
        )
        let body = AIServiceAdapter.shared.buildRequestBody(
            for: profile,
            messages: [["role": "user", "content": "hi"]]
        )
        #expect(body[OllamaRequestDefaults.thinkingKey] == nil)
    }

    @Test("gemma4 进入推荐模型与可下载模型库")
    func gemma4IsOffered() {
        #expect(AIProtocolType.ollama.recommendedModels.contains("gemma4:e4b-it-qat"))
        #expect(OllamaLibrary.isInLibrary("gemma4:e4b-it-qat"))
        #expect(OllamaLibrary.isInLibrary("gemma4:e2b-it-qat"))
        #expect(OllamaLibrary.getLibraryInfo(for: "gemma4:e4b-it-qat")?.parameterSize == "7.5B")
    }

    @Test("已下载的模型不再出现在可下载列表里")
    func downloadedModelsAreExcluded() {
        let available = OllamaLibrary.availableModels(excludingDownloaded: ["gemma4:e4b-it-qat"])
        #expect(available.contains { $0.name == "gemma4:e4b-it-qat" } == false)
        #expect(available.contains { $0.name == "gemma4:e2b-it-qat" })
    }

    @Test("Ollama 默认超时足够本地模型冷加载")
    func ollamaDefaultTimeoutCoversColdStart() {
        // 实测 gemma4:e4b-it-qat 关思考冷启动 8 秒；旧的 5 秒默认值必然超时
        #expect(AIProtocolType.ollama.defaultTimeout >= 30)
        #expect(AIProtocolType.ollama.defaultTimeout > AIProtocolType.legacyOllamaTimeout)
    }

    @Test("旧配置迁移：Ollama 的 5 秒超时被抬升，手调过的大值保留")
    func legacyOllamaTimeoutIsMigrated() throws {
        func decodeProfile(protocolType: String, timeout: Double) throws -> AIServiceProfile {
            let json = """
            {"id":"\(UUID().uuidString)","name":"旧配置","protocolType":"\(protocolType)",
             "endpoint":"http://127.0.0.1:11434","apiKey":"","defaultModel":"gemma2:2b",
             "timeout":\(timeout),"isDefault":true}
            """
            return try JSONDecoder().decode(AIServiceProfile.self, from: Data(json.utf8))
        }

        let migrated = try decodeProfile(protocolType: "ollama", timeout: 5.0)
        #expect(migrated.timeout == AIProtocolType.ollama.defaultTimeout)

        let userTuned = try decodeProfile(protocolType: "ollama", timeout: 90.0)
        #expect(userTuned.timeout == 90.0)

        // 云端协议的短超时是用户自己的选择，不受这条迁移影响
        let cloud = try decodeProfile(protocolType: "openai", timeout: 5.0)
        #expect(cloud.timeout == 5.0)
    }
}
