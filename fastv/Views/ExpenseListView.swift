//
//  ExpenseListView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI

struct ExpenseListView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @ObservedObject private var store = ExpenseStore.shared
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.items) { item in
                    ExpenseRow(item: item, viewModel: viewModel)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Expense Row

struct ExpenseRow: View {
    let item: ExpenseItem
    @ObservedObject var viewModel: ExpenseViewModel
    @State private var isHovered = false
    @ObservedObject private var store = ExpenseStore.shared
    
    var category: ExpenseCategory? {
        store.category(id: item.categoryId)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 类型图标
            Image(systemName: item.type.icon)
                .font(.title3)
                .foregroundStyle(typeColor)
                .frame(width: 30)
            
            // 内容
            VStack(alignment: .leading, spacing: 4) {
                // 金额和分类
                HStack {
                    Text("¥\(formatAmount(item.amount))")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    if let category = category {
                        Label(category.name, systemImage: category.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(hex: category.color).opacity(0.2))
                            }
                    }
                }
                
                // 备注和日期
                HStack(spacing: 12) {
                    if let note = item.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(formatDate(item.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // 操作按钮
            if isHovered {
                Button(action: {
                    viewModel.showEditItem(item)
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("编辑")
                
                Button(action: {
                    viewModel.deleteItem(item)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("删除")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
                .overlay {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    }
                }
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
    }
    
    private var typeColor: Color {
        switch item.type {
        case .income:
            return .green
        case .expense:
            return .red
        case .transfer:
            return .blue
        }
    }
    
    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "0.00"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

