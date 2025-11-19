//
//  WelcomeView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ffmpegAvailable = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题区域
            VStack(spacing: 16) {
                Image(systemName: "video.badge.waveform")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: ffmpegAvailable)
                
                VStack(spacing: 6) {
                    Text("欢迎使用 FastV")
                        .font(.system(size: 28, weight: .bold))
                    
                    Text("快速提取视频帧、音频和文本")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 50)
            .padding(.bottom, 30)
            .background {
                Rectangle()
                    .fill(.regularMaterial)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 功能介绍
                    FeatureSection(
                        icon: "photo.on.rectangle",
                        title: "提取视频帧",
                        description: "快速提取视频的第一帧和最后一帧，支持 PNG、JPEG 格式"
                    )
                    
                    FeatureSection(
                        icon: "music.note",
                        title: "提取音频",
                        description: "从视频中提取音频，支持 M4A、MP3、WAV 格式"
                    )
                    
                    FeatureSection(
                        icon: "text.bubble",
                        title: "语音转文字",
                        description: "使用 AI 模型将视频中的语音转换为文字稿"
                    )
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // FFmpeg 说明
                    FFmpegInfoSection(ffmpegAvailable: $ffmpegAvailable)
                }
                .padding(30)
            }
            
            // 底部按钮
            HStack(spacing: 12) {
                if !ffmpegAvailable {
                    Button(action: {
                        if let url = URL(string: "https://brew.sh") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Label("安装 Homebrew", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                Button(action: {
                    UserPreferences.shared.markWelcomeAsShown()
                    dismiss()
                }) {
                    Text("开始使用")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(20)
            .background {
                Rectangle()
                    .fill(.regularMaterial)
            }
        }
        .background(.background)
        .onAppear {
            checkFFmpeg()
        }
    }
    
    private func checkFFmpeg() {
        Task {
            ffmpegAvailable = FFmpegHelper.isAvailable()
        }
    }
}

// MARK: - 功能说明卡片
struct FeatureSection: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - FFmpeg 信息说明
struct FFmpegInfoSection: View {
    @Binding var ffmpegAvailable: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: ffmpegAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ffmpegAvailable ? .green : .orange)
                
                Text("MP3 格式支持")
                    .font(.headline)
            }
            
            if ffmpegAvailable {
                Text("检测到已安装 FFmpeg，可以导出真正的 MP3 格式音频文件。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("要导出 MP3 格式音频，需要先安装 FFmpeg。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("安装步骤：")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            InstallationStep(number: "1", text: "安装 Homebrew（如果尚未安装）")
                            InstallationStep(number: "2", text: "在终端运行：", code: "brew install ffmpeg")
                        }
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.quaternary.opacity(0.5))
                    }
                    
                    Text("安装完成后，重新启动应用即可使用 MP3 格式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ffmpegAvailable ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(ffmpegAvailable ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                }
        }
    }
}

// MARK: - 安装步骤
struct InstallationStep: View {
    let number: String
    let text: String
    var code: String? = nil
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background {
                    Circle()
                        .fill(.tint)
                }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.body)
                
                if let code = code {
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.quaternary)
                        }
                }
            }
        }
    }
}

#Preview {
    WelcomeView()
}

