//
//  SettingsView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences = UserPreferences.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("提取第一帧", isOn: $preferences.extractFirstFrame)
                    Toggle("提取最后一帧", isOn: $preferences.extractLastFrame)
                    Toggle("提取音频", isOn: $preferences.extractAudio)
                    
                    Picker("音频格式", selection: $preferences.audioFormat) {
                        ForEach(AudioFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                } header: {
                    Text("默认处理选项")
                } footer: {
                    Text("这些选项将作为下次处理视频时的默认设置")
                }
                
                Section {
                    Picker("图片格式", selection: $preferences.imageFormat) {
                        ForEach(ImageFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    
                    HStack {
                        Text("最大宽度")
                        Spacer()
                        TextField("", value: $preferences.imageMaxWidth, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                        Text("像素")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("最大高度")
                        Spacer()
                        TextField("", value: $preferences.imageMaxHeight, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                        Text("像素")
                            .foregroundStyle(.secondary)
                    }
                    
                    Toggle("启用图片压缩", isOn: $preferences.imageCompressionEnabled)
                    
                    if preferences.imageCompressionEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("压缩质量")
                                Spacer()
                                Text("\(Int(preferences.imageCompressionQuality * 100))%")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $preferences.imageCompressionQuality, in: 0.1...1.0)
                        }
                        .padding(.leading, 20)
                    }
                } header: {
                    Text("图片设置")
                } footer: {
                    Text("设置图片的最大尺寸和压缩选项")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(minWidth: 520, minHeight: 480)
        }
    }
}

#Preview {
    SettingsView()
}
