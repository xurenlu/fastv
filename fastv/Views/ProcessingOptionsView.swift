//
//  ProcessingOptionsView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

struct ProcessingOptionsView: View {
    @ObservedObject var preferences = UserPreferences.shared
    var videoInfo: VideoInfo?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("提取第一帧", isOn: $preferences.extractFirstFrame)
            Toggle("提取最后一帧", isOn: $preferences.extractLastFrame)
            
            Toggle("检测画面变更", isOn: $preferences.detectSceneChanges)
            
            Toggle("提取音频", isOn: $preferences.extractAudio)
                .disabled(shouldDisableAudio)
            
            if shouldDisableAudio {
                Text("该视频没有音频轨道")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
            
            if preferences.extractAudio {
                HStack {
                    Text("音频格式")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $preferences.audioFormat) {
                        ForEach(AudioFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                .padding(.leading, 20)
                
                Toggle("提取文本稿", isOn: $preferences.extractTranscript)
                    .disabled(shouldDisableAudio)
                    .padding(.leading, 20)
                
                if preferences.extractTranscript && shouldDisableAudio {
                    Text("需要先提取音频才能转写文本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 40)
                }
                
                if preferences.extractTranscript && !shouldDisableAudio {
                    HStack {
                        Text("语言")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $preferences.transcriptLanguage) {
                            ForEach(TranscriptLanguage.allCases, id: \.self) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }
                    .padding(.leading, 20)
                }
            }
        }
    }
    
    private var shouldDisableAudio: Bool {
        if let videoInfo = videoInfo {
            return videoInfo.audioTracks.isEmpty
        }
        return false
    }
}

#Preview {
    ProcessingOptionsView(videoInfo: nil)
        .padding()
}
