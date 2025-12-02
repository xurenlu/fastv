//
//  EditDiaryEntryView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI

struct EditDiaryEntryView: View {
    let entry: DiaryEntry
    @ObservedObject var viewModel: DiaryViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var content: String
    @State private var selectedMood: DiaryMood?
    @State private var date: Date
    
    init(entry: DiaryEntry, viewModel: DiaryViewModel) {
        self.entry = entry
        self.viewModel = viewModel
        
        _title = State(initialValue: entry.title)
        _content = State(initialValue: entry.content)
        _selectedMood = State(initialValue: entry.mood)
        _date = State(initialValue: entry.date)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("编辑日记")
                .font(.title2)
                .fontWeight(.bold)
            
            // 标题
            VStack(alignment: .leading, spacing: 8) {
                Text("标题")
                    .font(.headline)
                TextField("标题", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            
            // 内容
            VStack(alignment: .leading, spacing: 8) {
                Text("内容")
                    .font(.headline)
                TextField("日记内容", text: $content, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(5...15)
            }
            
            // 心情
            VStack(alignment: .leading, spacing: 8) {
                Text("心情")
                    .font(.headline)
                Picker("心情", selection: $selectedMood) {
                    Text("无").tag(nil as DiaryMood?)
                    ForEach(DiaryMood.allCases, id: \.self) { mood in
                        Label(mood.displayName, systemImage: mood.icon)
                            .tag(mood as DiaryMood?)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // 日期
            VStack(alignment: .leading, spacing: 8) {
                Text("日期")
                    .font(.headline)
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
            }
            
            // 按钮
            HStack {
                Button("取消") {
                    viewModel.cancelEditEntry()
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("保存") {
                    saveEntry()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 500)
    }
    
    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func saveEntry() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedTitle.isEmpty && !trimmedContent.isEmpty else {
            return
        }
        
        viewModel.updateEntry(
            entry,
            title: trimmedTitle,
            content: trimmedContent,
            mood: selectedMood,
            date: date
        )
        
        dismiss()
    }
}

