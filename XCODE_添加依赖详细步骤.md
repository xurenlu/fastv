# Xcode 中添加 Swift Package 详细步骤

## 方法 1：通过项目设置添加（推荐）

### 步骤详解

1. **打开项目**
   ```bash
   open fastv.xcodeproj
   ```

2. **选择项目文件**
   - 在左侧项目导航器中，点击最顶部的 **蓝色图标**（项目名称 "fastv"）
   - 不是文件夹，是项目文件本身

3. **查看右侧面板**
   - 选择项目文件后，右侧会显示项目设置面板
   - 如果没有显示，点击右上角的 **"Show the File inspector"** 按钮（或按 `⌥⌘1`）

4. **找到 Package Dependencies**
   - 在项目设置面板中，你会看到多个标签页：
     - **General**（常规）
     - **Signing & Capabilities**（签名）
     - **Build Settings**（构建设置）
     - **Build Phases**（构建阶段）
     - **Build Rules**（构建规则）
     - **Info**（信息）
     - **Package Dependencies**（包依赖）← 这个！
   
   - 如果看不到 "Package Dependencies"，可能是：
     - Xcode 版本较旧（需要 Xcode 12+）
     - 需要先选择 Target

5. **选择 Target**
   - 在项目设置面板的顶部，有一个 **TARGETS** 列表
   - 选择 **"fastv"**（不是 fastvTests 或 fastvUITests）

6. **添加 Package**
   - 切换到 **"Package Dependencies"** 标签
   - 点击左下角的 **"+"** 按钮
   - 在搜索框输入：`https://github.com/microsoft/onnxruntime-swift`
   - 选择版本并添加

## 方法 2：通过菜单添加

1. **打开项目后**
2. **菜单栏** → **File** → **Add Package Dependencies...**
3. 输入 URL：`https://github.com/microsoft/onnxruntime-swift`
4. 选择版本并添加

## 方法 3：如果以上都不行

### 检查 Xcode 版本

```bash
xcodebuild -version
```

需要 Xcode 12.0 或更高版本。

### 如果 Xcode 版本较旧

可以尝试手动编辑项目文件，或者升级 Xcode。

## 截图说明位置

项目文件选择后，你应该看到：

```
┌─────────────────────────────────────┐
│  fastv (项目图标)                    │ ← 点击这个蓝色图标
├─────────────────────────────────────┤
│  TARGETS                            │
│  ☑ fastv                            │ ← 选择这个
│  ☐ fastvTests                       │
│  ☐ fastvUITests                     │
├─────────────────────────────────────┤
│  [标签页]                            │
│  General | Signing | Build Settings │
│  Build Phases | Package Dependencies│ ← 点击这个
│  Info | ...                         │
└─────────────────────────────────────┘
```

## 如果仍然找不到

请告诉我：
1. 你的 Xcode 版本（菜单栏 → About Xcode）
2. 选择项目文件后，右侧面板显示了哪些标签页
3. 是否有看到 "TARGETS" 列表

我可以根据你的具体情况提供更精确的指导。

