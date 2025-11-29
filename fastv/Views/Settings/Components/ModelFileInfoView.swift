//
//  ModelFileInfoView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

/// 模型文件信息视图
struct ModelFileInfoView: View {
    @State private var isModelDownloaded = false
    @State private var showOnboarding = false
    @ObservedObject private var downloader = ModelDownloader.shared
    @ObservedObject private var preferences = UserPreferences.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: isModelDownloaded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(isModelDownloaded ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("模型文件状态")
                        .font(.body)
                    
                    Text(isModelDownloaded ? "已下载" : "未下载")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !isModelDownloaded {
                    Button(action: {
                        showOnboarding = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("下载模型")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            
            if isModelDownloaded {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("模型文件已就绪，可以使用语音输入功能")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("首次使用需要下载模型文件（约 894MB）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            checkModelStatus()
        }
        .onChange(of: downloader.isDownloading) { oldValue, newValue in
            // 如果下载完成（从下载中变为非下载中），检查模型状态
            if oldValue && !newValue {
                checkModelStatus()
                // 如果模型已下载，关闭 onboarding sheet
                if isModelDownloaded {
                    showOnboarding = false
                }
            }
        }
        .onChange(of: preferences.isModelDownloaded) { oldValue, newValue in
            if newValue {
                checkModelStatus()
                // 如果模型已下载，关闭 onboarding sheet
                if isModelDownloaded {
                    showOnboarding = false
                }
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }
    
    private func checkModelStatus() {
        // 统一使用 checkModelFilesExist() 检查，并同步 preferences.isModelDownloaded
        let modelExists = ModelDownloader.shared.checkModelFilesExist()
        isModelDownloaded = modelExists
        if modelExists {
            preferences.isModelDownloaded = true
        } else {
            preferences.isModelDownloaded = false
        }
    }
}

