#!/usr/bin/env python3
"""
将 ONNX 模型转换为 CoreML 格式
使用方法：
    python convert_to_coreml.py
"""

import os
import sys

def convert_onnx_to_coreml():
    """将 ONNX 模型转换为 CoreML 格式"""
    
    # 模型路径
    onnx_model_path = "fastv/Resources/Models/sensevoice-small/model.onnx"
    coreml_model_path = "fastv/Resources/Models/sensevoice-small/model.mlmodel"
    
    # 检查 ONNX 模型是否存在
    if not os.path.exists(onnx_model_path):
        print(f"错误：找不到 ONNX 模型文件: {onnx_model_path}")
        return False
    
    try:
        import coremltools as ct
        import onnx
        print("正在加载 ONNX 模型...")
        
        # 加载 ONNX 模型
        onnx_model = onnx.load(onnx_model_path)
        
        print("正在转换为 CoreML 模型...")
        print("注意：转换可能需要几分钟时间，请耐心等待...")
        
        # 转换为 CoreML 模型
        # 注意：SenseVoice 模型可能包含一些复杂操作，转换可能需要特殊处理
        # coremltools 7.x 版本使用 ct.converters.onnx.convert()
        try:
            # 尝试使用 onnx 转换器
            coreml_model = ct.converters.onnx.convert(
                onnx_model,
                minimum_deployment_target=ct.target.macOS12,  # macOS 12.0+
                compute_units=ct.ComputeUnit.ALL,  # 使用所有可用计算单元（CPU + GPU + Neural Engine）
            )
        except AttributeError:
            # 如果不存在，尝试直接转换
            coreml_model = ct.convert(
                onnx_model_path,
                source='auto',
                minimum_deployment_target=ct.target.macOS12,
                compute_units=ct.ComputeUnit.ALL,
            )
        
        # 设置模型元数据
        coreml_model.author = "FastV"
        coreml_model.short_description = "SenseVoice Small 语音识别模型"
        coreml_model.version = "1.0"
        
        # 设置输入输出描述
        # 注意：需要根据实际模型调整输入输出名称和形状
        # SenseVoice 模型的输入通常是 [batch, sequence_length, feature_dim]
        # 输出通常是 token IDs
        
        print("正在保存 CoreML 模型...")
        coreml_model.save(coreml_model_path)
        
        print(f"✅ 转换成功！")
        print(f"CoreML 模型已保存到: {coreml_model_path}")
        print(f"\n模型大小: {os.path.getsize(coreml_model_path) / (1024*1024):.2f} MB")
        
        return True
        
    except ImportError as e:
        print(f"错误：导入失败: {e}")
        print("\n请先安装依赖：")
        print("  source venv/bin/activate")
        print("  pip install coremltools onnx")
        return False
    except Exception as e:
        print(f"转换失败: {e}")
        print("\n可能的原因：")
        print("1. 模型包含 CoreML 不支持的操作")
        print("2. 模型结构过于复杂")
        print("3. 需要手动指定输入输出形状")
        print("\n建议：")
        print("- 检查模型是否包含动态形状（可能需要固定形状）")
        print("- 查看 coremltools 文档了解支持的 ONNX 操作")
        print("- 考虑使用 ONNX Runtime（支持更完整的 ONNX 操作）")
        return False

if __name__ == "__main__":
    print("=" * 60)
    print("ONNX 到 CoreML 模型转换工具")
    print("=" * 60)
    print()
    
    success = convert_onnx_to_coreml()
    
    if success:
        print("\n下一步：")
        print("1. 将 model.mlmodel 添加到 Xcode 项目中")
        print("2. 使用 CoreMLWrapper.swift 替换 ONNXRuntimeWrapper.swift")
        print("3. 构建并测试应用")
    else:
        print("\n如果转换失败，可以继续使用 ONNX Runtime 方案")
        sys.exit(1)

