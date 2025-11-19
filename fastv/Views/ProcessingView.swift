//
//  ProcessingView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

struct ProcessingView: View {
    let progress: Double
    let status: String
    
    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress) {
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .progressViewStyle(.linear)
            
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

#Preview {
    ProcessingView(progress: 0.65, status: "正在提取音频...")
        .padding()
}

