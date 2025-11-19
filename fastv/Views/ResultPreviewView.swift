//
//  ResultPreviewView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import AppKit

struct ResultPreviewView: View {
    let firstFrameImage: NSImage?
    let lastFrameImage: NSImage?
    let audioURL: URL?
    let outputDirectory: URL?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("处理结果")
                .font(.headline)
            
            HStack(spacing: 16) {
                // 第一帧预览
                if let firstFrameImage = firstFrameImage {
                    FramePreview(image: firstFrameImage, title: "第一帧")
                }
                
                // 最后一帧预览
                if let lastFrameImage = lastFrameImage {
                    FramePreview(image: lastFrameImage, title: "最后一帧")
                }
            }
            
            // 音频文件信息
            if let audioURL = audioURL {
                HStack {
                    Image(systemName: "music.note")
                        .foregroundColor(.secondary)
                    Text(audioURL.lastPathComponent)
                        .font(.subheadline)
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
            
            // 操作按钮
            HStack(spacing: 12) {
                if let outputDirectory = outputDirectory {
                    Button(action: {
                        FileManager.default.revealInFinder(outputDirectory)
                    }) {
                        Label("打开保存位置", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

struct FramePreview: View {
    let image: NSImage
    let title: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 200, height: 150)
                .cornerRadius(6)
                .shadow(radius: 2)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ResultPreviewView(
        firstFrameImage: nil,
        lastFrameImage: nil,
        audioURL: URL(fileURLWithPath: "/path/to/audio.m4a"),
        outputDirectory: URL(fileURLWithPath: "/path/to/output")
    )
    .padding()
}

