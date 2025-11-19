//
//  LastVideoBannerView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

struct LastVideoBannerView: View {
    let lastVideoURL: URL
    let onOpen: () -> Void
    let onDismiss: () -> Void
    @State private var isVisible = true
    
    var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                    .imageScale(.medium)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("上次打开的文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lastVideoURL.lastPathComponent)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button(action: {
                    onOpen()
                    withAnimation {
                        isVisible = false
                    }
                }) {
                    Text("打开")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button(action: {
                    onDismiss()
                    withAnimation {
                        isVisible = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: isVisible)
        }
    }
}

#Preview {
    LastVideoBannerView(
        lastVideoURL: URL(fileURLWithPath: "/Users/test/video.mp4"),
        onOpen: {},
        onDismiss: {}
    )
    .padding()
}

