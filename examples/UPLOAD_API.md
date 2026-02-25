# MicroApp 上传 API 使用说明

## 概述

row1 平台现在为所有 MicroApp 提供了统一的上传 API，开发者无需自己实现上传逻辑，也无需配置服务器。

## API 使用方法

### 基本用法

```javascript
// 上传文件（支持图片、文档等）
const file = document.getElementById('file-input').files[0];
const imageUrl = await window.row1.uploadFile(file);
console.log('上传成功，URL:', imageUrl);
```

### 完整示例

```javascript
// 文件选择和处理
document.getElementById('pick-btn').addEventListener('click', () => {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = 'image/*';
  input.onchange = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    
    try {
      // 使用 row1 平台提供的上传 API
      const imageUrl = await window.row1.uploadFile(file);
      console.log('上传成功，URL:', imageUrl);
      
      // 使用上传后的 URL
      await window.row1.vision({
        imageUrl: imageUrl,
        prompt: '请识别这张图片'
      });
    } catch (error) {
      console.error('上传失败:', error);
      alert('上传失败: ' + error.message);
    }
  };
  input.click();
});
```

## API 特性

1. **自动处理**：平台自动处理文件编码、路径生成、上传等所有步骤
2. **返回 CDN URL**：上传成功后返回可直接使用的 CDN URL（`https://cdn.facev.app/...`）
3. **支持所有文件类型**：不仅限于图片，支持任何文件类型
4. **无需配置**：开发者无需配置服务器、API Key 等

## 返回值

- **成功**：返回文件的 CDN URL（字符串）
- **失败**：抛出错误，包含错误信息

## 注意事项

1. 确保 `window.row1` 对象存在（平台会自动注入）
2. 上传的文件会自动保存到 Cloudflare CDN
3. 文件路径格式：`upload/YYYYMM/timestamp-random.ext`
4. 上传的文件可通过返回的 URL 公开访问

## 迁移指南

如果你之前自己实现了上传功能，可以按以下步骤迁移：

### 之前（需要自己实现）

```javascript
const UPLOAD_URL = 'https://cfworker.xurenlu9959.workers.dev/';
const AUTH_KEY = 'baby9527';

async function uploadImage(file) {
  // 复杂的上传逻辑...
  const response = await fetch(`${UPLOAD_URL}${targetPath}`, {
    method: 'PUT',
    headers: {
      'X-Custom-Auth-Key': AUTH_KEY,
      'Content-Type': file.type
    },
    body: file
  });
  // ...
}
```

### 现在（使用平台 API）

```javascript
async function uploadImage(file) {
  // 一行代码搞定！
  return await window.row1.uploadFile(file);
}
```

## 示例应用

所有示例 MicroApp 都已更新使用新的上传 API：
- `plant-care.microapp` - 植物养护助手
- `food-recognition.microapp` - 美食识别助手
- `outfit-advisor.microapp` - 穿搭顾问
- `doc-translator.microapp` - 文档翻译助手
- `math-solver.microapp` - 数学解题助手
- `business-card.microapp` - 名片识别助手
- `business-card-generator.microapp` - 名片生成助手
- `contract-reviewer.microapp` - 合同审查助手
- `medical-record.microapp` - 病历识别助手
- `resume-screener.microapp` - 简历筛选助手
- `wechat-seller.microapp` - 微商营销助手

