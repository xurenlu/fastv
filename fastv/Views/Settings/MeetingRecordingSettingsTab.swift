//
//  MeetingRecordingSettingsTab.swift
//  fastv
//
//  Created by rocky on 2025/11/29.
//

import SwiftUI

/// Tab 3: 会议与录音
/// 包含：会议记录相关设置、自动录音、静音检测等
struct MeetingRecordingSettingsTab: View {
    @ObservedObject var preferences = UserPreferences.shared
    @State private var serviceURL: String = ""
    @State private var isTestingConnection = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var errorMessage: String?
    
    enum ConnectionStatus {
        case unknown
        case connecting
        case connected
        case failed(String)
    }
    
    var body: some View {
        Form {
            Section {
                Toggle("检测到会议时自动开始录音", isOn: $preferences.enableAutoStartRecording)
                
                if preferences.enableAutoStartRecording {
                    Toggle("自动开始同时捕获系统音频", isOn: $preferences.autoStartCaptureSystemAudio)
                        .padding(.leading, 20)
                }
                
                Divider()
                
                // 静音检测配置
                VStack(alignment: .leading, spacing: 12) {
                    Text("静音检测设置")
                        .font(.headline)
                    
                    // 静音检测时长
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("静音检测时长")
                            Spacer()
                            Text("\(String(format: "%.1f", preferences.silenceDetectionDuration)) 秒")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $preferences.silenceDetectionDuration, in: 1.0...3.0, step: 0.1)
                    }
                    
                    // 绝对阈值
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("绝对阈值")
                            Spacer()
                            Text("\(String(format: "%.3f", preferences.silenceThreshold))")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $preferences.silenceThreshold, in: 0.005...0.05, step: 0.001)
                    }
                    
                    // 相对阈值
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("相对阈值")
                            Spacer()
                            Text("\(Int(preferences.silenceRelativeThreshold * 100))%")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $preferences.silenceRelativeThreshold, in: 0.2...0.5, step: 0.05)
                    }
                }
                .padding(.vertical, 4)
                
                Divider()
                
                // 说话人分离配置
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("启用说话人分离", isOn: $preferences.enableSpeakerDiarization)
                        .font(.headline)
                    
                    if preferences.enableSpeakerDiarization {
                        // 服务地址配置
                        VStack(alignment: .leading, spacing: 12) {
                            Text("服务地址配置")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 8) {
                                TextField("http://127.0.0.1:50001", text: $serviceURL)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: serviceURL) { _, newValue in
                                        preferences.diarizationServiceURL = newValue
                                        connectionStatus = .unknown
                                        errorMessage = nil
                                    }
                                
                                Button(action: {
                                    testConnection()
                                }) {
                                    if isTestingConnection {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Label("测试", systemImage: "network")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isTestingConnection || serviceURL.isEmpty)
                            }
                            
                            // 连接状态
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(connectionStatusColor)
                                    .frame(width: 8, height: 8)
                                
                                Text(connectionStatusText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                            }
                            
                            // 错误信息
                            if let error = errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            
                            // 提示信息
                            Text("请确保说话人分离服务已启动并可通过上述地址访问。服务部署说明请查看 SpeakerDiarization/README.md")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.05))
                        }
                        .onAppear {
                            serviceURL = preferences.diarizationServiceURL
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            // 最小说话人数量
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("最小说话人数量")
                                    Spacer()
                                    if let minSpeakers = preferences.diarizationMinSpeakers {
                                        Text("\(minSpeakers) 人")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    } else {
                                        Text("自动检测")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                HStack(spacing: 8) {
                                    Slider(
                                        value: Binding(
                                            get: { Double(preferences.diarizationMinSpeakers ?? 1) },
                                            set: { preferences.diarizationMinSpeakers = Int($0) >= 1 ? Int($0) : nil }
                                        ),
                                        in: 1...10,
                                        step: 1
                                    )
                                    
                                    Button(action: {
                                        preferences.diarizationMinSpeakers = nil
                                    }) {
                                        Text("清除")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(preferences.diarizationMinSpeakers == nil)
                                }
                            }
                            
                            // 最大说话人数量
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("最大说话人数量")
                                    Spacer()
                                    if let maxSpeakers = preferences.diarizationMaxSpeakers {
                                        Text("\(maxSpeakers) 人")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    } else {
                                        Text("自动检测")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                HStack(spacing: 8) {
                                    Slider(
                                        value: Binding(
                                            get: { Double(preferences.diarizationMaxSpeakers ?? 2) },
                                            set: { preferences.diarizationMaxSpeakers = Int($0) >= 1 ? Int($0) : nil }
                                        ),
                                        in: 1...20,
                                        step: 1
                                    )
                                    
                                    Button(action: {
                                        preferences.diarizationMaxSpeakers = nil
                                    }) {
                                        Text("清除")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(preferences.diarizationMaxSpeakers == nil)
                                }
                            }
                        }
                        .padding(.leading, 20)
                        .padding(.top, 8)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("会议记录")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if preferences.enableAutoStartRecording {
                        Text("启用后，检测到会议软件时会自动开始录音，无需手动确认。")
                        if preferences.autoStartCaptureSystemAudio {
                            Text("系统音频捕获需要安装 BlackHole 虚拟音频设备。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text("静音检测：当说话人停顿达到设定时长且录音>=3秒时，自动转写前一段音频。混合检测算法结合绝对阈值和相对下降检测，能更好地适应环境噪音。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    
                    if preferences.enableSpeakerDiarization {
                        Text("说话人分离：自动识别和区分不同的说话人。如果知道会议的人数范围，可以设置最小/最大说话人数量以提高准确性。不设置时，模型会自动检测说话人数量。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Computed Properties
    
    private var connectionStatusColor: Color {
        switch connectionStatus {
        case .unknown:
            return .gray
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .failed:
            return .red
        }
    }
    
    private var connectionStatusText: String {
        switch connectionStatus {
        case .unknown:
            return "未测试"
        case .connecting:
            return "测试中..."
        case .connected:
            return "连接成功"
        case .failed(let message):
            return "连接失败: \(message)"
        }
    }
    
    // MARK: - Methods
    
    private func testConnection() {
        isTestingConnection = true
        connectionStatus = .connecting
        errorMessage = nil
        
        Task {
            do {
                let isConnected = try await SpeakerDiarizationService.shared.testConnection()
                await MainActor.run {
                    isTestingConnection = false
                    if isConnected {
                        connectionStatus = .connected
                        errorMessage = nil
                    } else {
                        connectionStatus = .failed("服务未就绪")
                        errorMessage = "服务正在运行但模型可能未加载"
                    }
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    let errorMsg = error.localizedDescription
                    connectionStatus = .failed(errorMsg)
                    errorMessage = errorMsg
                }
            }
        }
    }
}

#Preview {
    MeetingRecordingSettingsTab()
}

