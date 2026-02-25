# Micro-App 示例

## 植物养护助手

这是一个示例 Micro-App，演示如何使用 row1 平台的 JS Bridge API。

### 功能

1. **选择并上传图片**：用户选择植物照片后，应用自动上传到云存储
2. **识别植物**：使用视觉识别 API（传入图片 URL）识别植物种类和特征
3. **获取养护建议**：使用聊天 API 获取详细的养护指南

### 重要说明：图片上传

**row1 平台不提供文件上传功能**。所有 Micro-App 需要：
1. 自行实现图片上传逻辑（上传到云存储服务）
2. 获取图片的公开访问 URL
3. 将 URL 传递给 `window.row1.vision()` API

当前示例使用了免费的图床服务 sm.ms 作为演示。**实际部署时，请替换为您自己的上传服务**。

### 安装方法

1. 将 `plant-care.microapp` 目录打包成 zip 文件：
   ```bash
   cd plant-care.microapp
   zip -r ../plant-care.microapp.zip .
   ```

2. 在 row1 应用中：
   - 打开「市场」页面
   - 点击「安装本地包」
   - 选择 `plant-care.microapp.zip` 文件

3. 安装完成后，在侧边栏「已安装」中可以看到「植物养护助手」

### 使用方法

1. 点击侧边栏中的「植物养护助手」
2. 点击「选择植物图片」按钮，选择一张植物照片
3. 应用会自动上传图片到云存储（当前使用 sm.ms）
4. 上传成功后，点击「识别植物」按钮，等待识别结果
5. 识别成功后，点击「获取养护建议」获取详细的养护指南

### API 使用示例

这个示例应用使用了以下 row1 Bridge API：

- `window.row1.vision({ imageUrl, prompt })` - 视觉识别（需要图片 URL）
- `window.row1.chat({ messages, ... })` - AI 对话
- `window.row1.showToast(message)` - 显示提示

**注意**：`vision()` API 需要图片的公开访问 URL，不支持 base64 或本地文件路径。

### 自定义上传服务

修改 `static/app.js` 中的 `uploadImage()` 函数，替换为您自己的上传逻辑：

```javascript
async function uploadImage(file) {
  // 使用您的云存储服务
  const formData = new FormData();
  formData.append('file', file);
  
  const response = await fetch('YOUR_UPLOAD_ENDPOINT', {
    method: 'POST',
    headers: {
      'Authorization': 'Bearer YOUR_TOKEN'
    },
    body: formData
  });
  
  const data = await response.json();
  return data.url; // 返回可公开访问的图片 URL
}
```

详细说明请参考 `static/README.md`。

