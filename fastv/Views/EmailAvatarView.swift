//
//  EmailAvatarView.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI
import AppKit

/// 邮箱头像视图
struct EmailAvatarView: View {
    let email: String
    let size: CGFloat
    
    @State private var avatarImage: NSImage?
    
    init(email: String, size: CGFloat = 40) {
        self.email = email
        self.size = size
    }
    
    var body: some View {
        Group {
            if let image = avatarImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // 多彩占位符 - 根据邮箱地址生成固定颜色
                Circle()
                    .fill(avatarColor)
                    .overlay {
                        Text(initials)
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .task {
            await loadAvatar()
        }
    }
    
    /// 根据邮箱地址生成固定的颜色
    private var avatarColor: Color {
        // 现代感强的柔和色板
        let colors: [Color] = [
            Color(red: 0.0, green: 0.48, blue: 1.0),      // Blue
            Color(red: 0.58, green: 0.40, blue: 0.86),    // Purple
            Color(red: 1.0, green: 0.18, blue: 0.33),     // Pink
            Color(red: 0.0, green: 0.78, blue: 0.78),      // Teal
            Color(red: 0.35, green: 0.34, blue: 0.84),    // Indigo
            Color(red: 1.0, green: 0.58, blue: 0.0),      // Orange
            Color(red: 0.0, green: 0.78, blue: 0.33),     // Green
            Color(red: 0.99, green: 0.24, blue: 0.37),    // Red
        ]
        
        // 使用邮箱地址的哈希值来选择颜色，确保同一邮箱总是相同颜色
        let hash = email.hashValue
        let index = abs(hash) % colors.count
        return colors[index]
    }
    
    private var initials: String {
        let components = email.components(separatedBy: "@")
        if let first = components.first, !first.isEmpty {
            return String(first.prefix(2)).uppercased()
        }
        return "??"
    }
    
    private func loadAvatar() async {
        avatarImage = await AvatarService.shared.getAvatar(for: email, size: Int(size))
    }
}

#Preview {
    HStack {
        EmailAvatarView(email: "test@example.com")
        EmailAvatarView(email: "user@gmail.com", size: 60)
    }
    .padding()
}

