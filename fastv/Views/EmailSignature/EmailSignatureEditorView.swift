//
//  EmailSignatureEditorView.swift
//  fastv
//
//  Created for Email Signature Editor View
//

import SwiftUI
import AppKit
import Combine

// MARK: - 控制器：把光标插入指令从 SwiftUI 这一侧传给底层 NSTextView

/// 签名编辑器的"插入指令"桥。
/// 让"点击变量芯片"这种 SwiftUI 事件能精确落到 NSTextView 当前光标位置，
/// 而不是粗暴地往字符串末尾追加（粗暴追加会破坏用户正在编辑的位置）。
final class SignatureEditorController: ObservableObject {
    fileprivate weak var textView: NSTextView?

    /// 在当前光标位置插入一段文本，支持 Undo，并把光标推到插入后的末尾。
    /// 若 NSTextView 还没就绪（视图尚未挂载），fallback 到 onAppend 回调，由调用方往 binding 末尾追加。
    func insert(_ fragment: String, onAppend: (() -> Void)? = nil) {
        guard let tv = textView else {
            onAppend?()
            return
        }
        let range = tv.selectedRange()
        guard tv.shouldChangeText(in: range, replacementString: fragment) else { return }
        tv.replaceCharacters(in: range, with: fragment)
        tv.didChangeText()

        let inserted = (fragment as NSString).length
        let newLocation = range.location + inserted
        tv.setSelectedRange(NSRange(location: newLocation, length: 0))
        tv.window?.makeFirstResponder(tv)
        tv.scrollRangeToVisible(NSRange(location: newLocation, length: 0))
    }
}

// MARK: - NSTextView 包装：支持等宽/常规字体切换 + 暴露光标 NSTextView 给控制器

struct SignatureTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isMonospace: Bool
    @ObservedObject var controller: SignatureEditorController

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let tv = NSTextView()
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.font = Self.font(isMonospace: isMonospace)
        tv.string = text
        tv.delegate = context.coordinator

        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .lineBorder
        scroll.drawsBackground = false

        controller.textView = tv
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        // 字体可能在 isHtml 切换时变化。
        let wantFont = Self.font(isMonospace: isMonospace)
        if tv.font != wantFont { tv.font = wantFont }
        // 外部 binding 变化时把内容同步进来；保留选中位置，避免抢光标。
        if tv.string != text {
            let prev = tv.selectedRange()
            tv.string = text
            let cap = (text as NSString).length
            let loc = min(prev.location, cap)
            tv.setSelectedRange(NSRange(location: loc, length: 0))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private static func font(isMonospace: Bool) -> NSFont {
        isMonospace
            ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 13)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SignatureTextEditor
        init(_ parent: SignatureTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

// MARK: - 主编辑视图

struct EmailSignatureEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: EmailSignatureViewModel
    @StateObject private var editor = SignatureEditorController()

    @State private var name: String
    @State private var content: String
    @State private var isHtml: Bool
    @State private var isDefault: Bool
    @State private var showPreview = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let signature: EmailSignature?
    private let template: EmailSignatureTemplate?
    private let accountId: UUID?

    init(signature: EmailSignature? = nil, template: EmailSignatureTemplate? = nil, viewModel: EmailSignatureViewModel) {
        self.signature = signature
        self.template = template
        self.viewModel = viewModel

        if let template = template {
            _name = State(initialValue: template.name)
            _content = State(initialValue: template.content)
            _isHtml = State(initialValue: template.isHtml)
            _isDefault = State(initialValue: false)
        } else {
            _name = State(initialValue: signature?.name ?? "")
            _content = State(initialValue: signature?.content ?? "")
            _isHtml = State(initialValue: signature?.isHtml ?? false)
            _isDefault = State(initialValue: signature?.isDefault ?? false)
        }

        self.accountId = EmailStore.shared.getDefaultAccount()?.id
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let errorMessage = errorMessage {
                        errorBanner(errorMessage)
                    }

                    nameAndOptionsRow

                    Divider()

                    editorBlock

                    Divider()

                    variableChipsBlock

                    Divider()

                    helpAndPreviewRow
                }
                .padding(20)
            }
            .navigationTitle(signature == nil ? "新建签名" : "编辑签名")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showPreview) { previewSheet }
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 520, idealHeight: 600)
    }

    // MARK: - 子块

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// 名称 + HTML / 默认 / 预览 一行搞定，省竖向空间。
    private var nameAndOptionsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("名称")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)
                TextField("例如：日常工作 / 商务正式", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 16) {
                Toggle("HTML 格式", isOn: $isHtml)
                    .toggleStyle(.checkbox)
                Toggle("设为默认", isOn: $isDefault)
                    .toggleStyle(.checkbox)
                Spacer()
                Button {
                    showPreview = true
                } label: {
                    Label("预览", systemImage: "eye")
                }
                .controlSize(.small)
                .disabled(content.isEmpty)
            }
        }
    }

    private var editorBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("签名内容")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if isHtml {
                    Text("HTML")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }
            SignatureTextEditor(text: $content, isMonospace: isHtml, controller: editor)
                .frame(minHeight: 180, idealHeight: 220, maxHeight: 320)
        }
    }

    /// 紧凑的可点击变量芯片，横向网格自动换行，点击插入到光标位置。
    private var variableChipsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "curlybraces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("可用变量")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("点击插入到光标位置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130, maximum: 200), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(SignatureVariable.allCases, id: \.self) { variable in
                    variableChip(variable)
                }
            }
        }
    }

    private func variableChip(_ variable: SignatureVariable) -> some View {
        Button {
            insertVariable(variable.rawValue)
        } label: {
            HStack(spacing: 6) {
                Text(variable.rawValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(variable.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue.opacity(0.18), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("点击把 \(variable.rawValue) 插入光标位置 — \(variable.description)")
    }

    private func insertVariable(_ token: String) {
        editor.insert(token) {
            // NSTextView 还没挂上时的兜底：往字符串末尾追加。
            content += token
        }
    }

    /// 把原先 4 行 footer + 信息文案压成一句 + 折叠的"了解更多"，省一截高度。
    private var helpAndPreviewRow: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                Text("• 变量在发送时自动替换：例如 {{name}} → 发件人姓名。")
                Text("• {{name}} / {{email}} 从账号信息自动读取。")
                Text("• 其他变量（{{title}}, {{phone}} …）需要在编辑时手动替换为实际内容，未填写的会在发送时自动移除。")
                if isHtml {
                    Text("• HTML 兼容性：建议使用 <table> 表格布局 + 内联样式，避免 Flexbox / Grid 与复杂阴影渐变。")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("变量替换规则")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
                .disabled(isSaving)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await saveSignature() }
            } label: {
                if isSaving {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Text("保存")
                }
            }
            .disabled(name.isEmpty || content.isEmpty || isSaving)
        }
    }

    // MARK: - 预览 Sheet

    @ViewBuilder
    private var previewSheet: some View {
        if let accountId = accountId {
            SignaturePreviewView(content: content, isHtml: isHtml, accountId: accountId)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("无法预览").font(.headline)
                Text("请先添加邮箱账号")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        }
    }

    // MARK: - 保存

    private func saveSignature() async {
        guard let accountId = accountId else {
            errorMessage = "未找到邮箱账号，请先添加邮箱账号后再创建签名"
            return
        }
        isSaving = true
        errorMessage = nil

        let signatureToSave: EmailSignature
        if let existing = signature {
            signatureToSave = EmailSignature(
                id: existing.id,
                accountId: accountId,
                name: name,
                content: content,
                isHtml: isHtml,
                isDefault: isDefault,
                createdAt: existing.createdAt,
                updatedAt: Date()
            )
        } else {
            signatureToSave = EmailSignature(
                accountId: accountId,
                name: name,
                content: content,
                isHtml: isHtml,
                isDefault: isDefault
            )
        }

        do {
            try await EmailSignatureService.shared.saveSignature(signatureToSave)
            if isDefault {
                try await EmailSignatureService.shared.setDefaultSignature(id: signatureToSave.id, accountId: accountId)
            }
            await viewModel.loadSignatures()
            dismiss()
        } catch {
            errorMessage = "保存签名失败: \(error.localizedDescription)"
            print("❌ [EmailSignatureEditorView] 保存签名失败: \(error)")
        }
        isSaving = false
    }
}

// MARK: - 预览视图

struct SignaturePreviewView: View {
    let content: String
    let isHtml: Bool
    let accountId: UUID
    @Environment(\.dismiss) private var dismiss

    private var renderedContent: String {
        guard let account = EmailStore.shared.getAccount(id: accountId) else {
            return content
        }
        let signature = EmailSignature(
            accountId: accountId,
            name: "预览",
            content: content,
            isHtml: isHtml
        )
        return EmailSignatureService.shared.renderSignature(signature, for: account)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if isHtml {
                    EmailBodyWebView(htmlBody: renderedContent, textBody: nil, showImages: true)
                        .frame(minHeight: 200)
                        .padding()
                } else {
                    Text(renderedContent)
                        .font(.system(.body))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .navigationTitle("签名预览")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
