//
//  StatusBarManager.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import AppKit
import SwiftUI
import Combine

class StatusBarManager: NSObject, ObservableObject {
    static let shared = StatusBarManager()
    
    private var statusItem: NSStatusItem?
    private var statusBarButton: NSStatusBarButton?
    
    override init() {
        super.init()
        setupStatusBar()
    }
    
    private func setupStatusBar() {
        // 创建状态栏项
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let statusItem = statusItem else { return }
        
        // 设置图标
        if let button = statusItem.button {
            statusBarButton = button
            // 使用闪电图标，表示快速打字输入
            let appName = NSLocalizedString("app.name", comment: "")
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: appName)
            button.image?.isTemplate = true // 让图标适配深色/浅色模式
            button.toolTip = appName
        }
        
        // 创建菜单（设置菜单后，点击图标会自动显示菜单）
        updateMenu()
    }
    
    private func updateMenu() {
        guard let statusItem = statusItem else { return }
        
        let menu = NSMenu()
        
        // 显示主界面
        let appName = NSLocalizedString("app.name", comment: "")
        let showMenuItem = NSMenuItem(
            title: String(format: NSLocalizedString("show.app", value: "显示 %@", comment: ""), appName),
            action: #selector(showMainWindow(_:)),
            keyEquivalent: ""
        )
        showMenuItem.target = self
        menu.addItem(showMenuItem)
        
        // 分隔线
        menu.addItem(NSMenuItem.separator())
        
        // 退出
        let quitMenuItem = NSMenuItem(
            title: "退出",
            action: #selector(quitApplication(_:)),
            keyEquivalent: "q"
        )
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)
        
        statusItem.menu = menu
    }
    
    @objc private func showMainWindow(_ sender: NSMenuItem) {
        // 显示主窗口
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            // 如果没有窗口，创建一个新窗口
            // 这通常不会发生，因为 WindowGroup 会自动创建窗口
            NSApplication.shared.windows.forEach { window in
                window.makeKeyAndOrderFront(nil)
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    
    @objc private func quitApplication(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
    
    func show() {
        // 确保状态栏项可见
        statusItem?.isVisible = true
    }
    
    func hide() {
        // 隐藏状态栏项（通常不需要）
        statusItem?.isVisible = false
    }
    
    func cleanup() {
        // 清理资源
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        statusBarButton = nil
    }
}

