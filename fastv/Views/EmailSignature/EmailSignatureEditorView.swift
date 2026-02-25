//
//  EmailSignatureEditorView.swift
//  fastv
//
//  Created for Email Signature Editor View
//

import SwiftUI

/// 邮件签名编辑界面
struct EmailSignatureEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: EmailSignatureViewModel
    
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
        
        // 如果从模板创建，使用模板的内容（保留变量占位符，让用户编辑）
        if let template = template {
            _name = State(initialValue: template.name)
            _content = State(initialValue: template.content) // 使用原始模板内容，保留变量占位符
            _isHtml = State(initialValue: template.isHtml)
            _isDefault = State(initialValue: false)
        } else {
            _name = State(initialValue: signature?.name ?? "")
            _content = State(initialValue: signature?.content ?? "")
            _isHtml = State(initialValue: signature?.isHtml ?? false)
            _isDefault = State(initialValue: signature?.isDefault ?? false)
        }
        
        // 获取默认账号ID，如果没有则设为nil（保存时会检查）
        self.accountId = EmailStore.shared.getDefaultAccount()?.id
    }
    
    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section {
                    TextField("签名名称", text: $name)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("基本信息")
                }
                
                Section {
                    Toggle("HTML格式", isOn: $isHtml)
                    
                    if isHtml {
                        TextEditor(text: $content)
                            .frame(height: 250)
                            .font(.system(.body, design: .monospaced))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                        
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                                .font(.caption)
                            Text("为了确保在所有邮件客户端（如Outlook, Gmail）中显示正常，建议使用表格布局（<table>）而非 Flexbox/Grid，并使用内联样式。避免使用复杂的 CSS（如阴影、圆角、渐变）。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    } else {
                        TextEditor(text: $content)
                            .frame(height: 250)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    
                    // 变量提示 - 改进UI
                    VStack(alignment: .leading, spacing: 12) {
                        Text("可用变量")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(SignatureVariable.allCases, id: \.self) { variable in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(variable.rawValue)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.blue)
                                        .textSelection(.enabled)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    
                                    Text(variable.description)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("签名内容")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• 使用变量可以自动替换为实际值，例如 {{name}} 会被替换为发件人姓名")
                        Text("• {{name}} 和 {{email}} 会自动从账号信息中获取")
                        Text("• 其他变量（如 {{title}}, {{phone}} 等）请在编辑时手动替换为实际内容")
                        Text("• 未填写的变量在发送邮件时会自动移除，不会显示占位符")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                Section {
                    Toggle("设为默认签名", isOn: $isDefault)
                } header: {
                    Text("设置")
                }
                
                Section {
                    Button(action: {
                        showPreview = true
                    }) {
                        Label("预览签名", systemImage: "eye")
                    }
                }
            }
            .navigationTitle(signature == nil ? "新建签名" : "编辑签名")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        Task {
                            await saveSignature()
                        }
                    }) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("保存")
                        }
                    }
                    .disabled(name.isEmpty || content.isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showPreview) {
                if let accountId = accountId {
                    SignaturePreviewView(content: content, isHtml: isHtml, accountId: accountId)
                } else {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)
                        Text("无法预览")
                            .font(.headline)
                        Text("请先添加邮箱账号")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }
    
    private func saveSignature() async {
        // 检查账号是否存在
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
            
            // 如果设为默认，更新默认设置
            if isDefault {
                try await EmailSignatureService.shared.setDefaultSignature(id: signatureToSave.id, accountId: accountId)
            }
            
            await viewModel.loadSignatures()
            dismiss()
        } catch {
            let errorDesc = error.localizedDescription
            errorMessage = "保存签名失败: \(errorDesc)"
            print("❌ [EmailSignatureEditorView] 保存签名失败: \(error)")
        }
        
        isSaving = false
    }
}

/// 签名预览视图
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
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

