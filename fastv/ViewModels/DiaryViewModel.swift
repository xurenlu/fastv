//
//  DiaryViewModel.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import Combine

/// 日记 ViewModel
@MainActor
class DiaryViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var isRecording: Bool = false
    @Published var isProcessingAI: Bool = false
    @Published var aiErrorMessage: String?
    @Published var aiSuccessMessage: String?
    
    private let store = DiaryStore.shared
    private let aiService = DiaryAIService.shared
    private let voiceService = VoiceInputService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // 订阅 store 的变化
        store.$entries
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    var entries: [DiaryEntry] {
        store.entries
    }
    
    // MARK: - Voice Input
    
    func startVoiceRecording() {
        guard !isRecording else { return }
        
        do {
            try voiceService.startRecording()
            isRecording = true
            aiErrorMessage = nil
            aiSuccessMessage = nil
        } catch {
            aiErrorMessage = error.localizedDescription
            isRecording = false
        }
    }
    
    func stopVoiceRecording() async {
        guard isRecording else { return }
        
        isRecording = false
        
        do {
            guard let recording = try await voiceService.stopRecording() else {
                aiErrorMessage = "录音失败，未获取到音频数据"
                return
            }
            
            // 转文字
            let language = UserPreferences.shared.transcriptLanguage
            let transcribedText = try await SpeechTranscriber.transcribe(recording: recording, language: language)
            
            // 将转录文本填入输入框
            inputText = transcribedText
            
            // 自动触发 AI 分析
            await processWithAI(transcribedText)
            
        } catch {
            aiErrorMessage = "语音转文字失败: \(error.localizedDescription)"
        }
    }
    
    func cancelVoiceRecording() {
        voiceService.cancelRecording()
        isRecording = false
    }
    
    // MARK: - AI Processing
    
    func processWithAI(_ text: String? = nil) async {
        let input = text ?? inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            aiErrorMessage = "请输入内容"
            return
        }
        
        isProcessingAI = true
        aiErrorMessage = nil
        aiSuccessMessage = nil
        
        // 获取用户设置
        let preferences = UserPreferences.shared
        let config = preferences.getConfig(for: .diaryAnalysis)
        
        do {
            // 调用 AI 分析
            let analysis = try await aiService.analyzeDiary(
                content: input,
                profile: config.profile,
                model: config.model,
                timeout: config.timeout
            )
            
            // 创建日记条目
            let title = analysis.title ?? "无标题"
            var mood: DiaryMood? = nil
            if let moodStr = analysis.mood {
                mood = DiaryMood(rawValue: moodStr)
            }
            
            let entry = DiaryEntry(
                title: title,
                content: input,
                date: Date(),
                mood: mood,
                aiSummary: analysis.summary,
                aiMoodAnalysis: analysis.moodAnalysis
            )
            
            store.add(entry)
            
            // 清空输入框
            inputText = ""
            
            // 显示成功消息
            aiSuccessMessage = "日记已保存"
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    aiSuccessMessage = nil
                }
            }
            
        } catch {
            aiErrorMessage = "AI 处理失败: \(error.localizedDescription)"
            print("❌ [DiaryViewModel] AI 处理失败: \(error)")
        }
        
        isProcessingAI = false
    }
    
    // MARK: - CRUD Operations
    
    func deleteEntry(_ entry: DiaryEntry) {
        store.delete(entry)
    }
    
    func updateEntry(_ entry: DiaryEntry, title: String? = nil, content: String? = nil, mood: DiaryMood? = nil) {
        var updated = entry
        updated.update(title: title, content: content, mood: mood)
        store.update(updated)
    }
}

