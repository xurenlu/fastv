//
//  EmailSignatureView.swift
//  fastv
//
//  Created for Email Signature Management View
//

import SwiftUI
import Combine

/// 邮件签名管理界面
struct EmailSignatureView: View {
    @StateObject private var viewModel = EmailSignatureViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false
    @State private var editingSignature: EmailSignature?
    @State private var showTemplatePicker = false
    @State private var selectedTemplate: EmailSignatureTemplate?
    
    // 确保模板选择后能正确打开编辑器
    private func handleTemplateSelected(_ template: EmailSignatureTemplate) {
        selectedTemplate = template
        editingSignature = nil
        showTemplatePicker = false
        // 延迟一点确保状态更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showEditor = true
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.signatures.isEmpty {
                    emptyStateView
                } else {
                    signatureListView
                }
            }
            .navigationTitle("邮件签名")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: {
                            editingSignature = nil
                            showEditor = true
                        }) {
                            Label("创建空白签名", systemImage: "doc.text")
                        }
                        
                        Divider()
                        
                        Button(action: {
                            showTemplatePicker = true
                        }) {
                            Label("从模板创建", systemImage: "square.grid.2x2")
                        }
                    } label: {
                        Label("新建", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showTemplatePicker) {
                SignatureTemplatePickerView(viewModel: viewModel) { template in
                    handleTemplateSelected(template)
                }
            }
            .sheet(isPresented: $showEditor) {
                if let signature = editingSignature {
                    EmailSignatureEditorView(signature: signature, viewModel: viewModel)
                } else if let template = selectedTemplate {
                    EmailSignatureEditorView(template: template, viewModel: viewModel)
                } else {
                    EmailSignatureEditorView(viewModel: viewModel)
                }
            }
            .task {
                await viewModel.loadSignatures()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "signature")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("还没有签名")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("创建签名后，可以在编写邮件时自动插入")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                Button(action: {
                    editingSignature = nil
                    selectedTemplate = nil
                    showEditor = true
                }) {
                    Label("创建空白签名", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    showTemplatePicker = true
                }) {
                    Label("从模板创建", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var signatureListView: some View {
        List {
            ForEach(viewModel.signatures) { signature in
                SignatureRow(signature: signature, viewModel: viewModel) {
                    editingSignature = signature
                    showEditor = true
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listStyle(.inset)
    }
}

/// 签名行视图
struct SignatureRow: View {
    let signature: EmailSignature
    @ObservedObject var viewModel: EmailSignatureViewModel
    let onEdit: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // 左侧图标
            Image(systemName: signature.isDefault ? "star.fill" : "signature")
                .font(.title3)
                .foregroundStyle(signature.isDefault ? .yellow : .secondary)
                .frame(width: 32)
            
            // 中间内容
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(signature.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    if signature.isDefault {
                        Label("默认", systemImage: "star.fill")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.8), Color.accentColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    
                    if signature.isHtml {
                        Text("HTML")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
                
                // 预览签名（纯文本版本）
                let preview = signature.isHtml ? 
                    signature.content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "&nbsp;", with: " ")
                        .replacingOccurrences(of: "&amp;", with: "&")
                        .replacingOccurrences(of: "&lt;", with: "<")
                        .replacingOccurrences(of: "&gt;", with: ">")
                        .replacingOccurrences(of: "&quot;", with: "\"")
                    : signature.content
                
                Text(String(preview.prefix(120)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            // 右侧操作菜单
            Menu {
                Button(action: {
                    Task {
                        await viewModel.setDefault(signature.id)
                    }
                }) {
                    Label("设为默认", systemImage: signature.isDefault ? "checkmark.circle.fill" : "circle")
                }
                .disabled(signature.isDefault)
                
                Button(action: onEdit) {
                    Label("编辑", systemImage: "pencil")
                }
                
                Divider()
                
                Button(role: .destructive, action: {
                    Task {
                        await viewModel.deleteSignature(signature.id)
                    }
                }) {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }
}

/// 签名管理视图模型
@MainActor
class EmailSignatureViewModel: ObservableObject {
    @Published var signatures: [EmailSignature] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let signatureService = EmailSignatureService.shared
    private let emailStore = EmailStore.shared
    
    func loadSignatures() async {
        guard let accountId = emailStore.getDefaultAccount()?.id else {
            errorMessage = "未选择账号"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            signatures = try await signatureService.getSignatures(for: accountId)
        } catch {
            errorMessage = "加载签名失败: \(error.localizedDescription)"
            print("❌ [EmailSignatureViewModel] 加载签名失败: \(error)")
        }
        
        isLoading = false
    }
    
    func setDefault(_ signatureId: UUID) async {
        guard let accountId = emailStore.getDefaultAccount()?.id else { return }
        
        do {
            try await signatureService.setDefaultSignature(id: signatureId, accountId: accountId)
            await loadSignatures()
        } catch {
            errorMessage = "设置默认签名失败: \(error.localizedDescription)"
            print("❌ [EmailSignatureViewModel] 设置默认签名失败: \(error)")
        }
    }
    
    func deleteSignature(_ signatureId: UUID) async {
        do {
            try await signatureService.deleteSignature(id: signatureId)
            await loadSignatures()
        } catch {
            errorMessage = "删除签名失败: \(error.localizedDescription)"
            print("❌ [EmailSignatureViewModel] 删除签名失败: \(error)")
        }
    }
}

