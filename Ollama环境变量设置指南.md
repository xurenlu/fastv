# Ollama 环境变量设置指南（macOS）

## 📋 回答：需要重启 Ollama 吗？

**是的，需要重启 Ollama 应用才能使环境变量生效。**

## 🚀 设置方法（macOS）

### 方法 1：使用 launchctl（推荐，系统级设置）⭐

#### 步骤 1：设置环境变量
```bash
# 设置线程数
launchctl setenv OLLAMA_NUM_THREAD 8

# 设置 GPU 数量（macOS M2 使用 Metal）
launchctl setenv OLLAMA_NUM_GPU 1

# 设置最大加载模型数（节省内存）
launchctl setenv OLLAMA_MAX_LOADED_MODELS 1
```

#### 步骤 2：重启 Ollama
```bash
# 方法 A：通过命令行重启
killall ollama
# 然后重新打开 Ollama.app

# 方法 B：手动重启
# 1. 退出 Ollama 应用（右键菜单栏图标 → 退出）
# 2. 重新打开 Ollama.app
```

#### 步骤 3：验证设置
```bash
# 检查环境变量是否设置成功
launchctl getenv OLLAMA_NUM_THREAD
# 应该输出: 8
```

### 方法 2：在 shell 配置文件中设置（仅对终端启动的 ollama 有效）

#### 步骤 1：编辑配置文件
```bash
# 使用 fish shell（你的默认 shell）
echo 'set -gx OLLAMA_NUM_THREAD 8' >> ~/.config/fish/config.fish
echo 'set -gx OLLAMA_NUM_GPU 1' >> ~/.config/fish/config.fish
echo 'set -gx OLLAMA_MAX_LOADED_MODELS 1' >> ~/.config/fish/config.fish
```

#### 步骤 2：重新加载配置
```bash
source ~/.config/fish/config.fish
```

**注意**：这种方法只对从终端启动的 ollama 命令有效，对 GUI 应用（Ollama.app）无效。

### 方法 3：创建启动脚本（适用于 GUI 应用）

#### 步骤 1：创建启动脚本
```bash
# 创建启动脚本
cat > ~/start_ollama.sh << 'EOF'
#!/bin/bash
export OLLAMA_NUM_THREAD=8
export OLLAMA_NUM_GPU=1
export OLLAMA_MAX_LOADED_MODELS=1
open -a Ollama
EOF

chmod +x ~/start_ollama.sh
```

#### 步骤 2：使用脚本启动
以后使用 `~/start_ollama.sh` 来启动 Ollama，而不是直接打开 Ollama.app。

## 🔍 验证环境变量是否生效

### 方法 1：检查进程环境变量
```bash
# 查看 ollama serve 进程的环境变量
ps eww -p $(pgrep -f "ollama serve") | grep OLLAMA
```

### 方法 2：测试性能
```bash
# 运行测试脚本，观察响应时间是否有改善
ruby test_injection.rb http://127.0.0.1:11434 deepseek-r1:1.5b
```

## 📊 环境变量说明

| 变量名 | 说明 | 推荐值 | 作用 |
|--------|------|--------|------|
| `OLLAMA_NUM_THREAD` | CPU 线程数 | 8（你的 CPU 核心数） | 使用所有 CPU 核心加速推理 |
| `OLLAMA_NUM_GPU` | GPU 数量 | 1 | 使用 GPU（macOS M2 自动使用 Metal） |
| `OLLAMA_MAX_LOADED_MODELS` | 最大加载模型数 | 1 | 只加载一个模型，节省内存 |

## ⚠️ 注意事项

1. **必须重启**：设置环境变量后，必须重启 Ollama 应用才能生效。

2. **launchctl 的限制**：
   - `launchctl setenv` 设置的环境变量在系统重启后会丢失
   - 如果需要永久设置，需要创建 plist 文件（见下方）

3. **GUI vs 终端**：
   - 通过 GUI（Ollama.app）启动的应用不会读取 shell 配置文件（.zshrc, .bash_profile 等）
   - 只有通过 `launchctl setenv` 设置的环境变量才会被 GUI 应用读取

4. **macOS M2 GPU**：
   - macOS M2 会自动使用 Metal GPU 加速
   - 设置 `OLLAMA_NUM_GPU=1` 主要是明确指定，实际可能已经自动启用

## 🔧 永久设置（可选）

如果需要永久设置环境变量（系统重启后仍然有效），可以创建 plist 文件：

```bash
# 创建 plist 文件
cat > ~/Library/LaunchAgents/com.ollama.env.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ollama.env</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/launchctl</string>
        <string>setenv</string>
        <string>OLLAMA_NUM_THREAD</string>
        <string>8</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

# 加载 plist
launchctl load ~/Library/LaunchAgents/com.ollama.env.plist
```

## 💡 推荐方案

**对于你的情况（使用 Ollama.app GUI 应用），推荐使用方法 1：**

```bash
# 1. 设置环境变量
launchctl setenv OLLAMA_NUM_THREAD 8
launchctl setenv OLLAMA_MAX_LOADED_MODELS 1

# 2. 重启 Ollama
killall ollama
# 然后重新打开 Ollama.app

# 3. 验证
launchctl getenv OLLAMA_NUM_THREAD
# 应该输出: 8
```

## 🎯 总结

- ✅ **需要重启**：设置环境变量后必须重启 Ollama 应用
- ✅ **推荐方法**：使用 `launchctl setenv` 设置系统级环境变量
- ✅ **验证方法**：使用 `launchctl getenv` 或测试性能

