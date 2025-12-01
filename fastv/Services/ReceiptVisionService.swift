//
//  ReceiptVisionService.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation
import AppKit

/// 票据识别结果
struct ReceiptRecognitionResult: Codable {
    var amount: Double?         // 使用 Double 以便 JSON 编码/解码
    var type: String?           // "income", "expense", "transfer"
    var categoryName: String?   // 分类名称
    var note: String?           // 备注（商家名称、航班号、车次等）
    var date: String?           // ISO8601 格式日期
    var receiptType: String?    // 票据类型：餐饮、出租车、火车、飞机、购物等
    
    /// 转换为 Decimal 金额
    var amountDecimal: Decimal? {
        guard let amount = amount else { return nil }
        return Decimal(amount)
    }
}

/// 票据图片识别服务（使用 qwen3-vl-plus）
@MainActor
class ReceiptVisionService {
    static let shared = ReceiptVisionService()
    
    private init() {}
    
    /// 识别票据图片
    /// - Parameters:
    ///   - imageData: 图片数据
    ///   - apiKey: 阿里云 DashScope API Key
    ///   - categories: 可用分类列表
    ///   - userInput: 用户输入的文字（可选，用于提供上下文）
    /// - Returns: 识别结果
    func recognizeReceipt(
        imageData: Data,
        apiKey: String,
        categories: [ExpenseCategory],
        userInput: String? = nil
    ) async throws -> ReceiptRecognitionResult {
        guard !apiKey.isEmpty else {
            throw ReceiptVisionError.missingAPIKey
        }
        
        // 将图片数据转为 base64
        let base64Image = imageData.base64EncodedString()
        let imageUrl = "data:image/jpeg;base64,\(base64Image)"
        
        // 构建分类上下文
        let categoriesContext = categories.map { category in
            "- \(category.name) (\(category.type.displayName))"
        }.joined(separator: "\n")
        
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = TimeZone.current
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let currentDateISO = isoFormatter.string(from: now)
        
        let localizedFormatter = DateFormatter()
        localizedFormatter.locale = Locale(identifier: "zh_CN")
        localizedFormatter.dateStyle = .full
        localizedFormatter.timeStyle = .medium
        let currentDateLocalized = localizedFormatter.string(from: now)
        
        let systemPrompt = #"""
你是一个智能票据识别助手。用户会上传各种票据图片（餐饮小票、出租车票、火车票、机票、购物发票等），你需要从中提取关键信息。

【可用分类列表】
\#(categoriesContext)

【当前时间上下文】
- 当前日期时间: \#(currentDateLocalized)
- 当前时间（ISO8601）: \#(currentDateISO)

【你的任务】
从票据图片中提取以下信息：
1. 金额（必需，如果图片中有多张票据，请将所有金额累加）
   - 例如：如果图片中有两张火车票，金额分别是 100 和 150，则返回 250
   - 只返回总金额，不要分别列出
2. 类型：expense（支出，大多数票据都是支出）
3. 分类名称（根据票据类型自动分类）：
   - 餐饮小票/发票 → 餐饮
   - 出租车票 → 交通
   - 火车票 → 交通
   - 机票/登机牌 → 交通
   - 购物发票 → 购物
   - 其他消费凭证 → 根据内容判断
4. 备注（提取商家名称、航班号、车次、目的地等关键信息，如果有多张票据，合并所有信息）
5. 日期（从票据上识别日期，如果有多张票据，使用最早的日期，如果无法识别则使用当前时间）
6. 票据类型（餐饮、出租车、火车、飞机、购物等，如果有多张不同类型，使用主要类型）

【分类匹配规则】
- 餐饮小票/发票 → 餐饮（支出）
- 出租车票 → 交通（支出）
- 火车票 → 交通（支出）
- 机票/登机牌 → 交通（支出）
- 购物发票 → 购物（支出）
- 如果无法确定，使用"其他"分类

【输出格式】
只返回 JSON 对象，格式如下：
{
  "amount": 35.00,
  "type": "expense",
  "categoryName": "交通",
  "note": "北京-上海 G123",
  "date": "2025-01-15T10:00:00+08:00",
  "receiptType": "火车"
}

【重要规则】
1. 只返回 JSON 对象，不要其他任何内容
2. amount 必须是数字，不要包含货币符号
3. type 通常是 "expense"（支出），除非是收入类票据
4. categoryName 必须从可用分类列表中选择
5. 如果无法识别日期，date 字段可以为空或使用当前时间
6. 仔细识别票据上的所有文字信息，特别是金额和日期
"""#
        
        // 构建用户提示
        var userPrompt = "请识别这张票据图片，提取金额、日期、类型、分类和备注信息。"
        if let userInput = userInput, !userInput.isEmpty {
            userPrompt += "\n\n用户补充说明：\(userInput)\n请结合用户说明和图片内容进行识别。如果图片中有多张票据（如两张火车票），请将所有金额累加。"
        } else {
            userPrompt += "\n\n如果图片中有多张票据（如两张火车票），请将所有金额累加。"
        }
        
        // 构建请求 URL（阿里云 DashScope）
        let baseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw ReceiptVisionError.invalidEndpoint
        }
        
        // 构建请求体（OpenAI 兼容格式）
        let requestBody: [String: Any] = [
            "model": "qwen3-vl-plus",
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": imageUrl
                            ]
                        ],
                        [
                            "type": "text",
                            "text": userPrompt
                        ]
                    ]
                ]
            ],
            "temperature": 0.2,
            "top_p": 0.9
        ]
        
        // 构建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60.0 // 图片识别可能需要更长时间
        
        print("🤖 [ReceiptVisionService] 发送图片识别请求到 qwen-vl-plus...")
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReceiptVisionError.invalidResponse
        }
        
        print("🤖 [ReceiptVisionService] 收到响应，状态码: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [ReceiptVisionService] 请求失败（状态码: \(httpResponse.statusCode)）：\(errorMessage)")
            throw ReceiptVisionError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        // 解析响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [ReceiptVisionService] 无法解析响应 JSON")
            throw ReceiptVisionError.invalidResponse
        }
        
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            print("❌ [ReceiptVisionService] 响应格式解析失败")
            throw ReceiptVisionError.invalidResponse
        }
        
        let rawResponse = content.trimmingCharacters(in: .whitespacesAndNewlines)
        print("📝 [ReceiptVisionService] AI 原始响应: \(rawResponse)")
        
        // 尝试解析 JSON（可能包含在代码块中）
        var jsonString = rawResponse
        
        // 移除可能的 markdown 代码块标记
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 尝试解析 JSON
        guard let jsonData = jsonString.data(using: .utf8),
              let result = try? JSONDecoder().decode(ReceiptRecognitionResult.self, from: jsonData) else {
            print("⚠️ [ReceiptVisionService] JSON 解析失败")
            throw ReceiptVisionError.invalidResponse
        }
        
        print("✅ [ReceiptVisionService] 识别成功")
        return result
    }
}

/// 票据识别错误
enum ReceiptVisionError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case invalidResponse
    case requestFailed(Int, String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "缺少阿里云 API Key，请在设置中配置"
        case .invalidEndpoint:
            return "无效的 API 端点地址"
        case .invalidResponse:
            return "无效的响应格式"
        case .requestFailed(let code, let message):
            return "请求失败 (状态码: \(code)): \(message)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}

