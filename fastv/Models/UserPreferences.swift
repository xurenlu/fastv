//
//  UserPreferences.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import Combine
import AppKit

@MainActor
class UserPreferences: ObservableObject {
    static let shared = UserPreferences()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Keys
    private enum Keys {
        static let lastVideoURL = "lastVideoURL"
        static let extractFirstFrame = "extractFirstFrame"
        static let extractLastFrame = "extractLastFrame"
        static let extractAudio = "extractAudio"
        static let extractTranscript = "extractTranscript"
        static let audioFormat = "audioFormat"
        static let imageMaxWidth = "imageMaxWidth"
        static let imageMaxHeight = "imageMaxHeight"
        static let imageCompressionEnabled = "imageCompressionEnabled"
        static let imageCompressionQuality = "imageCompressionQuality"
        static let imageFormat = "imageFormat"
        static let customOutputDirectory = "customOutputDirectory"
        static let useCustomOutputDirectory = "useCustomOutputDirectory"
        static let hasShownWelcome = "hasShownWelcome"
        static let enableVoiceInput = "enableVoiceInput"
        static let voiceInputShortcutKeyCode = "voiceInputShortcutKeyCode"
        static let voiceInputShortcutModifiers = "voiceInputShortcutModifiers"
        static let voiceInputLanguage = "voiceInputLanguage"
        static let transcriptLanguage = "transcriptLanguage"
        static let waveformWindowPosition = "waveformWindowPosition"
    }
    
    // MARK: - Published Properties
    
    @Published var extractFirstFrame: Bool {
        willSet { defaults.set(newValue, forKey: Keys.extractFirstFrame) }
    }
    
    @Published var extractLastFrame: Bool {
        willSet { defaults.set(newValue, forKey: Keys.extractLastFrame) }
    }
    
    @Published var extractAudio: Bool {
        willSet { defaults.set(newValue, forKey: Keys.extractAudio) }
    }
    
    @Published var extractTranscript: Bool {
        willSet { defaults.set(newValue, forKey: Keys.extractTranscript) }
    }
    
    @Published var audioFormat: AudioFormat {
        willSet { defaults.set(newValue.rawValue, forKey: Keys.audioFormat) }
    }
    
    @Published var imageMaxWidth: Int {
        willSet { defaults.set(newValue, forKey: Keys.imageMaxWidth) }
    }
    
    @Published var imageMaxHeight: Int {
        willSet { defaults.set(newValue, forKey: Keys.imageMaxHeight) }
    }
    
    @Published var imageCompressionEnabled: Bool {
        willSet { defaults.set(newValue, forKey: Keys.imageCompressionEnabled) }
    }
    
    @Published var imageCompressionQuality: Double {
        willSet { defaults.set(newValue, forKey: Keys.imageCompressionQuality) }
    }
    
    @Published var imageFormat: ImageFormat {
        willSet { defaults.set(newValue.fileExtension, forKey: Keys.imageFormat) }
    }
    
    @Published var useCustomOutputDirectory: Bool {
        willSet { defaults.set(newValue, forKey: Keys.useCustomOutputDirectory) }
    }
    
    @Published var enableVoiceInput: Bool {
        willSet { defaults.set(newValue, forKey: Keys.enableVoiceInput) }
    }
    
    @Published var voiceInputShortcutKeyCode: UInt16 {
        willSet { defaults.set(newValue, forKey: Keys.voiceInputShortcutKeyCode) }
    }
    
    @Published var voiceInputShortcutModifiers: NSEvent.ModifierFlags {
        willSet { defaults.set(newValue.rawValue, forKey: Keys.voiceInputShortcutModifiers) }
    }
    
    @Published var voiceInputLanguage: String {
        willSet { defaults.set(newValue, forKey: Keys.voiceInputLanguage) }
    }
    
    @Published var transcriptLanguage: TranscriptLanguage {
        willSet { defaults.set(newValue.rawValue, forKey: Keys.transcriptLanguage) }
    }
    
    @Published var waveformWindowPosition: WaveformWindowPosition {
        willSet { defaults.set(newValue.rawValue, forKey: Keys.waveformWindowPosition) }
    }
    
    // MARK: - Initialization
    
    private init() {
        // 加载默认值
        extractFirstFrame = defaults.object(forKey: Keys.extractFirstFrame) as? Bool ?? true
        extractLastFrame = defaults.object(forKey: Keys.extractLastFrame) as? Bool ?? true
        extractAudio = defaults.object(forKey: Keys.extractAudio) as? Bool ?? true
        extractTranscript = defaults.object(forKey: Keys.extractTranscript) as? Bool ?? false
        
        if let formatString = defaults.string(forKey: Keys.audioFormat),
           let format = AudioFormat(rawValue: formatString) {
            audioFormat = format
        } else {
            audioFormat = .m4a
        }
        
        imageMaxWidth = defaults.object(forKey: Keys.imageMaxWidth) as? Int ?? 1920
        imageMaxHeight = defaults.object(forKey: Keys.imageMaxHeight) as? Int ?? 1080
        imageCompressionEnabled = defaults.object(forKey: Keys.imageCompressionEnabled) as? Bool ?? true
        imageCompressionQuality = defaults.object(forKey: Keys.imageCompressionQuality) as? Double ?? 0.8
        
        if let formatString = defaults.string(forKey: Keys.imageFormat),
           let format = ImageFormat(rawValue: formatString) {
            imageFormat = format
        } else {
            imageFormat = .png
        }
        
        useCustomOutputDirectory = defaults.object(forKey: Keys.useCustomOutputDirectory) as? Bool ?? false
        
        // 语音输入法设置
        enableVoiceInput = defaults.object(forKey: Keys.enableVoiceInput) as? Bool ?? false
        
        // 默认快捷键：Option + V（⌥V）
        // 注意：FN键在macOS上难以抢占，因为：
        // 1. FN键的行为因键盘而异
        // 2. 系统和其他应用可能已经注册了FN键
        // 3. 全局快捷键监听需要辅助功能权限，且无法强制抢占其他应用的快捷键
        // 因此我们使用 Option + V 作为默认快捷键，用户可以在设置中自定义
        if let savedKeyCode = defaults.object(forKey: Keys.voiceInputShortcutKeyCode) as? UInt16 {
            voiceInputShortcutKeyCode = savedKeyCode
        } else {
            voiceInputShortcutKeyCode = 0x09 // V键
        }
        
        if let savedModifiers = defaults.object(forKey: Keys.voiceInputShortcutModifiers) as? UInt {
            voiceInputShortcutModifiers = NSEvent.ModifierFlags(rawValue: savedModifiers)
        } else {
            // 默认使用 Option 键作为修饰键
            voiceInputShortcutModifiers = .option
        }
        
        voiceInputLanguage = defaults.string(forKey: Keys.voiceInputLanguage) ?? "auto"
        
        // 文本稿语言设置，默认为自动检测
        if let languageString = defaults.string(forKey: Keys.transcriptLanguage),
           let language = TranscriptLanguage(rawValue: languageString) {
            transcriptLanguage = language
        } else {
            transcriptLanguage = .auto
        }
        
        // 波形窗口位置设置，默认为右上角
        if let positionString = defaults.string(forKey: Keys.waveformWindowPosition),
           let position = WaveformWindowPosition(rawValue: positionString) {
            waveformWindowPosition = position
        } else {
            waveformWindowPosition = .topRight
        }
    }
    
    // MARK: - Methods
    
    func saveCustomOutputDirectory(_ url: URL?) {
        if let url = url {
            defaults.set(url.path, forKey: Keys.customOutputDirectory)
            useCustomOutputDirectory = true
        } else {
            defaults.removeObject(forKey: Keys.customOutputDirectory)
            useCustomOutputDirectory = false
        }
    }
    
    func getCustomOutputDirectory() -> URL? {
        guard useCustomOutputDirectory,
              let path = defaults.string(forKey: Keys.customOutputDirectory),
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
    
    func saveLastVideoURL(_ url: URL?) {
        if let url = url {
            defaults.set(url.path, forKey: Keys.lastVideoURL)
        } else {
            defaults.removeObject(forKey: Keys.lastVideoURL)
        }
    }
    
    func getLastVideoURL() -> URL? {
        guard let path = defaults.string(forKey: Keys.lastVideoURL) else { return nil }
        return URL(fileURLWithPath: path)
    }
    
    /// 检查是否已显示过欢迎窗口
    var hasShownWelcome: Bool {
        get {
            defaults.bool(forKey: Keys.hasShownWelcome)
        }
        set {
            defaults.set(newValue, forKey: Keys.hasShownWelcome)
        }
    }
    
    /// 标记已显示欢迎窗口
    func markWelcomeAsShown() {
        hasShownWelcome = true
    }
}

