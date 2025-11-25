//
//  MeetingRecordFloatingBar.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI
import AppKit
import Combine

/// 会议记录悬浮工具条
class MeetingRecordFloatingBar: ObservableObject {
    static let shared = MeetingRecordFloatingBar()
    
    @Published var isVisible = false
    @Published var meetingAppName: String = ""
    
    private var window: NSWindow?
    private var hostingView: NSHostingView<MeetingRecordFloatingBarView>?
    private var onStartRecording: (() -> Void)?
    private var onDismiss: (() -> Void)?
    
    private init() {}
    
    /// 显示悬浮工具条
    func show(meetingAppName: String, onStart: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        guard !isVisible else { return }
        
        self.meetingAppName = meetingAppName
        self.onStartRecording = onStart
        self.onDismiss = onDismiss
        
        let contentView = MeetingRecordFloatingBarView(
            meetingAppName: meetingAppName,
            onStart: { [weak self] in
                self?.hide()
                self?.onStartRecording?()
            },
            onDismiss: { [weak self] in
                self?.hide()
                self?.onDismiss?()
            }
        )
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        
        let window = NSWindow(
            contentRect: calculateWindowFrame(),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        
        self.window = window
        self.hostingView = hostingView
        self.isVisible = true
        
        window.makeKeyAndOrderFront(nil)
        print("📱 [MeetingRecordFloatingBar] 显示悬浮工具条: \(meetingAppName)")
    }
    
    /// 隐藏悬浮工具条
    func hide() {
        guard isVisible else { return }
        
        window?.close()
        window = nil
        hostingView = nil
        isVisible = false
        
        print("📱 [MeetingRecordFloatingBar] 隐藏悬浮工具条")
    }
    
    /// 计算窗口位置（屏幕右上角）
    private func calculateWindowFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 100, y: 100, width: 320, height: 120)
        }
        
        let screenFrame = screen.visibleFrame
        let windowWidth: CGFloat = 320
        let windowHeight: CGFloat = 120
        let margin: CGFloat = 20
        
        let x = screenFrame.maxX - windowWidth - margin
        let y = screenFrame.maxY - windowHeight - margin
        
        return NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
    }
}

/// 会议记录悬浮工具条视图
struct MeetingRecordFloatingBarView: View {
    let meetingAppName: String
    let onStart: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "video.fill")
                    .foregroundStyle(.blue)
                Text("检测到 \(meetingAppName)")
                    .font(.headline)
                Spacer()
            }
            
            Text("是否开始记录会议？")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                Button("取消", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                
                Button("开始记录", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        }
    }
}

