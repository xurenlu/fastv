# 全面个人AI助理扩展计划

## 项目概述

将现有的"妙打"应用扩展为全面的个人AI助理，新增健康管理、AI对话等核心模块，打造一站式个人助理应用。

---

## 一、已完成功能

### 1. 健康助理 (Health Assistant) ✅

完整的健康管理模块，已实现以下功能：

#### 1.1 用户健康档案
- ✅ 身高、体重、年龄、性别设置
- ✅ 活动水平设置（久坐、轻度活动、中度活动、高度活动、极高活动）
- ✅ 健康目标设置（减重、维持体重、增重、增肌）
- ✅ 自动计算基础代谢率（BMR）和每日总消耗（TDEE）

#### 1.2 饮食追踪
- ✅ 对话式输入界面：文本 + 多图片上传
- ✅ AI食物识别（使用阿里云 DashScope qwen-vl-plus 引擎）
  - 识别菜品名称
  - 估算份量（如：1碗、250ml、1个等）
  - 估算卡路里
- ✅ 智能问答流程：针对多道菜逐一询问食用比例
  - 支持"全部"、"一半"、"三分之一"、"四分之一"等选项
  - 根据食用比例自动计算实际卡路里
- ✅ 卡路里自动计算：基于食物数据库 + AI估算
- ✅ 支持多种餐次类型：早餐、午餐、晚餐、零食、饮料

#### 1.3 运动追踪
- ✅ 文字/图片记录运动
- ✅ 基于身高体重计算消耗卡路里
- ✅ 支持常见运动类型：跑步、步行、骑行、游泳、健身房、瑜伽、徒步、篮球、足球、网球、羽毛球、舞蹈等
- ✅ 支持自定义运动名称
- ✅ 支持记录运动时长和距离

#### 1.4 健康指标记录
- ✅ 体重记录
- ✅ 血压记录（收缩压、舒张压）
- ✅ 心率记录
- ✅ 血糖记录
- ✅ 体脂率记录
- ✅ 睡眠记录
- ✅ 饮水量追踪
- ✅ 情绪状态记录
- ✅ 用药记录

#### 1.5 数据整合
- ✅ 与 Apple HealthKit 同步
  - 自动同步卡路里摄入和消耗
  - 同步体重、心率、血压等健康指标
- ✅ 健康仪表盘
  - 今日卡路里摄入/消耗/净摄入统计
  - 每日目标消耗（TDEE）进度显示
  - 今日记录概览

#### 1.6 技术实现

**数据模型**
- `HealthProfile.swift` - 用户健康档案
- `MealRecord.swift` - 饮食记录
- `ExerciseRecord.swift` - 运动记录
- `HealthMetric.swift` - 健康指标
- `HealthStore.swift` - 健康数据存储管理器

**服务层**
- `FoodRecognitionService.swift` - 食物识别服务（DashScope qwen-vl）
- `CalorieCalculator.swift` - 卡路里计算服务
- `HealthKitService.swift` - Apple HealthKit 集成

**视图层**
- `HealthAssistantView.swift` - 健康助理主界面
- `HealthDashboardView.swift` - 健康仪表盘
- `MealInputView.swift` - 饮食输入界面
- `ExerciseInputView.swift` - 运动输入界面
- `HealthMetricsView.swift` - 健康指标记录界面
- `HealthProfileSetupView.swift` - 健康档案设置界面

**权限配置**
- ✅ HealthKit 权限（已添加到 entitlements）

---

## 二、计划功能（暂未实现）

### 2.1 浏览器自动化 (AI Browser) - 高优先级

**功能规划**
- 内嵌 WKWebView 浏览器标签页
- 自然语言指令解析："帮我在京东搜索iPhone 16"
- DOM元素智能识别和定位
- 自动化操作：点击、输入、滚动、等待
- 多步骤任务脚本：循环翻页查找目标元素
- 页面快照和元素高亮显示
- 操作历史记录和回放

**技术实现方案**
- 使用 WKWebView + JavaScript 注入
- AI解析用户意图 -> 生成操作指令
- 实时DOM分析和元素选择器生成

**状态**: 已创建基础 WebView 占位符，完整功能待实现

---

### 2.2 思维导图 (Mind Map) - 高优先级

**功能规划**
- AI自动生成思维导图（从文本/对话）
- 可视化编辑器（拖拽、缩放）
- 多种布局模式（树形、放射状、鱼骨图）
- 导出为图片/PDF
- 与AI Chat联动：对话生成导图

**技术实现方案**

**数据模型**
- `MindMapNode.swift` - 思维导图节点
  - id: UUID
  - text: String（节点文本）
  - position: CGPoint（节点位置）
  - level: Int（层级，0为中心节点）
  - parentId: UUID?（父节点ID）
  - childrenIds: [UUID]（子节点ID列表）
  - color: Color（节点颜色）
  - fontSize: CGFloat（字体大小）
  - shape: NodeShape（节点形状：圆形、矩形、圆角矩形）

- `MindMap.swift` - 思维导图整体
  - id: UUID
  - title: String
  - rootNodeId: UUID（根节点ID）
  - nodes: [UUID: MindMapNode]（所有节点的字典）
  - layout: LayoutType（布局类型：树形、放射状、鱼骨图）
  - backgroundColor: Color

**可视化渲染**
- 使用 SwiftUI Canvas API 进行高性能绘制
- 支持节点拖拽、缩放、平移
- 使用 GeometryReader 处理坐标转换
- 实现平滑的动画效果

**AI生成功能**
- `MindMapGenerator.swift` - 思维导图生成服务
  - `generateFromText(_ text: String) -> MindMap`
  - `generateFromChat(_ conversation: [ChatMessage]) -> MindMap`
  - `expandNode(_ node: MindMapNode, context: String) -> [MindMapNode]`（扩展节点）

**编辑功能**
- 添加节点（双击空白处、右键菜单）
- 删除节点（Delete键、右键菜单）
- 编辑节点文本（双击节点）
- 移动节点（拖拽）
- 连接节点（拖拽创建父子关系）
- 自动布局（树形、放射状）
- 样式设置（节点颜色、形状、字体大小、连接线样式）

**存储和导出**
- `MindMapStore.swift` - 思维导图存储管理器
- 导出为图片（PNG、JPEG）
- 导出为PDF
- 导出为JSON（数据格式）

**状态**: 详细计划已制定，待实现

---

### 2.3 知识库/笔记 (Knowledge Base) - 中优先级

**功能规划**
- Markdown编辑器
- 双向链接支持（[[链接]]语法）
- 标签和分类管理
- 全文搜索
- AI辅助：自动摘要、关联推荐

**状态**: 暂未实现

---

### 2.4 日程管理 (Calendar) - 中优先级

**功能规划**
- 与系统日历集成（EventKit）
- AI智能创建事件（从对话/邮件）
- 日/周/月视图
- 提醒通知

**状态**: 暂未实现

---

### 2.5 文件管理 (File Manager) - 中优先级

**功能规划**
- AI辅助文件整理
- 智能搜索和分类
- 文件内容摘要
- 批量重命名

**状态**: 暂未实现

---

### 2.6 书签管理 (Bookmarks) - 已移除

**原计划功能**
- 网页收藏
- AI自动摘要
- 标签分类
- 全文搜索
- 从Safari/Chrome导入书签

**移除原因**: 用户认为功能意义不大，已从计划中移除

**状态**: 已移除，不再开发

---

## 三、技术架构

### 3.1 数据模型层 (`fastv/Models/`)

**健康相关**
- ✅ `HealthProfile.swift` - 用户健康档案
- ✅ `MealRecord.swift` - 饮食记录
- ✅ `ExerciseRecord.swift` - 运动记录
- ✅ `HealthMetric.swift` - 健康指标
- ✅ `HealthStore.swift` - 健康数据存储管理器

**计划中的模型**
- `MindMapNode.swift` - 思维导图节点
- `MindMap.swift` - 思维导图整体
- `KnowledgeNote.swift` - 知识笔记
- `BrowserSession.swift` - 浏览器会话

### 3.2 服务层 (`fastv/Services/`)

**已实现**
- ✅ `HealthKitService.swift` - Apple HealthKit 集成
- ✅ `FoodRecognitionService.swift` - 食物识别（DashScope qwen-vl）
- ✅ `CalorieCalculator.swift` - 卡路里计算

**计划中**
- `BrowserAutomationService.swift` - 浏览器自动化
- `MindMapGenerator.swift` - 思维导图生成

### 3.3 视图层 (`fastv/Views/`)

**已实现**
- ✅ `HealthAssistantView.swift` - 健康助理主界面
- ✅ `HealthDashboardView.swift` - 健康仪表盘
- ✅ `MealInputView.swift` - 饮食输入界面
- ✅ `ExerciseInputView.swift` - 运动输入界面
- ✅ `HealthMetricsView.swift` - 健康指标记录界面
- ✅ `HealthProfileSetupView.swift` - 健康档案设置界面

**计划中**
- `MindMapView.swift` - 思维导图界面
- `MindMapCanvasView.swift` - 思维导图画布视图
- `KnowledgeBaseView.swift` - 知识库界面
- `AIBrowserView.swift` - 浏览器自动化界面

### 3.4 权限配置

**已配置**
- ✅ HealthKit 权限（`fastv/fastv.entitlements`）
- ✅ 相册访问权限（图片上传）

---

## 四、实现优先级

### Phase 1 - 健康助理核心 ✅ 已完成
1. ✅ 用户健康档案设置
2. ✅ 饮食记录界面（文本+图片）
3. ✅ AI食物识别集成（DashScope qwen-vl）
4. ✅ 卡路里计算逻辑
5. ✅ HealthKit 基础集成

### Phase 2 - 健康助理完善 ✅ 已完成
6. ✅ 运动记录
7. ✅ 健康指标记录（血压、心率等）
8. ✅ 健康仪表盘和趋势图表
9. ⏳ AI健康建议（待完善）

### Phase 3 - 浏览器自动化 ⏳ 待实现
10. ⏳ 内嵌浏览器基础
11. ⏳ AI指令解析
12. ⏳ DOM操作和自动化

### Phase 4 - 思维导图 ⏳ 待实现
13. ⏳ 基础数据结构
14. ⏳ 可视化渲染
15. ⏳ 编辑功能
16. ⏳ AI集成
17. ⏳ 导出功能

### Phase 5 - 其他功能 ⏳ 待实现
18. ⏳ 知识库
19. ⏳ 日程管理
20. ⏳ 文件管理

---

## 五、关键技术要点

### 5.1 AI服务集成

**食物识别**
- 使用阿里云 DashScope API
- 模型：qwen-vl-plus（默认）或 qwen-vl-max
- 端点：`https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions`
- 格式：DashScope 兼容模式（OpenAI 格式）

**请求格式**
```json
{
  "model": "qwen-vl-plus",
  "messages": [
    {
      "role": "system",
      "content": "系统提示词"
    },
    {
      "role": "user",
      "content": [
        {"image": "data:image/jpeg;base64,..."},
        {"text": "用户提示词"}
      ]
    }
  ],
  "temperature": 0.2,
  "top_p": 0.9
}
```

### 5.2 HealthKit 集成

**权限配置**
- 在 `fastv.entitlements` 中添加 `com.apple.developer.healthkit`
- 在 Info.plist 中添加使用说明

**数据同步**
- 自动同步卡路里摄入和消耗
- 同步体重、心率、血压等健康指标
- 支持读取和写入操作

### 5.3 数据存储

**健康数据**
- 使用 `HealthStore` 单例管理
- 数据存储在 UserDefaults
- 支持自动保存和延迟保存机制

**数据模型**
- 所有模型都实现 `Codable` 协议
- 使用 UUID 作为唯一标识符
- 包含创建时间和更新时间

---

## 六、用户体验设计

### 6.1 健康助理界面

**主界面**
- 顶部工具栏：视图模式切换（仪表盘、饮食、运动、指标）
- 日期选择器：查看不同日期的记录
- 内容区域：根据选择的视图模式显示相应内容

**饮食记录**
- 餐次选择器（早餐、午餐、晚餐、零食、饮料）
- 文本输入框 + 图片上传按钮
- 图片预览区域
- AI识别后的对话式询问界面
- 记录列表展示

**运动记录**
- 运动类型选择器
- 自定义运动名称输入
- 时长和距离输入
- 文字描述输入
- 图片上传（可选）

**健康指标**
- 指标类型选择器
- 数值输入
- 备注输入（可选）
- 记录列表展示

### 6.2 交互流程

**饮食记录流程**
1. 用户上传图片或输入文字描述
2. 点击发送按钮
3. AI识别食物（如果有图片）
4. 逐一询问每道菜的食用比例
5. 用户选择比例（全部/一半/三分之一/四分之一）
6. 自动计算卡路里并保存记录

**运动记录流程**
1. 选择运动类型或输入自定义名称
2. 输入运动时长和/或距离
3. 可选：添加文字描述和图片
4. 点击保存
5. 自动计算消耗的卡路里并保存

---

## 七、已知问题和待优化

### 7.1 已解决的问题
- ✅ HealthKit 权限配置
- ✅ DashScope API 集成
- ✅ 多图片上传支持
- ✅ 对话式饮食记录流程

### 7.2 待优化项
- ⏳ AI健康建议功能
- ⏳ 健康数据趋势图表（周/月视图）
- ⏳ 食物数据库扩展（更准确的卡路里数据）
- ⏳ 运动类型模板优化
- ⏳ 健康报告生成（每日/周/月）

---

## 八、开发规范

### 8.1 代码组织
- 使用 `@MainActor` 标记 UI 相关的类
- 使用 `ObservableObject` 和 `@Published` 进行状态管理
- 使用 Combine 框架处理数据流
- 服务层使用单例模式

### 8.2 错误处理
- 定义专门的错误枚举类型
- 提供友好的错误提示信息
- 记录详细的错误日志

### 8.3 性能优化
- 使用延迟保存机制（Timer）
- 图片数据异步加载
- AI请求使用合理的超时时间
- 避免不必要的UI刷新

---

## 九、后续计划

### 短期计划（1-2个月）
1. 完善健康助理功能
   - AI健康建议
   - 趋势图表
   - 健康报告生成

2. 实现思维导图功能
   - 基础数据模型
   - Canvas 渲染
   - AI生成功能

### 中期计划（3-6个月）
1. 浏览器自动化功能
2. 知识库功能
3. 日程管理功能

### 长期计划（6个月以上）
1. 文件管理功能
2. 跨设备同步
3. 更多AI能力集成

---

## 十、参考资料

### API文档
- [阿里云 DashScope API 文档](https://help.aliyun.com/zh/dashscope/)
- [Apple HealthKit 文档](https://developer.apple.com/documentation/healthkit)

### 技术文档
- [SwiftUI Canvas API](https://developer.apple.com/documentation/swiftui/canvas)
- [EventKit 框架](https://developer.apple.com/documentation/eventkit)

---

**文档版本**: v1.0  
**最后更新**: 2025-01-XX  
**维护者**: fastv 开发团队

