//
//  HealthKitService.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import HealthKit

/// HealthKit 服务错误
enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case saveFailed(Error)
    case readFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit 不可用"
        case .notAuthorized:
            return "未授权访问 HealthKit"
        case .saveFailed(let error):
            return "保存失败: \(error.localizedDescription)"
        case .readFailed(let error):
            return "读取失败: \(error.localizedDescription)"
        }
    }
}

/// HealthKit 服务
@MainActor
class HealthKitService {
    static let shared = HealthKitService()
    
    private let healthStore = HKHealthStore()
    
    // 需要读取和写入的数据类型
    private let readTypes: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .height)!,
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!,
        HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!,
        HKObjectType.quantityType(forIdentifier: .bloodGlucose)!,
        HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.quantityType(forIdentifier: .dietaryWater)!
    ]
    
    private let writeTypes: Set<HKSampleType> = [
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .height)!,
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!,
        HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!,
        HKObjectType.quantityType(forIdentifier: .bloodGlucose)!,
        HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.quantityType(forIdentifier: .dietaryWater)!
    ]
    
    private init() {}
    
    /// 检查 HealthKit 是否可用
    var isAvailable: Bool {
        return HKHealthStore.isHealthDataAvailable()
    }
    
    /// 请求授权
    func requestAuthorization() async throws {
        guard isAvailable else {
            throw HealthKitError.notAvailable
        }
        
        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
    }
    
    /// 检查授权状态
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        return healthStore.authorizationStatus(for: type)
    }
    
    // MARK: - 保存数据
    
    /// 保存体重
    func saveWeight(_ weight: Double, date: Date = Date()) async throws {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return
        }
        
        let quantity = HKQuantity(unit: HKUnit.gramUnit(with: .kilo), doubleValue: weight)
        let sample = HKQuantitySample(
            type: weightType,
            quantity: quantity,
            start: date,
            end: date
        )
        
        try await healthStore.save(sample)
    }
    
    /// 保存身高
    func saveHeight(_ height: Double, date: Date = Date()) async throws {
        guard let heightType = HKQuantityType.quantityType(forIdentifier: .height) else {
            return
        }
        
        let quantity = HKQuantity(unit: HKUnit.meterUnit(with: .centi), doubleValue: height)
        let sample = HKQuantitySample(
            type: heightType,
            quantity: quantity,
            start: date,
            end: date
        )
        
        try await healthStore.save(sample)
    }
    
    /// 保存心率
    func saveHeartRate(_ heartRate: Double, date: Date = Date()) async throws {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return
        }
        
        let quantity = HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: heartRate)
        let sample = HKQuantitySample(
            type: heartRateType,
            quantity: quantity,
            start: date,
            end: date
        )
        
        try await healthStore.save(sample)
    }
    
    /// 保存血压
    func saveBloodPressure(systolic: Double, diastolic: Double, date: Date = Date()) async throws {
        guard let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else {
            return
        }
        
        let systolicQuantity = HKQuantity(unit: HKUnit.millimeterOfMercury(), doubleValue: systolic)
        let diastolicQuantity = HKQuantity(unit: HKUnit.millimeterOfMercury(), doubleValue: diastolic)
        
        let systolicSample = HKQuantitySample(
            type: systolicType,
            quantity: systolicQuantity,
            start: date,
            end: date
        )
        
        let diastolicSample = HKQuantitySample(
            type: diastolicType,
            quantity: diastolicQuantity,
            start: date,
            end: date
        )
        
        // 血压需要同时保存收缩压和舒张压
        let correlationType = HKObjectType.correlationType(forIdentifier: .bloodPressure)!
        let correlation = HKCorrelation(
            type: correlationType,
            start: date,
            end: date,
            objects: [systolicSample, diastolicSample]
        )
        
        try await healthStore.save(correlation)
    }
    
    /// 保存血糖
    func saveBloodSugar(_ bloodSugar: Double, date: Date = Date()) async throws {
        guard let bloodSugarType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return
        }
        
        let quantity = HKQuantity(unit: HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: HKUnit.liter()), doubleValue: bloodSugar)
        let sample = HKQuantitySample(
            type: bloodSugarType,
            quantity: quantity,
            start: date,
            end: date
        )
        
        try await healthStore.save(sample)
    }
    
    /// 保存体脂率
    func saveBodyFatPercentage(_ percentage: Double, date: Date = Date()) async throws {
        guard let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else {
            return
        }
        
        let quantity = HKQuantity(unit: HKUnit.percent(), doubleValue: percentage / 100.0)
        let sample = HKQuantitySample(
            type: bodyFatType,
            quantity: quantity,
            start: date,
            end: date
        )
        
        try await healthStore.save(sample)
    }
    
    /// 保存卡路里摄入
    func saveCaloriesIntake(_ calories: Double, date: Date = Date()) async throws {
        guard let caloriesType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else {
            return
        }
        
        let quantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: calories)
        let sample = HKQuantitySample(
            type: caloriesType,
            quantity: quantity,
            start: date,
            end: date
        )
        
        try await healthStore.save(sample)
    }
    
    /// 保存卡路里消耗
    func saveCaloriesBurned(_ calories: Double, date: Date = Date()) async throws {
        guard let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return
        }
        
        let quantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: calories)
        let sample = HKQuantitySample(
            type: caloriesType,
            quantity: quantity,
            start: date,
            end: date
        )
        
        try await healthStore.save(sample)
    }
    
    /// 保存睡眠
    func saveSleep(startDate: Date, endDate: Date) async throws {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return
        }
        
        let sample = HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.asleep.rawValue,
            start: startDate,
            end: endDate
        )
        
        try await healthStore.save(sample)
    }
    
    /// 保存饮水量
    func saveWater(_ water: Double, date: Date = Date()) async throws {
        guard let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            return
        }
        
        let quantity = HKQuantity(unit: HKUnit.literUnit(with: .milli), doubleValue: water)
        let sample = HKQuantitySample(
            type: waterType,
            quantity: quantity,
            start: date,
            end: date
        )
        
        try await healthStore.save(sample)
    }
    
    // MARK: - 读取数据
    
    /// 读取最近的体重
    func readLatestWeight() async throws -> Double? {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return nil
        }
        
        let sample = try await mostRecentQuantitySample(of: weightType)
        return sample?.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
    }
    
    /// 读取最近的身高
    func readLatestHeight() async throws -> Double? {
        guard let heightType = HKQuantityType.quantityType(forIdentifier: .height) else {
            return nil
        }
        
        let sample = try await mostRecentQuantitySample(of: heightType)
        return sample?.quantity.doubleValue(for: HKUnit.meterUnit(with: .centi))
    }
    
    /// 获取最近的样本（内部方法）
    private func mostRecentQuantitySample(of type: HKQuantityType) async throws -> HKQuantitySample? {
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.first as? HKQuantitySample)
                }
            }
            
            self.healthStore.execute(query)
        }
    }
}

