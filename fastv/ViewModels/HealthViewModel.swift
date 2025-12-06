//
//  HealthViewModel.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

/// 健康助理视图模式
enum HealthViewMode: String, CaseIterable {
    case dashboard = "dashboard"    // 仪表盘
    case meals = "meals"             // 饮食记录
    case exercise = "exercise"       // 运动记录
    case metrics = "metrics"         // 健康指标
    
    var displayName: String {
        switch self {
        case .dashboard:
            return "仪表盘"
        case .meals:
            return "饮食"
        case .exercise:
            return "运动"
        case .metrics:
            return "指标"
        }
    }
    
    var icon: String {
        switch self {
        case .dashboard:
            return "chart.bar.fill"
        case .meals:
            return "fork.knife"
        case .exercise:
            return "figure.run"
        case .metrics:
            return "heart.text.square.fill"
        }
    }
}

/// 饮食记录对话状态
enum MealConversationState {
    case idle                    // 空闲
    case analyzing              // 分析中
    case needClarification      // 需要追问（等待用户回答）
    case completed              // 完成
}

/// 健康助理 ViewModel
@MainActor
class HealthViewModel: ObservableObject {
    @Published var viewMode: HealthViewMode = .dashboard
    @Published var selectedDate: Date = Date()
    
    // 饮食记录相关
    @Published var mealInputText: String = ""
    @Published var mealSelectedImages: [(id: UUID, data: Data)] = []
    @Published var mealType: MealType = .lunch  // 用户选择的餐次（AI会自动识别，这个作为备选）
    @Published var isProcessingMeal: Bool = false
    @Published var mealErrorMessage: String?
    @Published var mealConversationState: MealConversationState = .idle
    @Published var currentMealRecord: MealRecord?
    @Published var currentFoodIndex: Int = 0  // 当前询问的食物索引
    
    // 智能分析相关
    @Published var aiQuestion: String?  // AI追问的问题
    @Published var conversationHistory: [[String: Any]] = []  // 对话历史
    @Published var analyzedFoods: [AnalyzedFood] = []  // 分析的食物列表
    
    // 运动记录相关
    @Published var exerciseInputText: String = ""
    @Published var exerciseSelectedImages: [(id: UUID, data: Data)] = []
    @Published var exerciseType: ExerciseType?
    @Published var exerciseCustomName: String = ""
    @Published var exerciseDuration: TimeInterval?
    @Published var exerciseDistance: Double?
    @Published var isProcessingExercise: Bool = false
    @Published var exerciseErrorMessage: String?
    
    // 健康指标相关
    @Published var selectedMetricType: MetricType = .weight
    @Published var metricValue: String = ""
    @Published var metricNote: String = ""
    
    // 健康档案
    @Published var showProfileSetup: Bool = false
    @Published var profileHeight: String = ""
    @Published var profileWeight: String = ""
    @Published var profileAge: String = ""
    @Published var profileGender: Gender?
    @Published var profileActivityLevel: ActivityLevel?
    @Published var profileGoal: HealthGoal?
    
    private let store = HealthStore.shared
    private let foodService = FoodRecognitionService.shared
    private let intelligentMealService = IntelligentMealAnalysisService.shared
    private let calorieCalculator = CalorieCalculator.shared
    private let healthKitService = HealthKitService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // 订阅 store 的变化
        store.$mealRecords
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        store.$exerciseRecords
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        store.$healthMetrics
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // 检查是否需要设置健康档案
        if store.profile == nil {
            showProfileSetup = true
        }
    }
    
    var profile: HealthProfile? {
        store.profile
    }
    
    var mealRecords: [MealRecord] {
        store.mealRecords(for: selectedDate)
    }
    
    var exerciseRecords: [ExerciseRecord] {
        store.exerciseRecords(for: selectedDate)
    }
    
    var healthMetrics: [HealthMetric] {
        store.healthMetrics(for: selectedDate)
    }
    
    /// 今日总卡路里摄入
    var todayCaloriesIntake: Double {
        store.totalCaloriesIntake(for: Date())
    }
    
    /// 今日总卡路里消耗
    var todayCaloriesBurned: Double {
        store.totalCaloriesBurned(for: Date())
    }
    
    /// 今日净卡路里
    var todayNetCalories: Double {
        todayCaloriesIntake - todayCaloriesBurned
    }
    
    // MARK: - Profile Management
    
    func saveProfile() {
        var newProfile = HealthProfile()
        
        if let height = Double(profileHeight) {
            newProfile.height = height
        }
        if let weight = Double(profileWeight) {
            newProfile.weight = weight
        }
        if let age = Int(profileAge) {
            newProfile.age = age
        }
        newProfile.gender = profileGender
        newProfile.activityLevel = profileActivityLevel
        newProfile.goal = profileGoal
        
        store.updateProfile(newProfile)
        showProfileSetup = false
    }
    
    // MARK: - Meal Recording
    
    /// 选择图片（支持多选）
    func selectMealImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "选择食物图片（可多选）"
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let imageData = try? Data(contentsOf: url) {
                    mealSelectedImages.append((id: UUID(), data: imageData))
                }
            }
        }
    }
    
    /// 删除选中的图片
    func removeMealImage(id: UUID) {
        mealSelectedImages.removeAll { $0.id == id }
    }
    
    /// 发送饮食记录（开始AI智能分析流程）
    func sendMealRecord() async {
        // 如果没有文字也没有图片，提示用户
        guard !mealInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !mealSelectedImages.isEmpty else {
            mealErrorMessage = "请输入文字描述或上传图片"
            return
        }
        
        isProcessingMeal = true
        mealErrorMessage = nil
        mealConversationState = .analyzing
        
        // 开始智能分析
        await analyzeMealIntelligently()
    }
    
    /// 回答AI的追问
    func answerClarification(_ answer: String) async {
        guard mealConversationState == .needClarification else { return }
        
        mealInputText = answer
        mealConversationState = .analyzing
        await analyzeMealIntelligently()
    }
    
    /// 智能分析饮食（支持对话式追问）
    private func analyzeMealIntelligently() async {
        let preferences = UserPreferences.shared
        
        // 查找DashScope配置（必须使用DashScope的qwen-vl引擎）
        guard let dashScopeProfile = preferences.aiServiceProfiles.first(where: { $0.protocolType == .dashScope }),
              !dashScopeProfile.apiKey.isEmpty else {
            mealErrorMessage = "请先在设置中配置阿里云 DashScope API Key"
            mealConversationState = .idle
            isProcessingMeal = false
            return
        }
        
        // 使用qwen-vl-plus或qwen-vl-max模型
        let visionModel = findVisionModel(profile: dashScopeProfile) ?? "qwen-vl-plus"
        
        do {
            let response = try await intelligentMealService.analyzeMeal(
                textInput: mealInputText,
                imageData: mealSelectedImages.map { $0.data },
                conversationHistory: conversationHistory,
                profile: dashScopeProfile,
                model: visionModel,
                timeout: 60.0
            )
            
            // 更新对话历史
            conversationHistory.append([
                "role": "user",
                "content": mealInputText
            ])
            conversationHistory.append([
                "role": "assistant",
                "content": response.question ?? "分析完成"
            ])
            
            // 根据响应类型处理
            switch response.type {
            case .complete:
                // 信息完整，可以直接保存
                await saveMealRecord(from: response)
                mealConversationState = .completed
                isProcessingMeal = false
                
                // 清空输入和对话历史
                mealInputText = ""
                mealSelectedImages = []
                conversationHistory = []
                aiQuestion = nil
                
            case .needClarification:
                // 需要追问
                analyzedFoods = response.foods
                aiQuestion = response.question
                mealConversationState = .needClarification
                isProcessingMeal = false
                
                // 清空输入框，等待用户回答
                mealInputText = ""
            }
            
        } catch {
            mealErrorMessage = "饮食分析失败: \(error.localizedDescription)"
            mealConversationState = .idle
            isProcessingMeal = false
            print("❌ [HealthViewModel] 饮食分析失败: \(error)")
        }
    }
    
    /// 保存饮食记录
    private func saveMealRecord(from response: MealAnalysisResponse) async {
        // 确定餐次类型（优先使用AI识别的，否则使用用户选择的）
        let finalMealType = response.mealType ?? mealType
        
        // 转换AnalyzedFood为RecognizedFood
        var recognizedFoods: [RecognizedFood] = []
        var totalCalories: Double = 0
        
        for analyzedFood in response.foods {
            let actualCalories = analyzedFood.actualCalories ?? analyzedFood.calories ?? 0
            totalCalories += actualCalories
            
            let recognizedFood = RecognizedFood(
                name: analyzedFood.name,
                estimatedAmount: analyzedFood.amount,
                consumedRatio: analyzedFood.consumedRatio ?? 1.0,
                calories: actualCalories,
                protein: analyzedFood.protein,
                carbs: analyzedFood.carbs,
                fat: analyzedFood.fat
            )
            recognizedFoods.append(recognizedFood)
        }
        
        // 创建记录
        let record = MealRecord(
            mealType: finalMealType,
            date: Date(),
            textDescription: mealInputText.isEmpty ? nil : mealInputText,
            imageData: mealSelectedImages.map { $0.data },
            recognizedFoods: recognizedFoods,
            totalCalories: totalCalories > 0 ? totalCalories : nil
        )
        
        // 保存到Store
        store.addMealRecord(record)
        
        // 同步到HealthKit
        await syncMealToHealthKit(record)
        
        print("✅ [HealthViewModel] 饮食记录已保存，总卡路里: \(totalCalories)")
    }
    
    /// 同步饮食记录到HealthKit
    private func syncMealToHealthKit(_ record: MealRecord) async {
        guard let totalCalories = record.totalCalories, totalCalories > 0 else { return }
        
        do {
            try await healthKitService.saveCaloriesIntake(totalCalories, date: record.date)
            print("✅ [HealthViewModel] HealthKit: 饮食卡路里 \(totalCalories) kcal 已同步")
        } catch {
            print("❌ [HealthViewModel] HealthKit: 同步饮食卡路里失败: \(error.localizedDescription)")
        }
    }
    
    /// 查找支持视觉的模型（仅支持DashScope的qwen-vl系列）
    private func findVisionModel(profile: AIServiceProfile) -> String? {
        // 只支持DashScope的qwen-vl系列模型
        guard profile.protocolType == .dashScope else {
            return nil
        }
        
        // 优先使用qwen-vl-plus，如果有配置qwen-vl-max也可以使用
        // 检查profile中是否有配置的视觉模型
        if profile.defaultModel.contains("qwen-vl") {
            return profile.defaultModel
        }
        
        // 默认返回qwen-vl-plus
        return "qwen-vl-plus"
    }
    
    /// 设置食物的食用比例
    func setFoodConsumedRatio(foodId: UUID, ratio: Double) {
        guard var record = currentMealRecord else { return }
        
        if let index = record.recognizedFoods.firstIndex(where: { $0.id == foodId }) {
            record.recognizedFoods[index].consumedRatio = ratio
            // 重新计算实际卡路里
            if let calories = record.recognizedFoods[index].calories {
                record.recognizedFoods[index].calories = calories * ratio
            }
            currentMealRecord = record
        }
    }
    
    /// 完成当前食物的询问，继续下一个
    func nextFood() {
        guard let record = currentMealRecord else { return }
        
        currentFoodIndex += 1
        
        if currentFoodIndex >= record.recognizedFoods.count {
            // 所有食物都询问完了
            mealConversationState = .completed
            Task {
                await finalizeMealRecord()
            }
        }
    }
    
    /// 完成饮食记录
    private func finalizeMealRecord() async {
        guard var record = currentMealRecord else { return }
        
        // 计算总卡路里
        let totalCalories = record.recognizedFoods.compactMap { $0.actualCalories }.reduce(0, +)
        record.totalCalories = totalCalories > 0 ? totalCalories : nil
        
        // 保存记录
        store.addMealRecord(record)
        
        // 同步到 HealthKit
        if let calories = record.totalCalories {
            try? await healthKitService.saveCaloriesIntake(calories, date: record.date)
        }
        
        // 重置状态
        mealInputText = ""
        mealSelectedImages = []
        currentMealRecord = nil
        mealConversationState = .idle
        isProcessingMeal = false
        
        // 清空错误信息
        mealErrorMessage = nil
    }
    
    // MARK: - Exercise Recording
    
    /// 选择运动图片
    func selectExerciseImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "选择运动图片（可多选）"
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let imageData = try? Data(contentsOf: url) {
                    exerciseSelectedImages.append((id: UUID(), data: imageData))
                }
            }
        }
    }
    
    /// 删除选中的运动图片
    func removeExerciseImage(id: UUID) {
        exerciseSelectedImages.removeAll { $0.id == id }
    }
    
    /// 保存运动记录
    func saveExerciseRecord() async {
        guard let profile = store.profile else {
            exerciseErrorMessage = "请先设置健康档案"
            return
        }
        
        isProcessingExercise = true
        exerciseErrorMessage = nil
        
        // 计算消耗的卡路里
        let caloriesBurned = calorieCalculator.calculateExerciseCalories(
            exerciseType: exerciseType,
            customName: exerciseCustomName.isEmpty ? nil : exerciseCustomName,
            duration: exerciseDuration,
            weight: profile.weight,
            distance: exerciseDistance
        )
        
        let record = ExerciseRecord(
            exerciseType: exerciseType,
            customName: exerciseCustomName.isEmpty ? nil : exerciseCustomName,
            date: Date(),
            duration: exerciseDuration,
            distance: exerciseDistance,
            textDescription: exerciseInputText.isEmpty ? nil : exerciseInputText,
            imageData: exerciseSelectedImages.map { $0.data },
            caloriesBurned: caloriesBurned
        )
        
        store.addExerciseRecord(record)
        
        // 同步到 HealthKit
        if let calories = caloriesBurned {
            try? await healthKitService.saveCaloriesBurned(calories, date: record.date)
        }
        
        // 重置状态
        exerciseInputText = ""
        exerciseSelectedImages = []
        exerciseType = nil
        exerciseCustomName = ""
        exerciseDuration = nil
        exerciseDistance = nil
        isProcessingExercise = false
    }
    
    // MARK: - Health Metrics
    
    /// 保存健康指标
    func saveHealthMetric() async {
        guard let value = Double(metricValue) else {
            return
        }
        
        let metric = HealthMetric(
            metricType: selectedMetricType,
            value: value,
            unit: selectedMetricType.defaultUnit,
            date: Date(),
            note: metricNote.isEmpty ? nil : metricNote
        )
        
        store.addHealthMetric(metric)
        
        // 同步到 HealthKit
        switch selectedMetricType {
        case .weight:
            try? await healthKitService.saveWeight(value, date: metric.date)
        case .heartRate:
            try? await healthKitService.saveHeartRate(value, date: metric.date)
        case .bloodSugar:
            try? await healthKitService.saveBloodSugar(value, date: metric.date)
        case .bodyFat:
            try? await healthKitService.saveBodyFatPercentage(value, date: metric.date)
        case .water:
            try? await healthKitService.saveWater(value, date: metric.date)
        default:
            break
        }
        
        // 重置状态
        metricValue = ""
        metricNote = ""
    }
    
    // MARK: - Delete Operations
    
    func deleteMealRecord(_ record: MealRecord) {
        store.deleteMealRecord(record)
    }
    
    func deleteExerciseRecord(_ record: ExerciseRecord) {
        store.deleteExerciseRecord(record)
    }
    
    func deleteHealthMetric(_ metric: HealthMetric) {
        store.deleteHealthMetric(metric)
    }
}

