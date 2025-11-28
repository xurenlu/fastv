#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
说话人分离 API 服务
自动检测和安装依赖，提供说话人分离功能
"""

import os
import sys
import tempfile
import traceback
from pathlib import Path

# 设置代理（如果需要）
proxy_env = {
    "https_proxy": "http://127.0.0.1:7890",
    "http_proxy": "http://127.0.0.1:7890",
    "all_proxy": "socks5://127.0.0.1:7890"
}
for key, value in proxy_env.items():
    if key not in os.environ:
        os.environ[key] = value

# 检查并安装依赖
def check_and_install_dependencies():
    """检查并自动安装必要的依赖"""
    try:
        import fastapi
        import uvicorn
        import pyannote.audio
        print("✅ 所有依赖已安装")
        return True
    except ImportError as e:
        print(f"⚠️  缺少依赖: {e}")
        print("正在自动安装依赖...")
        
        import subprocess
        try:
            # 安装依赖
            subprocess.check_call([
                sys.executable, "-m", "pip", "install", 
                "--user", "--quiet",
                "fastapi", "uvicorn[standard]", "pyannote.audio", "torch", "torchaudio"
            ])
            print("✅ 依赖安装完成")
            return True
        except subprocess.CalledProcessError as e:
            print(f"❌ 依赖安装失败: {e}")
            return False

# 检查依赖
if not check_and_install_dependencies():
    print("❌ 无法安装依赖，请手动运行: pip3 install --user fastapi uvicorn pyannote.audio torch torchaudio")
    sys.exit(1)

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse
from typing import Optional
import uvicorn

app = FastAPI(title="说话人分离 API", version="1.0.0")

# 全局变量：延迟加载模型
_pipeline = None
_model_loading = False

def get_pipeline():
    """获取或加载说话人分离模型（延迟加载）"""
    global _pipeline, _model_loading
    
    if _pipeline is not None:
        return _pipeline
    
    if _model_loading:
        # 如果正在加载，等待
        import time
        while _model_loading:
            time.sleep(0.1)
        return _pipeline
    
    try:
        _model_loading = True
        print("📦 正在加载说话人分离模型（首次使用需要下载，可能需要几分钟）...")
        
        from pyannote.audio import Pipeline
        
        # 使用 pyannote.audio 3.1 模型
        # 注意：首次使用需要从 HuggingFace 下载模型（约 500MB）
        # 需要 HuggingFace token（可选，但推荐）
        pipeline = Pipeline.from_pretrained(
            "pyannote/speaker-diarization-3.1",
            use_auth_token=None  # 如果需要，可以设置 HF_TOKEN 环境变量
        )
        
        _pipeline = pipeline
        print("✅ 说话人分离模型加载完成")
        return pipeline
    except Exception as e:
        _model_loading = False
        print(f"❌ 模型加载失败: {e}")
        traceback.print_exc()
        raise
    finally:
        _model_loading = False


@app.get("/")
async def root():
    """API 信息"""
    return {
        "service": "说话人分离 API",
        "version": "1.0.0",
        "status": "running",
        "endpoints": {
            "/api/v1/diarization": "POST - 对音频文件进行说话人分离",
            "/health": "GET - 健康检查"
        }
    }


@app.get("/health")
async def health():
    """健康检查"""
    try:
        # 尝试加载模型（如果还没加载）
        pipeline = get_pipeline()
        return {
            "status": "healthy",
            "model_loaded": pipeline is not None
        }
    except Exception as e:
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "error": str(e)
            }
        )


@app.post("/api/v1/diarization")
async def diarize_audio(
    file: UploadFile = File(..., description="音频文件（WAV/MP3/M4A等）"),
    min_speakers: Optional[int] = None,
    max_speakers: Optional[int] = None
):
    """
    对音频文件进行说话人分离
    
    参数:
    - file: 音频文件
    - min_speakers: 最小说话人数量（可选）
    - max_speakers: 最大说话人数量（可选）
    
    返回:
    - segments: 说话人片段列表，每个片段包含 start, end, speaker
    """
    temp_file = None
    try:
        # 保存上传的文件到临时文件
        suffix = Path(file.filename).suffix if file.filename else ".wav"
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            content = await file.read()
            tmp.write(content)
            temp_file = tmp.name
        
        print(f"📝 处理音频文件: {file.filename} ({len(content)} bytes)")
        
        # 加载模型（如果还没加载）
        pipeline = get_pipeline()
        
        # 准备参数
        diarization_kwargs = {}
        if min_speakers is not None:
            diarization_kwargs["min_speakers"] = min_speakers
        if max_speakers is not None:
            diarization_kwargs["max_speakers"] = max_speakers
        
        # 执行说话人分离
        print("🔄 开始说话人分离...")
        diarization = pipeline(temp_file, **diarization_kwargs)
        
        # 转换为 JSON 格式
        segments = []
        for turn, _, speaker in diarization.itertracks(yield_label=True):
            segments.append({
                "start": round(turn.start, 2),
                "end": round(turn.end, 2),
                "speaker": speaker,
                "duration": round(turn.end - turn.start, 2)
            })
        
        print(f"✅ 说话人分离完成，识别到 {len(set(s['speaker'] for s in segments))} 个说话人，共 {len(segments)} 个片段")
        
        return {
            "success": True,
            "segments": segments,
            "speaker_count": len(set(s["speaker"] for s in segments)),
            "total_segments": len(segments)
        }
        
    except Exception as e:
        print(f"❌ 说话人分离失败: {e}")
        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail=f"说话人分离失败: {str(e)}"
        )
    finally:
        # 清理临时文件
        if temp_file and os.path.exists(temp_file):
            try:
                os.unlink(temp_file)
            except:
                pass


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="说话人分离 API 服务")
    parser.add_argument("--host", default="127.0.0.1", help="监听地址")
    parser.add_argument("--port", type=int, default=50001, help="监听端口")
    parser.add_argument("--reload", action="store_true", help="开发模式（自动重载）")
    
    args = parser.parse_args()
    
    print("=" * 60)
    print("说话人分离 API 服务")
    print("=" * 60)
    print(f"服务地址: http://{args.host}:{args.port}")
    print(f"API 文档: http://{args.host}:{args.port}/docs")
    print("=" * 60)
    print("\n提示：首次使用时会自动下载模型（约 500MB），请耐心等待...")
    print("按 Ctrl+C 停止服务\n")
    
    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        reload=args.reload,
        log_level="info"
    )

