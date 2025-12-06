//
//  HealthAssistantView.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import SwiftUI

struct HealthAssistantView: View {
    @StateObject private var viewModel = HealthViewModel()
    @ObservedObject private var store = HealthStore.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // 视图模式切换工具栏
            viewModeToolbar
            
            Divider()
            
            // 内容视图
            contentView
        }
        .navigationTitle("健康助理")
        .sheet(isPresented: $viewModel.showProfileSetup) {
            HealthProfileSetupView(viewModel: viewModel)
        }
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        switch viewModel.viewMode {
        case .dashboard:
            HealthDashboardView(viewModel: viewModel)
        case .meals:
            MealInputView(viewModel: viewModel)
        case .exercise:
            ExerciseInputView(viewModel: viewModel)
        case .metrics:
            HealthMetricsView(viewModel: viewModel)
        }
    }
    
    // MARK: - View Mode Toolbar
    
    private var viewModeToolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $viewModel.viewMode) {
                ForEach(HealthViewMode.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)
            
            Spacer()
            
            // 日期选择器
            DatePicker("日期", selection: $viewModel.selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .frame(width: 150)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.regularMaterial)
        }
    }
}

// MARK: - Health Dashboard View

struct HealthDashboardView: View {
    @ObservedObject var viewModel: HealthViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 今日概览卡片
                todayOverviewCard
                
                // 卡路里统计
                caloriesCard
                
                // 今日记录列表
                todayRecordsCard
            }
            .padding(20)
        }
    }
    
    private var todayOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日概览")
                .font(.headline)
            
            HStack(spacing: 20) {
                StatItem(
                    title: "摄入",
                    value: String(format: "%.0f", viewModel.todayCaloriesIntake),
                    unit: "大卡",
                    color: .blue
                )
                
                StatItem(
                    title: "消耗",
                    value: String(format: "%.0f", viewModel.todayCaloriesBurned),
                    unit: "大卡",
                    color: .green
                )
                
                StatItem(
                    title: "净摄入",
                    value: String(format: "%.0f", viewModel.todayNetCalories),
                    unit: "大卡",
                    color: viewModel.todayNetCalories > 0 ? .orange : .blue
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
    }
    
    private var caloriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("卡路里统计")
                .font(.headline)
            
            if let profile = viewModel.profile, let tdee = profile.tdee {
                VStack(alignment: .leading, spacing: 8) {
                    Text("每日目标消耗: \(String(format: "%.0f", tdee)) 大卡")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    ProgressView(value: viewModel.todayCaloriesIntake, total: tdee)
                        .progressViewStyle(.linear)
                    
                    Text("\(String(format: "%.0f", viewModel.todayCaloriesIntake)) / \(String(format: "%.0f", tdee)) 大卡")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("请先设置健康档案以查看目标")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
    }
    
    private var todayRecordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日记录")
                .font(.headline)
            
            if viewModel.mealRecords.isEmpty && viewModel.exerciseRecords.isEmpty {
                Text("暂无记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !viewModel.mealRecords.isEmpty {
                        Text("饮食记录: \(viewModel.mealRecords.count) 条")
                            .font(.subheadline)
                    }
                    
                    if !viewModel.exerciseRecords.isEmpty {
                        Text("运动记录: \(viewModel.exerciseRecords.count) 条")
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}

struct StatItem: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Meal Input View

struct MealInputView: View {
    @ObservedObject var viewModel: HealthViewModel
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 输入区域
            mealInputSection
            
            Divider()
            
            // 记录列表
            if viewModel.mealRecords.isEmpty {
                emptyMealStateView
            } else {
                mealRecordsList
            }
        }
    }
    
    private var mealInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 餐次选择（AI会自动识别，这里作为备选）
            VStack(alignment: .leading, spacing: 4) {
                Text("餐次（AI会自动识别）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                
                Picker("餐次", selection: $viewModel.mealType) {
                    ForEach(MealType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
            }
            .padding(.top, 16)
            
            // 输入框和按钮
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    TextField("描述今天吃了什么...", text: $viewModel.mealInputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...8)
                        .frame(minHeight: 60)
                        .focused($isInputFocused)
                    
                    // 图片选择按钮
                    Button(action: {
                        viewModel.selectMealImages()
                    }) {
                        Image(systemName: "photo.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isProcessingMeal)
                    .help("选择食物图片（可多选）")
                    
                    // 发送按钮
                    Button(action: {
                        Task {
                            await viewModel.sendMealRecord()
                        }
                    }) {
                        if viewModel.isProcessingMeal {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isProcessingMeal || (viewModel.mealInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.mealSelectedImages.isEmpty))
                    .help("发送")
                }
                
                // 选中的图片预览
                if !viewModel.mealSelectedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.mealSelectedImages, id: \.id) { imageItem in
                                ImagePreview(imageData: imageItem.data, onDelete: {
                                    viewModel.removeMealImage(id: imageItem.id)
                                })
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(height: 100)
                }
            }
            .padding(.horizontal, 20)
            
            // AI追问显示
            if viewModel.mealConversationState == .needClarification,
               let question = viewModel.aiQuestion {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("AI需要确认")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    
                    Text(question)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 24)
                    
                    // 快速回答按钮（可选）
                    HStack(spacing: 8) {
                        Button("全部") {
                            Task {
                                await viewModel.answerClarification("全部")
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("一半") {
                            Task {
                                await viewModel.answerClarification("一半")
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("三分之一") {
                            Task {
                                await viewModel.answerClarification("三分之一")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.leading, 24)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 20)
            }
            
            // 分析中状态
            if viewModel.mealConversationState == .analyzing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("AI正在分析中...")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            
            // 旧的对话状态显示（已废弃，保留兼容性，但不会执行）
            // 新的追问流程使用 needClarification 状态
            
            // 错误消息
            if let errorMessage = viewModel.mealErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func foodRatioQuestionView(food: RecognizedFood) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("请问您吃了多少 \(food.name)？")
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            HStack(spacing: 12) {
                Button("全部") {
                    viewModel.setFoodConsumedRatio(foodId: food.id, ratio: 1.0)
                    viewModel.nextFood()
                }
                .buttonStyle(.bordered)
                
                Button("一半") {
                    viewModel.setFoodConsumedRatio(foodId: food.id, ratio: 0.5)
                    viewModel.nextFood()
                }
                .buttonStyle(.bordered)
                
                Button("三分之一") {
                    viewModel.setFoodConsumedRatio(foodId: food.id, ratio: 0.33)
                    viewModel.nextFood()
                }
                .buttonStyle(.bordered)
                
                Button("四分之一") {
                    viewModel.setFoodConsumedRatio(foodId: food.id, ratio: 0.25)
                    viewModel.nextFood()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.blue.opacity(0.1))
        }
    }
    
    private var mealRecordsList: some View {
        List {
            ForEach(viewModel.mealRecords) { record in
                MealRecordRow(record: record)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.deleteMealRecord(record)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.inset)
    }
    
    private var emptyMealStateView: some View {
        ContentUnavailableView {
            Label("暂无饮食记录", systemImage: "fork.knife")
        } description: {
            Text("输入文字描述或上传图片来记录您的饮食")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MealRecordRow: View {
    let record: MealRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(record.mealType.displayName, systemImage: record.mealType.icon)
                    .font(.headline)
                
                Spacer()
                
                if let calories = record.totalCalories {
                    Text("\(String(format: "%.0f", calories)) 大卡")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let description = record.textDescription {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if !record.recognizedFoods.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(record.recognizedFoods) { food in
                        HStack {
                            Text(food.name)
                            if let amount = food.estimatedAmount {
                                Text("(\(amount))")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let calories = food.actualCalories {
                                Text("\(String(format: "%.0f", calories)) 大卡")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding(.top, 4)
            }
            
            Text(record.date, style: .time)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Exercise Input View

struct ExerciseInputView: View {
    @ObservedObject var viewModel: HealthViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // 输入区域
            exerciseInputSection
            
            Divider()
            
            // 记录列表
            if viewModel.exerciseRecords.isEmpty {
                emptyExerciseStateView
            } else {
                exerciseRecordsList
            }
        }
    }
    
    private var exerciseInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                // 运动类型选择
                Picker("运动类型", selection: Binding(
                    get: { viewModel.exerciseType },
                    set: { viewModel.exerciseType = $0 }
                )) {
                    Text("选择运动类型").tag(nil as ExerciseType?)
                    ForEach(ExerciseType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon)
                            .tag(type as ExerciseType?)
                    }
                }
                .pickerStyle(.menu)
                
                // 自定义名称
                TextField("或输入自定义运动名称", text: $viewModel.exerciseCustomName)
                    .textFieldStyle(.roundedBorder)
                
                // 持续时间
                HStack {
                    Text("持续时间（分钟）")
                    TextField("", value: $viewModel.exerciseDuration, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                
                // 距离（可选）
                HStack {
                    Text("距离（公里）")
                    TextField("", value: $viewModel.exerciseDistance, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                
                // 文字描述
                TextField("描述运动情况...", text: $viewModel.exerciseInputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .frame(minHeight: 60)
                
                // 图片选择
                HStack {
                    Button(action: {
                        viewModel.selectExerciseImages()
                    }) {
                        Label("选择图片", systemImage: "photo.fill")
                    }
                    .buttonStyle(.bordered)
                    
                    if !viewModel.exerciseSelectedImages.isEmpty {
                        Text("已选择 \(viewModel.exerciseSelectedImages.count) 张")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 保存按钮
                Button(action: {
                    Task {
                        await viewModel.saveExerciseRecord()
                    }
                }) {
                    if viewModel.isProcessingExercise {
                        ProgressView()
                    } else {
                        Text("保存运动记录")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isProcessingExercise)
            }
            .padding(20)
            
            if let errorMessage = viewModel.exerciseErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var exerciseRecordsList: some View {
        List {
            ForEach(viewModel.exerciseRecords) { record in
                ExerciseRecordRow(record: record)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.deleteExerciseRecord(record)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.inset)
    }
    
    private var emptyExerciseStateView: some View {
        ContentUnavailableView {
            Label("暂无运动记录", systemImage: "figure.run")
        } description: {
            Text("记录您的运动情况，追踪卡路里消耗")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ExerciseRecordRow: View {
    let record: ExerciseRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.name)
                    .font(.headline)
                
                Spacer()
                
                if let calories = record.caloriesBurned {
                    Text("消耗 \(String(format: "%.0f", calories)) 大卡")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let duration = record.duration {
                Text("时长: \(String(format: "%.0f", duration / 60)) 分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let distance = record.distance {
                Text("距离: \(String(format: "%.2f", distance)) 公里")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let description = record.textDescription {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(record.date, style: .time)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Health Metrics View

struct HealthMetricsView: View {
    @ObservedObject var viewModel: HealthViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // 输入区域
            metricsInputSection
            
            Divider()
            
            // 记录列表
            if viewModel.healthMetrics.isEmpty {
                emptyMetricsStateView
            } else {
                metricsList
            }
        }
    }
    
    private var metricsInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                // 指标类型选择
                Picker("指标类型", selection: $viewModel.selectedMetricType) {
                    ForEach(MetricType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.menu)
                
                // 数值输入
                HStack {
                    Text("数值")
                    TextField("", text: $viewModel.metricValue)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    
                    Text(viewModel.selectedMetricType.defaultUnit)
                        .foregroundStyle(.secondary)
                }
                
                // 备注
                TextField("备注（可选）", text: $viewModel.metricNote)
                    .textFieldStyle(.roundedBorder)
                
                // 保存按钮
                Button(action: {
                    Task {
                        await viewModel.saveHealthMetric()
                    }
                }) {
                    Text("保存")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var metricsList: some View {
        List {
            ForEach(viewModel.healthMetrics) { metric in
                HealthMetricRow(metric: metric)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.deleteHealthMetric(metric)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.inset)
    }
    
    private var emptyMetricsStateView: some View {
        ContentUnavailableView {
            Label("暂无健康指标记录", systemImage: "heart.text.square.fill")
        } description: {
            Text("记录您的健康指标，追踪身体状况")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HealthMetricRow: View {
    let metric: HealthMetric
    
    var body: some View {
        HStack {
            Image(systemName: metric.metricType.icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.metricType.displayName)
                    .font(.headline)
                
                if let note = metric.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(String(format: "%.1f", metric.value)) \(metric.unit)")
                    .font(.headline)
                
                Text(metric.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Health Profile Setup View

struct HealthProfileSetupView: View {
    @ObservedObject var viewModel: HealthViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    HStack {
                        Text("身高（厘米）")
                        TextField("", text: $viewModel.profileHeight)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("体重（千克）")
                        TextField("", text: $viewModel.profileWeight)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("年龄")
                        TextField("", text: $viewModel.profileAge)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Picker("性别", selection: Binding(
                        get: { viewModel.profileGender },
                        set: { viewModel.profileGender = $0 }
                    )) {
                        Text("选择性别").tag(nil as Gender?)
                        ForEach(Gender.allCases, id: \.self) { gender in
                            Text(gender.displayName).tag(gender as Gender?)
                        }
                    }
                }
                
                Section("活动水平") {
                    Picker("活动水平", selection: Binding(
                        get: { viewModel.profileActivityLevel },
                        set: { viewModel.profileActivityLevel = $0 }
                    )) {
                        Text("选择活动水平").tag(nil as ActivityLevel?)
                        ForEach(ActivityLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level as ActivityLevel?)
                        }
                    }
                }
                
                Section("健康目标") {
                    Picker("目标", selection: Binding(
                        get: { viewModel.profileGoal },
                        set: { viewModel.profileGoal = $0 }
                    )) {
                        Text("选择目标").tag(nil as HealthGoal?)
                        ForEach(HealthGoal.allCases, id: \.self) { goal in
                            Text(goal.displayName).tag(goal as HealthGoal?)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("设置健康档案")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        viewModel.saveProfile()
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
    }
}

#Preview {
    HealthAssistantView()
}

