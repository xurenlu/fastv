//
//  EmailRuleManagementView.swift
//  fastv
//
//  Created for Email Rule Engine Management
//

import SwiftUI

/// 邮件规则管理界面
struct EmailRuleManagementView: View {
    @ObservedObject private var ruleEngine = EmailRuleEngine.shared
    @ObservedObject private var aiService = EmailRuleAIService.shared
    
    @State private var ruleFiles: [String] = []
    @State private var selectedFile: String?
    @State private var ruleContent: String = ""
    @State private var isEditing = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAIAssistant = false
    @State private var aiInput: String = ""
    @State private var aiResponse: String = ""
    
    var body: some View {
        NavigationView {
            HSplitView {
                // 左侧：规则文件列表
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("规则文件")
                            .font(.headline)
                        Spacer()
                        Button(action: createNewRule) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    
                    List(ruleFiles, id: \.self, selection: $selectedFile) { file in
                        Text(file)
                            .tag(file)
                    }
                    .listStyle(.sidebar)
                }
                .frame(minWidth: 200)
                
                // 右侧：规则编辑和 AI 助手
                VStack(alignment: .leading, spacing: 0) {
                    if let selected = selectedFile {
                        // 规则编辑器
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(selected)
                                    .font(.headline)
                                Spacer()
                                
                                Button(action: { showAIAssistant.toggle() }) {
                                    Label("AI 助手", systemImage: "sparkles")
                                }
                                
                                Button(action: testRule) {
                                    Label("测试", systemImage: "play.circle")
                                }
                                
                                Button(action: saveRule) {
                                    Label("保存", systemImage: "square.and.arrow.down")
                                }
                            }
                            .padding()
                            
                            if let error = errorMessage {
                                Text(error)
                                    .foregroundColor(.red)
                                    .padding(.horizontal)
                            }
                            
                            TextEditor(text: $ruleContent)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                        }
                    } else {
                        VStack {
                            Text("选择一个规则文件或创建新规则")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("邮件规则管理")
            .sheet(isPresented: $showAIAssistant) {
                AIAssistantView(
                    input: $aiInput,
                    response: $aiResponse,
                    onGenerate: generateRuleWithAI,
                    onModify: modifyRuleWithAI
                )
            }
            .onAppear {
                loadRuleFiles()
            }
            .onChange(of: selectedFile) { _, newValue in
                if let file = newValue {
                    loadRuleFile(file)
                }
            }
        }
    }
    
    private func loadRuleFiles() {
        ruleFiles = ruleEngine.listRuleFiles()
        if ruleFiles.isEmpty {
            // 如果没有规则文件，创建默认规则
            Task {
                await ruleEngine.loadRules()
                ruleFiles = ruleEngine.listRuleFiles()
            }
        }
    }
    
    private func loadRuleFile(_ filename: String) {
        Task {
            let rulesDir = ruleEngine.getRulesDirectory()
            let fileURL = rulesDir.appendingPathComponent(filename)
            
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                await MainActor.run {
                    ruleContent = content
                    errorMessage = nil
                }
            }
        }
    }
    
    private func createNewRule() {
        let newFileName = "rule_\(Date().timeIntervalSince1970).lua"
        ruleContent = """
        -- 新规则文件
        -- 在这里编写你的邮件处理规则
        
        function processEmail(email)
            local result = {
                isImportant = false,
                isSpam = false,
                isSubscription = false,
                tags = {},
                priority = "normal"
            }
            
            -- 在这里添加你的规则逻辑
            
            return result
        end
        """
        selectedFile = newFileName
        isEditing = true
    }
    
    private func saveRule() {
        guard let file = selectedFile else { return }
        
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                try await ruleEngine.saveRuleFile(file, content: ruleContent)
                await MainActor.run {
                    isLoading = false
                    errorMessage = "规则已保存"
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "保存失败: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func testRule() {
        guard !ruleContent.isEmpty else { return }
        
        Task {
            isLoading = true
            errorMessage = nil
            
            // 创建测试邮件
            let testMessage = EmailMessage(
                accountId: UUID(),
                subject: "测试邮件主题",
                from: EmailContact(name: "测试发件人", email: "test@example.com"),
                textBody: "这是测试邮件的正文内容",
                preview: "这是一封测试邮件"
            )
            
            do {
                let result = try await ruleEngine.testRule(ruleContent, with: testMessage)
                await MainActor.run {
                    isLoading = false
                    errorMessage = "测试成功: \(result)"
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "测试失败: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func generateRuleWithAI() {
        guard !aiInput.isEmpty else { return }
        
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                let generatedCode = try await aiService.generateRule(from: aiInput)
                await MainActor.run {
                    ruleContent = generatedCode
                    aiResponse = "规则已生成"
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "生成失败: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func modifyRuleWithAI() {
        guard !aiInput.isEmpty, !ruleContent.isEmpty else { return }
        
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                // 尝试提取函数名
                let functionName = extractFunctionName(from: ruleContent) ?? "processEmail"
                let modifiedCode = try await aiService.modifyRule(functionName, modification: aiInput)
                await MainActor.run {
                    ruleContent = modifiedCode
                    aiResponse = "规则已修改"
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "修改失败: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func extractFunctionName(from code: String) -> String? {
        if let range = code.range(of: "function ") {
            let remaining = String(code[range.upperBound...])
            if let endRange = remaining.range(of: "(") {
                return String(remaining[..<endRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

/// AI 助手视图
struct AIAssistantView: View {
    @Binding var input: String
    @Binding var response: String
    let onGenerate: () -> Void
    let onModify: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("描述你想要的规则，AI 会帮你生成或修改规则代码")
                    .foregroundColor(.secondary)
                
                TextEditor(text: $input)
                    .frame(height: 100)
                    .border(Color.gray.opacity(0.3))
                
                HStack {
                    Button("生成新规则") {
                        onGenerate()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("修改现有规则") {
                        onModify()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
                
                if !response.isEmpty {
                    Text("响应:")
                        .font(.headline)
                    Text(response)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("AI 规则助手")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    EmailRuleManagementView()
}

