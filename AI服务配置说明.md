# AI 服务配置说明

## 概述

fastv 现在支持多个 AI 服务配置，可以为不同的功能场景配置独立的 AI 服务和模型。

## 支持的 AI 服务类型

1. **OpenAI** - OpenAI API（默认 endpoint: `https://api.openai.com/v1`）
2. **Azure OpenAI** - Azure 托管的 OpenAI 服务
3. **阿里云 DashScope** - 阿里云通义千问服务（默认 endpoint: `https://dashscope.aliyuncs.com/compatible-mode/v1`）
4. **Ollama** - 本地 Ollama 服务（默认 endpoint: `http://127.0.0.1:11434`）
5. **Claude** - Anthropic Claude API（默认 endpoint: `https://api.anthropic.com/v1`）
6. **Some.IM** - Some.IM 服务（固定 endpoint: `https://api.some.im/api/v2/text-generation`，仅需填写 API Key）
7. **Google Gemini** - Google Gemini API（默认 endpoint: `https://generativelanguage.googleapis.com/v1beta`）
8. **自定义** - 自定义协议和端点

## 配置步骤

### 1. 添加 AI 服务

1. 打开设置界面
2. 进入「AI 服务配置」→「管理 AI 服务」
3. 点击「添加服务」按钮
4. 选择协议类型
5. 填写服务信息：
   - **服务名称**：自定义名称
   - **API Endpoint**：根据协议类型自动填充，可编辑（Some.IM 除外）
   - **API Key**：API 密钥（Ollama 不需要）
   - **默认模型**：选择或输入模型名称
   - **超时时间**：请求超时时间（秒）

### 2. 配置场景映射

1. 进入「AI 服务配置」→「场景配置」
2. 为每个场景选择：
   - **使用默认配置**：使用默认 AI 服务
   - **自定义配置**：选择特定的 AI 服务和模型

支持的场景：
- **语音输入优化**：语音转文字后的文本优化
- **会议摘要**：会议记录的 AI 摘要生成
- **Todo 解析**：语音或文本输入解析为待办事项
- **AI 聊天**：AI 聊天功能
- **文本纠错**：文本错误检测和纠正
- **错误检测**：AI 错误检测功能
- **视频分析**：视频场景分析

### 3. 测试连接

在「管理 AI 服务」界面中：
1. 选择要测试的服务
2. 点击「测试连接」按钮
3. 查看测试结果

## 特殊服务说明

### Some.IM

- **Endpoint**：固定为 `https://api.some.im/api/v2/text-generation`，不可编辑
- **协议**：OpenAI 兼容协议
- **配置**：只需填写 API Key

### Google Gemini

- **Endpoint**：默认 `https://generativelanguage.googleapis.com/v1beta`，可自定义
- **协议**：支持 OpenAI 兼容格式和原生 Gemini API 格式
- **认证**：使用 `x-goog-api-key` Header

### 阿里云 DashScope

- **Endpoint**：默认 `https://dashscope.aliyuncs.com/compatible-mode/v1`
- **协议**：DashScope 专用协议
- **认证**：使用 `Authorization: Bearer <token>` Header
- **特殊功能**：支持搜索增强和思考过程（thinking）

## 数据迁移

应用会自动将旧版 AI 配置迁移到新的多服务配置系统：
- 旧配置会自动转换为一个默认 Profile
- 所有场景默认使用该 Profile
- 用户可以在设置中进一步自定义

## 注意事项

1. **默认配置**：至少需要一个默认 AI 服务配置
2. **API Key 安全**：API Key 以加密形式存储在本地
3. **超时设置**：不同场景可能需要不同的超时时间
4. **模型兼容性**：确保选择的模型与协议类型兼容

## 常见问题

### Q: 如何为不同场景使用不同的 AI 服务？

A: 在「场景配置」中，取消「使用默认配置」，然后为每个场景选择对应的 AI 服务和模型。

### Q: Some.IM 只需要填写 API Key 吗？

A: 是的，Some.IM 使用固定的 endpoint，只需要填写 API Key 即可。

### Q: 如何测试 AI 服务连接？

A: 在「管理 AI 服务」中选择服务，点击「测试连接」按钮即可。

### Q: 旧配置会被删除吗？

A: 不会，旧配置会自动迁移为新的 Profile，不会丢失。

