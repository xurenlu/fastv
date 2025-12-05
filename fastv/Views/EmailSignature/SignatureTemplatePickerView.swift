//
//  SignatureTemplatePickerView.swift
//  fastv
//
//  Created for Signature Template Picker View
//

import SwiftUI
import AppKit

/// 签名模板选择器视图
struct SignatureTemplatePickerView: View {
    @ObservedObject var viewModel: EmailSignatureViewModel
    @Environment(\.dismiss) private var dismiss
    let onSelect: (EmailSignatureTemplate) -> Void
    
    @State private var selectedCategory: String = "简洁风格"
    
    private let templates = EmailSignatureTemplates.shared.templates
    
    // 按类别分组模板
    private var groupedTemplates: [(category: String, templates: [EmailSignatureTemplate])] {
        [
            ("简洁风格", templates.filter { ["classic", "minimal", "clean"].contains($0.id) }),
            ("商务风格", templates.filter { ["business_full", "corporate", "executive"].contains($0.id) }),
            ("创意风格", templates.filter { ["modern", "creative"].contains($0.id) }),
            ("纯文本风格", templates.filter { ["plain_simple", "plain_business", "plain_minimal"].contains($0.id) })
        ]
    }
    
    private var currentTemplates: [EmailSignatureTemplate] {
        groupedTemplates.first { $0.category == selectedCategory }?.templates ?? []
    }
    
    var body: some View {
        NavigationStack {
            HSplitView {
                // 左侧：类别列表
                List(selection: $selectedCategory) {
                    ForEach(groupedTemplates, id: \.category) { group in
                        Text(group.category)
                            .tag(group.category)
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 200)
                
                // 右侧：模板预览网格
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 320, maximum: 400), spacing: 20)
                    ], spacing: 20) {
                        ForEach(currentTemplates) { template in
                            TemplatePreviewCard(template: template) {
                                onSelect(template)
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(minWidth: 600)
            }
            .navigationTitle("选择签名模板")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

/// 模板列表项（侧边栏）
struct TemplateListItem: View {
    let template: EmailSignatureTemplate
    
    var body: some View {
        HStack(spacing: 10) {
            // 小预览
            TemplateMiniPreview(html: template.content)
                .frame(width: 40, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                
                Text(template.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 模板预览卡片（主视图）
struct TemplatePreviewCard: View {
    let template: EmailSignatureTemplate
    let onSelect: () -> Void
    
    private var previewContent: String {
        guard let account = EmailStore.shared.getDefaultAccount() else {
            // 如果没有账号，使用示例数据
            return template.content
                .replacingOccurrences(of: "{{name}}", with: "张三")
                .replacingOccurrences(of: "{{email}}", with: "zhangsan@example.com")
                .replacingOccurrences(of: "{{title}}", with: "产品经理")
                .replacingOccurrences(of: "{{company}}", with: "科技有限公司")
                .replacingOccurrences(of: "{{phone}}", with: "+86 138 0000 0000")
                .replacingOccurrences(of: "{{website}}", with: "www.example.com")
                .replacingOccurrences(of: "{{address}}", with: "北京市朝阳区")
        }
        
        // 使用真实账号信息创建预览（其他字段用示例数据）
        return template.content
            .replacingOccurrences(of: "{{name}}", with: account.displayName)
            .replacingOccurrences(of: "{{email}}", with: account.emailAddress)
            .replacingOccurrences(of: "{{title}}", with: "产品经理")
            .replacingOccurrences(of: "{{company}}", with: "科技有限公司")
            .replacingOccurrences(of: "{{phone}}", with: "+86 138 0000 0000")
            .replacingOccurrences(of: "{{website}}", with: "www.example.com")
            .replacingOccurrences(of: "{{address}}", with: "北京市朝阳区")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 预览区域
            VStack(spacing: 0) {
                EmailBodyWebView(htmlBody: previewContent, textBody: nil, showImages: true)
                    .frame(height: 140)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.bottom, 12)
            
            // 模板信息
            VStack(alignment: .leading, spacing: 6) {
                Text(template.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(template.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.bottom, 12)
            
            // 使用按钮
            Button(action: onSelect) {
                Label("使用此模板", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// 迷你预览（用于侧边栏）
struct TemplateMiniPreview: View {
    let html: String
    
    var body: some View {
        EmailBodyWebView(htmlBody: html, textBody: nil, showImages: true)
            .scaleEffect(0.3)
            .frame(width: 133, height: 100)
    }
}
