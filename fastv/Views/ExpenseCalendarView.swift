//
//  ExpenseCalendarView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI

struct ExpenseCalendarView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @ObservedObject private var store = ExpenseStore.shared
    @State private var selectedDate: Date = Date()
    
    var body: some View {
        VStack(spacing: 20) {
            // 日期选择器
            DatePicker("选择日期", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .padding()
            
            // 当日统计
            let dayItems = store.items(for: selectedDate)
            let dayTotal = dayItems.reduce(Decimal(0)) { $0 + $1.amount }
            
            HStack(spacing: 40) {
                VStack {
                    Text("当日总计")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("¥\(formatAmount(dayTotal))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                }
                
                VStack {
                    Text("记录数")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(dayItems.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
            }
            
            // 当日明细
            if dayItems.isEmpty {
                Text("当日无记录")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(dayItems) { item in
                            ExpenseRow(item: item, viewModel: viewModel)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
    }
    
    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "0.00"
    }
}

