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
    @State private var title: String = ""
    @State private var content: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("标题", text: $title)
                    .font(.title2)
                    .padding()
                
                Divider()
                
                TextEditor(text: $content)
                    .font(.body)
                    .padding()
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
    }
    
    private func saveNote() {
        let note = Note(
            title: title.isEmpty ? "无标题" : title,
            content: content
        )
        noteManager.add(note)
        dismiss()
    }
}

