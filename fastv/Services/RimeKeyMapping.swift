//
//  RimeKeyMapping.swift
//  fastv
//
//  macOS 键盘事件到 Rime（X11 keysym）键值的纯函数映射，以及
//  Rime UTF-8 光标偏移到 NSRange（UTF-16）的转换。
//  本文件同时编译进 musetype（供单测）与 QechoIME 两个 target，不依赖 AppKit。
//

import Foundation

enum RimeKeyMapping {

    // MARK: - X11 修饰键掩码（librime 约定）

    static let shiftMask: Int32 = 1 << 0
    static let lockMask: Int32 = 1 << 1
    static let controlMask: Int32 = 1 << 2
    static let altMask: Int32 = 1 << 3
    static let superMask: Int32 = 1 << 26
    static let releaseMask: Int32 = 1 << 30

    // MARK: - 常用 X11 keysym

    static let XK_space: Int32 = 0x20
    static let XK_BackSpace: Int32 = 0xFF08
    static let XK_Tab: Int32 = 0xFF09
    static let XK_Return: Int32 = 0xFF0D
    static let XK_Escape: Int32 = 0xFF1B
    static let XK_Home: Int32 = 0xFF50
    static let XK_Left: Int32 = 0xFF51
    static let XK_Up: Int32 = 0xFF52
    static let XK_Right: Int32 = 0xFF53
    static let XK_Down: Int32 = 0xFF54
    static let XK_PageUp: Int32 = 0xFF55
    static let XK_PageDown: Int32 = 0xFF56
    static let XK_End: Int32 = 0xFF57
    static let XK_Delete: Int32 = 0xFFFF
    static let XK_Shift_L: Int32 = 0xFFE1
    static let XK_Shift_R: Int32 = 0xFFE2

    // MARK: - 键值映射

    /// mac 虚拟键码 + 事件字符 → X11 keysym。
    /// 功能键按键码映射；可打印 ASCII 按字符映射（keysym 与 ASCII 码一致）；
    /// 其余（F 区、非 ASCII 输入等）返回 nil，由调用方透传给宿主应用。
    static func keysym(macKeyCode: UInt16, characters: String?) -> Int32? {
        switch macKeyCode {
        case 36: return XK_Return
        case 76: return XK_Return // 小键盘 Enter
        case 48: return XK_Tab
        case 49: return XK_space
        case 51: return XK_BackSpace
        case 53: return XK_Escape
        case 115: return XK_Home
        case 116: return XK_PageUp
        case 117: return XK_Delete // 正向删除
        case 119: return XK_End
        case 121: return XK_PageDown
        case 123: return XK_Left
        case 124: return XK_Right
        case 125: return XK_Down
        case 126: return XK_Up
        default: break
        }
        guard let scalars = characters?.unicodeScalars,
              scalars.count == 1,
              let scalar = scalars.first else {
            return nil
        }
        let value = scalar.value
        guard value >= 0x20 && value < 0x7F else { return nil }
        return Int32(value)
    }

    static func modifierMask(
        shift: Bool,
        control: Bool,
        option: Bool,
        command: Bool,
        capsLock: Bool,
        isRelease: Bool = false
    ) -> Int32 {
        var mask: Int32 = 0
        if shift { mask |= shiftMask }
        if control { mask |= controlMask }
        if option { mask |= altMask }
        if command { mask |= superMask }
        if capsLock { mask |= lockMask }
        if isRelease { mask |= releaseMask }
        return mask
    }

    // MARK: - 光标偏移转换

    /// Rime 返回的 preedit 光标是 UTF-8 字节偏移，转成 NSRange 需要的 UTF-16 偏移。
    /// 偏移落在合法字符边界之外时兜底返回字符串末尾。
    static func utf16Offset(fromUTF8Offset byteOffset: Int, in string: String) -> Int {
        guard byteOffset > 0 else { return 0 }
        let utf8View = string.utf8
        guard byteOffset <= utf8View.count,
              let utf8Index = utf8View.index(
                utf8View.startIndex,
                offsetBy: byteOffset,
                limitedBy: utf8View.endIndex
              ),
              let stringIndex = utf8Index.samePosition(in: string) else {
            return string.utf16.count
        }
        return string.utf16.distance(
            from: string.utf16.startIndex,
            to: stringIndex.samePosition(in: string.utf16) ?? string.utf16.endIndex
        )
    }
}
