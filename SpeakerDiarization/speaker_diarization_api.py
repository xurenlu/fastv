#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
说话人分离 API 服务
基于 FastAPI 的 RESTful 服务，使用 pyannote.audio 3.1 模型
"""

import os
import sys
import tempfile
import traceback
import logging
from pathlib import Path
from typing import Optional

# 修复 PyTorch 2.6 兼容性问题（必须在导入其他库之前执行）
try:
    import torch
    import torch.torch_version
    
    # 检查是否是 PyTorch 2.6+
    torch_version = torch.__version__.split('.')
    is_pytorch_26_plus = False
    if len(torch_version) >= 2:
        major, minor = int(torch_version[0]), int(torch_version[1])
        is_pytorch_26_plus = major > 2 or (major == 2 and minor >= 6)
    
    if is_pytorch_26_plus:
        # 方法1：尝试使用 add_safe_globals
        if hasattr(torch.serialization, 'add_safe_globals'):
            try:
                torch.serialization.add_safe_globals([torch.torch_version.TorchVersion])
            except Exception:
                pass
        
        # 方法2：Monkey patch torch.load
        original_torch_load = torch.load
        
        def patched_torch_load(*args, **kwargs):
            # 如果 weights_only 未指定，设置为 False（信任 HuggingFace 模型）
            if 'weights_only' not in kwargs:
                kwargs['weights_only'] = False
            return original_torch_load(*args, **kwargs)
        
        torch.load = patched_torch_load
except Exception:
    # 如果修复失败，继续执行（可能不是 PyTorch 2.6+）
    pass

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="说话人分离 API",
    version="1.0.0",
    description="基于 pyannote.audio 的说话人分离服务"
)

# 添加 CORS 支持
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 生产环境建议限制具体域名
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup_event():
    """启动时打印 token 信息"""
    print_startup_info()

# 全局变量：延迟加载模型
_pipeline = None
_model_loading = False


def mask_token(token: Optional[str]) -> str:
    """安全地显示 token（只显示前4位和后4位）"""
    if not token:
        return "未设置"
    if len(token) <= 8:
        return "***"  # 太短，完全隐藏
    return f"{token[:4]}...{token[-4:]}"


def print_startup_info():
    """打印启动信息，包括 token 状态"""
    hf_token = os.environ.get("HF_TOKEN")
    logger.info("=" * 60)
    logger.info("说话人分离 API 服务启动")
    logger.info("=" * 60)
    logger.info(f"HuggingFace Token: {mask_token(hf_token)}")
    if hf_token:
        logger.info("✅ Token 已设置")
    else:
        logger.warning("⚠️  Token 未设置，模型可能无法加载")
    logger.info("=" * 60)


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
        logger.info("正在加载说话人分离模型（首次使用需要下载，可能需要几分钟）...")
        
        from pyannote.audio import Pipeline
        
        # 获取 HuggingFace token（如果设置了环境变量）
        hf_token = os.environ.get("HF_TOKEN")
        
        # 检查 token 是否设置
        if not hf_token:
            error_msg = (
                "❌ HuggingFace token 未设置！\n"
                "该模型需要 HuggingFace 认证才能访问。请按以下步骤设置：\n"
                "1. 访问 https://huggingface.co/settings/tokens 创建 token（需要 read 权限）\n"
                "2. 访问 https://huggingface.co/pyannote/speaker-diarization-3.1 接受模型使用条款\n"
                "3. 访问 https://huggingface.co/pyannote/segmentation-3.0 接受模型使用条款\n"
                "4. 设置环境变量：export HF_TOKEN='your_token_here'\n"
                "5. 重启服务\n"
                "或者临时设置：HF_TOKEN='your_token' python speaker_diarization_api.py"
            )
            logger.error(error_msg)
            raise ValueError(error_msg)
        
        # 使用 pyannote.audio 3.1 模型
        # 注意：首次使用需要从 HuggingFace 下载模型（约 500MB）
        logger.info(f"从 HuggingFace 加载模型 (token: {mask_token(hf_token)})...")
        pipeline = Pipeline.from_pretrained(
            "pyannote/speaker-diarization-3.1",
            token=hf_token
        )
        
        _pipeline = pipeline
        logger.info("✅ 说话人分离模型加载完成")
        return pipeline
    except ValueError:
        # 重新抛出 ValueError（token 未设置）
        _model_loading = False
        raise
    except Exception as e:
        _model_loading = False
        error_str = str(e)
        error_lower = error_str.lower()
        
        # 检查是否是 PyTorch 2.6 weights_only 兼容性问题
        if "weights_only" in error_lower or "torch.torch_version.torchversion" in error_lower or "unsupported global" in error_lower:
            error_msg = (
                "❌ PyTorch 2.6 兼容性问题：模型加载失败\n\n"
                "这是因为 PyTorch 2.6 改变了 torch.load 的默认行为。\n\n"
                "解决方法（二选一）：\n\n"
                "方法一：降级 PyTorch（推荐）\n"
                "pip install 'torch<2.6' 'torchaudio<2.6'\n\n"
                "方法二：更新代码（已尝试自动修复，如果仍失败请使用方法一）\n"
                "代码已尝试设置安全全局对象，如果仍失败，请降级 PyTorch 版本\n\n"
                f"当前错误详情：{error_str[:200]}"
            )
            logger.error(error_msg)
            raise ValueError(error_msg)
        
        # 检查是否是 fine-grained token 权限问题
        if "fine-grained token" in error_lower or "public gated repositories" in error_lower or "enable access to public gated" in error_lower:
            error_msg = (
                "❌ Token 权限不足：fine-grained token 需要启用 'public gated repositories' 权限\n\n"
                "解决方法（二选一）：\n\n"
                "方法一：使用 Classic Token（推荐）\n"
                "1. 访问 https://huggingface.co/settings/tokens\n"
                "2. 切换到 'Classic tokens' 标签页\n"
                "3. 点击 'New token'，选择 'Read' 权限\n"
                "4. 复制 token 并设置：export HF_TOKEN='your_classic_token'\n\n"
                "方法二：修改 Fine-grained Token 权限\n"
                "1. 访问 https://huggingface.co/settings/tokens\n"
                "2. 找到你的 fine-grained token，点击编辑\n"
                "3. 在 'Repository access' 部分，启用 'Public gated repositories'\n"
                "4. 保存设置\n\n"
                "然后确保：\n"
                "- 已访问 https://huggingface.co/pyannote/speaker-diarization-3.1 并接受使用条款\n"
                "- 重启服务"
            )
            logger.error(error_msg)
            raise ValueError(error_msg)
        
        # 检查是否是访问受限错误
        if "gated repo" in error_lower or "restricted" in error_lower or "authenticated" in error_lower or "403" in error_str:
            # 检查具体是哪个模型访问失败
            failed_model = None
            if "segmentation-3.0" in error_str:
                failed_model = "pyannote/segmentation-3.0"
            elif "speaker-diarization-3.1" in error_str:
                failed_model = "pyannote/speaker-diarization-3.1"
            
            error_msg = (
                f"❌ 模型访问受限 (403 Forbidden)\n"
            )
            if failed_model:
                error_msg += f"访问失败的模型: {failed_model}\n\n"
            
            error_msg += (
                "可能的原因：\n"
                "1. Token 权限不足（fine-grained token 需要启用 'public gated repositories'）\n"
                "2. 未接受模型使用条款\n"
                "3. Token 已过期或无效\n\n"
                "解决步骤：\n"
                "1. 访问以下链接接受所有模型的使用条款：\n"
                "   - https://huggingface.co/pyannote/speaker-diarization-3.1\n"
                "   - https://huggingface.co/pyannote/segmentation-3.0\n"
                "   在每个页面点击 'Agree and access repository'\n"
                "2. 使用 Classic Token（推荐）或启用 fine-grained token 的 'public gated repositories' 权限\n"
                f"3. 验证 token：当前 token = {mask_token(hf_token)}\n"
                "4. 重启服务"
            )
            logger.error(error_msg)
            raise ValueError(error_msg)
        
        logger.error(f"❌ 模型加载失败: {e}")
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
        },
        "docs": {
            "swagger": "/docs",
            "redoc": "/redoc"
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
        logger.error(f"健康检查失败: {e}")
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
    - segments: 说话人片段列表，每个片段包含 start, end, speaker, duration
    """
    temp_file = None
    try:
        # 记录请求信息
        logger.info(f"收到说话人分离请求: {file.filename}, size: {file.size if hasattr(file, 'size') else 'unknown'}")
        
        # 保存上传的文件到临时文件
        suffix = Path(file.filename).suffix if file.filename else ".wav"
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            content = await file.read()
            tmp.write(content)
            temp_file = tmp.name
        
        logger.info(f"处理音频文件: {file.filename} ({len(content)} bytes)")
        
        # 加载模型（如果还没加载）
        pipeline = get_pipeline()
        
        # 准备参数
        diarization_kwargs = {}
        if min_speakers is not None:
            if min_speakers < 1:
                raise HTTPException(
                    status_code=400,
                    detail="min_speakers 必须大于 0"
                )
            diarization_kwargs["min_speakers"] = min_speakers
            logger.info(f"设置最小说话人数量: {min_speakers}")
            
        if max_speakers is not None:
            if max_speakers < 1:
                raise HTTPException(
                    status_code=400,
                    detail="max_speakers 必须大于 0"
                )
            diarization_kwargs["max_speakers"] = max_speakers
            logger.info(f"设置最大说话人数量: {max_speakers}")
        
        # 验证参数
        if min_speakers is not None and max_speakers is not None:
            if min_speakers > max_speakers:
                raise HTTPException(
                    status_code=400,
                    detail="min_speakers 不能大于 max_speakers"
                )
        
        # 执行说话人分离
        logger.info("开始说话人分离...")
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
        
        speaker_count = len(set(s["speaker"] for s in segments))
        logger.info(f"✅ 说话人分离完成，识别到 {speaker_count} 个说话人，共 {len(segments)} 个片段")
        
        return {
            "success": True,
            "segments": segments,
            "speaker_count": speaker_count,
            "total_segments": len(segments)
        }
        
    except HTTPException:
        # 重新抛出 HTTP 异常
        raise
    except Exception as e:
        logger.error(f"❌ 说话人分离失败: {e}")
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
                logger.debug(f"已清理临时文件: {temp_file}")
            except Exception as e:
                logger.warning(f"清理临时文件失败: {e}")


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="说话人分离 API 服务")
    parser.add_argument("--host", default="127.0.0.1", help="监听地址")
    parser.add_argument("--port", type=int, default=50001, help="监听端口")
    parser.add_argument("--reload", action="store_true", help="开发模式（自动重载）")
    
    args = parser.parse_args()
    
    # 打印启动信息（包括 token 状态）
    print_startup_info()
    
    print("=" * 60)
    print("说话人分离 API 服务")
    print("=" * 60)
    print(f"服务地址: http://{args.host}:{args.port}")
    print(f"API 文档: http://{args.host}:{args.port}/docs")
    print("=" * 60)
    print("\n提示：")
    print("- 首次使用时会自动下载模型（约 500MB），请耐心等待...")
    print("- 需要设置 HF_TOKEN 环境变量并接受模型使用条款")
    print("- 按 Ctrl+C 停止服务\n")
    
    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        reload=args.reload,
        log_level="info"
    )
