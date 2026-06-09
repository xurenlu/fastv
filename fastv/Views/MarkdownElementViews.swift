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
                .textSelection(.enabled)
                .contextMenu {
                    Button("复制") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(element.content, forType: .string)
                    }
                    .keyboardShortcut("c", modifiers: .command)
                }
                
        case .paragraph:
            RichTextView(text: element.content, isTransparentBackground: isTransparentBackground)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                
        case .codeBlock(let language):
            if let lang = language, lang.lowercased() == "mermaid" {
                MermaidBlockView(
                    source: element.content,
                    isTransparentBackground: isTransparentBackground
                )
            } else {
                MarkdownCodeBlockView(
                    code: element.content,
                    language: language,
                    isTransparentBackground: isTransparentBackground,
                    elementBackground: self.elementBackground,
                    secondaryTextColor: self.secondaryTextColor,
                    codeTextColor: self.codeTextColor
                )
            }
            
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
                    .textSelection(.enabled)
                    .contextMenu {
                        Button("复制") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(element.content, forType: .string)
                        }
                        .keyboardShortcut("c", modifiers: .command)
                    }
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
            .textSelection(.enabled)
            .contextMenu {
                Button("复制链接") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(url, forType: .string)
                }
                .keyboardShortcut("c", modifiers: .command)
                
                Button("打开链接") {
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
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

// MARK: - 代码块视图（带复制反馈）

struct MarkdownCodeBlockView: View {
    let code: String
    let language: String?
    let isTransparentBackground: Bool
    let elementBackground: Color
    let secondaryTextColor: Color
    let codeTextColor: Color
    
    @State private var showCopySuccess = false
    
    var body: some View {
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
                        copyToClipboard(code)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCopySuccess = true
                        }
                        // 1.5秒后恢复图标
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCopySuccess = false
                            }
                        }
                    }) {
                        Image(systemName: showCopySuccess ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(showCopySuccess ? .green : secondaryTextColor)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(showCopySuccess ? Color.green.opacity(0.1) : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(showCopySuccess ? "已复制" : "复制代码")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
            }
            
            Text(code)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(codeTextColor)
                .padding()
                .background(elementBackground)
                .cornerRadius(language != nil ? 0 : 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .contextMenu {
                    Button("复制") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(code, forType: .string)
                    }
                    .keyboardShortcut("c", modifiers: .command)
                }
        }
        .background(elementBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(secondaryTextColor.opacity(0.3), lineWidth: 1)
        )
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

// 表格视图（列对齐布局，确保每列宽度一致）
struct TableView: View {
    let headers: [String]
    let rows: [[String]]
    let isTransparentBackground: Bool
    
    private let cellPadding = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
    private let minColumnWidth: CGFloat = 80
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            // 按列布局：每列一个 VStack，保证同列单元格宽度一致
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { colIndex, header in
                    VStack(alignment: .leading, spacing: 0) {
                        // 表头
                        Text(header)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isTransparentBackground ? .white : .primary)
                            .padding(cellPadding)
                            .frame(minWidth: minColumnWidth, maxWidth: .infinity, alignment: .leading)
                            .background(isTransparentBackground ? Color.white.opacity(0.1) : Color.secondary.opacity(0.1))
                            .textSelection(.enabled)
                            .contextMenu {
                                Button("复制") {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(header, forType: .string)
                                }
                                .keyboardShortcut("c", modifiers: .command)
                            }
                        
                        // 数据行
                        ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                            let cellText = colIndex < row.count ? row[colIndex] : ""
                            Text(cellText)
                                .font(.system(size: 13))
                                .foregroundColor(isTransparentBackground ? .white.opacity(0.9) : .primary)
                                .padding(cellPadding)
                                .frame(minWidth: minColumnWidth, maxWidth: .infinity, alignment: .leading)
                                .background(
                                    rowIndex % 2 == 1
                                        ? (isTransparentBackground ? Color.white.opacity(0.03) : Color.secondary.opacity(0.04))
                                        : Color.clear
                                )
                                .textSelection(.enabled)
                                .contextMenu {
                                    Button("复制") {
                                        let pasteboard = NSPasteboard.general
                                        pasteboard.clearContents()
                                        pasteboard.setString(cellText, forType: .string)
                                    }
                                    .keyboardShortcut("c", modifiers: .command)
                                }
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if colIndex < headers.count - 1 {
                            Rectangle()
                                .fill(isTransparentBackground ? Color.white.opacity(0.2) : Color.secondary.opacity(0.2))
                                .frame(width: 1)
                        }
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isTransparentBackground ? Color.white.opacity(0.3) : Color.secondary.opacity(0.25), lineWidth: 1)
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

