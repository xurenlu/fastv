//
//  WordCloudView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI
import AppKit

/// 词云视图
struct WordCloudView: View {
    let keywordFrequency: [String: Int]
    let selectedKeyword: String?
    let onKeywordTapped: (String) -> Void
    
    @State private var wordPositions: [WordPosition] = []
    
    private struct WordPosition: Identifiable {
        let id: String
        let word: String
        let frequency: Int
        let fontSize: CGFloat
        let position: CGPoint
        let color: Color
    }
    
    private var maxFrequency: Int {
        keywordFrequency.values.max() ?? 1
    }
    
    private var minFrequency: Int {
        keywordFrequency.values.min() ?? 1
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(wordPositions) { wordPos in
                    Text(wordPos.word)
                        .font(.system(size: wordPos.fontSize, weight: .medium))
                        .foregroundStyle(wordPos.color)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(wordPos.word == selectedKeyword ? Color(NSColor.controlAccentColor).opacity(0.2) : Color.clear)
                        }
                        .overlay {
                            if wordPos.word == selectedKeyword {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color(NSColor.controlAccentColor), lineWidth: 2)
                            }
                        }
                        .position(wordPos.position)
                        .onTapGesture {
                            onKeywordTapped(wordPos.word)
                        }
                        .help("\(wordPos.word) (\(wordPos.frequency)次)")
                }
            }
            .onAppear {
                calculateWordPositions(in: geometry.size)
            }
            .onChange(of: keywordFrequency) { _, _ in
                calculateWordPositions(in: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                calculateWordPositions(in: newSize)
            }
        }
        .frame(height: 200)
    }
    
    private func calculateWordPositions(in size: CGSize) {
        var positions: [WordPosition] = []
        let sortedKeywords = keywordFrequency.sorted { $0.value > $1.value }
        
        // 基础字体大小范围
        let minFontSize: CGFloat = 12
        let maxFontSize: CGFloat = 32
        
        // 颜色方案（根据实体类型或随机）
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .pink, .red, .teal, .indigo
        ]
        
        var usedPositions: [CGPoint] = []
        let padding: CGFloat = 8
        let minDistance: CGFloat = 50
        
        for (index, (word, frequency)) in sortedKeywords.enumerated() {
            // 计算字体大小（基于频率）
            let normalizedFrequency = Double(frequency - minFrequency) / Double(maxFrequency - minFrequency)
            let fontSize = minFontSize + CGFloat(normalizedFrequency) * (maxFontSize - minFontSize)
            
            // 选择颜色
            let color = colors[index % colors.count]
            
            // 计算位置（简单的网格布局，避免重叠）
            var position: CGPoint
            var attempts = 0
            repeat {
                let row = index / 8
                let col = index % 8
                let x = padding + CGFloat(col) * (size.width - padding * 2) / 7
                let y = padding + CGFloat(row) * (size.height - padding * 2) / 5
                position = CGPoint(x: x, y: y)
                attempts += 1
            } while isTooClose(position, to: usedPositions, minDistance: minDistance) && attempts < 100
            
            usedPositions.append(position)
            
            positions.append(WordPosition(
                id: word,
                word: word,
                frequency: frequency,
                fontSize: fontSize,
                position: position,
                color: color
            ))
            
            // 限制显示的关键词数量
            if positions.count >= 30 {
                break
            }
        }
        
        wordPositions = positions
    }
    
    private func isTooClose(_ position: CGPoint, to usedPositions: [CGPoint], minDistance: CGFloat) -> Bool {
        for usedPos in usedPositions {
            let distance = sqrt(pow(position.x - usedPos.x, 2) + pow(position.y - usedPos.y, 2))
            if distance < minDistance {
                return true
            }
        }
        return false
    }
}

/// 词云容器视图（带标题和清除按钮）
struct WordCloudContainerView: View {
    @ObservedObject var viewModel: IntelViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("关键词云")
                    .font(.headline)
                
                Spacer()
                
                if viewModel.selectedKeyword != nil {
                    Button("清除筛选") {
                        viewModel.clearKeywordFilter()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            if viewModel.recentThreeMonthsKeywordFrequency.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.word.spacing")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("暂无关键词数据")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            } else {
                WordCloudView(
                    keywordFrequency: viewModel.recentThreeMonthsKeywordFrequency,
                    selectedKeyword: viewModel.selectedKeyword
                ) { keyword in
                    if viewModel.selectedKeyword == keyword {
                        viewModel.clearKeywordFilter()
                    } else {
                        viewModel.filterByKeyword(keyword)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        }
        .padding(.horizontal, 16)
    }
}

