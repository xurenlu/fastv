# Micro-App 示例

## 植物养护助手

这是一个示例 Micro-App，演示如何使用 row1 平台的 JS Bridge API。

### 功能

1. **选择图片**：用户可以选择一张植物照片
2. **识别植物**：使用视觉识别 API 识别植物种类和特征
3. **获取养护建议**：使用聊天 API 获取详细的养护指南

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
3. 点击「识别植物」按钮，等待识别结果
4. 识别成功后，点击「获取养护建议」获取详细的养护指南

### API 使用示例

这个示例应用使用了以下 row1 Bridge API：

- `window.row1.pickImage()` - 选择图片
- `window.row1.vision()` - 视觉识别
- `window.row1.chat()` - AI 对话
- `window.row1.showToast()` - 显示提示

详细 API 文档请参考主应用的文档。

