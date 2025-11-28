//
//  MeetingSoftwareDetector.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import AppKit
import Combine

/// 会议软件信息
struct MeetingSoftware {
    let name: String
    let bundleId: String
    let displayName: String
}

/// 会议软件检测器
@MainActor
class MeetingSoftwareDetector: ObservableObject {
    static let shared = MeetingSoftwareDetector()
    
    @Published var detectedMeeting: MeetingSoftware?
    @Published var isMeetingActive = false
    
    // 支持的会议软件列表
    private let meetingSoftwares: [MeetingSoftware] = [
        MeetingSoftware(name: "腾讯会议", bundleId: "com.tencent.meeting", displayName: "腾讯会议"),
        MeetingSoftware(name: "Zoom", bundleId: "us.zoom.xos", displayName: "Zoom"),
        MeetingSoftware(name: "Microsoft Teams", bundleId: "com.microsoft.teams", displayName: "Microsoft Teams"),
        MeetingSoftware(name: "钉钉", bundleId: "com.alibaba.DingTalk", displayName: "钉钉"),
        MeetingSoftware(name: "飞书", bundleId: "com.bytedance.ee.lark", displayName: "飞书"),
        MeetingSoftware(name: "Google Meet", bundleId: "com.google.Chrome", displayName: "Google Meet"), // Chrome 中运行
        MeetingSoftware(name: "Webex", bundleId: "com.cisco.webexmeetingsapp", displayName: "Webex"),
        MeetingSoftware(name: "Skype", bundleId: "com.skype.skype", displayName: "Skype"),
    ]
    
    private var detectionTimer: Timer?
    private var lastDetectedApp: NSRunningApplication?
    private var onMeetingDetected: ((MeetingSoftware) -> Void)?
    
    private init() {
        startMonitoring()
    }
    
    /// 开始监控会议软件
    func startMonitoring() {
        stopMonitoring()
        
        print("🔍 [MeetingSoftwareDetector] 开始监控会议软件...")
        
        // 每 3 秒检测一次
        detectionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForMeetingSoftware()
            }
        }
        
        // 立即检测一次
        checkForMeetingSoftware()
    }
    
    /// 停止监控
    func stopMonitoring() {
        detectionTimer?.invalidate()
        detectionTimer = nil
    }
    
    /// 设置会议检测回调
    func setOnMeetingDetected(_ callback: @escaping (MeetingSoftware) -> Void) {
        self.onMeetingDetected = callback
    }
    
    /// 检测会议软件
    private func checkForMeetingSoftware() {
        let runningApps = NSWorkspace.shared.runningApplications
        
        // 检查是否有会议软件在运行
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }
            
            // 检查是否是已知的会议软件
            if let meeting = meetingSoftwares.first(where: { $0.bundleId == bundleId }) {
                // 检查是否是新的检测（避免重复提示）
                if lastDetectedApp?.bundleIdentifier != bundleId {
                    print("✅ [MeetingSoftwareDetector] 检测到会议软件: \(meeting.displayName)")
                    
                    detectedMeeting = meeting
                    isMeetingActive = true
                    lastDetectedApp = app
                    
                    // 触发回调
                    onMeetingDetected?(meeting)
                }
                return
            }
        }
        
        // 如果没有检测到会议软件，清除状态
        if isMeetingActive {
            print("ℹ️ [MeetingSoftwareDetector] 会议软件已退出")
            detectedMeeting = nil
            isMeetingActive = false
            lastDetectedApp = nil
        }
    }
    
    /// 检查特定应用是否在运行
    func isAppRunning(bundleId: String) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == bundleId }
    }
}

