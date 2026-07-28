//
//  RimeEngine.swift
//  QechoIME
//
//  librime C API 的 Swift 封装。方案数据来自 bundle 的 RimeData/（含预编译词典），
//  用户词典与日志放 ~/Library/Application Support/QechoIME/。
//  所有调用都在主线程（IMK 事件与 CFMessagePort 回调均在主 RunLoop）。
//

import Foundation

final class RimeEngine {
    static let shared = RimeEngine()

    struct Candidate {
        let text: String
        let comment: String
    }

    struct CompositionState {
        let preedit: String
        let cursorUTF8: Int
        let candidates: [Candidate]
        let highlightedIndex: Int
        let pageNumber: Int
        let isLastPage: Bool
    }

    private let rime: RimeApi
    private var session: RimeSessionId = 0
    private(set) var ready = false
    private var hasCalledSetup = false

    private init() {
        rime = rime_get_api().pointee
    }

    // MARK: - 生命周期

    func startIfNeeded() {
        guard !ready else { return }
        guard let sharedDataURL = Bundle.main.resourceURL?.appendingPathComponent("RimeData") else {
            NSLog("QechoIME: bundle 里找不到 RimeData 目录")
            return
        }
        let fileManager = FileManager.default
        let userDataURL = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QechoIME", isDirectory: true)
        let logURL = userDataURL.appendingPathComponent("logs", isDirectory: true)
        try? fileManager.createDirectory(at: logURL, withIntermediateDirectories: true)

        var traits = RimeTraits()
        withUnsafeMutableBytes(of: &traits) { $0.assumingMemoryBound(to: UInt8.self).update(repeating: 0) }
        traits.data_size = Int32(MemoryLayout<RimeTraits>.size - MemoryLayout<Int32>.size)
        traits.shared_data_dir = Self.leakedCString(sharedDataURL.path)
        traits.prebuilt_data_dir = Self.leakedCString(sharedDataURL.appendingPathComponent("build").path)
        traits.user_data_dir = Self.leakedCString(userDataURL.path)
        traits.staging_dir = Self.leakedCString(userDataURL.appendingPathComponent("build").path)
        traits.log_dir = Self.leakedCString(logURL.path)
        traits.distribution_name = Self.leakedCString("轻语输入法")
        traits.distribution_code_name = Self.leakedCString("QechoIME")
        traits.distribution_version = Self.leakedCString(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        )
        traits.app_name = Self.leakedCString("rime.qecho")
        traits.min_log_level = 2 // 只记 ERROR 及以上

        // setup（glog 初始化）进程内只允许一次；restartForConfigChange 复用时跳过
        if !hasCalledSetup {
            rime.setup?(&traits)
            hasCalledSetup = true
        }
        rime.initialize?(&traits)
        // 首次运行会把预置配置同步到用户目录；词典已预编译，维护很快
        if rime.start_maintenance?(0) != 0 {
            rime.join_maintenance_thread?()
        }
        session = rime.create_session?() ?? 0
        ready = session != 0
        if !ready {
            NSLog("QechoIME: Rime session 创建失败")
        }
    }

    /// session 可能被 Rime 部署等操作销毁，用前确保有效
    private func ensureSession() -> Bool {
        guard ready else { return false }
        if rime.find_session?(session) == 0 {
            session = rime.create_session?() ?? 0
        }
        return session != 0
    }

    // MARK: - 按键与状态

    func processKey(keysym: Int32, modifiers: Int32) -> Bool {
        guard ensureSession() else { return false }
        return rime.process_key?(session, keysym, modifiers) != 0
    }

    func snapshot() -> CompositionState? {
        guard ensureSession() else { return nil }
        var context = RimeContext()
        withUnsafeMutableBytes(of: &context) { $0.assumingMemoryBound(to: UInt8.self).update(repeating: 0) }
        context.data_size = Int32(MemoryLayout<RimeContext>.size - MemoryLayout<Int32>.size)
        guard rime.get_context?(session, &context) != 0 else { return nil }
        defer { _ = rime.free_context?(&context) }

        let preedit = context.composition.preedit.map { String(cString: $0) } ?? ""
        var candidates: [Candidate] = []
        if let list = context.menu.candidates {
            for index in 0..<Int(context.menu.num_candidates) {
                let raw = list[index]
                candidates.append(Candidate(
                    text: raw.text.map { String(cString: $0) } ?? "",
                    comment: raw.comment.map { String(cString: $0) } ?? ""
                ))
            }
        }
        return CompositionState(
            preedit: preedit,
            cursorUTF8: Int(context.composition.cursor_pos),
            candidates: candidates,
            highlightedIndex: Int(context.menu.highlighted_candidate_index),
            pageNumber: Int(context.menu.page_no),
            isLastPage: context.menu.is_last_page != 0
        )
    }

    /// 取走待上屏文本（没有则返回 nil）
    func consumeCommit() -> String? {
        guard ensureSession() else { return nil }
        var commit = RimeCommit()
        withUnsafeMutableBytes(of: &commit) { $0.assumingMemoryBound(to: UInt8.self).update(repeating: 0) }
        commit.data_size = Int32(MemoryLayout<RimeCommit>.size - MemoryLayout<Int32>.size)
        guard rime.get_commit?(session, &commit) != 0 else { return nil }
        defer { _ = rime.free_commit?(&commit) }
        return commit.text.map { String(cString: $0) }
    }

    var isComposing: Bool {
        guard let state = snapshot() else { return false }
        return !state.preedit.isEmpty
    }

    func selectCandidate(onCurrentPage index: Int) -> Bool {
        guard ensureSession() else { return false }
        return rime.select_candidate_on_current_page?(session, index) != 0
    }

    func clearComposition() {
        guard ensureSession() else { return }
        rime.clear_composition?(session)
    }

    /// 当前未转换的原始输入码，不改变组字状态。
    func rawInput() -> String {
        guard ensureSession() else { return "" }
        return rime.get_input?(session).map { String(cString: $0) } ?? ""
    }

    /// 取出当前原始输入串并清空组字区（焦点切换时兜底上屏用）
    func takeRawInput() -> String? {
        guard ensureSession() else { return nil }
        let raw = rime.get_input?(session).map { String(cString: $0) }
        rime.clear_composition?(session)
        return raw
    }

    // MARK: - 方案与选项（设置页 / 输入法菜单）

    /// 当前会话使用的 Rime schema_id
    func currentSchemaId() -> String? {
        guard ensureSession() else { return nil }
        var buffer = [CChar](repeating: 0, count: 256)
        guard rime.get_current_schema?(session, &buffer, buffer.count) != 0 else { return nil }
        return String(cString: buffer)
    }

    @discardableResult
    func selectSchema(_ schemaId: String) -> Bool {
        guard ensureSession() else { return false }
        return schemaId.withCString { rime.select_schema?(session, $0) != 0 }
    }

    /// 运行时开关（ascii_mode / full_shape 等）
    func option(_ name: String) -> Bool {
        guard ensureSession() else { return false }
        return name.withCString { rime.get_option?(session, $0) != 0 }
    }

    func setOption(_ name: String, value: Bool) {
        guard ensureSession() else { return }
        name.withCString { rime.set_option?(session, $0, value ? 1 : 0) }
    }

    /// 配置文件（*.custom.yaml）变更后的整体重启：销毁会话 → finalize → 重新初始化并部署。
    /// 只应在用户改设置时触发，不在打字热路径上。
    func restartForConfigChange() {
        guard ready else {
            startIfNeeded()
            return
        }
        if session != 0 {
            _ = rime.destroy_session?(session)
            session = 0
        }
        rime.finalize?()
        ready = false
        startIfNeeded()
    }

    // MARK: - Private

    /// RimeTraits 要求 C 字符串在 setup/initialize 期间保持有效；
    /// 这些配置进程生命周期内只赋值一次，故意不释放。
    private static func leakedCString(_ string: String) -> UnsafePointer<CChar>? {
        UnsafePointer(strdup(string))
    }
}
