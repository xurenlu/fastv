# FastV STT API

聚焦语音输入与语音转文字能力暴露，提供 HTTP 与 WebSocket 接口。

## 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/v1/transcribe` | 上传音频文件（MP3/WAV/M4A 等）转文字 |
| WS | `/ws/transcribe` | 流式边说边转，停顿检测自动分段 |

## 快速开始

### 1. 安装依赖

```bash
cd stt-api
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

**注意**：MP3/M4A 等格式需要系统安装 [ffmpeg](https://ffmpeg.org/)。

### 2. 启动服务

```bash
python stt_api.py --host 127.0.0.1 --port 50002
```

首次运行会自动从 HuggingFace 下载 SenseVoice 模型。可设置 `HF_ENDPOINT=https://hf-mirror.com` 加速。

### 3. HTTP 接口示例

```bash
curl -X POST "http://127.0.0.1:50002/api/v1/transcribe?language=auto" \
  -F "file=@your_audio.mp3"
```

### 4. WebSocket 流式示例

客户端发送：
- **二进制**：PCM 16kHz 单声道 int16 音频数据
- **文本**：`{"type":"end"}` 结束会话

服务端推送：
- `{"type":"segment","text":"..."}` 每段转写结果
- `{"type":"done"}` 会话结束
- `{"type":"error","message":"..."}` 错误

## 版本

与主项目保持一致，通过 `X-API-Version` header 返回。
