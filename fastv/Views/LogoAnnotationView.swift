//
//  LogoAnnotationView.swift
//  fastv
//
//  Created by rocky on 2025/12/13.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LogoAnnotationView: View {
    @StateObject private var viewModel: LogoAnnotationViewModel
    @State private var dragStartPoint: CGPoint?
    @State private var showReplacementLogoPicker = false
    @State private var replacementLogoURL: URL?
    @Environment(\.dismiss) private var dismiss
    
    init(videoURL: URL) {
        _viewModel = StateObject(wrappedValue: LogoAnnotationViewModel(videoURL: videoURL))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 视频预览区域
            videoPreviewArea
            
            Divider()
            
            // 控制栏
            controlBar
            
            Divider()
            
            // 标注列表和操作
            annotationList
        }
        .frame(minWidth: 1000, minHeight: 700)
        .navigationTitle("Logo 标注")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("开始跟踪") {
                    startTracking()
                }
                .disabled(viewModel.annotations.isEmpty || replacementLogoURL == nil || isTracking)
            }
        }
        .fileImporter(
            isPresented: $showReplacementLogoPicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                replacementLogoURL = url
            }
        }
        .overlay {
            if isTracking {
                VStack {
                    ProgressView(value: trackingProgress)
                    Text(trackingStatus)
                        .font(.caption)
                        .padding()
                }
                .frame(maxWidth: 400)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .shadow(radius: 10)
            }
        }
        .alert("跟踪完成", isPresented: $showTrackingComplete) {
            Button("应用替换") {
                applyLogoReplacement()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已跟踪 \(trackingResults.count) 帧，是否应用 Logo 替换？")
        }
    }
    
    private var videoPreviewArea: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = viewModel.currentFrameImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView("加载视频...")
                }
                
                // 标注框
                ForEach(viewModel.annotations) { annotation in
                    if annotation.frameNumber == viewModel.currentFrameNumber {
                        Rectangle()
                            .stroke(Color.blue, lineWidth: 2)
                            .frame(
                                width: annotation.boundingBox.width,
                                height: annotation.boundingBox.height
                            )
                            .position(
                                x: annotation.boundingBox.midX,
                                y: annotation.boundingBox.midY
                            )
                    }
                }
                
                // 选择区域
                if viewModel.isSelectingRegion && !viewModel.selectionRect.isEmpty {
                    Rectangle()
                        .stroke(Color.green, lineWidth: 2)
                        .background(Color.green.opacity(0.2))
                        .frame(
                            width: viewModel.selectionRect.width,
                            height: viewModel.selectionRect.height
                        )
                        .position(
                            x: viewModel.selectionRect.midX,
                            y: viewModel.selectionRect.midY
                        )
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartPoint == nil {
                            dragStartPoint = value.startLocation
                            viewModel.startSelection(at: value.startLocation, in: geometry.size)
                        } else {
                            viewModel.updateSelection(to: value.location, in: geometry.size)
                        }
                    }
                    .onEnded { value in
                        if let start = dragStartPoint {
                            let rect = CGRect(
                                x: min(start.x, value.location.x),
                                y: min(start.y, value.location.y),
                                width: abs(value.location.x - start.x),
                                height: abs(value.location.y - start.y)
                            )
                            
                            if rect.width > 10 && rect.height > 10 {
                                viewModel.addAnnotation(boundingBox: rect)
                            }
                            
                            dragStartPoint = nil
                            viewModel.endSelection()
                        }
                    }
            )
        }
    }
    
    private var controlBar: some View {
        HStack(spacing: 16) {
            // 帧导航
            Button(action: { viewModel.previousFrame() }) {
                Image(systemName: "backward.frame.fill")
            }
            .buttonStyle(.bordered)
            
            Text("帧 \(viewModel.currentFrameNumber) / \(viewModel.totalFrames)")
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 120)
            
            Button(action: { viewModel.nextFrame() }) {
                Image(systemName: "forward.frame.fill")
            }
            .buttonStyle(.bordered)
            
            Divider()
                .frame(height: 20)
            
            // 时间显示
            Text(formatTime(viewModel.currentTimestamp))
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 100)
            
            Spacer()
            
            // 标注操作
            Button(action: {
                // 清除当前选择
                viewModel.endSelection()
            }) {
                Label("清除选择", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.isSelectingRegion)
        }
        .padding()
    }
    
    private var annotationList: some View {
        HStack(alignment: .top, spacing: 0) {
            // 标注列表
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("已标注关键帧 (\(viewModel.annotations.count))")
                        .font(.headline)
                        .padding()
                    Spacer()
                }
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.annotations) { annotation in
                            AnnotationRow(
                                annotation: annotation,
                                isSelected: viewModel.selectedAnnotation?.id == annotation.id,
                                onSelect: {
                                    viewModel.selectAnnotation(annotation)
                                },
                                onDelete: {
                                    viewModel.deleteAnnotation(annotation)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            .frame(width: 300)
            
            Divider()
            
            // 替换 Logo 选择
            VStack(alignment: .leading, spacing: 16) {
                Text("替换 Logo")
                    .font(.headline)
                    .padding()
                
                VStack(alignment: .leading, spacing: 12) {
                    if let logoURL = replacementLogoURL {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(logoURL.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Button("更改") {
                                showReplacementLogoPicker = true
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        Button(action: {
                            showReplacementLogoPicker = true
                        }) {
                            Label("选择替换 Logo", systemImage: "photo")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Text("选择一个图片文件作为替换 Logo，将覆盖原视频中的 Logo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                
                Spacer()
            }
            .frame(width: 300)
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
    
    @State private var isTracking = false
    @State private var trackingProgress: Double = 0.0
    @State private var trackingStatus: String = ""
    @State private var trackingResults: [LogoTrackingResult] = []
    @State private var showTrackingComplete = false
    
    private func startTracking() {
        guard let replacementLogoURL = replacementLogoURL,
              let videoURL = viewModel.videoURL else { return }
        
        let config = LogoTrackingConfig(
            annotations: viewModel.annotations,
            replacementLogoURL: replacementLogoURL
        )
        
        isTracking = true
        trackingProgress = 0.0
        trackingStatus = "开始跟踪..."
        
        Task {
            do {
                let results = try await LogoTrackingEngine.track(
                    videoURL: videoURL,
                    config: config,
                    progressHandler: { progress, status in
                        Task { @MainActor in
                            trackingProgress = progress
                            trackingStatus = status
                        }
                    }
                )
                
                await MainActor.run {
                    trackingResults = results
                    isTracking = false
                    showTrackingComplete = true
                }
            } catch {
                await MainActor.run {
                    isTracking = false
                    trackingStatus = "跟踪失败: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func applyLogoReplacement() {
        guard let videoURL = viewModel.videoURL,
              let replacementLogoURL = replacementLogoURL else { return }
        
        // 选择输出文件
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        savePanel.nameFieldStringValue = videoURL.deletingPathExtension().lastPathComponent + "_logo_replaced"
        
        if savePanel.runModal() == .OK, let outputURL = savePanel.url {
            isTracking = true
            trackingProgress = 0.0
            trackingStatus = "正在应用 Logo 替换..."
            
            Task {
                do {
                    try await VideoBlur.replaceTrackedLogo(
                        inputURL: videoURL,
                        outputURL: outputURL,
                        trackingResults: trackingResults,
                        replacementLogoURL: replacementLogoURL
                    ) { progress, status in
                        Task { @MainActor in
                            trackingProgress = progress
                            trackingStatus = status
                        }
                    }
                    
                    await MainActor.run {
                        trackingStatus = "Logo 替换完成！"
                        isTracking = false
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        trackingStatus = "替换失败: \(error.localizedDescription)"
                        isTracking = false
                    }
                }
            }
        }
    }
}

struct AnnotationRow: View {
    let annotation: LogoAnnotation
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("帧 \(annotation.frameNumber)")
                    .font(.body)
                Text(formatTime(annotation.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: onSelect) {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(8)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onTapGesture {
            onSelect()
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    LogoAnnotationView(videoURL: URL(fileURLWithPath: "/tmp/test.mp4"))
}
