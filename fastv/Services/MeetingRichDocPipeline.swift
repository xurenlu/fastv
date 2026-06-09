//
//  MeetingRichDocPipeline.swift
//  fastv
//
//  Created by rocky on 2026/06/03.
//

import Foundation
import Combine
import OSLog

/// 流式触发决策器输入
struct RichDocTriggerInput {
    /// 自上次触发以来累计的「未消费转写字符数」（按 Unicode 字符数计）
    let unconsumedCharCount: Int
    /// 距离上次触发的秒数（首次为 .infinity）
    let secondsSinceLastTrigger: Double
    /// 距离上次「有新增转写」的秒数；用来判断是否处于停顿态
    let secondsSinceLastTranscriptUpdate: Double
    /// 是否处于录音中。停止录音的尾段强制触发，由外部用 forceFinal 标记
    let isRecording: Bool
}

/// 流式触发决策器配置
struct RichDocTriggerConfig {
    /// 累计字符触发阈值（默认 200）
    var charThreshold: Int = 200
    /// 停顿触发阈值（默认距上次转写更新 >= 12 秒）
    var pauseSeconds: Double = 12.0
    /// 停顿触发要求的最小新增字符数（默认 30）
    var pauseMinChars: Int = 30
    /// 最短触发间隔（默认 25 秒，防止字符阈值被快速堆满后狂刷）
    var minIntervalSeconds: Double = 25.0
}

enum RichDocTriggerDecision: Equatable {
    case skip
    case trigger(reason: String)
}

/// 纯函数：根据输入决定要不要触发一次流式生成。可被单元测试直接调用。
func decideRichDocTrigger(
    input: RichDocTriggerInput,
    config: RichDocTriggerConfig = RichDocTriggerConfig()
) -> RichDocTriggerDecision {
    // 距上次触发太近，先放过（首次 secondsSinceLastTrigger 是 .infinity，不会卡到）
    if input.secondsSinceLastTrigger < config.minIntervalSeconds {
        return .skip
    }
    // 字符堆够阈值就直接触发
    if input.unconsumedCharCount >= config.charThreshold {
        return .trigger(reason: "chars>=\(config.charThreshold)")
    }
    // 进入停顿态，且有一定新增，触发一次「停顿收口」
    if input.unconsumedCharCount >= config.pauseMinChars &&
        input.secondsSinceLastTranscriptUpdate >= config.pauseSeconds {
        return .trigger(reason: "pause>=\(Int(config.pauseSeconds))s")
    }
    return .skip
}

/// 会议图文文档流式生成管线
///
/// 职责：
/// - 监听 MeetingRecordService 的转写增量（externally 调用 onTranscriptUpdated）
/// - 按段落 + 节流策略决定是否触发一次 AI 流式生成
/// - 用「已有图文文档 + 新增转写片段」做增量续写
/// - **流式期间**只更新 pipeline 自有 `@Published streamingMarkdown`，让 UI 单独订阅，
///   避免 token-by-token 写回 records[index] 触发整个 records 数组重新 publish
/// - 流式完成（commit）时一次性写回 record.richDocumentMarkdown 并 saveRecords
/// - 防重入：同一 record 不会并发触发多次
@MainActor
final class MeetingRichDocPipeline: ObservableObject {
    static let shared = MeetingRichDocPipeline()

    private let logger = Logger(subsystem: "com.fastv.meeting", category: "RichDocPipeline")
    var config = RichDocTriggerConfig()

    /// 当前正在流式的 record id（同一时间最多一条）
    @Published private(set) var streamingRecordId: UUID?
    /// 当前流式累计的 markdown（仅对 streamingRecordId 这条有效）。UI 应优先订阅这个，
    /// 录音中频繁的 token 增量只会刷新它，**不会**触发 records 数组重 publish。
    @Published private(set) var streamingMarkdown: String = ""

    private var streamingTask: Task<Void, Never>?
    /// 各 record 上一次转写更新时间（用于停顿判断）
    private var lastTranscriptUpdateAt: [UUID: Date] = [:]

    private init() {}

    /// UI 渲染辅助：传入 recordId 与该 record 的已落地 markdown，返回当下应展示的 markdown 文本。
    /// 流式中的那条 record → 返回 streamingMarkdown；其他 → 返回 fallbackMarkdown。
    func currentMarkdown(for recordId: UUID, fallback: String) -> String {
        if streamingRecordId == recordId && !streamingMarkdown.isEmpty {
            return streamingMarkdown
        }
        return fallback
    }

    /// 外部（MeetingRecordService）每次拿到新转写片段后调用一次
    func onTranscriptUpdated(recordId: UUID, in service: MeetingRecordService) {
        lastTranscriptUpdateAt[recordId] = Date()
        maybeTrigger(recordId: recordId, in: service, forceFinal: false)
    }

    /// 停止录音时调用，强制做最后一次整篇定稿
    func finalize(recordId: UUID, in service: MeetingRecordService) async {
        // 等当前流式跑完（如果有）
        if let task = streamingTask, streamingRecordId == recordId {
            await task.value
        }
        await runStream(recordId: recordId, in: service, isFinal: true)
        lastTranscriptUpdateAt.removeValue(forKey: recordId)
    }

    /// 录音被取消时调用
    func cancel(recordId: UUID) {
        if streamingRecordId == recordId {
            streamingTask?.cancel()
            streamingTask = nil
            streamingRecordId = nil
            streamingMarkdown = ""
        }
        lastTranscriptUpdateAt.removeValue(forKey: recordId)
    }

    // MARK: - 内部

    private func maybeTrigger(recordId: UUID, in service: MeetingRecordService, forceFinal: Bool) {
        guard streamingRecordId == nil else { return }  // 防重入
        guard let record = service.getRecord(id: recordId) else { return }

        let fullText = record.correctedText.isEmpty ? record.originalText : record.correctedText
        let cursor = min(record.richDocCursor, fullText.count)
        let unconsumed = max(0, fullText.count - cursor)

        let now = Date()
        let secondsSinceLastTrigger = record.lastRichDocAt.map { now.timeIntervalSince($0) } ?? .infinity
        let secondsSinceTranscript = lastTranscriptUpdateAt[recordId].map { now.timeIntervalSince($0) } ?? 0

        let decision = decideRichDocTrigger(
            input: RichDocTriggerInput(
                unconsumedCharCount: unconsumed,
                secondsSinceLastTrigger: secondsSinceLastTrigger,
                secondsSinceLastTranscriptUpdate: secondsSinceTranscript,
                isRecording: record.isRecording
            ),
            config: config
        )
        if forceFinal, unconsumed == 0, !record.richDocumentMarkdown.isEmpty {
            return
        }

        switch decision {
        case .skip:
            return
        case .trigger(let reason):
            logger.log("触发流式图文文档生成（\(reason, privacy: .public)），未消费 \(unconsumed) 字")
            streamingRecordId = recordId
            streamingMarkdown = record.richDocumentMarkdown  // 以已有文档为起点
            streamingTask = Task { @MainActor [weak self] in
                await self?.runStream(recordId: recordId, in: service, isFinal: false)
                self?.streamingRecordId = nil
                self?.streamingMarkdown = ""
                self?.streamingTask = nil
            }
        }
    }

    private func runStream(recordId: UUID, in service: MeetingRecordService, isFinal: Bool) async {
        guard let record = service.getRecord(id: recordId) else { return }
        let fullText = record.correctedText.isEmpty ? record.originalText : record.correctedText
        guard fullText.count > record.richDocCursor || (isFinal && !fullText.isEmpty) else { return }

        let newSegment = String(fullText.dropFirst(record.richDocCursor))
        let existingDoc = record.richDocumentMarkdown

        let preferences = UserPreferences.shared
        let config = preferences.getConfig(for: .meetingRichDoc)
        let profile = config.profile

        let systemPrompt = systemPromptForRichDoc(isFinal: isFinal)
        let userPrompt = userPromptForRichDoc(existingDoc: existingDoc, newSegment: newSegment, isFinal: isFinal)

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt],
        ]

        // 标记流式中，UI 显示打字光标（这一处只 mutate isRichDocStreaming bool，单字段刷新）
        service.setRichDocStreaming(true, for: recordId)

        var accumulated = ""
        let stream = ChatAIService.shared.sendMessageStream(
            messages: messages,
            profile: profile,
            model: config.model,
            timeout: config.timeout,
            systemPrompt: systemPrompt,
            preferences: preferences
        )

        do {
            for try await chunk in stream {
                if Task.isCancelled { break }
                accumulated += chunk
                // 流式期间**只**更新 pipeline 自有 @Published，不写回 records[index]，
                // 避免触发整个 records 数组 publish + UI 全列 diff
                streamingMarkdown = accumulated
            }
            // 收尾：一次性写回 record 并落盘
            service.commitRichDocStream(
                finalMarkdown: stripCodeFence(accumulated),
                cursor: fullText.count,
                triggeredAt: Date(),
                for: recordId
            )
            logger.log("流式图文文档完成，输出 \(accumulated.count) 字")
        } catch {
            logger.error("流式图文文档失败: \(error.localizedDescription)")
            // 失败时不推进 cursor，下次重试整段
            service.setRichDocStreaming(false, for: recordId)
        }
    }

    // MARK: - Prompt

    private func systemPromptForRichDoc(isFinal: Bool) -> String {
        let baseRules = """
你是一名专业的会议记录整理助手，输出**纯 Markdown**，不要包裹在代码块里。

【输出风格】
- 一级标题用 `# 会议主题`，下面分小节用 `## ## ##`
- 多用 **要点列表**、**表格**、**勾选框**（行动项），让文档「图文并茂」
- 当出现「流程 / 步骤 / 决策树 / 思维导图 / 架构关系」时，**主动用 mermaid 代码块**，例如：
  ```mermaid
  mindmap
    root((会议主题))
      议题A
      议题B
  ```
- 涉及数据对比、时间表、负责人/截止时间，**优先用表格**
- 行动项使用 `- [ ] 描述（负责人/截止）` 的勾选框语法
- 正文用简体中文，去掉口语化语气词

【硬性约束】
- 严格只输出 Markdown 文本本身，**不要加任何前后说明文字、不要写「以下是」、不要解释**
- 不要输出 ```markdown ... ``` 的外层 fence
- 不要重复输出整段原始转写文字，要做提炼
"""
        if isFinal {
            return baseRules + "\n【模式】最终定稿：请基于已有文档与全部新片段，输出**完整、连贯**的最终版图文文档，可以重新组织结构。"
        } else {
            return baseRules + "\n【模式】流式续写：在已有文档基础上，**保留并改写已有结构**，把新片段的信息融入合适小节。如果完全没有已有文档，请从 0 开始建立结构。允许直接输出新的完整文档版本，但要保持紧凑、可读。"
        }
    }

    private func userPromptForRichDoc(existingDoc: String, newSegment: String, isFinal: Bool) -> String {
        var prompt = ""
        if existingDoc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "【当前文档】\n（空，尚未生成）\n\n"
        } else {
            prompt += "【当前文档（Markdown）】\n\(existingDoc)\n\n"
        }
        prompt += "【新增转写片段】\n\(newSegment)\n\n"
        prompt += isFinal
            ? "请输出**最终版**完整图文文档（纯 Markdown）。"
            : "请输出**更新后的整篇**图文文档（纯 Markdown），把新片段融入合适的小节。"
        return prompt
    }

    private func stripCodeFence(_ s: String) -> String {
        var trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉模型偶尔多加的 ```markdown ... ``` 外壳
        if trimmed.hasPrefix("```markdown") || trimmed.hasPrefix("```Markdown") {
            trimmed = String(trimmed.dropFirst(11))
        } else if trimmed.hasPrefix("```") {
            // 去掉首行的 ```xxx
            if let firstNewline = trimmed.firstIndex(of: "\n") {
                trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
            }
        }
        if trimmed.hasSuffix("```") {
            trimmed = String(trimmed.dropLast(3))
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
