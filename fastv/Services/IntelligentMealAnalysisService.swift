//
//  IntelligentMealAnalysisService.swift
//  fastv
//
//  Created on 2025/01/XX.
//

import Foundation

/// 智能饮食分析响应类型
enum MealAnalysisResponseType: String, Codable {
    case complete = "complete"           // 信息完整，可以直接保存
    case needClarification = "need_clarification"  // 需要追问
}

/// 智能饮食分析响应
struct MealAnalysisResponse: Codable {
    var type: MealAnalysisResponseType
    var mealType: MealType?              // 识别的餐次类型
    var foods: [AnalyzedFood]            // 分析的食物列表
    var question: String?                // 如果需要追问，这里是问题
    var totalCalories: Double?           // 总卡路里
    var confidence: Double?               // 置信度（0-1）
}

/// 分析的食物
struct AnalyzedFood: Codable, Identifiable {
    let id: UUID
    var name: String                      // 食物名称
    var amount: String?                   // 份量描述（如"1个"、"250ml"、"1碗"）
    var amountValue: Double?              // 份量数值（如1.0、250.0）
    var amountUnit: String?               // 份量单位（如"个"、"ml"、"碗"、"g"）
    var calories: Double?                 // 卡路里（每份或每100g）
    var caloriesPer100g: Double?          // 每100克的卡路里
    var protein: Double?                  // 蛋白质（克）
    var carbs: Double?                    // 碳水化合物（克）
    var fat: Double?                      // 脂肪（克）
    var cookingMethod: String?            // 烹饪方式（如"猪油炒"、"清蒸"）
    var ingredients: [String]?            // 主要配料（如["白菜", "猪油"]）
    var consumedRatio: Double?            // 食用比例（0.0-1.0，默认1.0）
    var needsClarification: Bool         // 是否需要追问
    var clarificationQuestion: String?    // 追问的问题
    
    init(
        id: UUID = UUID(),
        name: String,
        amount: String? = nil,
        amountValue: Double? = nil,
        amountUnit: String? = nil,
        calories: Double? = nil,
        caloriesPer100g: Double? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        cookingMethod: String? = nil,
        ingredients: [String]? = nil,
        consumedRatio: Double? = 1.0,
        needsClarification: Bool = false,
        clarificationQuestion: String? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.amountValue = amountValue
        self.amountUnit = amountUnit
        self.calories = calories
        self.caloriesPer100g = caloriesPer100g
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.cookingMethod = cookingMethod
        self.ingredients = ingredients
        self.consumedRatio = consumedRatio
        self.needsClarification = needsClarification
        self.clarificationQuestion = clarificationQuestion
    }
    
    /// 计算实际摄入的卡路里
    var actualCalories: Double? {
        guard let calories = calories else { return nil }
        let ratio = consumedRatio ?? 1.0
        
        // 如果有每100g的卡路里和份量，优先使用
        if let caloriesPer100g = caloriesPer100g,
           let amountValue = amountValue,
           let amountUnit = amountUnit {
            var grams: Double = 0
            
            // 转换单位到克
            switch amountUnit.lowercased() {
            case "g", "克":
                grams = amountValue
            case "kg", "千克":
                grams = amountValue * 1000
            case "ml", "毫升", "l", "升":
                // 液体食物，假设密度接近水（1g/ml）
                grams = amountValue
            case "个", "只", "枚":
                // 需要根据食物类型估算重量，这里简化处理
                grams = amountValue * 50 // 默认每个50g
            case "碗":
                grams = amountValue * 200 // 默认每碗200g
            case "盘":
                grams = amountValue * 300 // 默认每盘300g
            default:
                grams = amountValue * 100 // 默认100g
            }
            
            return (caloriesPer100g / 100.0) * grams * ratio
        }
        
        return calories * ratio
    }
}

/// 智能饮食分析服务
@MainActor
class IntelligentMealAnalysisService {
    static let shared = IntelligentMealAnalysisService()
    
    private init() {}
    
    /// 分析饮食输入（文本+图片）
    /// - Parameters:
    ///   - textInput: 用户输入的文本描述
    ///   - imageData: 图片数据数组（可选）
    ///   - conversationHistory: 对话历史（用于追问）
    ///   - profile: AI服务配置
    ///   - model: 模型名称
    ///   - timeout: 超时时间
    /// - Returns: 分析结果
    func analyzeMeal(
        textInput: String,
        imageData: [Data] = [],
        conversationHistory: [[String: Any]] = [],
        profile: AIServiceProfile,
        model: String,
        timeout: TimeInterval = 60.0
    ) async throws -> MealAnalysisResponse {
        guard !profile.apiKey.isEmpty else {
            throw FoodRecognitionError.missingAPIKey
        }
        
        // 确保使用 DashScope API
        guard profile.protocolType == .dashScope ||
              profile.endpoint.lowercased().contains("dashscope") else {
            throw FoodRecognitionError.invalidEndpoint
        }
        
        let baseURL = profile.endpoint.isEmpty ? "https://dashscope.aliyuncs.com/compatible-mode/v1" : profile.endpoint
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw FoodRecognitionError.invalidEndpoint
        }
        
        // 构建系统提示词
        let systemPrompt = buildSystemPrompt()
        
        // 构建用户消息
        var userContent: [[String: Any]] = []
        
        // 添加图片
        for data in imageData {
            let base64Image = data.base64EncodedString()
            userContent.append(["image": "data:image/jpeg;base64,\(base64Image)"])
        }
        
        // 添加文本
        var userText = textInput
        if !conversationHistory.isEmpty {
            // 如果有对话历史，添加上下文
            userText = "用户回答：\(textInput)\n\n请根据用户的回答更新分析结果。"
        }
        userContent.append(["text": userText])
        
        // 构建消息列表
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        // 添加对话历史
        messages.append(contentsOf: conversationHistory)
        
        // 添加当前用户消息
        messages.append(["role": "user", "content": userContent])
        
        // 构建请求
        let requestBody: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.2,
            "top_p": 0.9
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(profile.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = timeout
        
        print("🤖 [IntelligentMealAnalysisService] 发送饮食分析请求...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FoodRecognitionError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            throw FoodRecognitionError.requestFailed(httpResponse.statusCode, errorMessage)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw FoodRecognitionError.invalidResponse
        }
        
        let rawResponse = content.trimmingCharacters(in: .whitespacesAndNewlines)
        print("📝 [IntelligentMealAnalysisService] AI 原始响应: \(rawResponse)")
        
        // 解析响应
        return try parseResponse(rawResponse)
    }
    
    /// 构建系统提示词
    private func buildSystemPrompt() -> String {
        return """
你是一个专业的饮食分析助手。你的任务是分析用户的饮食输入，识别所有食物、估算卡路里，并在信息不足时主动询问。

## 核心任务

1. **自动识别餐次类型**：从用户的描述中识别是早餐、午餐、晚餐、零食还是饮料
   - 关键词：早餐/早饭/早膳 → breakfast
   - 关键词：午餐/午饭/中饭 → lunch
   - 关键词：晚餐/晚饭/晚膳 → lunch
   - 关键词：零食/点心/加餐 → snack
   - 关键词：饮料/饮品/喝 → drink
   - 如果无法确定，根据时间推测（早上6-10点→早餐，11-14点→午餐，17-21点→晚餐）

2. **识别所有食物**：从描述中提取所有食物和饮品
   - 包括主菜、配菜、调料、饮品等
   - 识别烹饪方式（如"猪油炒"、"清蒸"、"油炸"等）
   - 识别主要配料（如"白菜用猪油炒" → 食物：炒白菜，配料：白菜、猪油）

3. **估算份量和卡路里**：
   - 对于每个食物，估算份量（如"1个鸡蛋"、"250ml牛奶"、"1碗米饭"）
   - 估算卡路里（优先使用每100g的卡路里数据）
   - 考虑烹饪方式对卡路里的影响（如猪油炒会增加脂肪和卡路里）

4. **主动追问**：如果以下信息不明确，必须主动询问：
   - 食物数量不明确（如"吃了鸡蛋" → 问"吃了几个鸡蛋？"）
   - 份量不明确（如"喝了牛奶" → 问"喝了多少毫升牛奶？"）
   - 烹饪方式影响卡路里但不明确（如"炒白菜" → 问"是用什么油炒的？用了多少油？"）
   - 食用比例不明确（如"吃了一盘菜" → 问"这盘菜你吃了多少？全部还是部分？"）

## 输出格式

你必须严格按照以下格式输出，使用标记符来分隔不同部分：

### 格式1：信息完整，可以直接保存

```json
<ANALYSIS_START>
{
  "type": "complete",
  "mealType": "dinner",
  "foods": [
    {
      "name": "炒白菜",
      "amount": "1盘",
      "amountValue": 1.0,
      "amountUnit": "盘",
      "caloriesPer100g": 120.0,
      "protein": 2.0,
      "carbs": 5.0,
      "fat": 8.0,
      "cookingMethod": "猪油炒",
      "ingredients": ["白菜", "猪油"],
      "consumedRatio": 1.0,
      "needsClarification": false
    }
  ],
  "totalCalories": 360.0,
  "confidence": 0.9
}
<ANALYSIS_END>
```

### 格式2：需要追问

```json
<ANALYSIS_START>
{
  "type": "need_clarification",
  "mealType": "dinner",
  "foods": [
    {
      "name": "炒白菜",
      "amount": null,
      "needsClarification": true,
      "clarificationQuestion": "这盘炒白菜你吃了多少？是全部吃完还是只吃了一部分？"
    }
  ],
  "question": "这盘炒白菜你吃了多少？是全部吃完还是只吃了一部分？",
  "confidence": 0.6
}
<ANALYSIS_END>
```

## 追问规则

1. **优先级高的问题**（必须问清楚）：
   - 食物数量（几个、几个）
   - 份量大小（多少毫升、多少克、几碗）
   - 食用比例（全部还是部分）

2. **优先级中等问题**（如果影响卡路里计算）：
   - 烹饪方式（用什么油、油炸还是清蒸）
   - 配料（是否加了糖、是否加了奶油）

3. **优先级低的问题**（可以估算）：
   - 品牌（不同品牌卡路里差异不大）
   - 具体时间（不影响卡路里计算）

## 卡路里估算参考

- 米饭：130 kcal/100g
- 面条：140 kcal/100g
- 鸡蛋：144 kcal/100g（约50g/个）
- 牛奶：60 kcal/100ml
- 猪油：900 kcal/100g
- 植物油：900 kcal/100g
- 白菜：16 kcal/100g
- 牛肉：250 kcal/100g
- 鸡肉：165 kcal/100g
- 猪肉：242 kcal/100g

## 重要提示

1. **必须使用标记符**：`<ANALYSIS_START>` 和 `<ANALYSIS_END>` 来标记JSON内容
2. **JSON必须有效**：输出的JSON必须可以被解析
3. **追问要具体**：问题要具体明确，一次只问一个关键问题
4. **估算要合理**：卡路里估算要基于常见食物数据库，不要随意猜测
5. **考虑中餐特点**：中餐经常是多人共享，要询问食用比例

现在请分析用户的饮食输入。
"""
    }
    
    /// 解析AI响应
    private func parseResponse(_ rawResponse: String) throws -> MealAnalysisResponse {
        // 提取标记符之间的内容
        guard let startRange = rawResponse.range(of: "<ANALYSIS_START>"),
              let endRange = rawResponse.range(of: "<ANALYSIS_END>") else {
            // 如果没有标记符，尝试直接解析JSON
            return try parseJSONResponse(rawResponse)
        }
        
        let jsonString = String(rawResponse[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return try parseJSONResponse(jsonString)
    }
    
    /// 解析JSON响应
    private func parseJSONResponse(_ jsonString: String) throws -> MealAnalysisResponse {
        // 清理JSON字符串
        var cleanedJSON = jsonString
        if cleanedJSON.hasPrefix("```json") {
            cleanedJSON = String(cleanedJSON.dropFirst(7))
        }
        if cleanedJSON.hasPrefix("```") {
            cleanedJSON = String(cleanedJSON.dropFirst(3))
        }
        if cleanedJSON.hasSuffix("```") {
            cleanedJSON = String(cleanedJSON.dropLast(3))
        }
        cleanedJSON = cleanedJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            throw FoodRecognitionError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(MealAnalysisResponse.self, from: jsonData)
    }
}

