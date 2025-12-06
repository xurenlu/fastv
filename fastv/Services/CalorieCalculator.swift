//
//  CalorieCalculator.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation

/// 卡路里计算服务
@MainActor
class CalorieCalculator {
    static let shared = CalorieCalculator()
    
    private init() {}
    
    /// 计算食物的卡路里（基于食物名称和份量）
    /// - Parameters:
    ///   - foodName: 食物名称
    ///   - amount: 份量描述（如"1碗"、"250ml"）
    ///   - consumedRatio: 食用比例（0.0-1.0）
    /// - Returns: 卡路里（大卡）
    func calculateCalories(
        foodName: String,
        amount: String?,
        consumedRatio: Double = 1.0
    ) -> Double? {
        // 首先尝试从食物数据库查找
        if let calories = lookupFoodDatabase(foodName: foodName, amount: amount) {
            return calories * consumedRatio
        }
        
        // 如果没有找到，使用估算值
        return estimateCalories(foodName: foodName, amount: amount) * consumedRatio
    }
    
    /// 从食物数据库查找（常见食物）
    private func lookupFoodDatabase(foodName: String, amount: String?) -> Double? {
        let name = foodName.lowercased()
        
        // 常见食物数据库（每100克的卡路里）
        let foodDatabase: [String: Double] = [
            // 主食
            "米饭": 116,
            "白米饭": 116,
            "面条": 109,
            "馒头": 223,
            "包子": 227,
            "饺子": 250,
            "馄饨": 200,
            "粥": 46,
            "白粥": 46,
            
            // 肉类
            "猪肉": 242,
            "牛肉": 250,
            "羊肉": 203,
            "鸡肉": 167,
            "鸭肉": 240,
            "鱼肉": 108,
            "虾": 93,
            "鸡蛋": 144,
            
            // 蔬菜
            "白菜": 17,
            "青菜": 15,
            "菠菜": 23,
            "西红柿": 18,
            "黄瓜": 15,
            "胡萝卜": 41,
            "土豆": 77,
            "茄子": 21,
            
            // 水果
            "苹果": 52,
            "香蕉": 89,
            "橙子": 47,
            "西瓜": 30,
            "葡萄": 43,
            
            // 饮料
            "牛奶": 54,  // 每100ml
            "酸奶": 99,  // 每100ml
            "可乐": 43,  // 每100ml
            "红牛": 45,  // 每100ml
            "咖啡": 2,   // 每100ml（黑咖啡）
            
            // 零食
            "薯片": 536,
            "巧克力": 546,
            "饼干": 433,
            "蛋糕": 347
        ]
        
        // 查找匹配的食物
        for (key, caloriesPer100g) in foodDatabase {
            if name.contains(key) {
                // 解析份量
                if let amount = amount {
                    return parseAmount(amount: amount, caloriesPer100g: caloriesPer100g)
                }
                // 默认按100克计算
                return caloriesPer100g
            }
        }
        
        return nil
    }
    
    /// 解析份量并计算卡路里
    private func parseAmount(amount: String, caloriesPer100g: Double) -> Double {
        let amountStr = amount.lowercased()
        
        // 解析数字
        let numbers = amountStr.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        guard let quantity = Double(numbers) else {
            return caloriesPer100g  // 默认100克
        }
        
        // 根据单位计算
        if amountStr.contains("碗") || amountStr.contains("份") {
            // 一碗约200-300克
            return caloriesPer100g * quantity * 2.5
        } else if amountStr.contains("ml") || amountStr.contains("毫升") {
            // 液体，按毫升计算（假设密度接近水，1ml≈1g）
            return caloriesPer100g * quantity / 100.0
        } else if amountStr.contains("个") || amountStr.contains("只") {
            // 按个计算，需要根据具体食物估算
            return caloriesPer100g * quantity * 0.5  // 假设每个约50克
        } else if amountStr.contains("瓶") {
            // 瓶装饮料，通常250-500ml
            return caloriesPer100g * quantity * 3.5  // 假设每瓶350ml
        } else if amountStr.contains("g") || amountStr.contains("克") {
            // 直接是克数
            return caloriesPer100g * quantity / 100.0
        }
        
        // 默认按100克计算
        return caloriesPer100g * quantity
    }
    
    /// 估算卡路里（当数据库中没有时）
    private func estimateCalories(foodName: String, amount: String?) -> Double {
        let name = foodName.lowercased()
        
        // 根据食物类型估算
        if name.contains("肉") || name.contains("鱼") || name.contains("虾") {
            // 肉类：约200-250大卡/100克
            return parseAmount(amount: amount ?? "100g", caloriesPer100g: 225)
        } else if name.contains("菜") || name.contains("蔬") {
            // 蔬菜：约20-30大卡/100克
            return parseAmount(amount: amount ?? "100g", caloriesPer100g: 25)
        } else if name.contains("饭") || name.contains("面") || name.contains("米") {
            // 主食：约100-120大卡/100克
            return parseAmount(amount: amount ?? "100g", caloriesPer100g: 110)
        } else if name.contains("汤") {
            // 汤类：约30-50大卡/100ml
            return parseAmount(amount: amount ?? "100ml", caloriesPer100g: 40)
        } else if name.contains("饮料") || name.contains("水") || name.contains("茶") {
            // 饮料：约40-50大卡/100ml（含糖）
            return parseAmount(amount: amount ?? "100ml", caloriesPer100g: 45)
        }
        
        // 默认：约150大卡/100克
        return parseAmount(amount: amount ?? "100g", caloriesPer100g: 150)
    }
    
    /// 计算运动消耗的卡路里
    /// - Parameters:
    ///   - exerciseType: 运动类型
    ///   - duration: 持续时间（分钟）
    ///   - weight: 体重（千克）
    ///   - distance: 距离（公里，可选）
    /// - Returns: 消耗的卡路里（大卡）
    func calculateExerciseCalories(
        exerciseType: ExerciseType?,
        customName: String?,
        duration: TimeInterval?,
        weight: Double?,
        distance: Double? = nil
    ) -> Double? {
        guard let weight = weight else {
            return nil
        }
        
        // 如果有距离，优先使用距离计算（适用于跑步、骑行等）
        if let distance = distance, let exerciseType = exerciseType {
            return calculateByDistance(exerciseType: exerciseType, distance: distance, weight: weight)
        }
        
        // 如果有持续时间，使用时间计算
        if let duration = duration, let exerciseType = exerciseType {
            let minutes = duration / 60.0
            return calculateByDuration(exerciseType: exerciseType, minutes: minutes, weight: weight)
        }
        
        // 如果有自定义名称，尝试估算
        if let customName = customName, let duration = duration {
            let minutes = duration / 60.0
            return estimateCustomExercise(name: customName, minutes: minutes, weight: weight)
        }
        
        return nil
    }
    
    /// 根据距离计算（跑步、骑行等）
    private func calculateByDistance(exerciseType: ExerciseType, distance: Double, weight: Double) -> Double {
        // MET值（代谢当量）* 体重(kg) * 时间(小时)
        // 这里简化为：MET * 体重 * 距离系数
        
        let metValues: [ExerciseType: Double] = [
            .running: 9.8,      // 跑步：约9.8 MET
            .walking: 3.5,      // 快走：约3.5 MET
            .cycling: 6.0,     // 骑行：约6.0 MET
            .swimming: 7.0,    // 游泳：约7.0 MET
            .hiking: 6.0      // 徒步：约6.0 MET
        ]
        
        let met = metValues[exerciseType] ?? 5.0
        
        // 简化公式：卡路里 = MET * 体重(kg) * 距离(km) * 0.8
        return met * weight * distance * 0.8
    }
    
    /// 根据持续时间计算
    private func calculateByDuration(exerciseType: ExerciseType, minutes: Double, weight: Double) -> Double {
        // MET值（代谢当量）* 体重(kg) * 时间(小时)
        
        let metValues: [ExerciseType: Double] = [
            .running: 9.8,
            .walking: 3.5,
            .cycling: 6.0,
            .swimming: 7.0,
            .gym: 5.0,         // 健身房：约5.0 MET
            .yoga: 2.5,        // 瑜伽：约2.5 MET
            .hiking: 6.0,
            .basketball: 8.0,  // 篮球：约8.0 MET
            .football: 7.0,    // 足球：约7.0 MET
            .tennis: 7.3,      // 网球：约7.3 MET
            .badminton: 5.5,   // 羽毛球：约5.5 MET
            .dancing: 4.8       // 舞蹈：约4.8 MET
        ]
        
        let met = metValues[exerciseType] ?? 5.0
        let hours = minutes / 60.0
        
        // 公式：卡路里 = MET * 体重(kg) * 时间(小时)
        return met * weight * hours
    }
    
    /// 估算自定义运动
    private func estimateCustomExercise(name: String, minutes: Double, weight: Double) -> Double {
        let nameLower = name.lowercased()
        
        // 根据名称关键词估算强度
        var met: Double = 5.0  // 默认中等强度
        
        if nameLower.contains("跑步") || nameLower.contains("跑") {
            met = 9.8
        } else if nameLower.contains("走") || nameLower.contains("散步") {
            met = 3.5
        } else if nameLower.contains("骑") || nameLower.contains("自行车") {
            met = 6.0
        } else if nameLower.contains("游泳") {
            met = 7.0
        } else if nameLower.contains("瑜伽") {
            met = 2.5
        } else if nameLower.contains("健身") || nameLower.contains("力量") {
            met = 5.0
        } else if nameLower.contains("球") {
            met = 7.0
        }
        
        let hours = minutes / 60.0
        return met * weight * hours
    }
}

