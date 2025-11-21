#!/usr/bin/env ruby
# frozen_string_literal: true

# 性能测试脚本 - 测试 Ollama 模型的性能指标

require 'net/http'
require 'net/https'
require 'openssl'
require 'json'
require 'uri'
require 'benchmark'

class PerformanceTester
  def initialize(endpoint: 'http://127.0.0.1:11434', model: 'deepseek-r1:1.5b')
    @endpoint = endpoint
    @model = model
    @system_prompt = <<~PROMPT
      你是一个专业的文本优化助手。你的任务是优化语音转文字的结果。
      只返回优化后的文本内容，不要添加任何解释、说明、引号、标记或其他任何内容。
    PROMPT
  end

  # 测试用例：不同长度的文本
  TEST_TEXTS = [
    {
      name: '短文本（10字）',
      text: '嗯那个今天天气不错',
      expected_time: 2.0
    },
    {
      name: '中等文本（50字）',
      text: '嗯那个我今天想去超市买点东西然后呢顺便看看有没有什么优惠活动如果价格合适的话就买一些日常用品',
      expected_time: 3.0
    },
    {
      name: '长文本（100字）',
      text: '嗯那个我今天想去超市买点东西然后呢顺便看看有没有什么优惠活动如果价格合适的话就买一些日常用品包括牛奶面包水果蔬菜什么的然后呢还要买一些日用品比如牙膏洗发水之类的最后呢如果时间允许的话还想逛逛看看有没有什么新商品',
      expected_time: 5.0
    },
    {
      name: '超长文本（200字）',
      text: '嗯那个我今天想去超市买点东西然后呢顺便看看有没有什么优惠活动如果价格合适的话就买一些日常用品包括牛奶面包水果蔬菜什么的然后呢还要买一些日用品比如牙膏洗发水之类的最后呢如果时间允许的话还想逛逛看看有没有什么新商品另外呢我还想买一些零食和饮料因为家里快没有了然后呢还要买一些调料和食材因为周末想在家做饭最后呢如果看到什么打折的商品也可以考虑买一些毕竟能省一点是一点',
      expected_time: 8.0
    }
  ].freeze

  def test_single_request(text)
    uri = URI("#{@endpoint}/api/generate")
    
    request_body = {
      model: @model,
      prompt: text,
      system: @system_prompt,
      stream: false,
      options: {
        temperature: 0.3,
        top_p: 0.9
      }
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 120
    http.open_timeout = 30
    
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
      optimized_text = result['response']&.strip || ''
      tokens_per_second = result['eval_count'] ? result['eval_count'].to_f / duration : nil
      
      {
        success: true,
        text: optimized_text,
        duration: duration,
        tokens_per_second: tokens_per_second,
        eval_count: result['eval_count'],
        prompt_eval_count: result['prompt_eval_count'],
        total_duration: result['total_duration']
      }
    else
      {
        success: false,
        error: "HTTP #{response.code}: #{response.body}",
        duration: duration
      }
    end
  rescue => e
    {
      success: false,
      error: e.message,
      duration: duration || 0
    }
  end

  def test_latency(iterations: 5)
    puts "\n" + "=" * 80
    puts "延迟测试（响应时间）"
    puts "=" * 80
    puts "模型: #{@model}"
    puts "测试次数: #{iterations}"
    puts "=" * 80
    
    test_text = TEST_TEXTS[1][:text] # 使用中等长度文本
    results = []
    
    iterations.times do |i|
      print "测试 #{i + 1}/#{iterations}... "
      result = test_single_request(test_text)
      
      if result[:success]
        duration = result[:duration]
        results << duration
        puts "✅ #{duration.round(2)}秒"
      else
        puts "❌ 失败: #{result[:error]}"
      end
      
      sleep(0.5) # 短暂休息，避免过热
    end
    
    if results.any?
      avg = results.sum / results.size
      min = results.min
      max = results.max
      median = results.sort[results.size / 2]
      
      puts "\n📊 延迟统计:"
      puts "  平均延迟: #{avg.round(2)}秒"
      puts "  最小延迟: #{min.round(2)}秒"
      puts "  最大延迟: #{max.round(2)}秒"
      puts "  中位数延迟: #{median.round(2)}秒"
      puts "  标准差: #{Math.sqrt(results.map { |x| (x - avg) ** 2 }.sum / results.size).round(2)}秒"
      
      # 评估
      if avg < 2.0
        puts "  ⚡️ 评估: 非常快，体验极佳"
      elsif avg < 5.0
        puts "  ✅ 评估: 正常，适合实时使用"
      elsif avg < 10.0
        puts "  ⚠️  评估: 较慢，可能影响体验"
      else
        puts "  ❌ 评估: 太慢，建议更换模型"
      end
    end
    
    results
  end

  def test_different_lengths
    puts "\n" + "=" * 80
    puts "不同长度文本处理能力测试"
    puts "=" * 80
    puts "模型: #{@model}"
    puts "=" * 80
    
    results = []
    
    TEST_TEXTS.each do |test_case|
      puts "\n[#{test_case[:name]}]"
      puts "原文长度: #{test_case[:text].length} 字符"
      puts "原文: #{test_case[:text][0..50]}..."
      
      result = test_single_request(test_case[:text])
      
      if result[:success]
        duration = result[:duration]
        output_length = result[:text].length
        chars_per_second = test_case[:text].length / duration
        
        puts "✅ 处理成功"
        puts "  响应时间: #{duration.round(2)}秒"
        puts "  输出长度: #{output_length} 字符"
        puts "  处理速度: #{chars_per_second.round(1)} 字符/秒"
        
        if result[:tokens_per_second]
          puts "  生成速度: #{result[:tokens_per_second].round(1)} tokens/秒"
        end
        
        # 评估
        if duration <= test_case[:expected_time]
          puts "  ✅ 速度符合预期（≤ #{test_case[:expected_time]}秒）"
        else
          puts "  ⚠️  速度较慢（预期 ≤ #{test_case[:expected_time]}秒）"
        end
        
        results << {
          name: test_case[:name],
          input_length: test_case[:text].length,
          output_length: output_length,
          duration: duration,
          chars_per_second: chars_per_second,
          tokens_per_second: result[:tokens_per_second]
        }
      else
        puts "❌ 处理失败: #{result[:error]}"
      end
    end
    
    # 汇总
    if results.any?
      puts "\n" + "=" * 80
      puts "处理速度汇总"
      puts "=" * 80
      printf "%-20s | %-10s | %-10s | %-12s | %-12s\n", 
        "文本类型", "输入长度", "响应时间", "字符/秒", "tokens/秒"
      puts "-" * 80
      
      results.each do |r|
        printf "%-20s | %-10s | %-10s | %-12s | %-12s\n",
          r[:name],
          r[:input_length],
          "#{r[:duration].round(2)}s",
          r[:chars_per_second].round(1),
          r[:tokens_per_second] ? r[:tokens_per_second].round(1) : "N/A"
      end
    end
    
    results
  end

  def test_throughput(iterations: 10)
    puts "\n" + "=" * 80
    puts "吞吐量测试（连续处理能力）"
    puts "=" * 80
    puts "模型: #{@model}"
    puts "测试次数: #{iterations}"
    puts "=" * 80
    
    test_text = TEST_TEXTS[1][:text]
    start_time = Time.now
    success_count = 0
    total_tokens = 0
    
    iterations.times do |i|
      print "处理 #{i + 1}/#{iterations}... "
      result = test_single_request(test_text)
      
      if result[:success]
        success_count += 1
        total_tokens += result[:eval_count] if result[:eval_count]
        puts "✅ #{result[:duration].round(2)}秒"
      else
        puts "❌ 失败: #{result[:error]}"
      end
    end
    
    total_time = Time.now - start_time
    
    puts "\n📊 吞吐量统计:"
    puts "  总耗时: #{total_time.round(2)}秒"
    puts "  成功次数: #{success_count}/#{iterations}"
    puts "  平均每次: #{(total_time / iterations).round(2)}秒"
    puts "  吞吐量: #{(iterations / total_time).round(2)} 次/秒"
    
    if total_tokens > 0
      puts "  总生成tokens: #{total_tokens}"
      puts "  平均tokens/秒: #{(total_tokens / total_time).round(1)}"
    end
    
    {
      total_time: total_time,
      success_count: success_count,
      throughput: iterations / total_time,
      avg_latency: total_time / iterations
    }
  end

  def test_concurrent(concurrency: 3, requests_per_thread: 2)
    puts "\n" + "=" * 80
    puts "并发处理能力测试"
    puts "=" * 80
    puts "模型: #{@model}"
    puts "并发数: #{concurrency}"
    puts "每线程请求数: #{requests_per_thread}"
    puts "=" * 80
    
    test_text = TEST_TEXTS[1][:text]
    threads = []
    results = []
    mutex = Mutex.new
    
    start_time = Time.now
    
    concurrency.times do |thread_id|
      threads << Thread.new do
        requests_per_thread.times do |req_id|
          result = test_single_request(test_text)
          mutex.synchronize do
            results << {
              thread: thread_id,
              request: req_id,
              result: result
            }
          end
        end
      end
    end
    
    threads.each(&:join)
    total_time = Time.now - start_time
    
    success_results = results.select { |r| r[:result][:success] }
    success_count = success_results.size
    avg_duration = success_results.any? ? 
      success_results.sum { |r| r[:result][:duration] } / success_results.size : 0
    
    puts "\n📊 并发测试结果:"
    puts "  总耗时: #{total_time.round(2)}秒"
    puts "  总请求数: #{results.size}"
    puts "  成功请求数: #{success_count}"
    puts "  平均响应时间: #{avg_duration.round(2)}秒"
    puts "  并发吞吐量: #{(success_count / total_time).round(2)} 次/秒"
    
    if success_count < results.size
      puts "  ⚠️  部分请求失败，可能达到并发限制"
    end
    
    {
      total_time: total_time,
      success_count: success_count,
      total_requests: results.size,
      avg_latency: avg_duration,
      throughput: success_count / total_time
    }
  end

  def run_all_tests
    puts "=" * 80
    puts "Ollama 模型性能测试"
    puts "=" * 80
    puts "端点: #{@endpoint}"
    puts "模型: #{@model}"
    puts "=" * 80
    
    # 1. 延迟测试
    latency_results = test_latency(iterations: 5)
    
    # 2. 不同长度文本测试
    length_results = test_different_lengths
    
    # 3. 吞吐量测试
    throughput_results = test_throughput(iterations: 10)
    
    # 4. 并发测试
    concurrent_results = test_concurrent(concurrency: 3, requests_per_thread: 2)
    
    # 最终汇总
    puts "\n" + "=" * 80
    puts "性能测试汇总报告"
    puts "=" * 80
    puts "模型: #{@model}"
    puts
    
    if latency_results.any?
      avg_latency = latency_results.sum / latency_results.size
      puts "📊 平均延迟: #{avg_latency.round(2)}秒"
    end
    
    if length_results.any?
      avg_chars_per_sec = length_results.sum { |r| r[:chars_per_second] } / length_results.size
      puts "📊 平均处理速度: #{avg_chars_per_sec.round(1)} 字符/秒"
    end
    
    puts "📊 吞吐量: #{throughput_results[:throughput].round(2)} 次/秒"
    puts "📊 并发吞吐量: #{concurrent_results[:throughput].round(2)} 次/秒"
    
    puts "\n" + "=" * 80
    puts "性能评估"
    puts "=" * 80
    
    if latency_results.any?
      avg_latency = latency_results.sum / latency_results.size
      if avg_latency < 2.0
        puts "⚡️ 响应速度: 非常快，适合实时应用"
      elsif avg_latency < 5.0
        puts "✅ 响应速度: 正常，适合实时使用"
      elsif avg_latency < 10.0
        puts "⚠️  响应速度: 较慢，可能影响体验"
      else
        puts "❌ 响应速度: 太慢，建议更换模型"
      end
    end
    
    if concurrent_results[:success_count] == concurrent_results[:total_requests]
      puts "✅ 并发能力: 良好，支持并发请求"
    else
      puts "⚠️  并发能力: 部分请求失败，可能达到并发限制"
    end
    
    puts "=" * 80
  end
end

# 主程序
if __FILE__ == $0
  endpoint = ARGV[0] || 'http://127.0.0.1:11434'
  model = ARGV[1] || 'deepseek-r1:1.5b'
  
  tester = PerformanceTester.new(endpoint: endpoint, model: model)
  tester.run_all_tests
end

