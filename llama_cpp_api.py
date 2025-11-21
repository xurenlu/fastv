#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
llama.cpp HTTP API 包装器
提供与 Ollama 兼容的 API 接口
"""

import subprocess
import json
import sys
import os
from flask import Flask, request, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

# 配置
MODEL_PATH = os.path.expanduser("~/models/deepseek-r1/deepseek-r1-1.5b.Q4_K_M.gguf")
LLAMA_CLI = "llama-cli"
DEFAULT_TEMP = 0.2
DEFAULT_TOP_K = 20
DEFAULT_MAX_TOKENS = 500
DEFAULT_THREADS = 8

def llama_inference(prompt, system_prompt=None, temperature=DEFAULT_TEMP, 
                   top_k=DEFAULT_TOP_K, max_tokens=DEFAULT_MAX_TOKENS):
    """调用 llama.cpp 进行推理"""
    
    # 检查模型文件是否存在
    if not os.path.exists(MODEL_PATH):
        raise FileNotFoundError(f"模型文件不存在: {MODEL_PATH}")
    
    # 构建命令
    cmd = [
        LLAMA_CLI,
        "-m", MODEL_PATH,
        "-p", prompt,
        "-n", str(max_tokens),
        "--temp", str(temperature),
        "--top-k", str(top_k),
        "--threads", str(DEFAULT_THREADS),
        "--ctx-size", "2048"
    ]
    
    # 如果有系统提示词，添加到 prompt 前面
    if system_prompt:
        full_prompt = f"{system_prompt}\n\n用户输入：{prompt}"
        cmd[cmd.index("-p") + 1] = full_prompt
    
    try:
        # 执行命令
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            check=True
        )
        
        # 提取输出（llama-cli 的输出可能包含一些元信息）
        output = result.stdout.strip()
        
        # 如果输出包含 prompt，只返回生成的部分
        if prompt in output:
            output = output.split(prompt, 1)[-1].strip()
        
        return output
    except subprocess.TimeoutExpired:
        raise TimeoutError("推理超时")
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"推理失败: {e.stderr}")
    except Exception as e:
        raise RuntimeError(f"执行错误: {str(e)}")

@app.route('/api/generate', methods=['POST'])
def generate():
    """Ollama 兼容的 API 端点"""
    try:
        data = request.json
        prompt = data.get('prompt', '')
        system = data.get('system', '')
        
        # 从 options 中获取参数
        options = data.get('options', {})
        temperature = options.get('temperature', DEFAULT_TEMP)
        top_k = options.get('top_k', DEFAULT_TOP_K)
        num_predict = options.get('num_predict', DEFAULT_MAX_TOKENS)
        
        if not prompt:
            return jsonify({"error": "prompt 参数不能为空"}), 400
        
        # 执行推理
        response_text = llama_inference(
            prompt=prompt,
            system_prompt=system,
            temperature=temperature,
            top_k=top_k,
            max_tokens=num_predict
        )
        
        return jsonify({
            "model": os.path.basename(MODEL_PATH),
            "response": response_text,
            "done": True
        })
        
    except FileNotFoundError as e:
        return jsonify({"error": str(e)}), 404
    except TimeoutError as e:
        return jsonify({"error": str(e)}), 408
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/tags', methods=['GET'])
def tags():
    """返回模型列表（兼容 Ollama API）"""
    model_name = os.path.basename(MODEL_PATH)
    return jsonify({
        "models": [{
            "name": model_name,
            "model": model_name,
            "size": os.path.getsize(MODEL_PATH) if os.path.exists(MODEL_PATH) else 0,
            "modified_at": "2025-01-01T00:00:00Z"
        }]
    })

@app.route('/health', methods=['GET'])
def health():
    """健康检查"""
    return jsonify({
        "status": "ok",
        "model_path": MODEL_PATH,
        "model_exists": os.path.exists(MODEL_PATH),
        "llama_cli": LLAMA_CLI
    })

if __name__ == '__main__':
    print("=" * 60)
    print("llama.cpp HTTP API 服务")
    print("=" * 60)
    print(f"模型路径: {MODEL_PATH}")
    print(f"模型存在: {os.path.exists(MODEL_PATH)}")
    print(f"llama-cli: {LLAMA_CLI}")
    print("=" * 60)
    print("\n启动服务在: http://127.0.0.1:11435")
    print("按 Ctrl+C 停止服务\n")
    
    app.run(host='127.0.0.1', port=11435, debug=False)

