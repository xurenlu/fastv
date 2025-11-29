//
//  HighFrequencyWordExtractionView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

// MARK: - 高频词提取视图

struct HighFrequencyWordExtractionView: View {
    @ObservedObject private var wordExtractor = HighFrequencyWordExtractor.shared
    @ObservedObject private var history = VoiceInputHistory.shared
    @State private var showExtractionAlert = false
    @State private var extractionMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                Text("高频词提取")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if !wordExtractor.highFrequencyWords.isEmpty {
                    Text("\(wordExtractor.highFrequencyWords.count) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if wordExtractor.isExtracting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(wordExtractor.extractionProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    Button(action: {
                        extractHighFrequencyWords()
                    }) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("从历史记录提取")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(history.items.isEmpty)
                    
                    if !wordExtractor.highFrequencyWords.isEmpty {
                        Button(action: {
                            wordExtractor.clear()
                            extractionMessage = "高频词已清空"
                            showExtractionAlert = true
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("清空")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundStyle(.red)
                    }
                }
            }
            
            if !wordExtractor.highFrequencyWords.isEmpty && !wordExtractor.isExtracting {
                // 显示前10个高频词
                let topWords = Array(wordExtractor.highFrequencyWords.prefix(10))
                VStack(alignment: .leading, spacing: 4) {
                    Text("高频词示例（前10个）：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(topWords.map { "\($0.word)(\($0.frequency))" }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
        .alert("提取结果", isPresented: $showExtractionAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(extractionMessage)
        }
    }
    
    private func extractHighFrequencyWords() {
        guard !history.items.isEmpty else {
            extractionMessage = "历史记录为空，无法提取高频词"
            showExtractionAlert = true
            return
        }
        
        Task {
            await wordExtractor.extractFromHistory(history.items)
            
            await MainActor.run {
                if wordExtractor.highFrequencyWords.isEmpty {
                    extractionMessage = "未找到高频词（需要至少出现3次）"
                } else {
                    extractionMessage = "提取完成，共找到 \(wordExtractor.highFrequencyWords.count) 个高频词"
                }
                showExtractionAlert = true
            }
        }
    }
}

