//
//  EmailDashboardView.swift
//  fastv
//
//  Created for Email Dashboard View
//

import SwiftUI

/// 邮箱首页仪表板 - 展示AI摘要聚合视图
struct EmailDashboardView: View {
    @ObservedObject var viewModel: EmailViewModel
    
    // 计算有AI摘要的邮件
    private var messagesWithSummary: [EmailMessage] {
        viewModel.messages.filter { message in
            guard let summary = message.aiSummary else { return false }
            return !summary.isEmpty
        }
    }
    
    // 今日有摘要的邮件
    private var todaySummaries: [EmailMessage] {
        let today = Calendar.current.startOfDay(for: Date())
        return messagesWithSummary.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }
    
    // 本周有摘要的邮件
    private var weekSummaries: [EmailMessage] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return messagesWithSummary.filter { $0.date >= weekAgo }
    }
    
    // 重要邮件（有摘要且未读或星标）
    private var importantSummaries: [EmailMessage] {
        Array(messagesWithSummary.filter { !$0.isRead || $0.isStarred || $0.isImportant }
            .sorted { $0.date > $1.date }
            .prefix(10))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 顶部统计卡片
                statisticsCards
                
                // 今日摘要概览
                if !todaySummaries.isEmpty {
                    todaySummarySection
                }
                
                // 重要邮件摘要
                if !importantSummaries.isEmpty {
                    importantSummariesSection
                }
                
                // 本周摘要列表
                if !weekSummaries.isEmpty {
                    weekSummariesSection
                }
                
                // 空状态
                if messagesWithSummary.isEmpty {
                    emptyStateView
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Statistics Cards
    
    private var statisticsCards: some View {
        HStack(spacing: 16) {
            StatCard(
                title: "有摘要的邮件",
                value: "\(messagesWithSummary.count)",
                icon: "sparkles",
                color: .blue
            )
            
            StatCard(
                title: "今日摘要",
                value: "\(todaySummaries.count)",
                icon: "calendar",
                color: .green
            )
            
            StatCard(
                title: "本周摘要",
                value: "\(weekSummaries.count)",
                icon: "chart.line.uptrend.xyaxis",
                color: .purple
            )
            
            StatCard(
                title: "重要邮件",
                value: "\(importantSummaries.count)",
                icon: "star.fill",
                color: .orange
            )
        }
    }
    
    // MARK: - Today Summary Section
    
    private var todaySummarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.orange)
                Text("今日摘要")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(todaySummaries.count) 封")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            LazyVStack(spacing: 12) {
                ForEach(Array(todaySummaries.prefix(5))) { message in
                    SummaryCard(message: message) {
                        viewModel.selectMessage(message)
                    }
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
    }
    
    // MARK: - Important Summaries Section
    
    private var importantSummariesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text("重要邮件摘要")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(importantSummaries.count) 封")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            LazyVStack(spacing: 12) {
                ForEach(Array(importantSummaries.prefix(5))) { message in
                    SummaryCard(message: message) {
                        viewModel.selectMessage(message)
                    }
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
    }
    
    // MARK: - Week Summaries Section
    
    private var weekSummariesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.purple)
                Text("本周摘要")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(weekSummaries.count) 封")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            LazyVStack(spacing: 12) {
                ForEach(Array(weekSummaries.prefix(10))) { message in
                    SummaryCard(message: message, showFullSummary: false) {
                        viewModel.selectMessage(message)
                    }
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("还没有AI摘要")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("打开邮件后，系统会自动生成AI摘要")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.title3)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.primary)
            
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let message: EmailMessage
    let onSelect: () -> Void
    var showFullSummary: Bool = true
    
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                // 邮件图标和状态
                VStack(spacing: 4) {
                    EmailAvatarView(email: message.from.email, size: 40)
                    
                    if !message.isRead {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                    }
                }
                
                // 邮件信息和摘要
                VStack(alignment: .leading, spacing: 8) {
                    // 发件人和主题
                    HStack {
                        Text(message.from.name ?? message.from.email)
                            .font(.subheadline)
                            .fontWeight(message.isRead ? .regular : .semibold)
                            .foregroundStyle(message.isRead ? .secondary : .primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(formatMessageDate(message.date))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    
                    Text(message.subject)
                        .font(.subheadline)
                        .fontWeight(message.isRead ? .regular : .medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    // AI摘要
                    if let summary = message.aiSummary, !summary.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(showFullSummary ? 3 : 2)
                        }
                        .padding(10)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.blue.opacity(0.08),
                                            Color.purple.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.blue.opacity(0.2),
                                            Color.purple.opacity(0.15)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                    }
                    
                    // 标签和状态
                    HStack(spacing: 6) {
                        if message.isStarred {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                        
                        if message.isImportant {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        
                        if !message.aiTags.isEmpty {
                            ForEach(message.aiTags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(message.isRead ? Color.clear : Color.blue.opacity(0.03))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

