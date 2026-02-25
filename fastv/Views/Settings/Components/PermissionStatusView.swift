//
//  PermissionStatusView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import AVFoundation
import AppKit

/// 权限状态视图
struct PermissionStatusView: View {
    @State private var microphoneStatus: AVAuthorizationStatus = .notDetermined
    @State private var accessibilityStatus: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 麦克风权限状态
            HStack(spacing: 8) {
                Image(systemName: microphoneStatus == .authorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(microphoneStatus == .authorized ? .green : .red)
                
                Text("麦克风权限")
                    .font(.system(size: 12))
                
                Spacer()
                
                Text(statusText(for: microphoneStatus))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                if microphoneStatus != .authorized {
                    HStack(spacing: 8) {
                        Button("申请权限") {
                            requestMicrophonePermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .font(.system(size: 11))
                        
                        Button("打开设置") {
                            openSystemSettings(for: .microphone)
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                    }
                }
            }
            
            // 辅助功能权限状态
            HStack(spacing: 8) {
                Image(systemName: accessibilityStatus ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(accessibilityStatus ? .green : .red)
                
                Text("辅助功能权限")
                    .font(.system(size: 12))
                
                Spacer()
                
                Text(accessibilityStatus ? "已授权" : "未授权")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                if !accessibilityStatus {
                    Button("打开设置") {
                        openSystemSettings(for: .accessibility)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        // 检查麦克风权限
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        // 检查辅助功能权限
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        accessibilityStatus = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    private func requestMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .notDetermined:
            // 请求权限
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.checkPermissions()
                }
            }
        case .denied, .restricted:
            // 权限被拒绝，打开系统设置
            openSystemSettings(for: .microphone)
        case .authorized:
            // 已授权，无需操作
            break
        @unknown default:
            break
        }
    }
    
    private func statusText(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "已授权"
        case .notDetermined:
            return "未请求"
        case .denied:
            return "已拒绝"
        case .restricted:
            return "受限"
        @unknown default:
            return "未知"
        }
    }
    
    private func openSystemSettings(for permission: PermissionType) {
        switch permission {
        case .microphone:
            // 打开系统设置中的麦克风权限页面
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        case .accessibility:
            // 打开系统设置中的辅助功能权限页面
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    enum PermissionType {
        case microphone
        case accessibility
    }
}

