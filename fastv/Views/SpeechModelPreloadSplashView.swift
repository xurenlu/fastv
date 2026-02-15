//
//  SpeechModelPreloadSplashView.swift
//  fastv
//
//  语音模型预加载启动屏，转移注意力并降低预期
//

import SwiftUI

/// 语音模型预加载启动屏
/// 在模型加载期间显示，让用户知道需要先加载模型
struct SpeechModelPreloadSplashView: View {
    @ObservedObject var preloadManager: SpeechModelPreloadManager
    
    var body: some View {
        if preloadManager.isPreloading {
            ZStack {
                Color(.windowBackgroundColor)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    
                    Text(NSLocalizedString("speech.model.preload.title", comment: ""))
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text(NSLocalizedString("speech.model.preload.message", comment: ""))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
