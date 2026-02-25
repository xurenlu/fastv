# 说话人分离服务

基于 FastAPI 的说话人分离 RESTful 服务，使用 `pyannote.audio` 3.1 模型实现高质量的说话人分离功能。

## 功能特性

- 🎤 自动识别和分离音频中的不同说话人
- 🚀 基于 FastAPI 的高性能 RESTful API
- 📦 使用 pyannote.audio 3.1 模型，准确度高
- 🔧 支持最小/最大说话人数量配置
- 📝 自动生成 API 文档

## 环境要求

- Python 3.8 或更高版本
- 约 2GB 可用磁盘空间（用于模型下载）
- 建议 4GB 以上内存

## 安装步骤

### 1. 创建虚拟环境

```bash
# 进入服务目录
cd SpeakerDiarization

# 创建虚拟环境
python3 -m venv venv

# 激活虚拟环境
# macOS/Linux:
source venv/bin/activate
# Windows:
# venv\Scripts\activate
```

### 2. 安装依赖

```bash
# 确保虚拟环境已激活，然后安装依赖
pip install -r requirements.txt
```

**注意：** 首次安装可能需要较长时间，因为需要下载 PyTorch 等大型依赖包。

### 3. 配置 HuggingFace Token（**必需**）

⚠️ **重要**：该模型需要 HuggingFace 认证才能访问，必须设置 token！

**步骤 1：获取 HuggingFace Token**

⚠️ **重要**：推荐使用 **Classic Token**（经典 token），而不是 Fine-grained Token（细粒度 token）

**推荐方式：使用 Classic Token**

1. 访问 https://huggingface.co/settings/tokens
2. 切换到 **"Classic tokens"** 标签页（不是 "Fine-grained tokens"）
3. 点击 "New token" 创建新 token
4. 填写名称（如：speaker-diarization），选择 **Read** 权限
5. 点击 "Generate token"，复制生成的 token（只显示一次，请妥善保存）

**如果使用 Fine-grained Token：**

如果必须使用 Fine-grained Token，需要额外配置：
1. 创建 token 后，点击编辑该 token
2. 在 "Repository access" 部分，启用 **"Public gated repositories"** 选项
3. 保存设置

**为什么推荐 Classic Token？**
- Classic Token 自动具有访问 gated repositories 的权限
- Fine-grained Token 需要手动配置，容易遗漏权限设置

**步骤 2：接受模型使用条款（重要）**

⚠️ **必须接受以下所有模型的使用条款**，否则无法访问：

1. 访问 https://huggingface.co/pyannote/speaker-diarization-3.1
   - 点击 "Agree and access repository" 接受使用条款
2. 访问 https://huggingface.co/pyannote/segmentation-3.0
   - 点击 "Agree and access repository" 接受使用条款

**注意**：`speaker-diarization-3.1` 依赖 `segmentation-3.0` 模型，两个模型的使用条款都需要接受。

**步骤 3：设置环境变量**

```bash
# 方式一：在当前终端会话中临时设置（fish shell）
set -x HF_TOKEN "your_huggingface_token_here"

# 方式二：永久设置（推荐，添加到 fish 配置文件）
echo 'set -x HF_TOKEN "your_huggingface_token_here"' >> ~/.config/fish/config.fish
source ~/.config/fish/config.fish

# 或者在 bash/zsh 中：
export HF_TOKEN="your_huggingface_token_here"
echo 'export HF_TOKEN="your_huggingface_token_here"' >> ~/.zshrc  # 或 ~/.bashrc
source ~/.zshrc
```

**验证设置：**

```bash
echo $HF_TOKEN  # 应该显示你的 token
```

### 4. 配置代理（如果需要）

如果需要通过代理访问 HuggingFace 下载模型：

```bash
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
export all_proxy=socks5://127.0.0.1:7890
```

## 启动服务

### 方式一：使用启动脚本（推荐）

```bash
# 确保虚拟环境已激活
source venv/bin/activate

# 运行启动脚本
./start.sh
```

### 方式二：直接运行 Python 脚本

```bash
# 确保虚拟环境已激活
source venv/bin/activate

# 运行服务
python speaker_diarization_api.py

# 或者指定主机和端口
python speaker_diarization_api.py --host 0.0.0.0 --port 50001
```

### 方式三：使用 uvicorn 直接启动

```bash
# 确保虚拟环境已激活
source venv/bin/activate

# 启动服务
uvicorn speaker_diarization_api:app --host 127.0.0.1 --port 50001
```

## 服务配置

### 命令行参数

- `--host`: 监听地址（默认: 127.0.0.1）
- `--port`: 监听端口（默认: 50001）
- `--reload`: 开发模式，自动重载（默认: False）

### 环境变量

- `HF_TOKEN`: HuggingFace token（**必需**，用于访问受限模型）
- `https_proxy`: HTTPS 代理地址（可选，如：http://127.0.0.1:7890）
- `http_proxy`: HTTP 代理地址（可选，如：http://127.0.0.1:7890）
- `all_proxy`: SOCKS5 代理地址（可选，如：socks5://127.0.0.1:7890）

## API 文档

服务启动后，访问以下地址查看交互式 API 文档：

- Swagger UI: http://127.0.0.1:50001/docs
- ReDoc: http://127.0.0.1:50001/redoc

## API 端点

### GET /

获取服务信息。

**响应示例：**
```json
{
  "service": "说话人分离 API",
  "version": "1.0.0",
  "status": "running",
  "endpoints": {
    "/api/v1/diarization": "POST - 对音频文件进行说话人分离",
    "/health": "GET - 健康检查"
  }
}
```

### GET /health

健康检查端点。

**响应示例：**
```json
{
  "status": "healthy",
  "model_loaded": true
}
```

### POST /api/v1/diarization

对音频文件进行说话人分离。

**请求参数：**
- `file` (multipart/form-data): 音频文件（支持 WAV/MP3/M4A 等格式）
- `min_speakers` (可选, int): 最小说话人数量
- `max_speakers` (可选, int): 最大说话人数量

**响应示例：**
```json
{
  "success": true,
  "segments": [
    {
      "start": 0.0,
      "end": 5.2,
      "speaker": "SPEAKER_00",
      "duration": 5.2
    },
    {
      "start": 5.2,
      "end": 10.5,
      "speaker": "SPEAKER_01",
      "duration": 5.3
    }
  ],
  "speaker_count": 2,
  "total_segments": 2
}
```

**使用示例：**

```bash
# 使用 curl 测试
curl -X POST "http://127.0.0.1:50001/api/v1/diarization" \
  -F "file=@audio.wav" \
  -F "min_speakers=2" \
  -F "max_speakers=5"
```

## 首次使用说明

首次运行时，服务会自动从 HuggingFace 下载模型文件（约 500MB）。下载过程可能需要几分钟，请耐心等待。下载完成后，模型会缓存到本地，后续启动会更快。

## 常见问题

### 1. 模型下载失败 / 访问受限错误 (403 Forbidden)

**错误信息示例：**
```
403 Forbidden: Please enable access to public gated repositories...
Cannot access gated repo...
Access to model pyannote/speaker-diarization-3.1 is restricted...
```

**解决方法：**

**情况 A：使用了 Fine-grained Token**
- 错误信息包含 "fine-grained token" 或 "public gated repositories"
- **解决方法**：
  1. 访问 https://huggingface.co/settings/tokens
  2. 找到你的 fine-grained token，点击编辑
  3. 在 "Repository access" 部分，启用 **"Public gated repositories"**
  4. 保存设置并重启服务
- **或者**：改用 Classic Token（推荐，见下方）

**情况 B：使用 Classic Token 但仍报错**
1. ✅ **确保已设置 HF_TOKEN**：`echo $HF_TOKEN` 应该显示你的 token
2. ✅ **确保已接受所有模型使用条款**：
   - https://huggingface.co/pyannote/speaker-diarization-3.1
   - https://huggingface.co/pyannote/segmentation-3.0
   - 在每个页面点击 "Agree and access repository"
3. ✅ **检查 token 类型**：确保使用的是 Classic Token，不是 Fine-grained Token
4. ✅ **检查 token 权限**：确保 token 有 Read 权限
5. ✅ **检查网络连接**：如果在中国大陆，可能需要配置代理
6. ✅ **重启服务**：设置环境变量后需要重启服务才能生效
7. ✅ **查看启动日志**：服务启动时会显示 token 状态（部分隐藏）

**推荐解决方案：**
如果遇到权限问题，最简单的方法是创建一个新的 **Classic Token**：
1. 访问 https://huggingface.co/settings/tokens
2. 切换到 "Classic tokens" 标签页
3. 创建新 token，选择 Read 权限
4. 替换旧的 HF_TOKEN 环境变量

### 2. 内存不足

- 关闭其他占用内存的程序
- 考虑使用更小的模型（需要修改代码）
- 增加系统内存或使用交换空间

### 3. 端口被占用

- 使用 `--port` 参数指定其他端口
- 检查是否有其他服务在使用该端口：`lsof -i :50001`

### 4. PyTorch 2.6 兼容性问题

**错误信息示例：**
```
Weights only load failed...
Unsupported global: GLOBAL torch.torch_version.TorchVersion...
```

**原因：** PyTorch 2.6 改变了 `torch.load` 的默认行为，导致某些模型无法加载。

**解决方法：**

**方法一：降级 PyTorch（推荐）**
```bash
pip install 'torch<2.6' 'torchaudio<2.6'
```

**方法二：使用代码自动修复**
代码已包含自动兼容性修复，如果仍失败，请使用方法一。

### 5. 依赖安装失败

- 确保 Python 版本 >= 3.8
- 升级 pip: `pip install --upgrade pip`
- 尝试使用国内镜像源：
  ```bash
  pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
  ```

## 性能优化建议

1. **模型缓存**: 首次下载后，模型会缓存在本地，后续启动更快
2. **批处理**: 对于多个文件，可以考虑实现批处理接口
3. **GPU 加速**: 如果系统有 GPU，PyTorch 会自动使用 GPU 加速

## 许可证

请参考项目主目录的许可证文件。

## 技术支持

如有问题，请查看项目文档或提交 Issue。

