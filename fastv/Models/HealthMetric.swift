//
//  HealthMetric.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation

/// 健康指标记录
struct HealthMetric: Identifiable, Codable {
    let id: UUID
    var metricType: MetricType      // 指标类型
    var value: Double              // 数值
    var unit: String               // 单位
    var date: Date                 // 记录时间
    var note: String?              // 备注
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        metricType: MetricType,
        value: Double,
        unit: String,
        date: Date = Date(),
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.metricType = metricType
        self.value = value
        self.unit = unit
        self.date = date
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 健康指标类型
enum MetricType: String, Codable, CaseIterable {
    case weight = "weight"                 // 体重
    case bloodPressureSystolic = "bloodPressureSystolic"  // 收缩压
    case bloodPressureDiastolic = "bloodPressureDiastolic" // 舒张压
    case heartRate = "heartRate"           // 心率
    case bloodSugar = "bloodSugar"         // 血糖
    case bodyFat = "bodyFat"               // 体脂率
    case sleep = "sleep"                   // 睡眠时长
    case water = "water"                   // 饮水量
    case mood = "mood"                     // 情绪
    case medication = "medication"         // 用药（记录是否服药）
    
    var displayName: String {
        switch self {
        case .weight:
            return "体重"
        case .bloodPressureSystolic:
            return "收缩压"
        case .bloodPressureDiastolic:
            return "舒张压"
        case .heartRate:
            return "心率"
        case .bloodSugar:
            return "血糖"
        case .bodyFat:
            return "体脂率"
        case .sleep:
            return "睡眠"
        case .water:
            return "饮水量"
        case .mood:
            return "情绪"
        case .medication:
            return "用药"
        }
    }
    
    var defaultUnit: String {
        switch self {
        case .weight:
            return "kg"
        case .bloodPressureSystolic, .bloodPressureDiastolic:
            return "mmHg"
        case .heartRate:
            return "bpm"
        case .bloodSugar:
            return "mmol/L"
        case .bodyFat:
            return "%"
        case .sleep:
            return "小时"
        case .water:
            return "ml"
        case .mood:
            return "分"  // 1-10分
        case .medication:
            return "次"  // 服药次数
        }
    }
    
    var icon: String {
        switch self {
        case .weight:
            return "scalemass.fill"
        case .bloodPressureSystolic, .bloodPressureDiastolic:
            return "heart.text.square.fill"
        case .heartRate:
            return "heart.fill"
        case .bloodSugar:
            return "drop.fill"
        case .bodyFat:
            return "percent"
        case .sleep:
            return "bed.double.fill"
        case .water:
            return "drop.circle.fill"
        case .mood:
            return "face.smiling.fill"
        case .medication:
            return "pills.fill"
        }
    }
}

/// 情绪记录（扩展）
struct MoodRecord: Identifiable, Codable {
    let id: UUID
    var score: Int              // 情绪分数 1-10
    var date: Date
    var note: String?
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        score: Int,
        date: Date = Date(),
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.score = score
        self.date = date
        self.note = note
        self.createdAt = createdAt
    }
}

/// 用药记录
struct MedicationRecord: Identifiable, Codable {
    let id: UUID
    var medicationName: String  // 药物名称
    var dosage: String?        // 剂量
    var date: Date
    var note: String?
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        medicationName: String,
        dosage: String? = nil,
        date: Date = Date(),
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.medicationName = medicationName
        self.dosage = dosage
        self.date = date
        self.note = note
        self.createdAt = createdAt
    }
}

