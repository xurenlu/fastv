//
//  CommonMistakeManagementSheet.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

/// 常用词管理弹窗
struct CommonMistakeManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var mistakeManager = CommonMistakeManager.shared
    @State private var showAddDialog = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 统计信息
                HStack(spacing: 30) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("常用词总数")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(mistakeManager.totalCount())")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("已修正次数")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(mistakeManager.totalCorrections())")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                    
                    Toggle("启用自动修正", isOn: $mistakeManager.enableAutoCorrection)
                }
                .padding()
                
                Divider()
                
                // 常用词列表（复用SettingsView中的组件）
                if mistakeManager.mistakes.isEmpty {
                    ContentUnavailableView {
                        Label("暂无常错词", systemImage: "text.badge.checkmark")
                    } description: {
                        Text("请手动添加常用词，系统会在语音转文字时自动修正")
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(mistakeManager.mistakes) { mistake in
                                CommonMistakeRow(
                                    mistake: mistake,
                                    onEdit: {
                                        // TODO: 实现编辑
                                    },
                                    onDelete: {
                                        mistakeManager.remove(mistake)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("常用词管理")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        showAddDialog = true
                    }) {
                        Label("添加", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddDialog) {
                AddMistakeSheetView()
            }
        }
        .frame(width: 600, height: 500)
    }
}

