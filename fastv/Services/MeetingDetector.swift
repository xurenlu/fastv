//
//  MeetingDetector.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import AppKit
import Combine

/// 会议软件检测服务
@MainActor
class MeetingDetector: ObservableObject {
    static let shared = MeetingDetector()
    
    @Published var detectedMeetingApp: MeetingApp?
    @Published var isDetecting = false
    
    private var detectionTimer: Timer?
    private let detectionInterval: TimeInterval = 5.0 // 每5秒检测一次
    
    /// 支持的会议应用
    enum MeetingApp: String, CaseIterable {
        case tencentMeeting = "com.tencent.meeting"
        case feishu = "com.bytedance.feishu"
        case zoom = "us.zoom.xos"
        case microsoftTeams = "com.microsoft.teams"
        case webex = "com.cisco.webexmeetingsapp"
        case skype = "com.skype.skype"
        
        var displayName: String {
            switch self {
            case .tencentMeeting:
                return "腾讯会议"
            case .feishu:
                return "飞书会议"
            case .zoom:
                return "Zoom"
            case .microsoftTeams:
                return "Microsoft Teams"
            case .webex:
                return "Webex"
            case .skype:
                return "Skype"
            }
        }
        
        var bundleId: String {
            return self.rawValue
        }
    }
    
    private init() {
        startDetection()
    }
    
    // 注意：由于是单例，deinit实际上不会被调用
    // 如果需要停止检测，可以调用stopDetection()方法
    
    /// 开始检测
    func startDetection() {
        guard !isDetecting else { return }
        
        isDetecting = true
        print("🔍 [MeetingDetector] 开始检测会议软件")
        
        // 立即检测一次
        detectMeetingApps()
        
        // 启动定时器
        detectionTimer = Timer.scheduledTimer(withTimeInterval: detectionInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.detectMeetingApps()
            }
        }
    }
    
    /// 停止检测
    func stopDetection() {
        isDetecting = false
        detectionTimer?.invalidate()
        detectionTimer = nil
        print("🛑 [MeetingDetector] 停止检测会议软件")
    }
    
    /// 检测会议应用
    private func detectMeetingApps() {
        let runningApps = NSWorkspace.shared.runningApplications
        
        // 检查是否有会议应用在运行
        for meetingApp in MeetingApp.allCases {
            if let app = runningApps.first(where: { $0.bundleIdentifier == meetingApp.bundleId }) {
                // 检查应用是否激活（在前台）
                if app.isActive || app.isHidden == false {
                    if detectedMeetingApp != meetingApp {
                        print("✅ [MeetingDetector] 检测到会议软件: \(meetingApp.displayName)")
                        detectedMeetingApp = meetingApp
                        
                        // 显示悬浮工具条
                        let floatingBar = MeetingRecordFloatingBar.shared
                        if !floatingBar.isVisible {
                            floatingBar.show(
                                meetingAppName: meetingApp.displayName,
                                onStart: {
                                    // 开始会议记录
                                    MeetingRecordService.shared.startRecording(meetingAppName: meetingApp.displayName)
                                },
                                onDismiss: {
                                    // 用户取消，不做任何操作
                                }
                            )
                        }
                        
                        // 发送通知
                        NotificationCenter.default.post(
                            name: .meetingAppDetected,
                            object: nil,
                            userInfo: ["app": meetingApp]
                        )
                    }
                    return
                }
            }
        }
        
        // 没有检测到会议应用
        if detectedMeetingApp != nil {
            print("ℹ️ [MeetingDetector] 会议软件已退出")
            
            // 如果正在录音，停止录音
            let recordService = MeetingRecordService.shared
            if recordService.isRecording {
                Task {
                    if let record = await recordService.stopRecording() {
                        // 保存记录
                        MeetingRecordStorage.shared.add(record)
                        
                        // 如果启用AI优化，生成总结
                        if UserPreferences.shared.enableAIOptimization {
                            await generateSummary(for: record)
                        }
                    }
                }
            }
            
            // 隐藏悬浮工具条
            MeetingRecordFloatingBar.shared.hide()
            
            detectedMeetingApp = nil
            // 发送通知
            NotificationCenter.default.post(
                name: .meetingAppExited,
                object: nil
            )
        }
    }
    
    /// 生成会议总结
    private func generateSummary(for record: MeetingRecord) async {
        guard !record.segments.isEmpty else { return }
        
        do {
            let summary = try await OllamaService.shared.summarizeMeeting(
                text: record.text,
                endpoint: UserPreferences.shared.aiAPIEndpoint,
                model: UserPreferences.shared.aiModel,
                apiToken: UserPreferences.shared.aiAPIToken.isEmpty ? nil : UserPreferences.shared.aiAPIToken,
                timeout: UserPreferences.shared.aiTimeout
            )
            
            var updatedRecord = record
            updatedRecord = MeetingRecord(
                id: record.id,
                app: record.app,
                segments: record.segments,
                summary: summary,
                createdAt: record.createdAt
            )
            MeetingRecordStorage.shared.update(updatedRecord)
        } catch {
            print("⚠️ [MeetingDetector] AI总结失败: \(error)")
        }
    }
    
    /// 手动检测一次
    func detectOnce() {
        detectMeetingApps()
    }
    
    /// 检查指定应用是否在运行
    func isAppRunning(_ app: MeetingApp) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == app.bundleId }
    }
}

extension Notification.Name {
    static let meetingAppDetected = Notification.Name("meetingAppDetected")
    static let meetingAppExited = Notification.Name("meetingAppExited")
}

