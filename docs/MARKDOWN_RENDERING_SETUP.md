# Markdown/LaTeX 渲染功能设置说明

## 概述

已从 markly 项目迁移完整的 Markdown 渲染系统到 fastv，支持：
- Markdown 基础语法（标题、段落、列表、引用等）
- 代码块语法高亮
- 表格渲染
- LaTeX 数学公式（块级和行内）
- 图片和链接

## 已迁移的文件

### 服务层
- `fastv/Services/LocalWebResourceManager.swift` - 本地资源管理器
- `fastv/Services/CDNManager.swift` - CDN 资源管理器

### 工具层
- `fastv/Utils/MarkdownModels.swift` - Markdown 解析模型和函数
- `fastv/Utils/NonScrollingWebView.swift` - 禁用滚动的 WebView

### 视图层
- `fastv/Views/LatexView.swift` - LaTeX 渲染组件
- `fastv/Views/RichTextView.swift` - 富文本渲染组件
- `fastv/Views/MarkdownElementViews.swift` - Markdown 元素视图组件

### 更新的文件
- `fastv/Views/ChatMessageView.swift` - 已更新为使用新的 Markdown 渲染系统

## 设置步骤

### 1. 复制 WebLibs 资源文件

运行以下脚本从 markly 项目复制 KaTeX 资源：

```bash
./copy_web_resources.sh
```

或者手动复制：
```bash
cp -r ~/Sites/markly/markly/Resources/WebLibs/katex ~/Sites/fastv/fastv/Resources/WebLibs/
```

### 2. 在 Xcode 中添加资源文件

1. 在 Xcode 中打开项目
2. 右键点击 `fastv/Resources` 文件夹
3. 选择 "Add Files to fastv..."
4. 选择 `WebLibs` 文件夹
5. 确保 "Create folder references" 选项被选中（蓝色文件夹图标）
6. 点击 "Add"

### 3. 验证资源文件

确保以下文件存在于项目中：
- `fastv/Resources/WebLibs/katex/katex.min.css`
- `fastv/Resources/WebLibs/katex/katex.min.js`
- `fastv/Resources/WebLibs/katex/auto-render.min.js`

## 使用方法

### 在聊天消息中使用

`ChatMessageView` 已自动使用新的 Markdown 渲染系统。AI 消息会自动解析并渲染 Markdown 内容。

### 在其他视图中使用

```swift
import SwiftUI

struct MyView: View {
    let markdownText: String
    
    var body: some View {
        let elements = parseMarkdown(markdownText)
        
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(elements.enumerated()), id: \.offset) { index, element in
                MarkdownElementView(element: element, isTransparentBackground: false)
            }
        }
    }
}
```

## 支持的 Markdown 语法

- **标题**: `# H1`, `## H2`, `### H3` 等
- **粗体**: `**text**` 或 `__text__`
- **斜体**: `*text*` 或 `_text_`
- **代码**: `` `code` `` 或 ` ```language\ncode\n``` `
- **列表**: `- item` 或 `1. item`
- **引用**: `> quote`
- **链接**: `[text](url)`
- **图片**: `![alt](url)`
- **表格**: 标准 Markdown 表格语法
- **LaTeX**: `$inline$` 或 `$$\nblock\n$$`

## 注意事项

1. **资源文件**: 如果本地资源文件不存在，系统会自动降级到 CDN。建议始终包含本地资源文件以确保离线可用性。

2. **性能**: 对于超长文档（>100,000 字符），系统会自动截断处理以保证响应性。

3. **LaTeX 渲染**: LaTeX 公式使用 WebView 渲染，首次加载可能需要一些时间。

4. **透明背景**: 某些组件支持 `isTransparentBackground` 参数，用于透明背景场景。

## 故障排除

如果 LaTeX 公式无法渲染：
1. 检查 WebLibs 资源文件是否正确添加到项目中
2. 检查控制台是否有错误信息
3. 确认网络连接（如果使用 CDN 降级）

如果 Markdown 解析失败：
1. 检查输入文本格式是否正确
2. 查看控制台日志获取详细错误信息

