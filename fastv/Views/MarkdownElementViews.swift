//
//  MarkdownElementViews.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import SwiftUI
import AppKit

// MARK: - 主要 Markdown 元素视图

// 单个 Markdown 元素的视图
struct MarkdownElementView: View {
    let element: MarkdownElement
    let isTransparentBackground: Bool
    
    private var elementBackground: Color {
        isTransparentBackground ? Color.white.opacity(0.1) : Color(NSColor.textBackgroundColor)
    }
    
    private var textColor: Color {
        if isTransparentBackground {
            return .white
        } else {
            return .primary
        }
    }
    
    private var secondaryTextColor: Color {
        if isTransparentBackground {
            return .white.opacity(0.7)
        } else {
            return .secondary
        }
    }
    
    private var codeTextColor: Color {
        if isTransparentBackground { return .white.opacity(0.9) }
        return Color(NSColor(calibratedWhite: 0.15, alpha: 1.0))
    }
    
    var body: some View {
        switch element.type {
        case .heading(let level):
            Text(element.content)
                .font(headingFont(for: level))
                .fontWeight(.bold)
                .foregroundColor(textColor)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                
        case .paragraph:
            RichTextView(text: element.content, isTransparentBackground: isTransparentBackground)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                
        case .codeBlock(let language):
            VStack(alignment: .leading, spacing: 4) {
                if let lang = language, !lang.isEmpty, !isTransparentBackground {
                    HStack {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text(lang.capitalized)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        Spacer()
                        
                        Button(action: {
                            copyToClipboard(element.content)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(secondaryTextColor)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                }
                
                Text(element.content)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(codeTextColor)
                    .padding()
                    .background(elementBackground)
                    .cornerRadius(language != nil ? 0 : 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .background(elementBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(secondaryTextColor.opacity(0.3), lineWidth: 1)
            )
            
        case .bulletList, .numberedList:
            VStack(alignment: .leading, spacing: 4) {
                if let children = element.children {
                    ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                        HStack(alignment: .top, spacing: 8) {
                            Text(element.type == .bulletList ? "•" : "\(index + 1).")
                                .font(.body)
                                .foregroundColor(secondaryTextColor)
                                .fixedSize()
                            
                            RichTextView(text: child.content, isTransparentBackground: isTransparentBackground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            
        case .checkboxList:
            VStack(alignment: .leading, spacing: 4) {
                if let children = element.children {
                    ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                        CheckboxItemView(content: child.content, isTransparentBackground: isTransparentBackground)
                    }
                }
            }
            
        case .blockquote:
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(isTransparentBackground ? Color.white.opacity(0.6) : Color.blue)
                    .frame(width: 4)
                
                Text(element.content)
                    .font(.body)
                    .foregroundColor(textColor)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(isTransparentBackground ? Color.white.opacity(0.05) : Color.blue.opacity(0.05))
            .cornerRadius(8)
            
        case .horizontalRule:
            Divider()
                .padding(.vertical, 8)
                
        case .latexBlock:
            LatexBlockView(
                latexCode: element.content,
                isTransparentBackground: isTransparentBackground
            )
                    
        case .image(let url, let altText):
            ImagePreviewView(url: url, altText: altText, isTransparentBackground: isTransparentBackground)
                    
        case .table(let headers, let rows):
            TableView(headers: headers, rows: rows, isTransparentBackground: isTransparentBackground)
                    
        case .link(let text, let url):
            Button(action: {
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            }) {
                Text(text)
                    .foregroundColor(.blue)
                    .underline()
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .largeTitle
        case 2: return .title
        case 3: return .title2
        case 4: return .title3
        case 5: return .headline
        default: return .subheadline
        }
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - 辅助视图

// 图片预览视图
struct ImagePreviewView: View {
    let url: String
    let altText: String
    let isTransparentBackground: Bool
    @State private var image: NSImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400, maxHeight: 400)
                    .cornerRadius(8)
            } else if isLoading {
                ProgressView()
                    .frame(width: 100, height: 100)
            } else {
                Text(altText.isEmpty ? "图片加载失败" : altText)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let imageURL = URL(string: url) else {
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: imageURL) { data, _, _ in
            if let data = data, let nsImage = NSImage(data: data) {
                DispatchQueue.main.async {
                    self.image = nsImage
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }.resume()
    }
}

// 表格视图
struct TableView: View {
    let headers: [String]
    let rows: [[String]]
    let isTransparentBackground: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 表头
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                    Text(header)
                        .font(.headline)
                        .foregroundColor(isTransparentBackground ? .white : .primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isTransparentBackground ? Color.white.opacity(0.1) : Color.secondary.opacity(0.1))
                    
                    if index < headers.count - 1 {
                        Divider()
                    }
                }
            }
            
            // 数据行
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                        Text(cell)
                            .font(.body)
                            .foregroundColor(isTransparentBackground ? .white.opacity(0.9) : .primary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if colIndex < row.count - 1 {
                            Divider()
                        }
                    }
                }
                
                if rowIndex < rows.count - 1 {
                    Divider()
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isTransparentBackground ? Color.white.opacity(0.3) : Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

// 勾选框项目视图
struct CheckboxItemView: View {
    let content: String
    let isTransparentBackground: Bool
    @State private var isChecked: Bool
    @State private var checkboxText: String
    
    init(content: String, isTransparentBackground: Bool) {
        self.content = content
        self.isTransparentBackground = isTransparentBackground
        
        let initialIsChecked = content.hasPrefix("[x]") || content.hasPrefix("[X]")
        let initialText: String
        if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
            initialText = String(content.dropFirst(4))
        } else if content.hasPrefix("[ ] ") {
            initialText = String(content.dropFirst(4))
        } else {
            initialText = content
        }
        
        self._isChecked = State(initialValue: initialIsChecked)
        self._checkboxText = State(initialValue: initialText)
    }
    
    private var secondaryTextColor: Color {
        if isTransparentBackground {
            return .white.opacity(0.7)
        } else {
            return .secondary
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: {
                isChecked.toggle()
            }) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundColor(isChecked ? 
                        (isTransparentBackground ? .white : .blue) : 
                        secondaryTextColor)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(PlainButtonStyle())
            
            RichTextView(text: checkboxText, isTransparentBackground: isTransparentBackground)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

