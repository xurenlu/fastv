//
//  WelcomeView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题区域
            VStack(spacing: 16) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                
                VStack(spacing: 6) {
                    Text("welcome.title")
                        .font(.system(size: 28, weight: .bold))
                    
                    Text("welcome.subtitle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 50)
            .padding(.bottom, 30)
            .background {
                Rectangle()
                    .fill(.regularMaterial)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 功能介绍
                    FeatureSection(
                        icon: "keyboard",
                        title: NSLocalizedString("welcome.feature.global.shortcut", comment: ""),
                        description: NSLocalizedString("welcome.feature.global.shortcut.desc", comment: "")
                    )
                    
                    FeatureSection(
                        icon: "waveform",
                        title: NSLocalizedString("welcome.feature.real.time", comment: ""),
                        description: NSLocalizedString("welcome.feature.real.time.desc", comment: "")
                    )
                    
                    FeatureSection(
                        icon: "sparkles",
                        title: NSLocalizedString("welcome.feature.ai.optimization", comment: ""),
                        description: NSLocalizedString("welcome.feature.ai.optimization.desc", comment: "")
                    )
                    
                    FeatureSection(
                        icon: "globe",
                        title: NSLocalizedString("welcome.feature.multilanguage", comment: ""),
                        description: NSLocalizedString("welcome.feature.multilanguage.desc", comment: "")
                    )
                }
                .padding(30)
            }
            
            // 底部按钮
            HStack {
                Spacer()
                
                Button(action: {
                    UserPreferences.shared.markWelcomeAsShown()
                    dismiss()
                }) {
                    Text("welcome.start.using")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(20)
            .background {
                Rectangle()
                    .fill(.regularMaterial)
            }
        }
        .background(.background)
        .frame(width: 600, height: 500)
    }
}

// MARK: - 功能说明卡片
struct FeatureSection: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    WelcomeView()
}
