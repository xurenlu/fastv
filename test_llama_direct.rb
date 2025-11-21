#!/usr/bin/env ruby
# frozen_string_literal: true

# 直接测试 llama-cli 性能（不需要 HTTP API）

require 'open3'
require 'time'

class LlamaDirectTester
  def initialize(model_path)
    @model_path = model_path
    @llama_cli = 'llama-cli'
  end

  def test_inference(text, system_prompt = nil)
    # 构建完整提示词
    full_prompt = system_prompt ? "#{system_prompt}\n\n用户输入：#{text}" : text
    
    cmd = [
      @llama_cli,
      '-m', @model_path,
      '-p', full_prompt,
      '-n', '200',
      '--temp', '0.2',
      '--top-k', '20',
      '--threads', '8',
      '--ctx-size', '2048'
    ]

    start_time = Time.now
    stdout, stderr, status = Open3.capture3(*cmd, timeout: 30)
    duration = Time.now - start_time

    if status.success?
      # 提取输出（移除 prompt）
      output = stdout.strip
      if full_prompt.length < output.length
        output = output[full_prompt.length..-1].strip
      end
      
      { success: true, text: output, duration: duration }
    else
      { success: false, error: stderr, duration: duration }
    end
  rescue => e
    { success: false, error: e.message, duration: Time.now - start_time rescue 0 }
  end

  def run_tests
    test_cases = [
      '嗯那个我今天想去超市买点东西然后呢顺便看看有没有什么优惠活动',
      '这个项目的进度还挺不错的我们因该能按时完成',
      '我我我觉得这个方案挺好的就就就这样吧'
    ]

    system_prompt = "你是一个专业的文本优化助手。只对文本进行轻微优化，添加标点符号。"

    puts "=" * 80
    puts "llama-cli 直接性能测试"
    puts "=" * 80
    puts "模型路径: #{@model_path}"
    puts "=" * 80
    puts

    results = []
    total_duration = 0

    test_cases.each_with_index do |text, index|
      puts "[测试 #{index + 1}/#{test_cases.size}]"
      puts "原文: #{text}"
      puts "-" * 80

      result = test_inference(text, system_prompt)
      total_duration += result[:duration]

      if result[:success]
        puts "✅ 成功"
        puts "耗时: #{result[:duration].round(2)} 秒"
        puts "输出: #{result[:text][0..100]}..."
        results << result[:duration]
      else
        puts "❌ 失败: #{result[:error]}"
      end

      puts
      puts "=" * 80
      puts
    end

    if results.any?
      avg = results.sum / results.size
      puts "性能汇总:"
      puts "  平均耗时: #{avg.round(2)} 秒"
      puts "  最快: #{results.min.round(2)} 秒"
      puts "  最慢: #{results.max.round(2)} 秒"
      puts "  总耗时: #{total_duration.round(2)} 秒"
    end
  end
end

# 主程序
if __FILE__ == $0
  model_path = ARGV[0] || ENV['LLAMA_MODEL_PATH'] || '~/models/deepseek-r1/deepseek-r1-1.5b.Q4_K_M.gguf'
  model_path = File.expand_path(model_path)

  unless File.exist?(model_path)
    puts "❌ 错误: 模型文件不存在: #{model_path}"
    puts ""
    puts "请提供模型路径:"
    puts "  ruby test_llama_direct.rb <模型路径>"
    puts ""
    puts "或者设置环境变量:"
    puts "  export LLAMA_MODEL_PATH=~/path/to/model.gguf"
    exit 1
  end

  tester = LlamaDirectTester.new(model_path)
  tester.run_tests
end

