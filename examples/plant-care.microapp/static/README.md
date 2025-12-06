# 植物养护助手 - 上传说明

## 图片上传

本应用需要开发者自行实现图片上传功能。应用会选择本地图片后自动上传到云存储，然后将图片 URL 传递给 row1 平台的视觉识别 API。

## 当前实现

当前示例使用了免费的图床服务 sm.ms 作为演示。**实际部署时，请替换为您自己的上传服务**。

## 推荐的上传方案

### 1. 使用云存储服务
- **阿里云 OSS**：适合国内用户
- **腾讯云 COS**：适合国内用户
- **AWS S3**：适合国际用户
- **七牛云**：提供免费额度

### 2. 使用第三方图床
- **sm.ms**：免费图床（当前示例使用）
- **imgur**：国际知名图床
- **GitHub**：使用 GitHub 作为图床

### 3. 修改上传逻辑

在 `app.js` 中修改 `uploadImage()` 函数：

```javascript
async function uploadImage(file) {
  // 替换为您的上传逻辑
  const formData = new FormData();
  formData.append('file', file);
  
  const response = await fetch('YOUR_UPLOAD_ENDPOINT', {
    method: 'POST',
    headers: {
      'Authorization': 'Bearer YOUR_TOKEN' // 如果需要认证
    },
    body: formData
  });
  
  const data = await response.json();
  return data.url; // 返回图片 URL
}
```

## API 调用格式

上传成功后，调用 `window.row1.vision()` 时传入图片 URL：

```javascript
const result = await window.row1.vision({
  imageUrl: 'https://example.com/image.jpg', // 必须是可公开访问的 URL
  prompt: '请识别这张图片中的植物'
});
```

## 注意事项

1. **URL 必须可公开访问**：row1 平台需要能够访问该 URL 来下载图片
2. **支持 HTTPS**：建议使用 HTTPS URL
3. **文件大小限制**：注意云存储服务的文件大小限制
4. **认证**：如果使用需要认证的存储服务，确保 URL 包含必要的认证信息或使用公开访问链接

