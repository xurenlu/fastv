//
//  MeetingDetectionAlertView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI
import AppKit

/// 会议检测提示视图
struct MeetingDetectionAlertView: View {
    let meeting: MeetingSoftware
    let onStartRecording: (Bool) -> Void  // 参数：是否捕获系统音频
    let onDismiss: () -> Void
    @State private var captureSystemAudio = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // 图标和标题
            VStack(spacing: 12) {
                Image(systemName: "video.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text("检测到会议")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("检测到 \(meeting.displayName) 正在运行")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            
            // 选项
            VStack(alignment: .leading, spacing: 12) {
                Toggle("开始会议记录", isOn: .constant(true))
                    .disabled(true)
                
                Toggle("同时捕获系统音频（对方的声音）", isOn: $captureSystemAudio)
                    .help("需要安装 BlackHole 虚拟音频设备才能捕获系统音频")
                
                if captureSystemAudio && !SystemAudioCaptureService.shared.isBlackHoleAvailable {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("未检测到 BlackHole，请先安装")
                            .font(.caption)
                            .foregroundColor(.orange)
                        
                        Button("查看安装指南") {
                            NSWorkspace.shared.open(SystemAudioCaptureService.shared.getBlackHoleInstallGuideURL())
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    .padding(.leading, 24)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            
            // 按钮
            HStack(spacing: 12) {
                Button("取消") {
                    onDismiss()
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("开始记录") {
                    onStartRecording(captureSystemAudio)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding(.bottom, 20)
        }
        .frame(width: 400, height: 300)
        .padding()
    }
}

/// 会议检测窗口管理器
/// 用于在检测到会议时显示提示窗口
@MainActor
class MeetingDetectionWindowManager {
    static let shared = MeetingDetectionWindowManager()
    
    private var alertWindow: NSWindow?
    
    private init() {}
    
    /// 显示会议检测提示窗口
    func showAlert(
        meeting: MeetingSoftware,
        onStartRecording: @escaping (Bool) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        // 如果已有窗口，先关闭
        closeAlert()
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "检测到会议"
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        
        let hostingView = NSHostingView(
            rootView: MeetingDetectionAlertView(
                meeting: meeting,
                onStartRecording: { captureSystemAudio in
                    onStartRecording(captureSystemAudio)
                    self.closeAlert()
                },
                onDismiss: {
                    onDismiss()
                    self.closeAlert()
                }
            )
        )
        
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        self.alertWindow = window
    }
    
    /// 关闭提示窗口
    func closeAlert() {
        alertWindow?.close()
        alertWindow = nil
    }
}

