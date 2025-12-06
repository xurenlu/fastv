//
//  HealthProfile.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation

/// 用户健康档案
struct HealthProfile: Codable {
    var height: Double?          // 身高（厘米）
    var weight: Double?          // 体重（千克）
    var age: Int?                // 年龄
    var gender: Gender?          // 性别
    var activityLevel: ActivityLevel?  // 活动水平
    var goal: HealthGoal?        // 健康目标
    var createdAt: Date
    var updatedAt: Date
    
    init(
        height: Double? = nil,
        weight: Double? = nil,
        age: Int? = nil,
        gender: Gender? = nil,
        activityLevel: ActivityLevel? = nil,
        goal: HealthGoal? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.height = height
        self.weight = weight
        self.age = age
        self.gender = gender
        self.activityLevel = activityLevel
        self.goal = goal
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// 计算基础代谢率（BMR）- 使用 Mifflin-St Jeor 公式
    var bmr: Double? {
        guard let weight = weight,
              let height = height,
              let age = age,
              let gender = gender else {
            return nil
        }
        
        // 男性: BMR = 10 × 体重(kg) + 6.25 × 身高(cm) - 5 × 年龄(岁) + 5
        // 女性: BMR = 10 × 体重(kg) + 6.25 × 身高(cm) - 5 × 年龄(岁) - 161
        let baseBMR = 10 * weight + 6.25 * height - 5 * Double(age)
        return gender == .male ? baseBMR + 5 : baseBMR - 161
    }
    
    /// 计算每日总消耗（TDEE）
    var tdee: Double? {
        guard let bmr = bmr,
              let activityLevel = activityLevel else {
            return nil
        }
        
        return bmr * activityLevel.multiplier
    }
}

/// 性别
enum Gender: String, Codable, CaseIterable {
    case male = "male"
    case female = "female"
    
    var displayName: String {
        switch self {
        case .male:
            return "男"
        case .female:
            return "女"
        }
    }
}

/// 活动水平
enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary = "sedentary"           // 久坐（很少或没有运动）
    case lightlyActive = "lightlyActive"   // 轻度活动（每周1-3天轻度运动）
    case moderatelyActive = "moderatelyActive"  // 中度活动（每周3-5天中等强度运动）
    case veryActive = "veryActive"        // 高度活动（每周6-7天高强度运动）
    case extraActive = "extraActive"     // 极高活动（每天高强度运动或体力工作）
    
    var displayName: String {
        switch self {
        case .sedentary:
            return "久坐"
        case .lightlyActive:
            return "轻度活动"
        case .moderatelyActive:
            return "中度活动"
        case .veryActive:
            return "高度活动"
        case .extraActive:
            return "极高活动"
        }
    }
    
    var multiplier: Double {
        switch self {
        case .sedentary:
            return 1.2
        case .lightlyActive:
            return 1.375
        case .moderatelyActive:
            return 1.55
        case .veryActive:
            return 1.725
        case .extraActive:
            return 1.9
        }
    }
}

/// 健康目标
enum HealthGoal: String, Codable, CaseIterable {
    case loseWeight = "loseWeight"         // 减重
    case maintainWeight = "maintainWeight"  // 维持体重
    case gainWeight = "gainWeight"        // 增重
    case buildMuscle = "buildMuscle"      // 增肌
    
    var displayName: String {
        switch self {
        case .loseWeight:
            return "减重"
        case .maintainWeight:
            return "维持体重"
        case .gainWeight:
            return "增重"
        case .buildMuscle:
            return "增肌"
        }
    }
}

