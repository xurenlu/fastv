//
//  MeetingRecordService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import AVFoundation
import Combine

/// 会议记录服务（自动分段转文字）
@MainActor
class MeetingRecordService: ObservableObject {
    static let shared = MeetingRecordService()
    
    @Published private(set) var isRecording = false
    @Published private(set) var currentSegments: [MeetingSegment] = []
    
    private let voiceService = VoiceInputService.shared
    private let silenceDetector = SilenceDetector.shared
    private var currentRecordId: UUID?
    private var meetingAppName: String = ""
    
    private init() {}
    
    /// 开始会议记录
    func startRecording(meetingAppName: String) {
        guard !isRecording else { return }
        
        self.meetingAppName = meetingAppName
        self.currentRecordId = UUID()
        self.currentSegments = []
        self.isRecording = true
        
        // 启用智能分段转文字
        voiceService.enableSegmentTranscription = true
        silenceDetector.silenceThreshold = 1.5 // 会议中停顿阈值
        
        // 设置分段转文字回调
        voiceService.onSegmentReady = { [weak self] segmentRecording in
            await self?.processSegment(segmentRecording: segmentRecording)
        }
        
        // 开始录音
        do {
            try voiceService.startRecording()
            print("🎤 [MeetingRecordService] 开始会议记录: \(meetingAppName)")
        } catch {
            print("❌ [MeetingRecordService] 开始录音失败: \(error)")
            isRecording = false
        }
    }
    
    /// 停止会议记录
    func stopRecording() async -> MeetingRecord? {
        guard isRecording else { return nil }
        
        isRecording = false
        
        // 处理最后一段
        if let recording = try? await voiceService.stopRecording() {
            await processSegment(segmentRecording: recording)
        }
        
        // 重置
        voiceService.enableSegmentTranscription = false
        voiceService.onSegmentReady = nil
        
        guard let recordId = currentRecordId, !currentSegments.isEmpty else {
            return nil
        }
        
        let record = MeetingRecord(
            id: recordId,
            app: meetingAppName,
            segments: currentSegments,
            createdAt: Date()
        )
        
        // 清空当前记录
        currentRecordId = nil
        currentSegments = []
        
        print("✅ [MeetingRecordService] 会议记录完成，共 \(currentSegments.count) 段")
        
        return record
    }
    
    /// 处理分段转文字
    private func processSegment(segmentRecording: VoiceRecording) async {
        let preferences = UserPreferences.shared
        
        do {
            // 获取用户设置的识别语言
            let languageString = preferences.voiceInputLanguage
            let language = TranscriptLanguage(rawValue: languageString) ?? .zh
            
            // 转文字
            var text = try await SpeechTranscriber.transcribe(recording: segmentRecording, language: language)
            
            // 快速纠错
            if preferences.enableFastCorrection {
                text = TextCorrectionService.shared.correctText(text)
            }
            
            // 常错词修正
            let mistakeManager = CommonMistakeManager.shared
            if mistakeManager.enableAutoCorrection {
                text = mistakeManager.applyCorrections(to: text)
            }
            
            // 添加到当前段
            if !text.isEmpty {
                let segment = MeetingSegment(text: text)
                currentSegments.append(segment)
                print("✅ [MeetingRecordService] 添加对话段: \(text.prefix(50))...")
            }
        } catch {
            print("❌ [MeetingRecordService] 分段转文字失败: \(error)")
        }
    }
}

