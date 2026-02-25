//
//  MonthCalendarView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI
import AppKit

/// 单月日历视图（五行七列）
struct MonthCalendarView: View {
    let month: Date
    let hasEntriesForDate: (Date) -> Bool
    let onDateSelected: (Date) -> Void
    
    @State private var selectedDate: Date?
    
    private let calendar = Calendar.current
    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
    
    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
    }
    
    private var monthEnd: Date {
        calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? month
    }
    
    private var firstDayOfWeek: Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday - 1) % 7  // 转换为周日=0的格式
    }
    
    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: month)?.count ?? 31
    }
    
    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: month)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // 月份标题
            Text(monthTitle)
                .font(.headline)
                .foregroundStyle(.primary)
            
            // 星期标题
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // 日期网格（五行七列）
            VStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { col in
                            let dayIndex = row * 7 + col
                            let day = dayIndex - firstDayOfWeek + 1
                            
                            if day > 0 && day <= daysInMonth {
                                let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
                                let hasEntries = hasEntriesForDate(date)
                                let isSelected = calendar.isDate(date, inSameDayAs: selectedDate ?? Date.distantPast)
                                
                                DayCell(
                                    day: day,
                                    hasEntries: hasEntries,
                                    isSelected: isSelected
                                ) {
                                    selectedDate = date
                                    onDateSelected(date)
                                }
                            } else {
                                // 空白单元格
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
    }
}

/// 日期单元格
struct DayCell: View {
    let day: Int
    let hasEntries: Bool
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // 背景
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color(NSColor.controlAccentColor).opacity(0.2) : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isSelected ? Color(NSColor.controlAccentColor) : Color.clear, lineWidth: 1)
                    }
                
                VStack(spacing: 2) {
                    // 日期数字
                    Text("\(day)")
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color(NSColor.controlAccentColor) : .primary)
                    
                    // 有情报的标记点
                    if hasEntries {
                        Circle()
                            .fill(Color(NSColor.controlAccentColor))
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 三个月日历视图
struct ThreeMonthCalendarView: View {
    @ObservedObject var viewModel: IntelViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // 导航工具栏
            HStack {
                Button(action: {
                    withAnimation {
                        viewModel.previousThreeMonths()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                
                Spacer()
                
                // 显示当前三个月的标题
                HStack(spacing: 16) {
                    ForEach(viewModel.calendarDisplayMonths, id: \.self) { month in
                        monthTitle(for: month)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        viewModel.nextThreeMonths()
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Divider()
            
            // 三个月的日历
            HStack(spacing: 16) {
                ForEach(viewModel.calendarDisplayMonths, id: \.self) { month in
                    MonthCalendarView(
                        month: month,
                        hasEntriesForDate: { date in
                            viewModel.hasEntries(for: date)
                        },
                        onDateSelected: { date in
                            viewModel.selectedDate = date
                            // 只有选择今天时才切换到「今日的情报」，否则保持在「历史情报」
                            if Calendar.current.isDateInToday(date) {
                                viewModel.selectedTab = .today
                                viewModel.clearHistoryDateFilter()
                            } else {
                                // 在历史 tab 中点击某天，按该日期筛选列表
                                viewModel.historyFilterDate = date
                            }
                            viewModel.load(date: date)
                        }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .frame(height: 300)
    }
    
    private func monthTitle(for month: Date) -> some View {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        
        return Text(formatter.string(from: month))
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

