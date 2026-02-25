//
//  ExerciseRecord.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation

/// 运动记录
struct ExerciseRecord: Identifiable, Codable {
    let id: UUID
    var exerciseType: ExerciseType?  // 运动类型（如果从模板选择）
    var customName: String?         // 自定义运动名称
    var date: Date                  // 日期时间
    var duration: TimeInterval?     // 持续时间（秒）
    var distance: Double?           // 距离（公里，适用于跑步、骑行等）
    var textDescription: String?    // 文字描述
    var imageData: [Data]          // 图片数据（可选）
    var caloriesBurned: Double?    // 消耗的卡路里
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        exerciseType: ExerciseType? = nil,
        customName: String? = nil,
        date: Date = Date(),
        duration: TimeInterval? = nil,
        distance: Double? = nil,
        textDescription: String? = nil,
        imageData: [Data] = [],
        caloriesBurned: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.exerciseType = exerciseType
        self.customName = customName
        self.date = date
        self.duration = duration
        self.distance = distance
        self.textDescription = textDescription
        self.imageData = imageData
        self.caloriesBurned = caloriesBurned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// 获取运动名称
    var name: String {
        if let customName = customName, !customName.isEmpty {
            return customName
        }
        return exerciseType?.displayName ?? "运动"
    }
}

/// 运动类型
enum ExerciseType: String, Codable, CaseIterable {
    case running = "running"           // 跑步
    case walking = "walking"           // 步行
    case cycling = "cycling"           // 骑行
    case swimming = "swimming"         // 游泳
    case gym = "gym"                   // 健身房
    case yoga = "yoga"                 // 瑜伽
    case hiking = "hiking"            // 徒步
    case basketball = "basketball"    // 篮球
    case football = "football"         // 足球
    case tennis = "tennis"             // 网球
    case badminton = "badminton"      // 羽毛球
    case dancing = "dancing"           // 舞蹈
    case other = "other"               // 其他
    
    var displayName: String {
        switch self {
        case .running:
            return "跑步"
        case .walking:
            return "步行"
        case .cycling:
            return "骑行"
        case .swimming:
            return "游泳"
        case .gym:
            return "健身房"
        case .yoga:
            return "瑜伽"
        case .hiking:
            return "徒步"
        case .basketball:
            return "篮球"
        case .football:
            return "足球"
        case .tennis:
            return "网球"
        case .badminton:
            return "羽毛球"
        case .dancing:
            return "舞蹈"
        case .other:
            return "其他"
        }
    }
    
    var icon: String {
        switch self {
        case .running:
            return "figure.run"
        case .walking:
            return "figure.walk"
        case .cycling:
            return "bicycle"
        case .swimming:
            return "figure.pool.swim"
        case .gym:
            return "dumbbell.fill"
        case .yoga:
            return "figure.yoga"
        case .hiking:
            return "figure.hiking"
        case .basketball:
            return "basketball.fill"
        case .football:
            return "soccerball"
        case .tennis:
            return "tennisball.fill"
        case .badminton:
            return "figure.badminton"
        case .dancing:
            return "figure.dance"
        case .other:
            return "figure.mixed.cardio"
        }
    }
}

