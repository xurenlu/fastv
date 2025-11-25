//
//  ContentView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

struct ContentView: View {
    @State private var showSettings = false
    @State private var showWelcome = false
    @ObservedObject private var preferences = UserPreferences.shared
    
    var body: some View {
        // 检查是否完成引导流程
        if !preferences.hasCompletedOnboarding {
            OnboardingView()
        } else {
            // 使用新的主界面
            MainDashboardView()
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showWelcome) {
                WelcomeView()
                    .frame(width: 600, height: 650)
            }
            .frame(minWidth: 900, minHeight: 700)
        .onAppear {
            // 延迟显示欢迎窗口，确保界面已加载完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // 检查是否首次启动
                if !UserPreferences.shared.hasShownWelcome {
                    showWelcome = true
                }
            }
        }
        }
    }
}

#Preview {
    ContentView()
}
