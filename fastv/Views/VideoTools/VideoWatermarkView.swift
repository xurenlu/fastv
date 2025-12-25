//
//  VideoWatermarkView.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct VideoWatermarkView: View {
    @ObservedObject var viewModel: VideoProcessorViewModel
    @State private var watermarkType: WatermarkType = .image
    @State private var watermarkImageURL: URL?
    @State private var watermarkText: String = ""
    @State private var position: WatermarkPosition = .bottomRight
    @State private var fontSize: Int = 100
    @State private var opacity: Double = 1.0
    @State private var isProcessing = false
    @State private var progress: Double = 0.0
    @State private var status: String = ""
    
    // 预览相关状态
    @State private var previewImage: NSImage?
    @State private var videoSize: CGSize?
    @State private var isLoadingPreview = false
    
    // 自定义位置和大小（nil 表示使用预设位置）
    @State private var customWatermarkPosition: CGPoint? = nil
    @State private var customWatermarkSize: CGSize? = nil
    
    // 字体文件（用于文字和时间戳水印）
    @State private var fontFileURL: URL? = nil
    
    // 预览组件高度
    @State private var previewHeight: CGFloat = 400
    
    // 随机移动配置
    @State private var enableRandomMovement: Bool = false
    @State private var movementMode: MovementMode = .fixedInterval
    @State private var fixedInterval: Double = 2.0
    @State private var randomIntervalMin: Double = 1.0
    @State private var randomIntervalMax: Double = 5.0
    
    // 漂移速度配置（像素/秒）
    @State private var driftSpeedMin: Double = 10.0
    @State private var driftSpeedMax: Double = 30.0
    
    // 旋转配置
    @State private var rotationMode: RotationMode = .fixed
    @State private var fixedRotationAngle: Double = 0.0  // 固定角度
    @State private var smoothRotationSpeed: Double = 10.0  // 度/秒
    @State private var randomRotationMin: Double = -45.0  // 随机角度最小值
    @State private var randomRotationMax: Double = 45.0   // 随机角度最大值
    
    // 文字颜色配置
    @State private var textColor: Color = .white
    @State private var useCustomColor: Bool = false
    @State private var textOpacity: Double = 80.0 // 默认 80% 不透明度
    
    // 透明度动画配置
    @State private var enableOpacityAnimation: Bool = false
    @State private var opacityAnimationMin: Double = 10.0
    @State private var opacityAnimationMax: Double = 80.0
    @State private var opacityAnimationDuration: Double = 3.0 // 完整周期时长（秒）
    
    // 历史记录
    @State private var watermarkTextHistory: [String] = []
    @State private var fontFileHistory: [URL] = []
    
    // 布局相关
    @State private var layoutMode: LayoutMode = .horizontal
    @State private var showVideoSelector = false
    
    enum WatermarkType {
        case image
        case text
        case timestamp
    }
    
    enum LayoutMode {
        case horizontal  // 横屏视频 - 上下布局
        case vertical    // 竖屏视频 - 左右布局
    }
    
    
    // 预设颜色数据
    private let presetColors = [
        (name: "白色", color: Color.white),
        (name: "黑色", color: Color.black),
        (name: "红色", color: Color.red),
        (name: "蓝色", color: Color.blue),
        (name: "黄色", color: Color.yellow),
        (name: "绿色", color: Color.green)
    ]
    
    // 根据视频宽高比计算布局模式
    private var calculatedLayoutMode: LayoutMode {
        guard let videoSize = videoSize else { return .horizontal }
        let aspectRatio = videoSize.width / videoSize.height
        return aspectRatio < 1.0 ? .vertical : .horizontal
    }
    
    var body: some View {
        Group {
            if viewModel.videoURL == nil {
                // 未选择视频 - 显示占位界面
                videoSelectionPlaceholder
            } else {
                // 已选择视频 - 根据布局模式显示
                if layoutMode == .horizontal {
                    horizontalLayoutView
                } else {
                    verticalLayoutView
                }
            }
        }
        .navigationTitle("水印Logo")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if viewModel.videoURL != nil {
                    Button(action: { showVideoSelector = true }) {
                        Label("更换视频", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showVideoSelector,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            handleVideoSelection(result)
        }
        .onAppear {
            loadPreview()
            
            // 加载历史记录
            watermarkTextHistory = UserPreferences.shared.getWatermarkTextHistory()
            fontFileHistory = UserPreferences.shared.getWatermarkFontHistory()
            
            // 自动填充上次使用的值
            if watermarkText.isEmpty, let lastText = UserPreferences.shared.getLastWatermarkText() {
                watermarkText = lastText
            }
            
            if fontFileURL == nil, let lastFontURL = UserPreferences.shared.getLastWatermarkFontURL() {
                fontFileURL = lastFontURL
            }
        }
        .onChange(of: viewModel.videoURL) { oldValue, newValue in
            if oldValue != newValue {
                loadPreview()
                updateLayoutMode()
            }
        }
        .onChange(of: videoSize) { _, _ in
            updateLayoutMode()
        }
        .onChange(of: watermarkType) { _, _ in
            // 水印类型改变时，预览会自动更新
        }
        .onChange(of: watermarkImageURL) { _, _ in
            // 水印图片改变时，预览会自动更新
        }
        .onChange(of: watermarkText) { _, _ in
            // 水印文字改变时，预览会自动更新
        }
        .onChange(of: position) { _, _ in
            // 位置改变时，预览会自动更新
        }
        .onChange(of: fontSize) { _, _ in
            // 字体大小改变时，预览会自动更新
        }
        .onChange(of: opacity) { _, _ in
            // 透明度改变时，预览会自动更新
        }
        .onChange(of: position) { oldValue, newValue in
            // 当位置改变时，清除自定义位置，使用新的预设位置
            if oldValue != newValue {
                customWatermarkPosition = nil
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateLayoutMode() {
        withAnimation(.easeInOut(duration: 0.3)) {
            layoutMode = calculatedLayoutMode
        }
    }
    
    private func handleVideoSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                viewModel.loadVideo(url)
            }
        case .failure(let error):
            print("选择视频失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Layout Views
    
    private var horizontalLayoutView: some View {
        VStack(spacing: 0) {
            // 上方: 视频预览区
            previewSection
                .frame(height: previewHeight)
            
            Divider()
            
            // 下方: 操作区 (可滚动)
            ScrollView {
                VStack(spacing: 20) {
                    settingsForm
                }
                .padding()
            }
        }
    }
    
    private var verticalLayoutView: some View {
        HSplitView {
            // 左侧: 视频预览区
            previewSection
                .frame(minWidth: 300, idealWidth: 400)
            
            // 右侧: 操作区 (可滚动)
            ScrollView {
                VStack(spacing: 20) {
                    settingsForm
                }
                .padding()
            }
            .frame(minWidth: 350, idealWidth: 450)
        }
    }
    
    // MARK: - Settings Form
    
    private var settingsForm: some View {
        Form {
            Section {
                Picker("水印类型", selection: $watermarkType) {
                    Text("图片水印").tag(WatermarkType.image)
                    Text("文字水印").tag(WatermarkType.text)
                    Text("时间戳").tag(WatermarkType.timestamp)
                }
                
                if watermarkType == .image {
                            HStack {
                                Text("Logo 图片")
                                Spacer()
                                if let url = watermarkImageURL {
                                    Text(url.lastPathComponent)
                                        .foregroundStyle(.secondary)
                                    Button("更改") {
                                        selectImage()
                                    }
                                } else {
                                    Button("选择图片") {
                                        selectImage()
                                    }
                                }
                            }
                        } else if watermarkType == .text {
                            TextField("输入水印文字", text: $watermarkText)
                            
                            // 文字水印历史记录快捷按钮
                            if !watermarkTextHistory.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("快捷选择")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    HStack(spacing: 8) {
                                        ForEach(watermarkTextHistory, id: \.self) { text in
                                            Button(action: {
                                                watermarkText = text
                                            }) {
                                                Text(text)
                                                    .font(.system(size: 12))
                                                    .lineLimit(1)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(watermarkText == text ? Color.blue : Color.gray.opacity(0.2))
                                                    .foregroundColor(watermarkText == text ? .white : .primary)
                                                    .cornerRadius(6)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // 字体文件选择（文字和时间戳模式都需要）
                        if watermarkType == .text || watermarkType == .timestamp {
                            HStack {
                                Text("字体文件")
                                Spacer()
                                if let url = fontFileURL {
                                    Text(url.lastPathComponent)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Button("更改") {
                                        selectFont()
                                    }
                                } else {
                                    Text("未选择")
                                        .foregroundStyle(.secondary)
                                    Button("选择字体") {
                                        selectFont()
                                    }
                                }
                            }
                            
                            // 版权提醒
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text("请使用无商业版权限制的字体文件")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            
                            // 字体文件历史记录快捷按钮
                            if !fontFileHistory.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("最近使用的字体")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    HStack(spacing: 8) {
                                        ForEach(fontFileHistory, id: \.path) { url in
                                            Button(action: {
                                                fontFileURL = url
                                            }) {
                                                Text(url.lastPathComponent)
                                                    .font(.system(size: 12))
                                                    .lineLimit(1)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(fontFileURL?.path == url.path ? Color.blue : Color.gray.opacity(0.2))
                                                    .foregroundColor(fontFileURL?.path == url.path ? .white : .primary)
                                                    .cornerRadius(6)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        
                        Picker("位置", selection: $position) {
                            ForEach(WatermarkPosition.allCases, id: \.self) { pos in
                                Text(pos.displayName).tag(pos)
                            }
                        }
                        
                        HStack {
                            Text("透明度")
                            Spacer()
                            Text(String(format: "%.0f%%", opacity * 100))
                                .monospacedDigit()
                        }
                        Slider(value: $opacity, in: 0.0...1.0, step: 0.1)
                        
                        if watermarkType == .text || watermarkType == .timestamp {
                            HStack {
                                Text("字体大小")
                                Spacer()
                                TextField("", value: $fontSize, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                    .onChange(of: fontSize) { newValue in
                                        fontSize = max(100, newValue)
                                    }
                            }
                        }
                        
                        // 文字颜色选择（文字和时间戳模式）
                        if watermarkType == .text || watermarkType == .timestamp {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("文字颜色")
                                HStack(spacing: 12) {
                                    // 预设颜色按钮
                                    ForEach(presetColors, id: \.name) { preset in
                                        Button(action: {
                                            useCustomColor = false
                                            textColor = preset.color
                                        }) {
                                            Circle()
                                                .fill(preset.color)
                                                .frame(width: 32, height: 32)
                                                .overlay {
                                                    if !useCustomColor && textColor == preset.color {
                                                        Circle()
                                                            .strokeBorder(Color.accentColor, lineWidth: 3)
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Divider()
                                        .frame(height: 32)
                                    
                                    // 自定义颜色选择器
                                    ColorPicker("自定义", selection: $textColor)
                                        .onChange(of: textColor) { _, _ in
                                            useCustomColor = true
                                        }
                                }
                            }
                            
                            // 透明度设置
                            VStack(alignment: .leading, spacing: 12) {
                                Text("文字透明度")
                                    .font(.headline)
                                
                                // 透明度动画开关
                                Toggle("启用透明度动画", isOn: $enableOpacityAnimation)
                                
                                if enableOpacityAnimation {
                                    // 动画范围设置
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("透明度变化范围")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        
                                        HStack {
                                            Text("最小值")
                                            Spacer()
                                            TextField("", value: $opacityAnimationMin, format: .number)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 50)
                                                .onChange(of: opacityAnimationMin) { newValue in
                                                    opacityAnimationMin = max(1, min(30, newValue))
                                                }
                                            Text("%")
                                        }
                                        Slider(value: $opacityAnimationMin, in: 1...30, step: 1)
                                        
                                        HStack {
                                            Text("最大值")
                                            Spacer()
                                            TextField("", value: $opacityAnimationMax, format: .number)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 50)
                                                .onChange(of: opacityAnimationMax) { newValue in
                                                    opacityAnimationMax = max(1, min(30, newValue))
                                                }
                                            Text("%")
                                        }
                                        Slider(value: $opacityAnimationMax, in: 1...30, step: 1)
                                        
                                        HStack {
                                            Text("动画周期")
                                            Spacer()
                                            TextField("", value: $opacityAnimationDuration, format: .number)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 50)
                                                .onChange(of: opacityAnimationDuration) { newValue in
                                                    opacityAnimationDuration = max(0.5, min(20, newValue))
                                                }
                                            Text("秒")
                                        }
                                        Slider(value: $opacityAnimationDuration, in: 0.5...20, step: 0.5)
                                        
                                        Text("透明度将在 \(Int(opacityAnimationMin))% 到 \(Int(opacityAnimationMax))% 之间循环变化")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    // 精细调节：1% - 30%
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("精细调节 (1%-30%)")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text("\(Int(textOpacity))%")
                                                .font(.subheadline)
                                                .foregroundColor(.blue)
                                        }
                                        
                                        HStack {
                                            Slider(value: $textOpacity, in: 1...30, step: 1)
                                            TextField("", value: $textOpacity, format: .number)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 50)
                                                .onChange(of: textOpacity) { newValue in
                                                    textOpacity = max(1, min(100, newValue))
                                                }
                                        }
                                    }
                                    
                                    // 快捷选择：40% - 100%
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("快捷选择")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        
                                        // 第一行：40-70
                                        HStack(spacing: 8) {
                                            ForEach([40, 45, 50, 55, 60, 65, 70], id: \.self) { value in
                                                Button(action: {
                                                    textOpacity = Double(value)
                                                }) {
                                                    Text("\(value)%")
                                                        .font(.system(size: 12))
                                                        .frame(width: 45, height: 28)
                                                        .background(Int(textOpacity) == value ? Color.blue : Color.gray.opacity(0.2))
                                                        .foregroundColor(Int(textOpacity) == value ? .white : .primary)
                                                        .cornerRadius(6)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        
                                        // 第二行：75-100
                                        HStack(spacing: 8) {
                                            ForEach([75, 80, 85, 90, 95, 100], id: \.self) { value in
                                                Button(action: {
                                                    textOpacity = Double(value)
                                                }) {
                                                    Text("\(value)%")
                                                        .font(.system(size: 12))
                                                        .frame(width: 45, height: 28)
                                                        .background(Int(textOpacity) == value ? Color.blue : Color.gray.opacity(0.2))
                                                        .foregroundColor(Int(textOpacity) == value ? .white : .primary)
                                                        .cornerRadius(6)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            Spacer()
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    } header: {
                        Text("水印设置")
                    }
                    
                    // 旋转设置（暂时注释，等待 FFmpeg 支持）
                    /*
                    if watermarkType == .text || watermarkType == .timestamp {
                        Section {
                            Picker("旋转模式", selection: $rotationMode) {
                                Text("固定角度").tag(RotationMode.fixed)
                                Text("缓慢旋转").tag(RotationMode.smooth)
                                Text("随机旋转").tag(RotationMode.random)
                            }
                            
                            switch rotationMode {
                            case .fixed:
                                VStack(spacing: 8) {
                                    HStack {
                                        Text("旋转角度")
                                        Spacer()
                                        Text("\(Int(fixedRotationAngle))°")
                                            .monospacedDigit()
                                    }
                                    Slider(value: $fixedRotationAngle, in: -180...180, step: 15)
                                    
                                    // 快捷角度按钮
                                    HStack(spacing: 8) {
                                        ForEach([0, 30, 45, 90, -30, -45], id: \.self) { angle in
                                            Button("\(angle)°") {
                                                fixedRotationAngle = Double(angle)
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                }
                                
                            case .smooth:
                                VStack {
                                    HStack {
                                        Text("旋转速度")
                                        Spacer()
                                        TextField("", value: $smoothRotationSpeed, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                        Text("度/秒")
                                    }
                                    Slider(value: $smoothRotationSpeed, in: 1...60, step: 1)
                                    
                                    Text("水印将持续匀速旋转")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                            case .random:
                                VStack {
                                    Text("每次位置变化时随机选择旋转角度")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    HStack {
                                        Text("角度范围")
                                        Spacer()
                                        Text("\(Int(randomRotationMin))° ~ \(Int(randomRotationMax))°")
                                            .monospacedDigit()
                                    }
                                    
                                    Text("最小角度: \(Int(randomRotationMin))°")
                                        .font(.caption)
                                    Slider(value: $randomRotationMin, in: -180...0, step: 15)
                                    
                                    Text("最大角度: \(Int(randomRotationMax))°")
                                        .font(.caption)
                                    Slider(value: $randomRotationMax, in: 0...180, step: 15)
                                }
                            }
                        } header: {
                            Text("旋转设置")
                        }
                    }
                    */
                    
                    // 随机移动配置
                    if watermarkType == .text || watermarkType == .timestamp {
                        Section {
                            Toggle("启用随机移动", isOn: $enableRandomMovement)
                                .help("水印位置会定期随机变化，防止被擦除")
                            
                            if enableRandomMovement {
                                Picker("移动模式", selection: $movementMode) {
                                    Text("固定间隔").tag(MovementMode.fixedInterval)
                                    Text("随机间隔").tag(MovementMode.randomInterval)
                                }
                                
                                if movementMode == .fixedInterval {
                                    HStack {
                                        Text("间隔时间")
                                        Spacer()
                                        TextField("", value: $fixedInterval, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                        Text("秒")
                                    }
                                    Slider(value: $fixedInterval, in: 0.5...10.0, step: 0.5)
                                } else {
                                    VStack {
                                        HStack {
                                            Text("最小间隔")
                                            Spacer()
                                            TextField("", value: $randomIntervalMin, format: .number)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 60)
                                            Text("秒")
                                        }
                                        HStack {
                                            Text("最大间隔")
                                            Spacer()
                                            TextField("", value: $randomIntervalMax, format: .number)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 60)
                                            Text("秒")
                                        }
                                    }
                                }
                                
                                // 漂移速度配置
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("漂移速度（像素/秒）")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    HStack {
                                        Text("最小速度")
                                        Spacer()
                                        TextField("", value: $driftSpeedMin, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                            .onChange(of: driftSpeedMin) { newValue in
                                                driftSpeedMin = max(0.1, min(50, newValue))
                                            }
                                        Text("px/s")
                                    }
                                    Slider(value: $driftSpeedMin, in: 0.1...50, step: 0.1)
                                    
                                    HStack {
                                        Text("最大速度")
                                        Spacer()
                                        TextField("", value: $driftSpeedMax, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                            .onChange(of: driftSpeedMax) { newValue in
                                                driftSpeedMax = max(0.1, min(50, newValue))
                                            }
                                        Text("px/s")
                                    }
                                    Slider(value: $driftSpeedMax, in: 0.1...50, step: 0.1)
                                    
                                    Text("水印将在跳转间隔内缓慢漂移 \(String(format: "%.1f", driftSpeedMin))-\(String(format: "%.1f", driftSpeedMax)) 像素/秒")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text("提示：0.5 px/s ≈ 每秒移动半个像素（非常缓慢）")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                if rotationMode == .random {
                                    Text("随机旋转将在每次位置变化时生效")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else if rotationMode == .random {
                                Text("随机旋转需要启用随机移动")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        } header: {
                            Text("防擦除设置")
                        }
                    }
                    
                    if isProcessing {
                        Section {
                            ProgressView(value: progress)
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } header: {
                            Text("处理进度")
                        }
                    }
                
                    Section {
                Button(action: {
                    startWatermark()
                }) {
                    Label("添加水印", systemImage: "text.badge.plus")
                                .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.videoURL == nil || isProcessing || (watermarkType == .image && watermarkImageURL == nil) || (watermarkType == .text && watermarkText.isEmpty) || ((watermarkType == .text || watermarkType == .timestamp) && fontFileURL == nil))
                    }
                }
                .formStyle(.grouped)
    }
    
    // MARK: - Preview Section
    
    @ViewBuilder
    private var previewSection: some View {
        if viewModel.videoURL != nil {
            if let previewImage = previewImage, let videoSize = videoSize {
                watermarkPreviewContent(previewImage: previewImage, videoSize: videoSize)
            } else if isLoadingPreview {
                loadingPreviewView
            } else {
                dropZoneView(message: "拖拽视频文件到这里")
            }
        } else {
            dropZoneView(message: "请先选择视频文件")
        }
    }
    
    @ViewBuilder
    private func watermarkPreviewContent(previewImage: NSImage, videoSize: CGSize) -> some View {
        let previewWatermarkType: WatermarkDraggablePreviewView.WatermarkType = {
            switch watermarkType {
            case .image: return .image
            case .text: return .text
            case .timestamp: return .timestamp
            }
        }()
        
        VStack(spacing: 0) {
        WatermarkDraggablePreviewView(
            previewImage: previewImage,
            videoSize: videoSize,
            watermarkType: previewWatermarkType,
            watermarkImageURL: watermarkImageURL,
            watermarkText: watermarkText,
            fontSize: fontSize,
            opacity: textOpacity / 100.0, // 使用文字透明度
            fontURL: fontFileURL,
            textColor: textColor,
            rotationMode: watermarkType == .text || watermarkType == .timestamp ? rotationMode : nil,
            fixedRotationAngle: fixedRotationAngle,
            smoothRotationSpeed: smoothRotationSpeed,
            randomRotationRange: rotationMode == .random ? (randomRotationMin, randomRotationMax) : nil,
            enableRandomMovement: enableRandomMovement,
            customPosition: $customWatermarkPosition,
            customSize: $customWatermarkSize,
            position: $position
        )
            .frame(height: layoutMode == .horizontal ? previewHeight : nil)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
            }
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.05))
            }
            .onDrop(of: [.fileURL], isTargeted: .constant(false)) { providers in
                handleVideoDrop(providers: providers)
            }
            
            // 可拖动的调整大小控制条 (仅在横屏布局时显示)
            if layoutMode == .horizontal {
                Divider()
                    .frame(height: 8)
                    .background(Color.gray.opacity(0.3))
            }
        }
    }
    
    private var loadingPreviewView: some View {
        ProgressView("加载预览...")
            .frame(minHeight: 300, maxHeight: 600)
    }
    
    @ViewBuilder
    private func dropZoneView(message: String) -> some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
                .frame(minHeight: 300, maxHeight: 600)
                .frame(maxWidth: 600) // 限制最大宽度
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(message)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: .constant(false)) { providers in
                    handleVideoDrop(providers: providers)
                }
            Spacer()
        }
    }
    
    // MARK: - Video Selection Placeholder
    
    private var videoSelectionPlaceholder: some View {
        VStack(spacing: 24) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("选择视频文件")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("支持拖拽视频文件或点击按钮选择")
                .font(.body)
                .foregroundStyle(.secondary)
            
            Button(action: { showVideoSelector = true }) {
                Label("选择视频", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: .constant(false)) { providers in
            handleVideoDrop(providers: providers)
        }
    }
    
    // MARK: - Video Drop Handler
    
    // 处理视频拖拽
    private func handleVideoDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                urls.append(url)
            }
        }
        
        group.notify(queue: .main) {
            if let url = urls.first {
                viewModel.loadVideo(url)
            }
        }
        
        return true
    }
    
    // 加载预览（异步，不阻塞 UI）
    private func loadPreview() {
        guard let videoURL = viewModel.videoURL else {
            previewImage = nil
            videoSize = nil
            isLoadingPreview = false
            return
        }
        
        isLoadingPreview = true
        previewImage = nil
        videoSize = nil
        
        // 使用 Task.detached 确保在后台线程执行，不阻塞 UI
        Task.detached(priority: .userInitiated) {
            // 在沙盒环境下，需要获取安全作用域资源访问权限
            let hasAccess = videoURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    videoURL.stopAccessingSecurityScopedResource()
                }
            }
            
            do {
                // 首先检查文件是否存在和可访问
                let fileManager = FileManager.default
                guard fileManager.fileExists(atPath: videoURL.path) else {
                    throw NSError(
                        domain: "VideoWatermarkView",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "视频文件不存在: \(videoURL.path)"]
                    )
                }
                
                // 检查文件是否可读
                guard fileManager.isReadableFile(atPath: videoURL.path) else {
                    throw NSError(
                        domain: "VideoWatermarkView",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "视频文件无法读取（沙盒权限问题）: \(videoURL.path)\n请尝试重新拖入或选择文件"]
                    )
                }
                
                // 获取视频尺寸
                let videoInfo = try await VideoInfoService.getVideoInfo(from: videoURL)
                
                // 提取第一帧作为预览
                let image = try await FrameExtractor.extractFirstFrame(from: videoURL)
                
                // 回到主线程更新 UI
                await MainActor.run {
                    videoSize = videoInfo.resolution
                    previewImage = image
                    isLoadingPreview = false
                }
            } catch {
                print("❌ [VideoWatermarkView] 加载预览失败: \(error)")
                await MainActor.run {
                    previewImage = nil
                    videoSize = nil
                    isLoadingPreview = false
                }
            }
        }
    }
    
    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            watermarkImageURL = url
        }
    }
    
    private func selectFont() {
        let panel = NSOpenPanel()
        // 允许常见的字体文件类型
        panel.allowedContentTypes = [
            .font, // 通用字体类型
            UTType(filenameExtension: "ttf")!,
            UTType(filenameExtension: "otf")!,
            UTType(filenameExtension: "ttc")!,
            UTType(filenameExtension: "dfont")!
        ]
        panel.allowsMultipleSelection = false
        panel.title = "选择字体文件"
        panel.prompt = "选择"
        
        if panel.runModal() == .OK, let url = panel.url {
            fontFileURL = url
        }
    }
    
    private func startWatermark() {
        guard let inputURL = viewModel.videoURL else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.movie, .mpeg4Movie]
        
        // 获取输入文件的扩展名，如果没有则使用 .mp4
        let inputExtension = inputURL.pathExtension.isEmpty ? "mp4" : inputURL.pathExtension
        savePanel.nameFieldStringValue = inputURL.deletingPathExtension().lastPathComponent + "_watermarked.\(inputExtension)"
        
        if savePanel.runModal() == .OK, var outputURL = savePanel.url {
            // 确保输出文件有扩展名
            if outputURL.pathExtension.isEmpty {
                outputURL = outputURL.appendingPathExtension("mp4")
            }
            isProcessing = true
            progress = 0.0
            status = "准备添加水印..."
            
            Task {
                do {
                    // 保存水印文字到历史记录
                    if watermarkType == .text && !watermarkText.isEmpty {
                        var history = watermarkTextHistory
                        if !history.contains(watermarkText) {
                            history.insert(watermarkText, at: 0)
                            if history.count > 3 {
                                history = Array(history.prefix(3))
                            }
                            watermarkTextHistory = history
                        }
                    }
                    
                    // 保存字体文件到历史记录
                    if let fontURL = fontFileURL, (watermarkType == .text || watermarkType == .timestamp) {
                        var history = fontFileHistory
                        if !history.contains(where: { $0.path == fontURL.path }) {
                            history.insert(fontURL, at: 0)
                            if history.count > 3 {
                                history = Array(history.prefix(3))
                            }
                            fontFileHistory = history
                            // 保存到 UserDefaults
                            let paths = history.map { $0.path }
                            UserDefaults.standard.set(paths, forKey: "watermarkFontHistory")
                        }
                        UserDefaults.standard.set(fontURL.path, forKey: "lastWatermarkFontURL")
                    }
                    
                    switch watermarkType {
                    case .image:
                        guard let watermarkImageURL = watermarkImageURL else { return }
                        try await VideoWatermark.addImageWatermarkWithParallel(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            watermarkImageURL: watermarkImageURL,
                            position: position,
                        customPosition: customWatermarkPosition,
                        customSize: customWatermarkSize,
                            opacity: opacity,
                            margin: 20,
                        progressHandler: { prog, stat in
                                Task { @MainActor in
                                    progress = prog
                                    status = stat
                                }
                            }
                        )
                    case .text:
                        try await VideoWatermark.addTextWatermarkWithParallel(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            text: watermarkText,
                            position: position,
                            fontSize: fontSize,
                            fontColor: textColor.toHexString(),
                            fontPath: fontFileURL?.path,
                            opacity: textOpacity / 100.0,
                            enableOpacityAnimation: enableOpacityAnimation,
                            opacityAnimationRange: enableOpacityAnimation ? (min: opacityAnimationMin, max: opacityAnimationMax) : nil,
                            opacityAnimationDuration: opacityAnimationDuration,
                            margin: 20,
                            enableRandomMovement: enableRandomMovement,
                            movementInterval: movementMode == .fixedInterval ? fixedInterval : nil,
                            randomIntervalRange: movementMode == .randomInterval ? (min: randomIntervalMin, max: randomIntervalMax) : nil,
                            driftSpeedRange: (min: driftSpeedMin, max: driftSpeedMax),
                            progressHandler: { prog, stat in
                                Task { @MainActor in
                                    progress = prog
                                    status = stat
                                }
                            }
                        )
                    case .timestamp:
                        try await VideoWatermark.addTimestampWatermark(
                            inputURL: inputURL,
                            outputURL: outputURL,
                            position: position,
                            fontSize: fontSize,
                            fontColor: textColor.toHexString(),
                            fontPath: fontFileURL?.path,
                            opacity: textOpacity / 100.0,
                            enableOpacityAnimation: enableOpacityAnimation,
                            opacityAnimationRange: enableOpacityAnimation ? (min: opacityAnimationMin, max: opacityAnimationMax) : nil,
                            opacityAnimationDuration: opacityAnimationDuration,
                            margin: 20,
                            enableRandomMovement: enableRandomMovement,
                            movementInterval: movementMode == .fixedInterval ? fixedInterval : nil,
                            randomIntervalRange: movementMode == .randomInterval ? (min: randomIntervalMin, max: randomIntervalMax) : nil,
                            driftSpeedRange: (min: driftSpeedMin, max: driftSpeedMax),
                            progressHandler: { prog, stat in
                                Task { @MainActor in
                                    progress = prog
                                    status = stat
                                }
                            }
                        )
                    }
                    
                    await MainActor.run {
                        isProcessing = false
                        status = "水印添加完成！"
                        print("✅ [VideoWatermarkView] 水印添加成功: \(outputURL.path)")
                    }
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        status = "处理失败: \(error.localizedDescription)"
                        if let ffmpegError = error as? FFmpegError {
                            print("❌ [VideoWatermarkView] FFmpeg错误: \(ffmpegError)")
                        } else {
                            print("❌ [VideoWatermarkView] 添加水印失败: \(error)")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 预览视图
struct VideoWatermarkPreviewView: View {
    let image: NSImage?
    let videoSize: CGSize?
    let watermarkType: VideoWatermarkView.WatermarkType
    let watermarkText: String
    let watermarkImageURL: URL?
    let position: WatermarkPosition
    let opacity: Double
    let fontSize: Int
    let textColor: Color
    let fontURL: URL?
    let margin: Int
    let customPosition: CGPoint?
    let customSize: CGSize?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景图片
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay {
                            Text("无预览")
                                .foregroundStyle(.secondary)
                        }
                }
                
                // 水印预览
                if watermarkType == .text && !watermarkText.isEmpty {
                    Text(watermarkText)
                        .font(.system(size: CGFloat(fontSize)))
                        .foregroundColor(textColor.opacity(opacity))
                        .position(calculatePosition(in: geometry.size))
                } else if watermarkType == .image, let url = watermarkImageURL, let watermarkImage = NSImage(contentsOf: url) {
                    Image(nsImage: watermarkImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(opacity)
                        .frame(width: calculateWatermarkSize(in: geometry.size).width,
                               height: calculateWatermarkSize(in: geometry.size).height)
                        .position(calculatePosition(in: geometry.size))
                }
            }
        }
    }
    
    private func calculatePosition(in size: CGSize) -> CGPoint {
        if let customPos = customPosition, let videoSize = videoSize {
            // 将视频坐标系转换为预览坐标系
            let scaleX = size.width / videoSize.width
            let scaleY = size.height / videoSize.height
            return CGPoint(x: customPos.x * scaleX, y: customPos.y * scaleY)
        }
        
        // 使用预设位置
        let m = CGFloat(margin)
        switch position {
        case .topLeft:
            return CGPoint(x: m, y: m)
        case .topCenter:
            return CGPoint(x: size.width / 2, y: m)
        case .topRight:
            return CGPoint(x: size.width - m, y: m)
        case .middleLeft:
            return CGPoint(x: m, y: size.height / 2)
        case .center:
            return CGPoint(x: size.width / 2, y: size.height / 2)
        case .middleRight:
            return CGPoint(x: size.width - m, y: size.height / 2)
        case .bottomLeft:
            return CGPoint(x: m, y: size.height - m)
        case .bottomCenter:
            return CGPoint(x: size.width / 2, y: size.height - m)
        case .bottomRight:
            return CGPoint(x: size.width - m, y: size.height - m)
        }
    }
    
    private func calculateWatermarkSize(in size: CGSize) -> CGSize {
        if let customSize = customSize, let videoSize = videoSize {
            // 将视频坐标系转换为预览坐标系
            let scaleX = size.width / videoSize.width
            let scaleY = size.height / videoSize.height
            return CGSize(width: customSize.width * scaleX, height: customSize.height * scaleY)
        }
        
        // 默认大小（视频宽度的 15%）
        let maxWidth = size.width * 0.15
        return CGSize(width: maxWidth, height: maxWidth)
    }
}

// MARK: - 颜色预设
struct ColorPreset {
    let name: String
    let color: Color
}

// 预设颜色列表
private let presetColors: [ColorPreset] = [
    ColorPreset(name: "白色", color: .white),
    ColorPreset(name: "黑色", color: .black),
    ColorPreset(name: "红色", color: .red),
    ColorPreset(name: "黄色", color: .yellow)
]

// MARK: - Color Extension
extension Color {
    func toHexString() -> String {
        #if os(macOS)
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else {
            return "FFFFFF"
        }
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        return String(format: "%02X%02X%02X", r, g, b)
        #else
        return "FFFFFF"
        #endif
    }
}

// MARK: - 预览
#Preview {
    VideoWatermarkView(viewModel: VideoProcessorViewModel())
        .frame(width: 800, height: 600)
}
