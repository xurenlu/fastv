//
//  VoiceInputView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

struct VoiceInputView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var errorMessage: String?
    @State private var testInputText: String = ""
    @FocusState private var isTestInputFocused: Bool
    @State private var showModelDownload = false
    @State private var isModelDownloaded = false
    @ObservedObject private var downloader = ModelDownloader.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // 模型未下载提示横幅
            if !isModelDownloaded {
                Button(action: {
                    showModelDownload = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("model.not.downloaded.title", comment: ""))
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            Text(NSLocalizedString("model.not.downloaded.message", comment: ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color.orange.opacity(0.1))
                            .overlay {
                                RoundedRectangle(cornerRadius: 0)
                                    .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.plain)
                .onHover { _ in }
            }
            
            // 测试输入框区域
            VStack(alignment: .leading, spacing: 12) {
                // 重要提示
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    
                    Text(NSLocalizedString("main.usage.hint", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.1))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("test.input.label", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    TextField(NSLocalizedString("test.input.placeholder", comment: ""), text: $testInputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...2)
                        .focused($isTestInputFocused)
                        .frame(height: 50)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .navigationTitle(NSLocalizedString("voice.input", comment: ""))
        .alert(NSLocalizedString("error", comment: ""), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(NSLocalizedString("ok", comment: ""), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .sheet(isPresented: $showModelDownload) {
            OnboardingView()
        }
        .onAppear {
            checkModelStatus()
        }
        .onChange(of: preferences.isModelDownloaded) { _, _ in
            checkModelStatus()
        }
        .onChange(of: downloader.isDownloading) { oldValue, newValue in
            if oldValue && !newValue {
                checkModelStatus()
            }
        }
    }
    
    private func checkModelStatus() {
        isModelDownloaded = ModelDownloader.shared.checkModelFilesExist()
    }
}

#Preview {
    VoiceInputView()
}
