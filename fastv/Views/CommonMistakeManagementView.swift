//
//  CommonMistakeManagementView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

// MARK: - 常错词管理视图

struct CommonMistakeManagementView: View {
    @ObservedObject private var mistakeManager = CommonMistakeManager.shared
    @State private var searchText = "" {
        didSet {
            // 搜索文本改变时清除缓存
            filteredMistakesCache = []
            lastCacheUpdate = nil
        }
    }
    @State private var showAddDialog = false
    @State private var showEditDialog = false
    @State private var editingMistake: CommonMistake?
    @State private var newWrong = ""
    @State private var newCorrect = ""
    @State private var isAnalyzing = false
    @State private var analysisProgress = ""
    @State private var sortOption: SortOption = .frequency {
        didSet {
            // 排序选项改变时清除缓存
            filteredMistakesCache = []
            lastCacheUpdate = nil
        }
    }
    
    enum SortOption: String, CaseIterable {
        case frequency = "出现次数"
        case confidence = "置信度"
        case alphabetical = "字母顺序"
    }
    
    @State private var filteredMistakesCache: [CommonMistake] = []
    @State private var lastCacheUpdate: Date?
    
    var filteredMistakes: [CommonMistake] {
        // 如果缓存有效且搜索文本和排序选项没变，使用缓存
        let now = Date()
        if let lastUpdate = lastCacheUpdate,
           now.timeIntervalSince(lastUpdate) < 0.5, // 0.5秒内的缓存有效
           !filteredMistakesCache.isEmpty {
            return filteredMistakesCache
        }
        
        var mistakes = mistakeManager.mistakes
        
        // 搜索过滤
        if !searchText.isEmpty {
            mistakes = mistakes.filter { mistake in
                mistake.wrong.localizedCaseInsensitiveContains(searchText) ||
                mistake.correct.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // 排序
        switch sortOption {
        case .frequency:
            mistakes.sort { $0.frequency > $1.frequency }
        case .confidence:
            mistakes.sort { $0.confidence > $1.confidence }
        case .alphabetical:
            mistakes.sort { $0.wrong < $1.wrong }
        }
        
        // 更新缓存
        filteredMistakesCache = mistakes
        lastCacheUpdate = now
        
        return mistakes
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 统计信息和开关
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("常错词总数")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(mistakeManager.totalCount()) 个")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("已修正次数")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(mistakeManager.totalCorrections()) 次")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                Toggle("启用自动修正", isOn: $mistakeManager.enableAutoCorrection)
                    .toggleStyle(.switch)
                    .fixedSize()
            }
            
            Divider()
            
            // 操作按钮
            HStack(spacing: 12) {
                Button(action: {
                    newWrong = ""
                    newCorrect = ""
                    showAddDialog = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("手动添加")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .fixedSize()
                
                if !mistakeManager.mistakes.isEmpty {
                    Button(action: {
                        mistakeManager.remove(mistakeManager.mistakes)
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("清空全部")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .foregroundStyle(.red)
                    .fixedSize()
                }
            }
            
            // 搜索和排序
            if !mistakeManager.mistakes.isEmpty {
                HStack {
                    TextField("搜索错误词或正确词", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.regular)
                    
                    Picker("排序", selection: $sortOption) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.regular)
                    .fixedSize()
                }
            }
            
            Divider()
            
            // 常错词列表
            if mistakeManager.mistakes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.badge.checkmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.5))
                    
                    Text("暂无常错词")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("请手动添加常错词，系统会在语音转文字时自动修正")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if filteredMistakes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("未找到匹配的常错词")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredMistakes) { mistake in
                            CommonMistakeRow(mistake: mistake) {
                                editingMistake = mistake
                                newWrong = mistake.wrong
                                newCorrect = mistake.correct
                                showEditDialog = true
                            } onDelete: {
                                mistakeManager.remove(mistake)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 200, maxHeight: 400)
            }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 500)
        .onChange(of: mistakeManager.mistakes.count) { _, _ in
            // 常错词列表改变时清除缓存
            filteredMistakesCache = []
            lastCacheUpdate = nil
        }
        .sheet(isPresented: $showAddDialog) {
            AddMistakeDialog(
                wrong: $newWrong,
                correct: $newCorrect,
                onSave: {
                    if !newWrong.isEmpty && !newCorrect.isEmpty {
                        mistakeManager.addOrUpdate(wrong: newWrong, correct: newCorrect)
                        newWrong = ""
                        newCorrect = ""
                    }
                    showAddDialog = false
                },
                onCancel: {
                    showAddDialog = false
                }
            )
        }
        .sheet(isPresented: $showEditDialog) {
            if let mistake = editingMistake {
                EditMistakeDialog(
                    mistake: mistake,
                    wrong: $newWrong,
                    correct: $newCorrect,
                    onSave: {
                        var updated = mistake
                        updated.wrong = newWrong
                        updated.correct = newCorrect
                        mistakeManager.update(updated)
                        showEditDialog = false
                    },
                    onCancel: {
                        showEditDialog = false
                    }
                )
            }
        }
    }
}

// MARK: - 常错词行视图

struct CommonMistakeRow: View {
    let mistake: CommonMistake
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 错误词 -> 正确词
            HStack(spacing: 8) {
                Text(mistake.wrong)
                    .foregroundStyle(.red)
                    .strikethrough()
                    .font(.body)
                
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(mistake.correct)
                    .foregroundStyle(.green)
                    .fontWeight(.medium)
                    .font(.body)
            }
            
            Spacer()
            
            // 出现次数和置信度
            HStack(spacing: 12) {
                Label("\(mistake.frequency)", systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Label(String(format: "%.0f%%", mistake.confidence * 100), systemImage: "chart.bar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // 操作按钮 - 始终保留空间，hover时显示
            HStack(spacing: 8) {
                if isHovered {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.body)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("编辑")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.body)
                            .foregroundStyle(.red)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("删除")
                } else {
                    // 占位空间，保持布局稳定
                    Spacer()
                        .frame(width: 60)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - 添加常错词对话框

struct AddMistakeDialog: View {
    @Binding var wrong: String
    @Binding var correct: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("手动添加常错词")
                .font(.headline)
            
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
            
            HStack(spacing: 12) {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                
                Spacer()
                
                Button("添加", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(wrong.isEmpty || correct.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - 编辑常错词对话框

struct EditMistakeDialog: View {
    let mistake: CommonMistake
    @Binding var wrong: String
    @Binding var correct: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("编辑常错词")
                .font(.headline)
            
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
            
            HStack(spacing: 8) {
                Text("出现次数：\(mistake.frequency)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("置信度：\(String(format: "%.0f%%", mistake.confidence * 100))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 12) {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                
                Spacer()
                
                Button("保存", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(wrong.isEmpty || correct.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

