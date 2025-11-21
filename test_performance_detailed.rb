#!/usr/bin/env ruby
# frozen_string_literal: true

# 详细性能测试脚本 - 分析各个阶段的耗时

require 'net/http'
require 'net/https'
require 'openssl'
require 'json'
require 'uri'
require 'socket'
require 'resolv'

class DetailedPerformanceTester
  def initialize(endpoint: 'http://127.0.0.1:11434', model: 'deepseek-r1:1.5b', proxy: nil, use_cdnproxy: false)
    @original_endpoint = endpoint
    @model = model
    @proxy = proxy  # 代理地址，格式: 'http://127.0.0.1:7856'
    @use_cdnproxy = use_cdnproxy  # 是否使用 CDNProxy URL 修改方式
    
    # 如果使用 CDNProxy，修改 endpoint URL
    if @use_cdnproxy && endpoint.start_with?('https://')
      # 将 https://example.com 转换为 https://cdnproxy.some.im/example.com
      @endpoint = endpoint.sub('https://', 'https://cdnproxy.some.im/')
    else
      @endpoint = endpoint
    end
    
    @system_prompt = <<~PROMPT
      你是一个专业的文本优化助手。你的任务是优化语音转文字的结果。
      只返回优化后的文本内容，不要添加任何解释、说明、引号、标记或其他任何内容。
    PROMPT
  end

  TEST_TEXT = '嗯那个我今天想去超市买点东西然后呢顺便看看有没有什么优惠活动如果价格合适的话就买一些日常用品'

  # DNS 解析时间
  def measure_dns_time(hostname)
    start = Time.now
    Resolv.getaddress(hostname)
    Time.now - start
  rescue => e
    nil
  end

  # TCP 连接时间
  def measure_tcp_time(hostname, port)
    start = Time.now
    socket = Socket.tcp(hostname, port, connect_timeout: 10)
    socket.close
    Time.now - start
  rescue => e
    nil
  end

  # 测试单个请求，详细分析各个阶段耗时
  def test_single_request_detailed(text)
    uri = URI(@endpoint)
    full_uri = URI("#{@endpoint}/api/generate")
    
    timing = {
      dns_time: nil,
      tcp_time: nil,
      ssl_time: nil,
      request_send_time: nil,
      ttfb: nil,  # Time To First Byte
      download_time: nil,
      total_http_time: nil,
      model_inference_time: nil,
      total_time: nil
    }
    
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

    # 1. DNS 解析
    if uri.hostname && uri.hostname != '127.0.0.1' && uri.hostname != 'localhost'
      dns_start = Time.now
      timing[:dns_time] = measure_dns_time(uri.hostname)
    end

    # 2. TCP 连接
    if uri.hostname && uri.hostname != '127.0.0.1' && uri.hostname != 'localhost'
      tcp_start = Time.now
      timing[:tcp_time] = measure_tcp_time(uri.hostname, uri.port || (uri.scheme == 'https' ? 443 : 80))
    end

    # 设置代理
    if @proxy
      proxy_uri = URI(@proxy)
      http = Net::HTTP.new(full_uri.host, full_uri.port, proxy_uri.hostname, proxy_uri.port)
    else
      http = Net::HTTP.new(full_uri.host, full_uri.port)
    end
    
    http.read_timeout = 120
    http.open_timeout = 30
    
    if full_uri.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    request = Net::HTTP::Post.new(full_uri.path)
    request['Content-Type'] = 'application/json'
    request.body = request_body.to_json

    # 3. 总请求时间
    total_start = Time.now
    
    # 4. 发送请求并等待响应
    response = http.request(request)
    
    total_time = Time.now - total_start
    timing[:total_http_time] = total_time

    if response.code == '200'
      result = JSON.parse(response.body)
      optimized_text = result['response']&.strip || ''
      
      # 从响应中获取模型推理时间
      if result['total_duration']
        # total_duration 是纳秒，转换为秒
        timing[:model_inference_time] = result['total_duration'] / 1_000_000_000.0
      end
      
      # 估算各个阶段时间
      # TTFB 通常是总时间的 10-30%，取决于网络延迟
      # 下载时间取决于响应大小
      response_size = response.body.bytesize
      
      # 粗略估算：假设推理时间占总时间的大部分
      if timing[:model_inference_time]
        # 网络时间 = 总时间 - 推理时间
        network_time = total_time - timing[:model_inference_time]
        timing[:ttfb] = network_time * 0.3  # 假设 TTFB 占网络时间的 30%
        timing[:download_time] = network_time * 0.7  # 下载占 70%
      else
        # 如果没有推理时间，假设推理占 80%，网络占 20%
        timing[:model_inference_time] = total_time * 0.8
        network_time = total_time * 0.2
        timing[:ttfb] = network_time * 0.3
        timing[:download_time] = network_time * 0.7
      end
      
      timing[:total_time] = total_time
      
      {
        success: true,
        text: optimized_text,
        timing: timing,
        eval_count: result['eval_count'],
        prompt_eval_count: result['prompt_eval_count'],
        total_duration: result['total_duration'],
        response_size: response_size
      }
    else
      timing[:total_time] = total_time
      {
        success: false,
        error: "HTTP #{response.code}: #{response.body}",
        timing: timing
      }
    end
  rescue => e
    {
      success: false,
      error: e.message,
      timing: timing
    }
  end

  # 测试连接性能（不发送完整请求）
  def test_connection_only
    uri = URI(@endpoint)
    
    puts "\n" + "=" * 80
    puts "连接性能测试（不包含模型推理）"
    puts "=" * 80
    puts "端点: #{@endpoint}"
    puts "=" * 80
    
    results = []
    
    5.times do |i|
      print "测试 #{i + 1}/5... "
      
      timing = {}
      
      # DNS 解析
      if uri.hostname && uri.hostname != '127.0.0.1' && uri.hostname != 'localhost'
        dns_time = measure_dns_time(uri.hostname)
        timing[:dns] = dns_time
        print "DNS: #{dns_time ? dns_time.round(3) : 'N/A'}s "
      end
      
      # TCP 连接
      if uri.hostname && uri.hostname != '127.0.0.1' && uri.hostname != 'localhost'
        tcp_time = measure_tcp_time(uri.hostname, uri.port || (uri.scheme == 'https' ? 443 : 80))
        timing[:tcp] = tcp_time
        print "TCP: #{tcp_time ? tcp_time.round(3) : 'N/A'}s "
      end
      
      # HTTPS 连接测试
      if uri.scheme == 'https'
        begin
          ssl_start = Time.now
          if @proxy
            proxy_uri = URI(@proxy)
            http = Net::HTTP.new(uri.host, uri.port || 443, proxy_uri.hostname, proxy_uri.port)
          else
            http = Net::HTTP.new(uri.host, uri.port || 443)
          end
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          http.open_timeout = 10
          http.read_timeout = 5
          http.start do |conn|
            conn.request_get('/')
          end
          ssl_time = Time.now - ssl_start
          timing[:ssl] = ssl_time
          print "SSL: #{ssl_time.round(3)}s "
        rescue => e
          timing[:ssl] = nil
          print "SSL: 失败 "
        end
      end
      
      results << timing
      puts "✅"
      
      sleep(0.5)
    end
    
    # 统计
    if results.any?
      puts "\n📊 连接性能统计:"
      
      if results.first[:dns]
        dns_times = results.map { |r| r[:dns] }.compact
        if dns_times.any?
          puts "  DNS 解析:"
          puts "    平均: #{(dns_times.sum / dns_times.size).round(3)}秒"
          puts "    最小: #{dns_times.min.round(3)}秒"
          puts "    最大: #{dns_times.max.round(3)}秒"
        end
      end
      
      if results.first[:tcp]
        tcp_times = results.map { |r| r[:tcp] }.compact
        if tcp_times.any?
          puts "  TCP 连接:"
          puts "    平均: #{(tcp_times.sum / tcp_times.size).round(3)}秒"
          puts "    最小: #{tcp_times.min.round(3)}秒"
          puts "    最大: #{tcp_times.max.round(3)}秒"
        end
      end
      
      if results.first[:ssl]
        ssl_times = results.map { |r| r[:ssl] }.compact
        if ssl_times.any?
          puts "  SSL 握手:"
          puts "    平均: #{(ssl_times.sum / ssl_times.size).round(3)}秒"
          puts "    最小: #{ssl_times.min.round(3)}秒"
          puts "    最大: #{ssl_times.max.round(3)}秒"
        end
      end
    end
    
    results
  end

  # 详细性能测试
  def test_detailed_performance(iterations: 5)
    puts "\n" + "=" * 80
    puts "详细性能分析测试"
    puts "=" * 80
    puts "端点: #{@endpoint}"
    puts "模型: #{@model}"
    puts "测试次数: #{iterations}"
    puts "=" * 80
    
    results = []
    
    iterations.times do |i|
      print "\n[测试 #{i + 1}/#{iterations}] "
      result = test_single_request_detailed(TEST_TEXT)
      
      if result[:success]
        timing = result[:timing]
        puts "✅ 成功"
        puts "  总耗时: #{timing[:total_time].round(2)}秒"
        
        if timing[:dns_time]
          puts "  DNS 解析: #{timing[:dns_time].round(3)}秒"
        end
        
        if timing[:tcp_time]
          puts "  TCP 连接: #{timing[:tcp_time].round(3)}秒"
        end
        
        puts "  HTTP 总时间: #{timing[:total_http_time].round(2)}秒"
        puts "    - TTFB (首字节时间): #{timing[:ttfb].round(3)}秒"
        puts "    - 下载时间: #{timing[:download_time].round(3)}秒"
        
        if timing[:model_inference_time]
          puts "  模型推理时间: #{timing[:model_inference_time].round(2)}秒"
          puts "  推理占比: #{(timing[:model_inference_time] / timing[:total_time] * 100).round(1)}%"
        end
        
        network_time = timing[:total_time] - (timing[:model_inference_time] || 0)
        puts "  网络时间: #{network_time.round(2)}秒"
        puts "  网络占比: #{(network_time / timing[:total_time] * 100).round(1)}%"
        
        if result[:eval_count]
          tokens_per_sec = result[:eval_count] / timing[:model_inference_time] if timing[:model_inference_time]
          puts "  生成速度: #{tokens_per_sec.round(1)} tokens/秒" if tokens_per_sec
        end
        
        results << result
      else
        puts "❌ 失败: #{result[:error]}"
      end
    end
    
    # 汇总分析
    if results.any?
      puts "\n" + "=" * 80
      puts "性能分析汇总"
      puts "=" * 80
      
      total_times = results.map { |r| r[:timing][:total_time] }
      inference_times = results.map { |r| r[:timing][:model_inference_time] }.compact
      network_times = total_times.map.with_index { |total, i| 
        total - (results[i][:timing][:model_inference_time] || 0) 
      }
      
      puts "\n📊 总耗时统计:"
      puts "  平均: #{(total_times.sum / total_times.size).round(2)}秒"
      puts "  最小: #{total_times.min.round(2)}秒"
      puts "  最大: #{total_times.max.round(2)}秒"
      
      if inference_times.any?
        puts "\n📊 模型推理时间:"
        puts "  平均: #{(inference_times.sum / inference_times.size).round(2)}秒"
        puts "  最小: #{inference_times.min.round(2)}秒"
        puts "  最大: #{inference_times.max.round(2)}秒"
        puts "  占比: #{(inference_times.sum / total_times.sum * 100).round(1)}%"
      end
      
      if network_times.any?
        puts "\n📊 网络传输时间:"
        puts "  平均: #{(network_times.sum / network_times.size).round(2)}秒"
        puts "  最小: #{network_times.min.round(2)}秒"
        puts "  最大: #{network_times.max.round(2)}秒"
        puts "  占比: #{(network_times.sum / total_times.sum * 100).round(1)}%"
      end
      
      # 关键结论
      avg_inference = inference_times.any? ? inference_times.sum / inference_times.size : 0
      avg_network = network_times.sum / network_times.size
      avg_total = total_times.sum / total_times.size
      
      puts "\n" + "=" * 80
      puts "关键结论"
      puts "=" * 80
      
      if avg_network > avg_inference * 0.5
        puts "⚠️  网络延迟是主要瓶颈！"
        puts "   - 网络时间占比: #{(avg_network / avg_total * 100).round(1)}%"
        puts "   - 建议：部署到更近的节点（如香港）可以显著提升性能"
        puts "   - 预期提升: 如果网络时间减少 50%，总时间可减少约 #{(avg_network * 0.5).round(1)}秒"
      else
        puts "✅ 模型推理是主要耗时！"
        puts "   - 推理时间占比: #{(avg_inference / avg_total * 100).round(1)}%"
        puts "   - 网络时间占比: #{(avg_network / avg_total * 100).round(1)}%"
        puts "   - 说明：更换节点对性能提升有限，主要受模型推理速度影响"
      end
      
      if avg_network > 2.0
        puts "\n💡 优化建议:"
        puts "   1. 考虑部署到香港节点，可以减少网络延迟"
        puts "   2. 当前网络延迟较高，可能影响用户体验"
        puts "   3. 如果部署到香港，预期总时间可减少约 #{(avg_network * 0.6).round(1)}-#{(avg_network * 0.8).round(1)}秒"
      end
    end
    
    results
  end

  def run_all_tests
    puts "=" * 80
    puts "Ollama 详细性能测试"
    puts "=" * 80
    puts "原始端点: #{@original_endpoint}"
    puts "实际端点: #{@endpoint}"
    puts "模型: #{@model}"
    puts "HTTP代理: #{@proxy || '无'}"
    puts "CDNProxy: #{@use_cdnproxy ? '是' : '否'}"
    puts "=" * 80
    
    # 1. 连接性能测试
    connection_results = test_connection_only
    
    # 2. 详细性能分析
    performance_results = test_detailed_performance(iterations: 5)
    
    puts "\n" + "=" * 80
    puts "测试完成"
    puts "=" * 80
  end
end

# 主程序
if __FILE__ == $0
  endpoint = ARGV[0] || 'http://127.0.0.1:11434'
  model = ARGV[1] || 'deepseek-r1:1.5b'
  proxy = ARGV[2] || nil  # 第三个参数为 HTTP 代理地址，如 'http://127.0.0.1:7856'
  use_cdnproxy = ARGV[3] == 'true' || ARGV[3] == 'cdnproxy'  # 第四个参数为是否使用 CDNProxy
  
  tester = DetailedPerformanceTester.new(
    endpoint: endpoint, 
    model: model, 
    proxy: proxy,
    use_cdnproxy: use_cdnproxy
  )
  tester.run_all_tests
end

