//
//  ProcessingOptionsView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

// 协议定义处理选项
protocol ProcessingOptionsProvider {
    var extractFirstFrame: Bool { get set }
    var extractLastFrame: Bool { get set }
    var extractAudio: Bool { get set }
    var extractTranscript: Bool { get set }
    var selectedAudioFormat: AudioFormat { get set }
    var videoInfo: VideoInfo? { get }
}

// 扩展 VideoProcessorViewModel 使其符合协议
extension VideoProcessorViewModel: ProcessingOptionsProvider {
    // videoInfo 已经存在，不需要重新定义
}

// 扩展 VideoListViewModel 使其符合协议
extension VideoListViewModel: ProcessingOptionsProvider {
    var videoInfo: VideoInfo? {
        nil // 多视频模式下不显示单个视频信息
    }
}

struct ProcessingOptionsView<Provider: ProcessingOptionsProvider & ObservableObject>: View {
    @ObservedObject var provider: Provider
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("提取第一帧", isOn: Binding(
                get: { [weak provider] in provider?.extractFirstFrame ?? false },
                set: { [weak provider] newValue in
                    Task { @MainActor in
                        provider?.extractFirstFrame = newValue
                    }
                }
            ))
            Toggle("提取最后一帧", isOn: Binding(
                get: { [weak provider] in provider?.extractLastFrame ?? false },
                set: { [weak provider] newValue in
                    Task { @MainActor in
                        provider?.extractLastFrame = newValue
                    }
                }
            ))
            
            Toggle("提取音频", isOn: Binding(
                get: { [weak provider] in provider?.extractAudio ?? false },
                set: { [weak provider] newValue in
                    Task { @MainActor in
                        provider?.extractAudio = newValue
                    }
                }
            ))
            .disabled(shouldDisableAudio)
            
            if shouldDisableAudio {
                Text("该视频没有音频轨道")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
            
            if provider.extractAudio {
                HStack {
                    Text("音频格式")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { [weak provider] in provider?.selectedAudioFormat ?? .m4a },
                        set: { [weak provider] newValue in
                            Task { @MainActor in
                                provider?.selectedAudioFormat = newValue
                            }
                        }
                    )) {
                        ForEach(AudioFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                .padding(.leading, 20)
                
                Toggle("提取文本稿", isOn: Binding(
                    get: { [weak provider] in provider?.extractTranscript ?? false },
                    set: { [weak provider] newValue in
                        Task { @MainActor in
                            provider?.extractTranscript = newValue
                        }
                    }
                ))
                .disabled(shouldDisableAudio)
                .padding(.leading, 20)
                
                if provider.extractTranscript && shouldDisableAudio {
                    Text("需要先提取音频才能转写文本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 40)
                }
            }
        }
    }
    
    private var shouldDisableAudio: Bool {
        if let videoInfo = provider.videoInfo {
            return videoInfo.audioTracks.isEmpty
        }
        return false
    }
}

// 为了向后兼容，保留原来的类型别名
typealias ProcessingOptionsViewForSingle = ProcessingOptionsView<VideoProcessorViewModel>
typealias ProcessingOptionsViewForList = ProcessingOptionsView<VideoListViewModel>

#Preview {
    ProcessingOptionsView(provider: VideoProcessorViewModel())
        .padding()
}
