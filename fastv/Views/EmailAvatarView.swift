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
                // 占位符
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .overlay {
                        Text(initials)
                            .font(.system(size: size * 0.4, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task {
            await loadAvatar()
        }
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

