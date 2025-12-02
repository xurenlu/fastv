//
//  MoodFilterView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI

// MARK: - DiaryMood UI Extension

extension DiaryMood {
    var color: Color {
        switch self {
        case .happy:
            return .yellow
        case .calm:
            return .green
        case .sad:
            return .blue
        case .anxious:
            return .orange
        case .excited:
            return .pink
        case .tired:
            return .purple
        }
    }
    
    var gradientColors: [Color] {
        switch self {
        case .happy:
            return [.yellow, .orange]
        case .calm:
            return [.green, .mint]
        case .sad:
            return [.blue, .cyan]
        case .anxious:
            return [.orange, .red]
        case .excited:
            return [.pink, .purple]
        case .tired:
            return [.purple, .indigo]
        }
    }
}

struct MoodFilterView: View {
    @ObservedObject var viewModel: DiaryViewModel
    @Namespace private var animation
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                // 全部
                moodCard(
                    mood: nil,
                    title: "全部",
                    icon: "square.grid.2x2.fill",
                    color: .gray,
                    gradientColors: [.gray.opacity(0.6), .gray.opacity(0.4)]
                )
                
                // 普通（没有心情）
                moodCard(
                    mood: nil,
                    title: "普通",
                    icon: "circle.fill",
                    color: .secondary,
                    gradientColors: [.secondary.opacity(0.6), .secondary.opacity(0.4)],
                    isNormal: true
                )
                
                // 各个心情
                ForEach(DiaryMood.allCases, id: \.self) { mood in
                    moodCard(
                        mood: mood,
                        title: mood.displayName,
                        icon: mood.icon,
                        color: mood.color,
                        gradientColors: mood.gradientColors
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }
    
    private func moodCard(
        mood: DiaryMood?,
        title: String,
        icon: String,
        color: Color,
        gradientColors: [Color],
        isNormal: Bool = false
    ) -> some View {
        let isSelected: Bool = {
            if isNormal {
                // "普通"：只显示没有心情的日记
                return viewModel.showNormalOnly
            } else if mood == nil {
                // "全部"：清除所有筛选
                return viewModel.selectedMood == nil && !viewModel.showNormalOnly && viewModel.searchText.isEmpty
            } else {
                return viewModel.selectedMood == mood && !viewModel.showNormalOnly
            }
        }()
        
        let count = viewModel.count(for: isNormal ? nil : mood)
        
        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if isNormal {
                    // "普通"：切换只显示没有心情的日记
                    if viewModel.showNormalOnly {
                        viewModel.showNormalOnly = false
                    } else {
                        viewModel.showNormalOnly = true
                        viewModel.selectedMood = nil
                        viewModel.searchText = ""
                    }
                } else if mood == nil {
                    // "全部"：清除所有筛选
                    viewModel.clearFilters()
                } else {
                    // 切换心情筛选
                    viewModel.showNormalOnly = false
                    if viewModel.selectedMood == mood {
                        viewModel.selectedMood = nil
                    } else {
                        viewModel.selectedMood = mood
                    }
                }
            }
        }) {
            VStack(spacing: 8) {
                // 图标
                ZStack {
                    // 渐变背景
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(color: color.opacity(0.3), radius: isSelected ? 8 : 4, y: isSelected ? 4 : 2)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(isSelected ? 1.1 : 1.0)
                
                // 标题和数量
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? color : .secondary)
                }
            }
            .frame(width: 80)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? color.opacity(0.1) : Color.clear)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: gradientColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        }
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

