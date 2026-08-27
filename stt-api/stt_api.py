#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FastV STT API 服务
聚焦语音输入与语音转文字能力暴露：
- HTTP: POST /api/v1/transcribe 接受 MP3/WAV 等音频文件
- WebSocket: /ws/transcribe 流式边说边转（停顿检测）
"""

import asyncio
import io
import logging
import os
import tempfile
import threading
from pathlib import Path
from typing import Literal, Optional

from fastapi import FastAPI, File, UploadFile, HTTPException, WebSocket, WebSocketDisconnect, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
import uvicorn

# 上传体积上限：50 MB
MAX_UPLOAD_BYTES = 50 * 1024 * 1024

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# 版本号（与主项目保持一致）
API_VERSION = "2.5.0-rc5"

app = FastAPI(
    title="FastV STT API",
    version=API_VERSION,
    description="语音转文字 API：HTTP 文件上传 + WebSocket 流式边说边转",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class BodySizeLimitMiddleware(BaseHTTPMiddleware):
    """拒绝任何 Content-Length 超过 MAX_UPLOAD_BYTES 的 HTTP 请求。"""

    async def dispatch(self, request: Request, call_next):
        cl = request.headers.get("content-length")
        if cl is not None:
            try:
                if int(cl) > MAX_UPLOAD_BYTES:
                    return JSONResponse(
                        status_code=413,
                        content={
                            "detail": f"上传文件过大，限制 {MAX_UPLOAD_BYTES // (1024 * 1024)} MB"
                        },
                    )
            except ValueError:
                pass
        return await call_next(request)


app.add_middleware(BodySizeLimitMiddleware)


@app.middleware("http")
async def add_version_header(request, call_next):
    """为所有响应添加版本号 header"""
    response = await call_next(request)
    response.headers["X-API-Version"] = API_VERSION
    return response

# 全局模型（延迟加载，跨连接共享 _model / _frontend；_vad 改为每连接独立实例）
_model = None
_frontend = None
_download_path: Optional[str] = None
_model_load_lock = threading.Lock()


def _get_download_path() -> str:
    global _download_path
    if _download_path is None:
        _download_path = os.environ.get(
            "SENSEVOICE_MODEL_PATH",
            os.path.join(os.path.dirname(__file__), "resource"),
        )
    return _download_path


def _ensure_model():
    """延迟加载 SenseVoice 模型。线程安全：用 threading.Lock 防止并发首请求重复加载。"""
    global _model, _frontend

    if _model is not None:
        return

    with _model_load_lock:
        if _model is not None:
            return

        logger.info("正在加载 SenseVoice 模型...")

        from huggingface_hub import snapshot_download

        download_path = _get_download_path()
        if not os.path.exists(download_path):
            logger.info("从 HuggingFace 下载模型（可设置 HF_ENDPOINT=https://hf-mirror.com 加速）...")
            snapshot_download(
                repo_id="lovemefan/SenseVoice-onnx",
                local_dir=download_path,
            )

        from sensevoice.onnx.sense_voice_ort_session import SenseVoiceInferenceSession
        from sensevoice.utils.frontend import WavFrontend

        am_mvn = os.path.join(download_path, "am.mvn")
        encoder = os.path.join(download_path, "sense-voice-encoder.onnx")
        embedding = os.path.join(download_path, "embedding.npy")
        bpe_model = os.path.join(download_path, "chn_jpn_yue_eng_ko_spectok.bpe.model")

        _frontend = WavFrontend(am_mvn)
        _model = SenseVoiceInferenceSession(
            embedding,
            encoder,
            bpe_model,
            device=-1,
            num_threads=4,
        )

        logger.info("SenseVoice 模型加载完成")


def _make_vad():
    """每个 WS 连接 / 每次 HTTP 转写各自一份 FSMNVad，避免共享状态被互相 reset。"""
    from sensevoice.utils.fsmn_vad import FSMNVad
    return FSMNVad(_get_download_path())


# 语言映射（与 sensevoice 一致）
LANGUAGES = {"auto": 0, "zh": 3, "en": 4, "yue": 7, "ja": 11, "ko": 12, "nospeech": 13}


def _preprocess_audio_to_wav(audio_bytes: bytes, suffix: str = ".wav") -> str:
    """将 MP3/WAV/M4A 等转为 16kHz 单声道 WAV 临时文件路径。MP3/M4A 需系统安装 ffmpeg。"""
    from pydub import AudioSegment

    suffix = suffix.lower()
    if suffix not in (".mp3", ".wav", ".m4a", ".ogg", ".flac"):
        suffix = ".wav"

    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(audio_bytes)
        tmp_path = tmp.name

    try:
        audio = AudioSegment.from_file(tmp_path)
        audio = audio.set_frame_rate(16000).set_channels(1)
        wav_bytes = io.BytesIO()
        audio.export(wav_bytes, format="wav")
        wav_bytes.seek(0)

        out_path = tmp_path + ".16k.wav"
        with open(out_path, "wb") as f:
            f.write(wav_bytes.read())
        os.unlink(tmp_path)
        return out_path
    except Exception as e:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise RuntimeError(f"音频预处理失败: {e}") from e


def _transcribe_file(wav_path: str, language: str = "auto", vad=None) -> str:
    """对 WAV 文件执行转录。`vad` 为可选独立实例；None 时临时新建一份，避免与并发请求共享状态。"""
    import soundfile as sf

    _ensure_model()
    own_vad = vad if vad is not None else _make_vad()
    waveform, _ = sf.read(wav_path, dtype="float32", always_2d=True)

    # 单声道
    if waveform.ndim > 1:
        channel_data = waveform[:, 0]
    else:
        channel_data = waveform

    segments = own_vad.segments_offline(channel_data)
    results = []
    for part in segments:
        audio_feats = _frontend.get_features(channel_data[part[0] * 16 : part[1] * 16])
        lang_id = LANGUAGES.get(language, 0)
        asr_result = _model(
            audio_feats[None, ...],
            language=lang_id,
            use_itn=True,
        )
        # 清理 SenseVoice 特殊 token
        text = _clean_sensevoice_result(asr_result)
        if text:
            results.append(text)
        own_vad.vad.all_reset_detection()

    return "".join(results) if results else ""


def _clean_sensevoice_result(raw: str) -> str:
    """移除 SenseVoice 输出中的特殊 token"""
    import re
    # 移除 <|zh|><|NEUTRAL|><|Speech|><|woitn|> 等
    return re.sub(r"<\|[^|]+\|>", "", raw).strip()


@app.get("/")
async def root():
    """API 信息"""
    return {
        "service": "FastV STT API",
        "version": API_VERSION,
        "status": "running",
        "endpoints": {
            "/api/v1/transcribe": "POST - 上传音频文件转文字（MP3/WAV/M4A）",
            "/ws/transcribe": "WebSocket - 流式边说边转（停顿检测）",
            "/health": "GET - 健康检查",
        },
        "docs": {"swagger": "/docs", "redoc": "/redoc"},
    }


@app.get("/health")
async def health():
    """健康检查"""
    try:
        _ensure_model()
        return {"status": "healthy", "model_loaded": _model is not None}
    except Exception as e:
        logger.error(f"健康检查失败: {e}")
        return JSONResponse(
            status_code=503,
            content={"status": "unhealthy", "error": str(e)},
        )


@app.post("/api/v1/transcribe")
async def transcribe_file(
    file: UploadFile = File(..., description="音频文件（MP3/WAV/M4A 等）"),
    language: Literal["auto", "zh", "en", "yue", "ja", "ko"] = "auto",
):
    """
    上传音频文件，返回转写文本。
    支持 MP3、WAV、M4A、OGG、FLAC 等格式。
    """
    temp_path = None
    try:
        # 分块读取，避免一次性把大文件读进内存触发 OOM
        content = bytearray()
        while True:
            chunk = await file.read(1 << 20)  # 1MB
            if not chunk:
                break
            if len(content) + len(chunk) > MAX_UPLOAD_BYTES:
                raise HTTPException(
                    status_code=413,
                    detail=f"上传文件过大，限制 {MAX_UPLOAD_BYTES // (1024 * 1024)} MB",
                )
            content.extend(chunk)
        if not content:
            raise HTTPException(status_code=400, detail="文件为空")

        suffix = Path(file.filename or "").suffix or ".wav"
        temp_path = _preprocess_audio_to_wav(bytes(content), suffix)

        try:
            text = _transcribe_file(temp_path, language)
            return {
                "success": True,
                "text": text,
                "language": language,
            }
        finally:
            if temp_path and os.path.exists(temp_path):
                os.unlink(temp_path)

    except HTTPException:
        raise
    except Exception:
        # detail 不暴露内部 traceback / 路径；详细错误进服务端 log
        logger.exception("转录失败")
        raise HTTPException(status_code=500, detail="转录失败，请稍后重试")


def _transcribe_pcm(pcm_bytes: bytes, sample_rate: int = 16000, vad=None) -> str:
    """对 PCM 16kHz 单声道 int16 数据执行转录。不再走临时 wav，直接喂 frontend。"""
    import numpy as np

    _ensure_model()
    own_vad = vad if vad is not None else _make_vad()
    samples = np.frombuffer(pcm_bytes, dtype=np.int16).astype(np.float32) / 32768

    segments = own_vad.segments_offline(samples)
    results = []
    for part in segments:
        audio_feats = _frontend.get_features(samples[part[0] * 16 : part[1] * 16])
        asr_result = _model(
            audio_feats[None, ...],
            language=LANGUAGES.get("auto", 0),
            use_itn=True,
        )
        text = _clean_sensevoice_result(asr_result)
        if text:
            results.append(text)
        own_vad.vad.all_reset_detection()
    return "".join(results)


@app.websocket("/ws/transcribe")
async def websocket_transcribe(websocket: WebSocket):
    """
    流式语音转文字：客户端持续发送 PCM 16kHz 单声道 int16 音频数据，
    服务端按段转写并推送。检测到停顿（约 1.5s 静音）或缓冲满（约 3s）时转写。
    控制消息：发送 JSON {"type":"end"} 结束并转写剩余内容。
    """
    await websocket.accept()

    try:
        _ensure_model()
    except Exception as e:
        await websocket.send_json({"type": "error", "message": str(e)})
        await websocket.close()
        return

    import json
    import numpy as np

    # 每个 WS 连接独立 VAD，避免与其他并发连接互相 reset 检测状态
    connection_vad = _make_vad()

    buffer = bytearray()
    sample_rate = 16000
    bytes_per_sec = sample_rate * 2  # 16bit
    min_segment_bytes = int(1.0 * bytes_per_sec)   # 至少 1 秒才转写
    max_buffer_bytes = int(3.0 * bytes_per_sec)   # 约 3 秒自动转写
    silence_threshold = 0.008
    silence_chunk_count = 0

    async def _try_transcribe():
        nonlocal buffer, silence_chunk_count
        if len(buffer) < min_segment_bytes:
            return
        data = bytes(buffer)
        buffer.clear()
        silence_chunk_count = 0
        try:
            text = _transcribe_pcm(data, sample_rate, vad=connection_vad)
            if text:
                await websocket.send_json({"type": "segment", "text": text})
        except Exception as e:
            logger.warning(f"片段转写失败: {e}")

    try:
        while True:
            try:
                msg = await websocket.receive()
            except WebSocketDisconnect:
                break

            if "bytes" in msg and msg["bytes"]:
                data = msg["bytes"]
                buffer.extend(data)

                # 静音检测：本块 RMS 低则计数
                arr = np.frombuffer(data, dtype=np.int16)
                rms = np.sqrt(np.mean(arr.astype(np.float32) ** 2)) / 32768
                if rms < silence_threshold:
                    silence_chunk_count += 1
                else:
                    silence_chunk_count = 0

                # 条件1：缓冲满 -> 转写
                if len(buffer) >= max_buffer_bytes:
                    await _try_transcribe()
                # 条件2：连续多块静音（约 1.5s）-> 转写
                elif silence_chunk_count >= 3 and len(buffer) >= min_segment_bytes:
                    await _try_transcribe()

            elif "text" in msg:
                try:
                    obj = json.loads(msg["text"])
                    if obj.get("type") == "end":
                        if len(buffer) >= min_segment_bytes:
                            await _try_transcribe()
                        await websocket.send_json({"type": "done"})
                        break
                except Exception:
                    pass

    except WebSocketDisconnect:
        pass
    except Exception:
        logger.exception("WebSocket 异常")
        try:
            await websocket.send_json({"type": "error", "message": "服务端异常"})
        except Exception:
            pass
    finally:
        try:
            await websocket.close()
        except Exception:
            pass


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="FastV STT API 服务")
    parser.add_argument("--host", default="127.0.0.1", help="监听地址")
    parser.add_argument("--port", type=int, default=50002, help="监听端口")
    parser.add_argument("--reload", action="store_true", help="开发模式（自动重载）")

    args = parser.parse_args()

    print("=" * 60)
    print("FastV STT API 服务")
    print("=" * 60)
    print(f"服务地址: http://{args.host}:{args.port}")
    print(f"API 文档: http://{args.host}:{args.port}/docs")
    print("=" * 60)
    print("\n端点:")
    print("  POST /api/v1/transcribe - 上传音频文件转文字")
    print("  WS   /ws/transcribe     - 流式边说边转")
    print("\n按 Ctrl+C 停止服务\n")

    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        reload=args.reload,
        log_level="info",
    )
