//
//  HealthStore.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import Combine

/// 健康数据存储管理器
@MainActor
class HealthStore: ObservableObject {
    static let shared = HealthStore()
    
    @Published private(set) var profile: HealthProfile?
    @Published private(set) var mealRecords: [MealRecord] = []
    @Published private(set) var exerciseRecords: [ExerciseRecord] = []
    @Published private(set) var healthMetrics: [HealthMetric] = []
    @Published private(set) var moodRecords: [MoodRecord] = []
    @Published private(set) var medicationRecords: [MedicationRecord] = []
    
    private let profileKey = "healthProfile"
    private let mealRecordsKey = "mealRecords"
    private let exerciseRecordsKey = "exerciseRecords"
    private let healthMetricsKey = "healthMetrics"
    private let moodRecordsKey = "moodRecords"
    private let medicationRecordsKey = "medicationRecords"
    
    private var saveTimer: Timer?
    private let saveDelay: TimeInterval = 1.0
    
    private init() {
        loadProfile()
        loadMealRecords()
        loadExerciseRecords()
        loadHealthMetrics()
        loadMoodRecords()
        loadMedicationRecords()
    }
    
    // MARK: - Profile Management
    
    func updateProfile(_ profile: HealthProfile) {
        self.profile = profile
        scheduleSaveProfile()
    }
    
    // MARK: - Meal Records
    
    func addMealRecord(_ record: MealRecord) {
        mealRecords.append(record)
        scheduleSaveMealRecords()
    }
    
    func updateMealRecord(_ record: MealRecord) {
        if let index = mealRecords.firstIndex(where: { $0.id == record.id }) {
            mealRecords[index] = record
            scheduleSaveMealRecords()
        }
    }
    
    func deleteMealRecord(_ record: MealRecord) {
        mealRecords.removeAll { $0.id == record.id }
        scheduleSaveMealRecords()
    }
    
    func mealRecords(for date: Date) -> [MealRecord] {
        let calendar = Calendar.current
        return mealRecords.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    func mealRecords(from startDate: Date, to endDate: Date) -> [MealRecord] {
        return mealRecords.filter { $0.date >= startDate && $0.date <= endDate }
    }
    
    /// 计算指定日期的总卡路里摄入
    func totalCaloriesIntake(for date: Date) -> Double {
        let records = mealRecords(for: date)
        return records.compactMap { $0.totalCalories }.reduce(0, +)
    }
    
    // MARK: - Exercise Records
    
    func addExerciseRecord(_ record: ExerciseRecord) {
        exerciseRecords.append(record)
        scheduleSaveExerciseRecords()
    }
    
    func updateExerciseRecord(_ record: ExerciseRecord) {
        if let index = exerciseRecords.firstIndex(where: { $0.id == record.id }) {
            exerciseRecords[index] = record
            scheduleSaveExerciseRecords()
        }
    }
    
    func deleteExerciseRecord(_ record: ExerciseRecord) {
        exerciseRecords.removeAll { $0.id == record.id }
        scheduleSaveExerciseRecords()
    }
    
    func exerciseRecords(for date: Date) -> [ExerciseRecord] {
        let calendar = Calendar.current
        return exerciseRecords.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    func exerciseRecords(from startDate: Date, to endDate: Date) -> [ExerciseRecord] {
        return exerciseRecords.filter { $0.date >= startDate && $0.date <= endDate }
    }
    
    /// 计算指定日期的总卡路里消耗
    func totalCaloriesBurned(for date: Date) -> Double {
        let records = exerciseRecords(for: date)
        return records.compactMap { $0.caloriesBurned }.reduce(0, +)
    }
    
    // MARK: - Health Metrics
    
    func addHealthMetric(_ metric: HealthMetric) {
        healthMetrics.append(metric)
        scheduleSaveHealthMetrics()
    }
    
    func updateHealthMetric(_ metric: HealthMetric) {
        if let index = healthMetrics.firstIndex(where: { $0.id == metric.id }) {
            healthMetrics[index] = metric
            scheduleSaveHealthMetrics()
        }
    }
    
    func deleteHealthMetric(_ metric: HealthMetric) {
        healthMetrics.removeAll { $0.id == metric.id }
        scheduleSaveHealthMetrics()
    }
    
    func healthMetrics(for date: Date) -> [HealthMetric] {
        let calendar = Calendar.current
        return healthMetrics.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    func healthMetrics(type: MetricType, from startDate: Date? = nil, to endDate: Date? = nil) -> [HealthMetric] {
        var filtered = healthMetrics.filter { $0.metricType == type }
        if let startDate = startDate, let endDate = endDate {
            filtered = filtered.filter { $0.date >= startDate && $0.date <= endDate }
        }
        return filtered.sorted { $0.date < $1.date }
    }
    
    // MARK: - Mood Records
    
    func addMoodRecord(_ record: MoodRecord) {
        moodRecords.append(record)
        scheduleSaveMoodRecords()
    }
    
    func updateMoodRecord(_ record: MoodRecord) {
        if let index = moodRecords.firstIndex(where: { $0.id == record.id }) {
            moodRecords[index] = record
            scheduleSaveMoodRecords()
        }
    }
    
    func deleteMoodRecord(_ record: MoodRecord) {
        moodRecords.removeAll { $0.id == record.id }
        scheduleSaveMoodRecords()
    }
    
    func moodRecords(for date: Date) -> [MoodRecord] {
        let calendar = Calendar.current
        return moodRecords.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    // MARK: - Medication Records
    
    func addMedicationRecord(_ record: MedicationRecord) {
        medicationRecords.append(record)
        scheduleSaveMedicationRecords()
    }
    
    func updateMedicationRecord(_ record: MedicationRecord) {
        if let index = medicationRecords.firstIndex(where: { $0.id == record.id }) {
            medicationRecords[index] = record
            scheduleSaveMedicationRecords()
        }
    }
    
    func deleteMedicationRecord(_ record: MedicationRecord) {
        medicationRecords.removeAll { $0.id == record.id }
        scheduleSaveMedicationRecords()
    }
    
    func medicationRecords(for date: Date) -> [MedicationRecord] {
        let calendar = Calendar.current
        return medicationRecords.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    // MARK: - Statistics
    
    /// 计算指定日期范围的卡路里净摄入（摄入 - 消耗）
    func netCalories(from startDate: Date, to endDate: Date) -> Double {
        let intake = mealRecords(from: startDate, to: endDate).compactMap { $0.totalCalories }.reduce(0, +)
        let burned = exerciseRecords(from: startDate, to: endDate).compactMap { $0.caloriesBurned }.reduce(0, +)
        return intake - burned
    }
    
    // MARK: - Persistence
    
    private func scheduleSaveProfile() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.saveProfile()
            }
        }
    }
    
    private func saveProfile() {
        if let profile = profile, let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: profileKey)
        }
    }
    
    private func loadProfile() {
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let decoded = try? JSONDecoder().decode(HealthProfile.self, from: data) {
            profile = decoded
        }
    }
    
    private func scheduleSaveMealRecords() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.saveMealRecords()
            }
        }
    }
    
    private func saveMealRecords() {
        if let encoded = try? JSONEncoder().encode(mealRecords) {
            UserDefaults.standard.set(encoded, forKey: mealRecordsKey)
        }
    }
    
    private func loadMealRecords() {
        if let data = UserDefaults.standard.data(forKey: mealRecordsKey),
           let decoded = try? JSONDecoder().decode([MealRecord].self, from: data) {
            mealRecords = decoded.sorted { $0.date > $1.date }
        }
    }
    
    private func scheduleSaveExerciseRecords() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.saveExerciseRecords()
            }
        }
    }
    
    private func saveExerciseRecords() {
        if let encoded = try? JSONEncoder().encode(exerciseRecords) {
            UserDefaults.standard.set(encoded, forKey: exerciseRecordsKey)
        }
    }
    
    private func loadExerciseRecords() {
        if let data = UserDefaults.standard.data(forKey: exerciseRecordsKey),
           let decoded = try? JSONDecoder().decode([ExerciseRecord].self, from: data) {
            exerciseRecords = decoded.sorted { $0.date > $1.date }
        }
    }
    
    private func scheduleSaveHealthMetrics() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.saveHealthMetrics()
            }
        }
    }
    
    private func saveHealthMetrics() {
        if let encoded = try? JSONEncoder().encode(healthMetrics) {
            UserDefaults.standard.set(encoded, forKey: healthMetricsKey)
        }
    }
    
    private func loadHealthMetrics() {
        if let data = UserDefaults.standard.data(forKey: healthMetricsKey),
           let decoded = try? JSONDecoder().decode([HealthMetric].self, from: data) {
            healthMetrics = decoded.sorted { $0.date > $1.date }
        }
    }
    
    private func scheduleSaveMoodRecords() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.saveMoodRecords()
            }
        }
    }
    
    private func saveMoodRecords() {
        if let encoded = try? JSONEncoder().encode(moodRecords) {
            UserDefaults.standard.set(encoded, forKey: moodRecordsKey)
        }
    }
    
    private func loadMoodRecords() {
        if let data = UserDefaults.standard.data(forKey: moodRecordsKey),
           let decoded = try? JSONDecoder().decode([MoodRecord].self, from: data) {
            moodRecords = decoded.sorted { $0.date > $1.date }
        }
    }
    
    private func scheduleSaveMedicationRecords() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.saveMedicationRecords()
            }
        }
    }
    
    private func saveMedicationRecords() {
        if let encoded = try? JSONEncoder().encode(medicationRecords) {
            UserDefaults.standard.set(encoded, forKey: medicationRecordsKey)
        }
    }
    
    private func loadMedicationRecords() {
        if let data = UserDefaults.standard.data(forKey: medicationRecordsKey),
           let decoded = try? JSONDecoder().decode([MedicationRecord].self, from: data) {
            medicationRecords = decoded.sorted { $0.date > $1.date }
        }
    }
}

