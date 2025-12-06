//
//  MealRecord.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation

/// 饮食记录
struct MealRecord: Identifiable, Codable {
    let id: UUID
    var mealType: MealType           // 餐次类型
    var date: Date                   // 日期时间
    var textDescription: String?     // 文字描述
    var imageData: [Data]            // 图片数据（多张）
    var recognizedFoods: [RecognizedFood]  // AI识别的食物列表
    var totalCalories: Double?       // 总卡路里
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        mealType: MealType,
        date: Date = Date(),
        textDescription: String? = nil,
        imageData: [Data] = [],
        recognizedFoods: [RecognizedFood] = [],
        totalCalories: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.mealType = mealType
        self.date = date
        self.textDescription = textDescription
        self.imageData = imageData
        self.recognizedFoods = recognizedFoods
        self.totalCalories = totalCalories
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 餐次类型
enum MealType: String, Codable, CaseIterable {
    case breakfast = "breakfast"     // 早餐
    case lunch = "lunch"             // 午餐
    case dinner = "dinner"           // 晚餐
    case snack = "snack"             // 零食
    case drink = "drink"             // 饮料
    
    var displayName: String {
        switch self {
        case .breakfast:
            return "早餐"
        case .lunch:
            return "午餐"
        case .dinner:
            return "晚餐"
        case .snack:
            return "零食"
        case .drink:
            return "饮料"
        }
    }
    
    var icon: String {
        switch self {
        case .breakfast:
            return "sunrise.fill"
        case .lunch:
            return "sun.max.fill"
        case .dinner:
            return "moon.stars.fill"
        case .snack:
            return "cup.and.saucer.fill"
        case .drink:
            return "drop.fill"
        }
    }
}

/// AI识别的食物
struct RecognizedFood: Codable, Identifiable {
    let id: UUID
    var name: String                 // 食物名称
    var estimatedAmount: String?     // 估算份量（如"1碗"、"250ml"）
    var consumedRatio: Double?       // 食用比例（0.0-1.0，如0.5表示吃了一半）
    var calories: Double?            // 卡路里
    var protein: Double?             // 蛋白质（克）
    var carbs: Double?               // 碳水化合物（克）
    var fat: Double?                 // 脂肪（克）
    
    init(
        id: UUID = UUID(),
        name: String,
        estimatedAmount: String? = nil,
        consumedRatio: Double? = nil,
        calories: Double? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.estimatedAmount = estimatedAmount
        self.consumedRatio = consumedRatio
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
    
    /// 计算实际摄入的卡路里（考虑食用比例）
    var actualCalories: Double? {
        guard let calories = calories,
              let ratio = consumedRatio else {
            return calories
        }
        return calories * ratio
    }
}

