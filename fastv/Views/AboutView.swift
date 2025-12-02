//
//  AboutView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI

/// 关于界面
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部图标和名称区域
            VStack(spacing: 16) {
                // App 图标（使用系统图标作为占位符）
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue.gradient)
                    .padding(.top, 40)
                
                // App 名称
                Text(NSLocalizedString("app.name", comment: ""))
                    .font(.system(size: 32, weight: .bold))
                
                // 版本信息
                Text("\(NSLocalizedString("about.version", comment: "")) \(AppVersionManager.fullVersion)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
            
            Divider()
            
            // 内容区域
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 开发者信息
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("about.developer", comment: ""))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("about.developer.name", comment: ""))
                                .font(.body)
                            
                            Text(NSLocalizedString("about.developer.name.en", comment: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    // 个人主页
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("about.website", comment: ""))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Link(destination: URL(string: "https://83d.me")!) {
                            HStack {
                                Text("83d.me")
                                    .font(.body)
                                    .foregroundStyle(.blue)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // 版权信息
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("about.copyright", comment: ""))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Text("© \(currentYear) \(NSLocalizedString("about.developer.name", comment: "")) (rocky.x)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 30)
            }
            
            Divider()
            
            // 底部按钮
            HStack {
                Spacer()
                Button(NSLocalizedString("ok", comment: "")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .frame(width: 500, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var currentYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: Date())
    }
}

#Preview {
    AboutView()
}

