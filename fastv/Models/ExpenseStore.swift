//
//  ExpenseStore.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import Combine

/// 记账存储管理器
@MainActor
class ExpenseStore: ObservableObject {
    static let shared = ExpenseStore()
    
    @Published private(set) var items: [ExpenseItem] = []
    @Published private(set) var categories: [ExpenseCategory] = []
    
    private let itemsKey = "expenseItems"
    private let categoriesKey = "expenseCategories"
    private var saveTimer: Timer?
    private let saveDelay: TimeInterval = 1.0
    
    private init() {
        loadItems()
        loadCategories()
        initializeDefaultCategoriesIfNeeded()
    }
    
    // MARK: - CRUD Operations
    
    /// 添加记账
    func add(_ item: ExpenseItem) {
        items.append(item)
        scheduleSaveItems()
    }
    
    /// 更新记账
    func update(_ item: ExpenseItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
            scheduleSaveItems()
        }
    }
    
    /// 删除记账
    func delete(_ item: ExpenseItem) {
        items.removeAll { $0.id == item.id }
        scheduleSaveItems()
    }
    
    /// 根据日期获取记账
    func items(for date: Date) -> [ExpenseItem] {
        let calendar = Calendar.current
        return items.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    /// 根据日期范围获取记账
    func items(from startDate: Date, to endDate: Date) -> [ExpenseItem] {
        return items.filter { $0.date >= startDate && $0.date <= endDate }
    }
    
    /// 根据类型获取记账
    func items(for type: ExpenseType) -> [ExpenseItem] {
        return items.filter { $0.type == type }
    }
    
    /// 根据分类获取记账
    func items(for category: ExpenseCategory) -> [ExpenseItem] {
        return items.filter { $0.categoryId == category.id }
    }
    
    // MARK: - Statistics
    
    /// 计算总金额（按类型）
    func totalAmount(for type: ExpenseType, from startDate: Date? = nil, to endDate: Date? = nil) -> Decimal {
        var filteredItems = items(for: type)
        
        if let startDate = startDate, let endDate = endDate {
            filteredItems = filteredItems.filter { $0.date >= startDate && $0.date <= endDate }
        }
        
        return filteredItems.reduce(Decimal(0)) { $0 + $1.amount }
    }
    
    /// 按分类统计金额
    func amountByCategory(for type: ExpenseType, from startDate: Date? = nil, to endDate: Date? = nil) -> [UUID: Decimal] {
        var filteredItems = items(for: type)
        
        if let startDate = startDate, let endDate = endDate {
            filteredItems = filteredItems.filter { $0.date >= startDate && $0.date <= endDate }
        }
        
        var result: [UUID: Decimal] = [:]
        for item in filteredItems {
            result[item.categoryId, default: 0] += item.amount
        }
        return result
    }
    
    // MARK: - Category Management
    
    /// 获取指定类型的所有分类
    func categories(for type: ExpenseType) -> [ExpenseCategory] {
        return categories.filter { $0.type == type }.sorted { $0.order < $1.order }
    }
    
    /// 添加分类
    func addCategory(_ category: ExpenseCategory) {
        categories.append(category)
        scheduleSaveCategories()
    }
    
    /// 更新分类
    func updateCategory(_ category: ExpenseCategory) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            // 不允许修改默认分类的名称和图标
            if categories[index].isDefault {
                var updated = category
                updated.name = categories[index].name
                updated.icon = categories[index].icon
                updated.isDefault = true
                categories[index] = updated
            } else {
                categories[index] = category
            }
            scheduleSaveCategories()
        }
    }
    
    /// 删除分类
    func deleteCategory(_ category: ExpenseCategory) {
        guard !category.isDefault else {
            print("⚠️ [ExpenseStore] 不允许删除默认分类")
            return
        }
        
        // 将该分类下的所有记账移到"其他"分类
        if let otherCategory = categories.first(where: { $0.type == category.type && $0.name == "其他" && $0.isDefault }) {
            for index in items.indices {
                if items[index].categoryId == category.id {
                    items[index].categoryId = otherCategory.id
                }
            }
        }
        
        categories.removeAll { $0.id == category.id }
        scheduleSaveCategories()
        scheduleSaveItems()
    }
    
    /// 根据 ID 获取分类
    func category(id: UUID) -> ExpenseCategory? {
        return categories.first { $0.id == id }
    }
    
    // MARK: - Default Categories
    
    /// 初始化默认分类
    private func initializeDefaultCategoriesIfNeeded() {
        if categories.isEmpty {
            createDefaultCategories()
        }
    }
    
    /// 创建默认分类
    private func createDefaultCategories() {
        let defaultCategories: [ExpenseCategory] = [
            // 支出分类
            ExpenseCategory(name: "餐饮", icon: "fork.knife", color: "#FF6B6B", isDefault: true, type: .expense, order: 0),
            ExpenseCategory(name: "交通", icon: "car.fill", color: "#4ECDC4", isDefault: true, type: .expense, order: 1),
            ExpenseCategory(name: "购物", icon: "bag.fill", color: "#95E1D3", isDefault: true, type: .expense, order: 2),
            ExpenseCategory(name: "娱乐", icon: "gamecontroller.fill", color: "#F38181", isDefault: true, type: .expense, order: 3),
            ExpenseCategory(name: "住房", icon: "house.fill", color: "#AA96DA", isDefault: true, type: .expense, order: 4),
            ExpenseCategory(name: "医疗", icon: "cross.case.fill", color: "#FCBAD3", isDefault: true, type: .expense, order: 5),
            ExpenseCategory(name: "教育", icon: "book.fill", color: "#A8E6CF", isDefault: true, type: .expense, order: 6),
            ExpenseCategory(name: "其他", icon: "ellipsis.circle.fill", color: "#C7C7C7", isDefault: true, type: .expense, order: 7),
            
            // 收入分类
            ExpenseCategory(name: "工资", icon: "dollarsign.circle.fill", color: "#51CF66", isDefault: true, type: .income, order: 0),
            ExpenseCategory(name: "奖金", icon: "gift.fill", color: "#FFD43B", isDefault: true, type: .income, order: 1),
            ExpenseCategory(name: "投资", icon: "chart.line.uptrend.xyaxis", color: "#339AF0", isDefault: true, type: .income, order: 2),
            ExpenseCategory(name: "兼职", icon: "briefcase.fill", color: "#FF6B9D", isDefault: true, type: .income, order: 3),
            ExpenseCategory(name: "其他", icon: "ellipsis.circle.fill", color: "#C7C7C7", isDefault: true, type: .income, order: 4),
            
            // 转账分类
            ExpenseCategory(name: "银行转账", icon: "arrow.left.arrow.right.circle.fill", color: "#74C0FC", isDefault: true, type: .transfer, order: 0),
            ExpenseCategory(name: "还款", icon: "arrow.uturn.backward.circle.fill", color: "#FF8787", isDefault: true, type: .transfer, order: 1),
            ExpenseCategory(name: "借出", icon: "arrow.right.circle.fill", color: "#63E6BE", isDefault: true, type: .transfer, order: 2),
            ExpenseCategory(name: "其他", icon: "ellipsis.circle.fill", color: "#C7C7C7", isDefault: true, type: .transfer, order: 3)
        ]
        
        categories = defaultCategories
        scheduleSaveCategories()
    }
    
    // MARK: - Persistence
    
    private func scheduleSaveItems() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.saveItems()
            }
        }
    }
    
    private func saveItems() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: itemsKey)
        }
    }
    
    private func loadItems() {
        if let data = UserDefaults.standard.data(forKey: itemsKey),
           let decoded = try? JSONDecoder().decode([ExpenseItem].self, from: data) {
            items = decoded.sorted { $0.date > $1.date }
        }
    }
    
    private func scheduleSaveCategories() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.saveCategories()
            }
        }
    }
    
    private func saveCategories() {
        if let encoded = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(encoded, forKey: categoriesKey)
        }
    }
    
    private func loadCategories() {
        if let data = UserDefaults.standard.data(forKey: categoriesKey),
           let decoded = try? JSONDecoder().decode([ExpenseCategory].self, from: data) {
            categories = decoded
        }
    }
}

