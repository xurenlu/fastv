//
//  DiaryCalendarView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI

struct DiaryCalendarView: View {
    @ObservedObject var viewModel: DiaryViewModel
    @ObservedObject private var store = DiaryStore.shared
    @State private var currentMonth: Date = Date()
    @State private var selectedDate: Date? = nil
    @State private var showingDayDetail = false
    
    private let calendar = Calendar.current
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索框
            searchSection
            
            Divider()
            
            // 月份导航和日历网格
            ScrollView {
                VStack(spacing: 20) {
                    // 月份导航
                    monthNavigationView
                    
                    // 日历网格
                    calendarGridView
                    
                    // 选中日期的详细记录
                    if let selectedDate = selectedDate {
                        dayDetailView(for: selectedDate)
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Search Section
    
    private var searchSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("搜索日记内容...", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
            
            if !viewModel.searchText.isEmpty {
                Button(action: {
                    viewModel.searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            Rectangle()
                .fill(.regularMaterial)
        }
    }
    
    // MARK: - Month Navigation
    
    private var monthNavigationView: some View {
        HStack {
            Button(action: {
                withAnimation {
                    currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                    selectedDate = nil
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text(monthYearString)
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button(action: {
                withAnimation {
                    currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                    selectedDate = nil
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            
            Button(action: {
                withAnimation {
                    currentMonth = Date()
                    selectedDate = nil
                }
            }) {
                Text("今天")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Calendar Grid
    
    private var calendarGridView: some View {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let adjustedFirstWeekday = (firstWeekday + 5) % 7 // 转换为周一为0的格式
        let daysInMonth = calendar.range(of: .day, in: .month, for: currentMonth)?.count ?? 30
        
        // 获取搜索匹配的日期集合
        let searchMatchedDates: Set<Date>
        if !viewModel.searchText.isEmpty {
            let matchedEntries = store.searchEntries(query: viewModel.searchText)
            searchMatchedDates = Set(matchedEntries.map { calendar.startOfDay(for: $0.date) })
        } else {
            searchMatchedDates = Set<Date>()
        }
        
        return VStack(spacing: 0) {
            // 星期标题
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            
            // 日期网格
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                // 填充月初空白
                ForEach(0..<adjustedFirstWeekday, id: \.self) { _ in
                    Color.clear
                        .frame(height: 80)
                }
                
                // 日期单元格
                ForEach(1...daysInMonth, id: \.self) { day in
                    if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                        let dayStart = calendar.startOfDay(for: date)
                        let dayEntries = store.entries(for: date)
                        let hasEntries = !dayEntries.isEmpty
                        let isSearchMatched = searchMatchedDates.contains(dayStart)
                        
                        calendarDayCell(
                            date: date,
                            day: day,
                            hasEntries: hasEntries,
                            isSearchMatched: isSearchMatched
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Calendar Day Cell
    
    private func calendarDayCell(date: Date, day: Int, hasEntries: Bool, isSearchMatched: Bool) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        
        return Button(action: {
            withAnimation {
                if isSelected {
                    selectedDate = nil
                } else {
                    selectedDate = date
                }
            }
        }) {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? .white : (isSelected ? .blue : .primary))
                
                if hasEntries {
                    Circle()
                        .fill(isToday ? Color.white.opacity(0.8) : Color.blue)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isToday ? Color.blue : (isSelected ? Color.blue.opacity(0.1) : Color.clear))
            }
            .overlay {
                if hasEntries && !isToday {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                }
                if isSearchMatched && !isToday {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.6), lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Day Detail View
    
    @ViewBuilder
    private func dayDetailView(for date: Date) -> some View {
        let dayEntries: [DiaryEntry] = {
            if !viewModel.searchText.isEmpty {
                // 如果正在搜索，只显示匹配的日记
                let allMatched = store.searchEntries(query: viewModel.searchText)
                return allMatched.filter { calendar.isDate($0.date, inSameDayAs: date) }
            } else {
                return store.entries(for: date)
            }
        }()
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(formatDateHeader(date))
                    .font(.headline)
                
                Spacer()
                
                Text("共 \(dayEntries.count) 篇")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)
            
            if dayEntries.isEmpty {
                Text(viewModel.searchText.isEmpty ? "当日无日记" : "当日无匹配的日记")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(dayEntries) { entry in
                            DiaryRow(entry: entry, viewModel: viewModel)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Helper Properties and Methods
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: currentMonth)
    }
    
    private func formatDateHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            return "今天"
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else {
            formatter.dateFormat = "M月d日 EEEE"
            return formatter.string(from: date)
        }
    }
}

