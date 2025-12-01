//
//  ExpenseChartView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI

struct ExpenseChartView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @ObservedObject private var store = ExpenseStore.shared
    @State private var selectedChartType: ChartType = .pie
    @State private var selectedExpenseType: ExpenseType = .expense
    
    enum ChartType {
        case pie
        case bar
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // 图表类型选择
            Picker("图表类型", selection: $selectedChartType) {
                Text("饼图").tag(ChartType.pie)
                Text("柱状图").tag(ChartType.bar)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .padding(.top, 20)
            
            // 类型选择
            Picker("类型", selection: $selectedExpenseType) {
                ForEach(ExpenseType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            
            // 统计信息
            HStack(spacing: 40) {
                VStack {
                    Text("总\(selectedExpenseType.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("¥\(formatAmount(viewModel.totalAmount(for: selectedExpenseType)))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(typeColor(selectedExpenseType))
                }
                
                VStack {
                    Text("记录数")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.items.filter { $0.type == selectedExpenseType }.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
            }
            
            // 图表
            if selectedChartType == .pie {
                pieChartView
            } else {
                barChartView
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Pie Chart
    
    private var pieChartView: some View {
        let categoryAmounts = viewModel.amountByCategory(for: selectedExpenseType)
        let chartData = categoryAmounts.compactMap { categoryId, amount -> ChartData? in
            guard let category = store.category(id: categoryId) else { return nil }
            return ChartData(category: category, amount: amount)
        }.sorted { $0.amount > $1.amount }
        
        if chartData.isEmpty {
            return AnyView(
                Text("暂无数据")
                    .foregroundStyle(.secondary)
                    .frame(height: 300)
            )
        }
        
        let total = chartData.reduce(Decimal(0)) { $0 + $1.amount }
        
        return AnyView(
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(chartData) { item in
                        HStack {
                            Circle()
                                .fill(Color(hex: item.category.color))
                                .frame(width: 12, height: 12)
                            
                            Text(item.category.name)
                                .font(.body)
                            
                            Spacer()
                            
                            Text("¥\(formatAmount(item.amount))")
                                .font(.body)
                                .fontWeight(.medium)
                            
                            Text("(\(formatPercent(item.amount, total: total)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .frame(height: 400)
        )
    }
    
    // MARK: - Bar Chart
    
    private var barChartView: some View {
        let categoryAmounts = viewModel.amountByCategory(for: selectedExpenseType)
        let chartData = categoryAmounts.compactMap { categoryId, amount -> ChartData? in
            guard let category = store.category(id: categoryId) else { return nil }
            return ChartData(category: category, amount: amount)
        }.sorted { $0.amount > $1.amount }
        
        if chartData.isEmpty {
            return AnyView(
                Text("暂无数据")
                    .foregroundStyle(.secondary)
                    .frame(height: 300)
            )
        }
        
        let maxAmount = chartData.map { $0.amount }.max() ?? 1
        
        return AnyView(
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(chartData) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.category.name)
                                    .font(.body)
                                
                                Spacer()
                                
                                Text("¥\(formatAmount(item.amount))")
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                            
                            GeometryReader { geometry in
                                HStack(spacing: 0) {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color(hex: item.category.color))
                                        .frame(width: geometry.size.width * CGFloat(truncating: (item.amount / maxAmount) as NSDecimalNumber))
                                }
                            }
                            .frame(height: 20)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .frame(height: 400)
        )
    }
    
    private func formatPercent(_ amount: Decimal, total: Decimal) -> String {
        guard total > 0 else { return "0%" }
        let percent = (amount / total) * 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return "\(formatter.string(from: percent as NSDecimalNumber) ?? "0")%"
    }
    
    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "0.00"
    }
    
    private func typeColor(_ type: ExpenseType) -> Color {
        switch type {
        case .income:
            return .green
        case .expense:
            return .red
        case .transfer:
            return .blue
        }
    }
}

// MARK: - Chart Data

struct ChartData: Identifiable {
    let id: UUID
    let category: ExpenseCategory
    let amount: Decimal
    
    init(category: ExpenseCategory, amount: Decimal) {
        self.id = category.id
        self.category = category
        self.amount = amount
    }
}

