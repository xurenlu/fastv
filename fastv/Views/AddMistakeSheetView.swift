//
//  AddMistakeSheetView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

/// 添加常用词弹窗视图
struct AddMistakeSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var mistakeManager = CommonMistakeManager.shared
    @State private var wrong = ""
    @State private var correct = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("错误词（语音识别结果）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    TextField("例如：你好", text: $wrong)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("正确词（用户修正后）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    TextField("例如：您好", text: $correct)
                        .textFieldStyle(.roundedBorder)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("添加常用词")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        saveMistake()
                    }
                    .disabled(wrong.isEmpty || correct.isEmpty)
                }
            }
        }
        .frame(width: 400, height: 300)
    }
    
    private func saveMistake() {
        mistakeManager.addOrUpdate(wrong: wrong, correct: correct)
        dismiss()
    }
}

