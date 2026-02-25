//
//  SpeechModelPreloadSplashView.swift
//  fastv
//
//  语音模型预加载启动屏 - 在模型加载期间展示产品特性
//

import SwiftUI

/// 语音模型预加载启动屏
/// 在模型加载期间显示产品特性轮播，转移注意力并展示亮点
struct SpeechModelPreloadSplashView: View {
    var preloadManager: SpeechModelPreloadManager
    @State private var currentIndex = 0
    @State private var autoRotateTimer: Timer?

    // 简化的特性列表（用于启动屏展示）
    private let features: [SplashFeature] = [
        SplashFeature(
            icon: "bolt.fill",
            iconColor: .yellow,
            title: NSLocalizedString("feature.intro.speed.title", comment: ""),
            subtitle: NSLocalizedString("feature.splash.speed.subtitle", comment: "")
        ),
        SplashFeature(
            icon: "brain.head.profile",
            iconColor: .purple,
            title: NSLocalizedString("feature.intro.accuracy.title", comment: ""),
            subtitle: NSLocalizedString("feature.splash.accuracy.subtitle", comment: "")
        ),
        SplashFeature(
            icon: "waveform.path",
            iconColor: .blue,
            title: NSLocalizedString("feature.intro.smart.title", comment: ""),
            subtitle: NSLocalizedString("feature.splash.smart.subtitle", comment: "")
        ),
        SplashFeature(
            icon: "globe",
            iconColor: .green,
            title: NSLocalizedString("feature.intro.multilang.title", comment: ""),
            subtitle: NSLocalizedString("feature.splash.multilang.subtitle", comment: "")
        )
    ]

    var body: some View {
        if preloadManager.isPreloading {
            ZStack {
                Color(.windowBackgroundColor)
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // 特性展示区域（自动轮播）
                    TabView(selection: $currentIndex) {
                        ForEach(0..<features.count, id: \.self) { index in
                            SplashFeatureCard(feature: features[index])
                                .tag(index)
                        }
                    }
                    .frame(height: 280)

                    // 页面指示器
                    HStack(spacing: 8) {
                        ForEach(0..<features.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentIndex ? Color.accentColor : Color.gray.opacity(0.3))
                                .frame(width: index == currentIndex ? 20 : 6, height: 6)
                                .animation(.easeInOut(duration: 0.3), value: currentIndex)
                        }
                    }

                    Spacer()

                    // 加载提示
                    VStack(spacing: 12) {
                        Text(NSLocalizedString("speech.model.preload.title", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        ProgressView()
                            .scaleEffect(1.0)
                    }
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                startAutoRotation()
            }
            .onDisappear {
                stopAutoRotation()
            }
        }
    }

    private func startAutoRotation() {
        // 每 3.5 秒切换一次特性展示
        autoRotateTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentIndex = (currentIndex + 1) % features.count
            }
        }
    }

    private func stopAutoRotation() {
        autoRotateTimer?.invalidate()
        autoRotateTimer = nil
    }
}

// MARK: - 启动屏特性卡片
struct SplashFeatureCard: View {
    let feature: SplashFeature
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 20) {
            // 图标
            ZStack {
                Circle()
                    .fill(feature.iconColor.opacity(0.15))
                    .frame(width: 100, height: 100)
                    .blur(radius: 15)

                Circle()
                    .fill(feature.iconColor.gradient)
                    .frame(width: 60, height: 60)
                    .shadow(color: feature.iconColor.opacity(0.3), radius: 10, x: 0, y: 5)

                Image(systemName: feature.icon)
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
            }
            .scaleEffect(isPulsing ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear {
                isPulsing = true
            }

            // 标题和副标题
            VStack(spacing: 8) {
                Text(feature.title)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(feature.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 60)
        }
    }
}

// MARK: - 启动屏特性数据模型
struct SplashFeature {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
}
