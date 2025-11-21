#!/usr/bin/env ruby
# frozen_string_literal: true

# 对比 Ollama 和 llama.cpp 的性能

require 'net/http'
require 'json'
require 'uri'
require 'open3'

class PerformanceTester
  def initialize
    @test_texts = [
      '嗯那个我今天想去超市买点东西然后呢顺便看看有没有什么优惠活动',
      '这个项目的进度还挺不错的我们因该能按时完成',
      '我我我觉得这个方案挺好的就就就这样吧'
    ]
  end

  def test_ollama(endpoint, model, text)
    uri = URI("#{endpoint}/api/generate")
    
    request_body = {
      model: model,
      prompt: text,
      system: "你是一个专业的文本优化助手。只对文本进行轻微优化，添加标点符号。",
      stream: false,
      options: {
        temperature: 0.2,
        top_p: 0.9,
        top_k: 20,
        num_predict: 500
      }
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 30
    http.open_timeout = 10
    
    if uri.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request.body = request_body.to_json

    start_time = Time.now
    response = http.request(request)
    duration = Time.now - start_time

    if response.code == '200'
      result = JSON.parse(response.body)
      { success: true, text: result['response']&.strip || '', duration: duration }
    else
      { success: false, error: "HTTP #{response.code}", duration: duration }
    end
  rescue => e
    { success: false, error: e.message, duration: Time.now - start_time rescue 0 }
  end

  def test_llama_cpp(model_path, text, system_prompt = nil)
    cmd = [
      'llama-cli',
      '-m', model_path,
      '-p', text,
      '-n', '200',
      '--temp', '0.2',
      '--top-k', '20',
      '--threads', '8'
    ]
    
    cmd += ['--system-prompt', system_prompt] if system_prompt

    start_time = Time.now
    stdout, stderr, status = Open3.capture3(*cmd, timeout: 30)
    duration = Time.now - start_time

    if status.success?
      { success: true, text: stdout.strip, duration: duration }
    else
      { success: false, error: stderr, duration: duration }
    end
  rescue => e
    { success: false, error: e.message, duration: Time.now - start_time rescue 0 }
  end

  def run_comparison(ollama_endpoint, ollama_model, llama_model_path = nil)
    puts "=" * 80
    puts "性能对比测试"
    puts "=" * 80
    puts "Ollama 端点: #{ollama_endpoint}"
    puts "Ollama 模型: #{ollama_model}"
    puts "llama.cpp 模型: #{llama_model_path || '未配置'}"
    puts "=" * 80
    puts

    ollama_results = []
    llama_results = []

    @test_texts.each_with_index do |text, index|
      puts "[测试 #{index + 1}/#{@test_texts.size}]"
      puts "原文: #{text}"
      puts "-" * 80

      # 测试 Ollama
      puts "\n测试 Ollama..."
      ollama_result = test_ollama(ollama_endpoint, ollama_model, text)
      if ollama_result[:success]
        puts "✅ Ollama 成功"
        puts "   耗时: #{ollama_result[:duration].round(2)} 秒"
        puts "   输出: #{ollama_result[:text][0..100]}..."
        ollama_results << ollama_result[:duration]
      else
        puts "❌ Ollama 失败: #{ollama_result[:error]}"
      end

      # 测试 llama.cpp（如果配置了）
      if llama_model_path && File.exist?(llama_model_path)
        puts "\n测试 llama.cpp..."
        llama_result = test_llama_cpp(
          llama_model_path,
          text,
          "你是一个专业的文本优化助手。只对文本进行轻微优化，添加标点符号。"
        )
        if llama_result[:success]
          puts "✅ llama.cpp 成功"
          puts "   耗时: #{llama_result[:duration].round(2)} 秒"
          puts "   输出: #{llama_result[:text][0..100]}..."
          llama_results << llama_result[:duration]
        else
          puts "❌ llama.cpp 失败: #{llama_result[:error]}"
        end
      end

      puts "\n" + "=" * 80
      puts
    end

    # 汇总
    puts "\n" + "=" * 80
    puts "性能汇总"
    puts "=" * 80

    if ollama_results.any?
      avg_ollama = ollama_results.sum / ollama_results.size
      puts "Ollama 平均耗时: #{avg_ollama.round(2)} 秒"
      puts "Ollama 最快: #{ollama_results.min.round(2)} 秒"
      puts "Ollama 最慢: #{ollama_results.max.round(2)} 秒"
    end

    if llama_results.any?
      avg_llama = llama_results.sum / llama_results.size
      puts "\nllama.cpp 平均耗时: #{avg_llama.round(2)} 秒"
      puts "llama.cpp 最快: #{llama_results.min.round(2)} 秒"
      puts "llama.cpp 最慢: #{llama_results.max.round(2)} 秒"

      if ollama_results.any?
        speedup = avg_ollama / avg_llama
        improvement = ((avg_ollama - avg_llama) / avg_ollama * 100).round(1)
        puts "\n性能提升:"
        puts "  速度提升: #{(speedup - 1) * 100}%"
        puts "  时间减少: #{improvement}%"
        puts "  加速比: #{speedup.round(2)}x"
      end
    end

    puts "=" * 80
  end
end

# 主程序
if __FILE__ == $0
  ollama_endpoint = ARGV[0] || 'http://127.0.0.1:11434'
  ollama_model = ARGV[1] || 'deepseek-r1:1.5b'
  llama_model_path = ARGV[2]  # 可选，例如: ~/models/deepseek-r1/deepseek-r1-1.5b.Q4_K_M.gguf

  tester = PerformanceTester.new
  tester.run_comparison(ollama_endpoint, ollama_model, llama_model_path)
end

