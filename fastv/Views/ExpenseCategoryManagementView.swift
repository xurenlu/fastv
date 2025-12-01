//
//  ExpenseCategoryManagementView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI

struct ExpenseCategoryManagementView: View {
    @ObservedObject private var store = ExpenseStore.shared
    @State private var selectedType: ExpenseType = .expense
    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryIcon = "circle.fill"
    @State private var newCategoryColor = "#FF6B6B"
    
    var body: some View {
        VStack(spacing: 0) {
            // 类型选择
            Picker("类型", selection: $selectedType) {
                ForEach(ExpenseType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            // 分类列表
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.categories(for: selectedType)) { category in
                        CategoryRow(category: category, store: store)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // 添加按钮
            Button(action: {
                showAddCategory = true
            }) {
                Label("添加分类", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .sheet(isPresented: $showAddCategory) {
            AddCategoryView(
                type: selectedType,
                onSave: { name, icon, color in
                    let maxOrder = store.categories(for: selectedType).map { $0.order }.max() ?? -1
                    let category = ExpenseCategory(
                        name: name,
                        icon: icon,
                        color: color,
                        isDefault: false,
                        type: selectedType,
                        order: maxOrder + 1
                    )
                    store.addCategory(category)
                    showAddCategory = false
                }
            )
        }
        .navigationTitle("分类管理")
    }
}

// MARK: - Category Row

struct CategoryRow: View {
    let category: ExpenseCategory
    @ObservedObject var store: ExpenseStore
    @State private var showEdit = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标和颜色
            Image(systemName: category.icon)
                .font(.title3)
                .foregroundStyle(Color(hex: category.color))
                .frame(width: 30)
            
            // 名称
            Text(category.name)
                .font(.body)
            
            Spacer()
            
            // 默认标签
            if category.isDefault {
                Text("默认")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(0.2))
                    }
            }
            
            // 操作按钮
            if !category.isDefault {
                Button(action: {
                    showEdit = true
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    store.deleteCategory(category)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        }
        .sheet(isPresented: $showEdit) {
            EditCategoryView(category: category, store: store)
        }
    }
}

// MARK: - Add Category View

struct AddCategoryView: View {
    let type: ExpenseType
    let onSave: (String, String, String) -> Void
    
    @State private var name = ""
    @State private var icon = "circle.fill"
    @State private var color = "#FF6B6B"
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("添加分类")
                .font(.title2)
                .fontWeight(.bold)
            
            TextField("分类名称", text: $name)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Text("图标:")
                TextField("SF Symbol 名称", text: $icon)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Text("颜色:")
                TextField("#FF6B6B", text: $color)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("保存") {
                    onSave(name, icon, color)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Edit Category View

struct EditCategoryView: View {
    let category: ExpenseCategory
    @ObservedObject var store: ExpenseStore
    
    @State private var name: String
    @State private var icon: String
    @State private var color: String
    @Environment(\.dismiss) private var dismiss
    
    init(category: ExpenseCategory, store: ExpenseStore) {
        self.category = category
        self.store = store
        _name = State(initialValue: category.name)
        _icon = State(initialValue: category.icon)
        _color = State(initialValue: category.color)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("编辑分类")
                .font(.title2)
                .fontWeight(.bold)
            
            TextField("分类名称", text: $name)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Text("图标:")
                TextField("SF Symbol 名称", text: $icon)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Text("颜色:")
                TextField("#FF6B6B", text: $color)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("保存") {
                    var updated = category
                    updated.name = name
                    updated.icon = icon
                    updated.color = color
                    store.updateCategory(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

