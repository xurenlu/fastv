//
//  EmailHomeView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

/// 邮箱首页视图 - 显示最近邮件的AI摘要概览（超精美版本）
struct EmailHomeView: View {
    @ObservedObject var viewModel: EmailViewModel
    @State private var recentMessages: [EmailMessage] = []
    @State private var isLoading = false
    @Environment(\.colorScheme) var colorScheme
    
    // 获取最近有AI摘要的邮件（最多20封）
    private var messagesWithSummary: [EmailMessage] {
        recentMessages
            .filter { $0.aiSummary != nil && !$0.aiSummary!.isEmpty }
            .prefix(20)
            .map { $0 }
    }
    
    // 按日期分组邮件
    private var groupedMessages: [(date: String, messages: [EmailMessage])] {
        let calendar = Calendar.current
        let now = Date()
        
        var groups: [String: [EmailMessage]] = [:]
        
        for message in messagesWithSummary {
            let dateKey: String
            if calendar.isDateInToday(message.date) {
                dateKey = "今天"
            } else if calendar.isDateInYesterday(message.date) {
                dateKey = "昨天"
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
                      message.date > weekAgo {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                formatter.locale = Locale(identifier: "zh_CN")
                dateKey = formatter.string(from: message.date)
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MM月dd日"
                formatter.locale = Locale(identifier: "zh_CN")
                dateKey = formatter.string(from: message.date)
            }
            
            if groups[dateKey] == nil {
                groups[dateKey] = []
            }
            groups[dateKey]?.append(message)
        }
        
        // 按日期排序（最新的在前）
        return groups.map { (date: $0.key, messages: $0.value.sorted { $0.date > $1.date }) }
            .sorted { date1, date2 in
                // 自定义排序：今天 > 昨天 > 其他日期
                if date1.date == "今天" { return true }
                if date2.date == "今天" { return false }
                if date1.date == "昨天" { return true }
                if date2.date == "昨天" { return false }
                return date1.date > date2.date
            }
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // 精美的渐变背景
            backgroundGradient
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 32) {
                    // 标题区域
                    headerView
                    
                    if isLoading {
                        loadingView
                    } else if messagesWithSummary.isEmpty {
                        emptyStateView
                    } else {
                        // 邮件摘要列表
                        summaryListView
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            loadRecentMessages()
        }
        .onChange(of: viewModel.messages.count) { _, _ in
            loadRecentMessages()
        }
        .onChange(of: viewModel.selectedMessageId) { _, _ in
            loadRecentMessages()
        }
    }
    
    // MARK: - Background Gradient
    
    private var backgroundGradient: some View {
        ZStack {
            // 主渐变背景
            LinearGradient(
                colors: colorScheme == .dark ? [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.08, green: 0.08, blue: 0.15),
                    Color(red: 0.05, green: 0.05, blue: 0.1)
                ] : [
                    Color(red: 0.98, green: 0.99, blue: 1.0),
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 0.98, green: 0.99, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // 装饰性渐变光晕
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.blue.opacity(0.08),
                            Color.purple.opacity(0.05),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 400
                    )
                )
                .frame(width: 800, height: 800)
                .offset(x: -200, y: -200)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.purple.opacity(0.06),
                            Color.pink.opacity(0.04),
                            Color.clear
                        ],
                        center: .bottomTrailing,
                        startRadius: 0,
                        endRadius: 500
                    )
                )
                .frame(width: 1000, height: 1000)
                .offset(x: 300, y: 300)
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                // 精美的图标容器
                ZStack {
                    // 渐变背景
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.2),
                                    Color.purple.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                    
                    // 图标
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("邮箱概览")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: colorScheme == .dark ? 
                                    [.white, Color(white: 0.9)] :
                                    [Color(red: 0.1, green: 0.1, blue: 0.2), Color(red: 0.2, green: 0.2, blue: 0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    HStack(spacing: 8) {
                        Image(systemName: "sparkle")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        
                        Text("基于最近邮件的AI摘要整理")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            
            // 精美的分割线
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .blue.opacity(0.3), .purple.opacity(0.3), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.blue)
            
            Text("正在加载邮件摘要...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            ZStack {
                // 背景光晕
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.blue.opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 12) {
                Text("暂无邮件摘要")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Text("当邮件生成AI摘要后，将在这里显示精美的概览")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
    
    // MARK: - Summary List View
    
    private var summaryListView: some View {
        VStack(alignment: .leading, spacing: 32) {
            ForEach(Array(groupedMessages.enumerated()), id: \.element.date) { index, group in
                dateGroupView(date: group.date, messages: group.messages, index: index)
            }
        }
    }
    
    // MARK: - Date Group View
    
    private func dateGroupView(date: String, messages: [EmailMessage], index: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // 精美的日期标题
            HStack(spacing: 12) {
                // 日期装饰线
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 4, height: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(date)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("\(messages.count) 封邮件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 4)
            
            // 邮件摘要卡片列表
            VStack(spacing: 16) {
                ForEach(Array(messages.enumerated()), id: \.element.id) { messageIndex, message in
                    messageSummaryCard(message: message, index: messageIndex)
                }
            }
        }
    }
    
    // MARK: - Message Summary Card
    
    private func messageSummaryCard(message: EmailMessage, index: Int) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewModel.selectMessage(message)
            }
        }) {
            VStack(alignment: .leading, spacing: 16) {
                // 邮件头部信息
                HStack(alignment: .top, spacing: 16) {
                    // 精美的发件人头像容器
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.blue.opacity(0.1),
                                        Color.purple.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                        
                        EmailAvatarView(email: message.from.email, size: 44)
                    }
                    .shadow(color: .blue.opacity(0.2), radius: 4, x: 0, y: 2)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        // 发件人名称和状态
                        HStack(spacing: 8) {
                            Text(message.from.name ?? message.from.email)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            
                            if message.isStarred {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.yellow, .orange],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                            
                            if let priority = message.aiPriority {
                                priorityBadge(priority: priority)
                            }
                        }
                        
                        // 邮件主题
                        Text(message.subject)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // 时间
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            
                            Text(formatMessageTime(message.date))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    Spacer()
                }
                
                // 精美的分割线
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, Color.blue.opacity(0.2), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 1)
                }
                .padding(.vertical, 4)
                
                // AI摘要内容
                if let summary = message.aiSummary, !summary.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        // AI图标
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.blue.opacity(0.15),
                                            Color.purple.opacity(0.15)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        
                        Text(summary)
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                            .lineSpacing(6)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                // AI标签（如果有）
                if !message.aiTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(message.aiTags.prefix(5), id: \.self) { tag in
                                tagBadge(tag: tag)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .background {
                // 毛玻璃效果卡片
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: colorScheme == .dark ? [
                                        Color.white.opacity(0.05),
                                        Color.white.opacity(0.02)
                                    ] : [
                                        Color.white.opacity(0.7),
                                        Color.white.opacity(0.5)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.blue.opacity(0.2),
                                        Color.purple.opacity(0.15),
                                        Color.blue.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.04), radius: 4, x: 0, y: 2)
            .shadow(color: .blue.opacity(0.1), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .scaleEffect(1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.selectedMessageId)
    }
    
    // MARK: - Tag Badge
    
    private func tagBadge(tag: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(.caption2)
            
            Text(tag)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.15),
                            Color.purple.opacity(0.12)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .foregroundStyle(
            LinearGradient(
                colors: [.blue, .purple],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.3),
                            Color.purple.opacity(0.2)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 0.5
                )
        }
    }
    
    // MARK: - Priority Badge
    
    private func priorityBadge(priority: EmailPriority) -> some View {
        HStack(spacing: 4) {
            Image(systemName: priorityIcon(for: priority))
                .font(.caption2)
            Text(priority.displayName)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(priorityColor(for: priority).opacity(0.2))
        }
        .foregroundStyle(priorityColor(for: priority))
        .overlay {
            Capsule()
                .strokeBorder(priorityColor(for: priority).opacity(0.4), lineWidth: 0.5)
        }
    }
    
    private func priorityIcon(for priority: EmailPriority) -> String {
        switch priority {
        case .low:
            return "arrow.down.circle.fill"
        case .normal:
            return "circle.fill"
        case .high:
            return "arrow.up.circle.fill"
        case .urgent:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private func priorityColor(for priority: EmailPriority) -> Color {
        switch priority {
        case .low:
            return .gray
        case .normal:
            return .blue
        case .high:
            return .orange
        case .urgent:
            return .red
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadRecentMessages() {
        // 获取最近的邮件（最多50封，用于筛选有摘要的）
        recentMessages = Array(viewModel.messages.prefix(50))
    }
    
    private func formatMessageTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd"
            return formatter.string(from: date)
        }
    }
}

#Preview {
    EmailHomeView(viewModel: EmailViewModel())
}
