//
//  SleepWakeNotifier.swift
//  fastv
//
//  Created by rocky on 2025/11/28.
//

import Foundation
import Combine
import IOKit
import IOKit.pwr_mgt

/// 系统睡眠/唤醒通知服务
class SleepWakeNotifier: ObservableObject {
    static let shared = SleepWakeNotifier()
    
    @Published private(set) var isSystemAwake = true
    
    // 睡眠/唤醒回调
    var onSystemWillSleep: (@MainActor () -> Void)?
    var onSystemDidWake: (@MainActor () -> Void)?
    
    // 保活断言(防止系统睡眠)
    private var preventSleepAssertion: IOPMAssertionID = 0
    private var isPreventingSleep = false
    private let preventSleepLock = NSLock()
    
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    
    private init() {
        setupSleepWakeNotifications()
    }
    
    deinit {
        cleanupNotifications()
        preventSleepLock.lock()
        let shouldDisable = isPreventingSleep
        preventSleepLock.unlock()
        if shouldDisable {
            _ = IOPMAssertionRelease(preventSleepAssertion)
        }
    }
    
    /// 设置睡眠/唤醒通知监听
    private func setupSleepWakeNotifications() {
        // 创建通知端口
        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notificationPort else {
            print("❌ [SleepWakeNotifier] 无法创建通知端口")
            return
        }
        
        // 将通知端口添加到运行循环
        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // 注册睡眠/唤醒通知
        let root_port = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(),
            &notificationPort,
            { (refCon, service, messageType, messageArgument) in
                guard let refCon = refCon else { return }
                let notifier = Unmanaged<SleepWakeNotifier>.fromOpaque(refCon).takeUnretainedValue()
                
                Task { @MainActor in
                    notifier.handlePowerNotification(
                        messageType: messageType,
                        messageArgument: messageArgument,
                        service: service
                    )
                }
            },
            &notifier
        )
        
        if root_port == 0 {
            print("❌ [SleepWakeNotifier] 注册系统电源通知失败")
            cleanupNotifications()
        } else {
            print("✅ [SleepWakeNotifier] 系统睡眠/唤醒监听已启动")
        }
    }
    
    /// 处理电源通知
    @MainActor
    private func handlePowerNotification(
        messageType: UInt32,
        messageArgument: UnsafeMutableRawPointer?,
        service: io_object_t
    ) {
        // IOKit 消息类型常量
        let kIOMessageCanSystemSleep: UInt32 = 0xE0000270
        let kIOMessageSystemWillSleep: UInt32 = 0xE0000280
        let kIOMessageSystemHasPoweredOn: UInt32 = 0xE0000300
        
        switch messageType {
        case kIOMessageCanSystemSleep:
            // 系统询问是否可以睡眠
            print("💤 [SleepWakeNotifier] 系统询问是否可以睡眠")
            // 如果正在防止睡眠,拒绝睡眠
            preventSleepLock.lock()
            let preventing = isPreventingSleep
            preventSleepLock.unlock()
            
            if preventing {
                print("🚫 [SleepWakeNotifier] 拒绝系统睡眠(录音中)")
                IOCancelPowerChange(service, intptr_t(bitPattern: messageArgument))
            } else {
                print("✅ [SleepWakeNotifier] 允许系统睡眠")
                IOAllowPowerChange(service, intptr_t(bitPattern: messageArgument))
            }
            
        case kIOMessageSystemWillSleep:
            // 系统即将睡眠
            print("💤 [SleepWakeNotifier] 系统即将睡眠")
            isSystemAwake = false
            onSystemWillSleep?()
            
            // 必须调用此函数确认收到通知
            IOAllowPowerChange(service, intptr_t(bitPattern: messageArgument))
            
        case kIOMessageSystemHasPoweredOn:
            // 系统已唤醒
            print("☀️ [SleepWakeNotifier] 系统已唤醒")
            isSystemAwake = true
            onSystemDidWake?()
            
        default:
            break
        }
    }
    
    /// 清理通知
    private func cleanupNotifications() {
        if notifier != 0 {
            IODeregisterForSystemPower(&notifier)
            notifier = 0
        }
        
        if let port = notificationPort {
            IONotificationPortDestroy(port)
            notificationPort = nil
        }
    }
    
    // MARK: - 防止系统睡眠
    
    /// 启用防睡眠断言(用于录音期间)
    func enablePreventSleep(reason: String = "录音中") {
        preventSleepLock.lock()
        defer { preventSleepLock.unlock() }
        
        guard !isPreventingSleep else {
            print("ℹ️ [SleepWakeNotifier] 已经在防止睡眠模式")
            return
        }
        
        let reasonCF = reason as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reasonCF,
            &preventSleepAssertion
        )
        
        if result == kIOReturnSuccess {
            isPreventingSleep = true
            print("✅ [SleepWakeNotifier] 已启用防睡眠断言: \(reason)")
        } else {
            print("❌ [SleepWakeNotifier] 启用防睡眠断言失败: \(result)")
        }
    }
    
    /// 禁用防睡眠断言
    func disablePreventSleep() {
        preventSleepLock.lock()
        defer { preventSleepLock.unlock() }
        
        guard isPreventingSleep else {
            print("ℹ️ [SleepWakeNotifier] 没有活动的防睡眠断言")
            return
        }
        
        let result = IOPMAssertionRelease(preventSleepAssertion)
        
        if result == kIOReturnSuccess {
            isPreventingSleep = false
            preventSleepAssertion = 0
            print("✅ [SleepWakeNotifier] 已禁用防睡眠断言")
        } else {
            print("❌ [SleepWakeNotifier] 禁用防睡眠断言失败: \(result)")
        }
    }
    
    /// 获取当前防睡眠状态
    func isCurrentlyPreventingSleep() -> Bool {
        preventSleepLock.lock()
        defer { preventSleepLock.unlock() }
        return isPreventingSleep
    }
}

