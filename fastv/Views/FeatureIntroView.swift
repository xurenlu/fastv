//
//  FeatureIntroView.swift
//  fastv
//
//  产品特性介绍视图 - 启动时展示核心特性
//

import SwiftUI

/// 产品特性介绍视图
/// 在启动时展示，介绍产品的核心特性
struct FeatureIntroView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0
    @State private var isAutoPlaying = true
    @State private var opacity: Double = 0.0
    @State private var scale: CGFloat = 0.8

    // 产品特性列表
    private let features: [Feature] = [
        Feature(
            icon: "bolt.fill",
            iconColor: .yellow,
            title: NSLocalizedString("feature.intro.speed.title", comment: ""),
            description: NSLocalizedString("feature.intro.speed.description", comment: ""),
            highlight: NSLocalizedString("feature.intro.speed.highlight", comment: "")
        ),
        Feature(
            icon: "brain.head.profile",
            iconColor: .purple,
            title: NSLocalizedString("feature.intro.accuracy.title", comment: ""),
            description: NSLocalizedString("feature.intro.accuracy.description", comment: ""),
            highlight: NSLocalizedString("feature.intro.accuracy.highlight", comment: "")
        ),
        Feature(
            icon: "waveform.path",
            iconColor: .blue,
            title: NSLocalizedString("feature.intro.smart.title", comment: ""),
            description: NSLocalizedString("feature.intro.smart.description", comment: ""),
            highlight: NSLocalizedString("feature.intro.smart.highlight", comment: "")
        ),
        Feature(
            icon: "globe",
            iconColor: .green,
            title: NSLocalizedString("feature.intro.multilang.title", comment: ""),
            description: NSLocalizedString("feature.intro.multilang.description", comment: ""),
            highlight: NSLocalizedString("feature.intro.multilang.highlight", comment: "")
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 顶部跳过按钮
            HStack {
                Spacer()
                Button(action: {
                    dismiss()
                }) {
                    Text(NSLocalizedString("feature.intro.skip", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
            .padding(.trailing, 30)

            Spacer()

            // 特性展示区域
            TabView(selection: $currentIndex) {
                ForEach(0..<features.count, id: \.self) { index in
                    FeatureCard(feature: features[index])
                        .tag(index)
                }
            }
            .frame(height: 400)
            .opacity(opacity)
            .scaleEffect(scale)

            // 页面指示器
            HStack(spacing: 8) {
                ForEach(0..<features.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentIndex ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: index == currentIndex ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3), value: currentIndex)
                }
            }
            .padding(.top, 40)

            Spacer()

            // 底部按钮
            HStack(spacing: 16) {
                if currentIndex > 0 {
                    Button(action: previousFeature) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text(NSLocalizedString("feature.intro.previous", comment: ""))
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button(action: nextFeature) {
                    HStack {
                        Text(currentIndex == features.count - 1
                             ? NSLocalizedString("feature.intro.start", comment: "")
                             : NSLocalizedString("feature.intro.next", comment: ""))
                        if currentIndex < features.count - 1 {
                            Image(systemName: "chevron.right")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .frame(width: 700, height: 550)
        .onAppear {
            // 入场动画
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                opacity = 1.0
                scale = 1.0
            }

            // 自动播放（可选）
            if isAutoPlaying {
                startAutoPlay()
            }
        }
        .onChange(of: currentIndex) { _, _ in
            // 切换动画
            withAnimation(.easeInOut(duration: 0.3)) {
                opacity = 0.0
                scale = 0.95
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    opacity = 1.0
                    scale = 1.0
                }
            }
        }
    }

    private func nextFeature() {
        if currentIndex < features.count - 1 {
            withAnimation {
                currentIndex += 1
            }
        } else {
            dismiss()
        }
    }

    private func previousFeature() {
        if currentIndex > 0 {
            withAnimation {
                currentIndex -= 1
            }
        }
    }

    private func startAutoPlay() {
        // 可选：自动轮播特性
        // Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
        //     if currentIndex < features.count - 1 {
        //         currentIndex += 1
        //     }
        // }
    }
}

// MARK: - 特性卡片
struct FeatureCard: View {
    let feature: Feature
    @State private var animateIcon = false

    var body: some View {
        VStack(spacing: 32) {
            // 图标
            ZStack {
                // 背景光晕
                Circle()
                    .fill(feature.iconColor.opacity(0.15))
                    .frame(width: 180, height: 180)
                    .blur(radius: 20)

                // 脉冲动画
                Circle()
                    .stroke(feature.iconColor.opacity(0.3), lineWidth: 2)
                    .frame(width: 120, height: 120)
                    .scaleEffect(animateIcon ? 1.2 : 1.0)
                    .opacity(animateIcon ? 0 : 1)

                // 主图标
                Circle()
                    .fill(feature.iconColor.gradient)
                    .frame(width: 100, height: 100)
                    .shadow(color: feature.iconColor.opacity(0.4), radius: 20, x: 0, y: 10)

                Image(systemName: feature.icon)
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    animateIcon = true
                }
            }

            // 标题和描述
            VStack(spacing: 16) {
                Text(feature.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(feature.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // 高亮数据
                if !feature.highlight.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(feature.highlight)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background {
                        Capsule()
                            .fill(Color.green.opacity(0.1))
                    }
                }
            }
            .padding(.horizontal, 60)
        }
    }
}

// MARK: - 特性数据模型
struct Feature {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let highlight: String
}

// MARK: - 预览
#Preview {
    FeatureIntroView()
}
