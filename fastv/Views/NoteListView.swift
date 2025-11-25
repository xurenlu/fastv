//
//  NoteListView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

/// 笔记列表视图
struct NoteListView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var noteManager = NoteManager.shared
    @State private var selectedNote: Note?
    @State private var showNoteDetail = false
    @State private var showCreateNote = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 统计信息
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("笔记总数")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(noteManager.count())")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今日笔记")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(noteManager.todayCount())")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        showCreateNote = true
                    }) {
                        Label("新建笔记", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                
                Divider()
                
                // 笔记列表
                if noteManager.notes.isEmpty {
                    ContentUnavailableView {
                        Label("暂无笔记", systemImage: "note.text")
                    } description: {
                        Text("点击"新建笔记"开始创建")
                    }
                } else {
                    List(selection: $selectedNote) {
                        ForEach(noteManager.notes) { note in
                            NoteRow(note: note)
                                .tag(note)
                                .onTapGesture {
                                    selectedNote = note
                                    showNoteDetail = true
                                }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                noteManager.delete(noteManager.notes[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("语音备忘录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showNoteDetail) {
                if let note = selectedNote {
                    NoteDetailView(note: note)
                }
            }
            .sheet(isPresented: $showCreateNote) {
                CreateNoteView()
            }
        }
        .frame(width: 700, height: 600)
    }
}

/// 笔记行视图
struct NoteRow: View {
    let note: Note
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.title)
                .font(.headline)
                .lineLimit(1)
            
            Text(note.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            
            HStack {
                Text(note.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                if note.updatedAt != note.createdAt {
                    Text("已编辑")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// 笔记详情视图
struct NoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var noteManager = NoteManager.shared
    let note: Note
    @State private var title: String
    @State private var content: String
    @State private var hasChanges = false
    
    init(note: Note) {
        self.note = note
        _title = State(initialValue: note.title)
        _content = State(initialValue: note.content)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 标题输入
                TextField("标题", text: $title)
                    .font(.title2)
                    .padding()
                    .onChange(of: title) { _, _ in
                        hasChanges = true
                    }
                
                Divider()
                
                // 内容输入
                TextEditor(text: $content)
                    .font(.body)
                    .padding()
                    .onChange(of: content) { _, _ in
                        hasChanges = true
                    }
            }
            .navigationTitle("编辑笔记")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveNote()
                    }
                    .disabled(!hasChanges)
                }
            }
        }
        .frame(width: 600, height: 500)
    }
    
    private func saveNote() {
        var updatedNote = note
        updatedNote = Note(
            id: note.id,
            title: title,
            content: content,
            createdAt: note.createdAt,
            updatedAt: Date()
        )
        noteManager.update(updatedNote)
        dismiss()
    }
}

/// 创建笔记视图
struct CreateNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var noteManager = NoteManager.shared
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var isRecording = false
    @State private var showVoiceInput = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 标题输入
                TextField("标题", text: $title)
                    .font(.title2)
                    .padding()
                
                Divider()
                
                // 内容输入区域
                VStack(spacing: 0) {
                    // 工具栏
                    HStack {
                        Button(action: {
                            showVoiceInput = true
                        }) {
                            Label("语音输入", systemImage: "mic.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Spacer()
                        
                        if preferences.enableAIOptimization {
                            Button(action: {
                                optimizeContent()
                            }) {
                                Label("AI优化", systemImage: "sparkles")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(content.isEmpty)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    
                    Divider()
                    
                    // 文本编辑器
                    TextEditor(text: $content)
                        .font(.body)
                        .padding()
                }
            }
            .navigationTitle("新建笔记")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveNote()
                    }
                    .disabled(title.isEmpty && content.isEmpty)
                }
            }
        }
        .frame(width: 600, height: 500)
        .sheet(isPresented: $showVoiceInput) {
            VoiceInputForNoteView(content: $content)
        }
    }
    
    private func saveNote() {
        let note = Note(
            title: title.isEmpty ? "无标题" : title,
            content: content
        )
        noteManager.add(note)
        dismiss()
    }
    
    private func optimizeContent() {
        guard !content.isEmpty, preferences.enableAIOptimization else { return }
        
        Task {
            do {
                let optimized = try await OllamaService.shared.optimizeTranscript(
                    text: content,
                    endpoint: preferences.aiAPIEndpoint,
                    model: preferences.aiModel,
                    apiToken: preferences.aiAPIToken.isEmpty ? nil : preferences.aiAPIToken,
                    timeout: preferences.aiTimeout,
                    systemPrompt: preferences.aiSystemPrompt
                )
                await MainActor.run {
                    content = optimized
                }
            } catch {
                print("⚠️ [CreateNoteView] AI优化失败: \(error)")
            }
        }
    }
}

/// 语音输入笔记视图
struct VoiceInputForNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var content: String
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var transcribedText = ""
    @State private var isTranscribing = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("语音输入笔记")
                .font(.headline)
            
            if isTranscribing {
                ProgressView()
                Text("正在转文字...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("按下快捷键开始录音")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if !transcribedText.isEmpty {
                ScrollView {
                    Text(transcribedText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxHeight: 200)
            }
            
            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("添加到笔记") {
                    if !transcribedText.isEmpty {
                        if content.isEmpty {
                            content = transcribedText
                        } else {
                            content += "\n\n" + transcribedText
                        }
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(transcribedText.isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
        .onAppear {
            // 监听语音输入完成事件
            setupVoiceInputListener()
        }
    }
    
    private func setupVoiceInputListener() {
        // 监听语音输入完成通知
        NotificationCenter.default.addObserver(
            forName: .voiceInputCompleted,
            object: nil,
            queue: .main
        ) { notification in
            if let text = notification.userInfo?["text"] as? String {
                self.transcribedText = text
                self.isTranscribing = false
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

