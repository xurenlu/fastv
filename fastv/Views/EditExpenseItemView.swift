//
//  EditExpenseItemView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI

struct EditExpenseItemView: View {
    let item: ExpenseItem
    @ObservedObject var viewModel: ExpenseViewModel
    @ObservedObject private var store = ExpenseStore.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var amount: String
    @State private var selectedType: ExpenseType
    @State private var selectedCategoryId: UUID
    @State private var note: String
    @State private var date: Date
    
    init(item: ExpenseItem, viewModel: ExpenseViewModel) {
        self.item = item
        self.viewModel = viewModel
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        
        _amount = State(initialValue: formatter.string(from: item.amount as NSDecimalNumber) ?? "0.00")
        _selectedType = State(initialValue: item.type)
        _selectedCategoryId = State(initialValue: item.categoryId)
        _note = State(initialValue: item.note ?? "")
        _date = State(initialValue: item.date)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("编辑记账")
                .font(.title2)
                .fontWeight(.bold)
            
            // 金额
            VStack(alignment: .leading, spacing: 8) {
                Text("金额")
                    .font(.headline)
                TextField("0.00", text: $amount)
                    .textFieldStyle(.roundedBorder)
            }
            
            // 类型
            VStack(alignment: .leading, spacing: 8) {
                Text("类型")
                    .font(.headline)
                Picker("类型", selection: $selectedType) {
                    ForEach(ExpenseType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedType) { _, newType in
                    // 当类型改变时，自动选择该类型的第一个分类
                    if let firstCategory = store.categories.first(where: { $0.type == newType }) {
                        selectedCategoryId = firstCategory.id
                    }
                }
            }
            
            // 分类
            VStack(alignment: .leading, spacing: 8) {
                Text("分类")
                    .font(.headline)
                Picker("分类", selection: $selectedCategoryId) {
                    ForEach(store.categories(for: selectedType), id: \.id) { category in
                        Label(category.name, systemImage: category.icon)
                            .tag(category.id)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // 备注
            VStack(alignment: .leading, spacing: 8) {
                Text("备注")
                    .font(.headline)
                TextField("备注（可选）", text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }
            
            // 日期
            VStack(alignment: .leading, spacing: 8) {
                Text("日期")
                    .font(.headline)
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
            }
            
            // 按钮
            HStack {
                Button("取消") {
                    viewModel.cancelEditItem()
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("保存") {
                    saveItem()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 500)
    }
    
    private var isValid: Bool {
        guard let amountValue = Decimal(string: amount), amountValue > 0 else {
            return false
        }
        return true
    }
    
    private func saveItem() {
        guard let amountValue = Decimal(string: amount), amountValue > 0 else {
            return
        }
        
        viewModel.updateItem(
            item,
            amount: amountValue,
            type: selectedType,
            categoryId: selectedCategoryId,
            note: note.isEmpty ? nil : note,
            date: date
        )
        
        dismiss()
    }
}

// MARK: - Decimal Extension

extension Decimal {
    init?(string: String) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        
        if let number = formatter.number(from: string) {
            self = number.decimalValue
        } else {
            // 尝试直接解析
            if let value = Double(string) {
                self = Decimal(value)
            } else {
                return nil
            }
        }
    }
}

