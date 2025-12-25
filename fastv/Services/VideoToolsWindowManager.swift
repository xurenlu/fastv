//
//  VideoToolsWindowManager.swift
//  fastv
//
//  Created by rocky on 2025/12/25.
//

import SwiftUI
import AppKit

/// 视频工具窗口管理器
@MainActor
class VideoToolsWindowManager {
    static let shared = VideoToolsWindowManager()
    
    private var window: NSWindow?
    private var hostingView: NSHostingView<VideoToolsMainView>?
    
    private init() {}
    
    /// 显示视频工具窗口
    func show() {
        print("🎬 [VideoToolsWindowManager] show() 被调用")
        
        // 如果窗口已存在，激活它而不是创建新窗口
        if let existingWindow = window {
            print("ℹ️ [VideoToolsWindowManager] 窗口已存在，激活窗口")
            existingWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        
        print("🎬 [VideoToolsWindowManager] 创建视频工具窗口...")
        
        let contentView = VideoToolsMainView()
        let hostingView = NSHostingView(rootView: contentView)
        
        // 设置窗口大小
        let windowWidth: CGFloat = 1200
        let windowHeight: CGFloat = 800
        hostingView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
        
        // 计算窗口位置（居中）
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowX = (screenFrame.width - windowWidth) / 2
        let windowY = (screenFrame.height - windowHeight) / 2
        let windowFrame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        
        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = hostingView
        window.title = "视频工具"
        window.minSize = NSSize(width: 1000, height: 600)
        window.isReleasedWhenClosed = false // 防止窗口被自动释放
        
        // 设置窗口委托，监听窗口关闭事件
        let delegate = VideoToolsWindowDelegate(manager: self)
        window.delegate = delegate
        
        self.window = window
        self.hostingView = hostingView
        
        print("🎬 [VideoToolsWindowManager] 显示窗口...")
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        print("✅ [VideoToolsWindowManager] 视频工具窗口已显示")
    }
    
    /// 关闭视频工具窗口
    func close() {
        print("🎬 [VideoToolsWindowManager] close() 被调用")
        window?.close()
        cleanup()
    }
    
    /// 清理窗口资源
    func cleanup() {
        print("🧹 [VideoToolsWindowManager] cleanup() 被调用")
        window?.contentView = nil
        window = nil
        hostingView = nil
    }
}

/// 视频工具窗口委托
private class VideoToolsWindowDelegate: NSObject, NSWindowDelegate {
    weak var manager: VideoToolsWindowManager?
    
    init(manager: VideoToolsWindowManager) {
        self.manager = manager
    }
    
    func windowWillClose(_ notification: Notification) {
        print("🎬 [VideoToolsWindowDelegate] 窗口即将关闭")
        manager?.cleanup()
    }
}

