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
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    MeetingRecordingSettingsTab()
}

