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
    
    private let signature: EmailSignature?
    private let accountId: UUID
    
    init(signature: EmailSignature? = nil, viewModel: EmailSignatureViewModel) {
        self.signature = signature
        self.viewModel = viewModel
        
        _name = State(initialValue: signature?.name ?? "")
        _content = State(initialValue: signature?.content ?? "")
        _isHtml = State(initialValue: signature?.isHtml ?? false)
        _isDefault = State(initialValue: signature?.isDefault ?? false)
        
        if let accountId = EmailStore.shared.getDefaultAccount()?.id {
            self.accountId = accountId
        } else {
            self.accountId = UUID()
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
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
                            .frame(height: 200)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        TextEditor(text: $content)
                            .frame(height: 200)
                    }
                    
                    // 变量提示
                    VStack(alignment: .leading, spacing: 8) {
                        Text("可用变量：")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        ForEach(SignatureVariable.allCases, id: \.self) { variable in
                            HStack(alignment: .top, spacing: 8) {
                                Text(variable.rawValue)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.blue)
                                    .textSelection(.enabled)
                                
                                Text(variable.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 8)
                } header: {
                    Text("签名内容")
                } footer: {
                    Text("使用变量可以自动替换为实际值，例如 {{name}} 会被替换为发件人姓名")
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
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        Task {
                            await saveSignature()
                        }
                    }
                    .disabled(name.isEmpty || content.isEmpty)
                }
            }
            .sheet(isPresented: $showPreview) {
                SignaturePreviewView(content: content, isHtml: isHtml, accountId: accountId)
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
    
    private func saveSignature() async {
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
            print("❌ [EmailSignatureEditorView] 保存签名失败: \(error)")
        }
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

