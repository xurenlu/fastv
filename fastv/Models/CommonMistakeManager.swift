//
//  CommonMistakeManager.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import Combine

/// 常错词管理器
@MainActor
class CommonMistakeManager: ObservableObject {
    static let shared = CommonMistakeManager()
    
    @Published private(set) var mistakes: [CommonMistake] = []
    @Published var enableAutoCorrection: Bool {
        didSet {
            UserDefaults.standard.set(enableAutoCorrection, forKey: "commonMistakeEnableAutoCorrection")
        }
    }
    
    private let storageKey = "commonMistakes"
    private var correctionCache: [String: String] = [:] // 缓存：错误词 -> 正确词
    private var sortedMistakesCache: [CommonMistake]? // 缓存排序后的常错词
    private var regexCache: [String: NSRegularExpression] = [:] // 缓存正则表达式
    
    private init() {
        enableAutoCorrection = UserDefaults.standard.bool(forKey: "commonMistakeEnableAutoCorrection")
        loadMistakes()
        initializeBuiltInRules()
        updateCache()
    }
    
    /// 添加或更新常错词
    func addOrUpdate(
        wrong: String,
        correct: String,
        frequency: Int = 1,
        confidence: Double = 0.5,
        category: CorrectionCategory = .other
    ) {
        // 查找是否已存在
        if let index = mistakes.firstIndex(where: { $0.wrong == wrong && $0.correct == correct }) {
            // 更新现有记录
            var mistake = mistakes[index]
            let newFrequency = mistake.frequency + frequency
            let newConfidence = max(mistake.confidence, confidence)
            mistake.update(frequency: newFrequency, confidence: newConfidence)
            // 如果显式传入了术语类别，把已有条目升级为术语
            if category == .terminology {
                mistake.category = .terminology
            }
            mistakes[index] = mistake
        } else {
            // 添加新记录
            let mistake = CommonMistake(
                wrong: wrong,
                correct: correct,
                frequency: frequency,
                confidence: confidence,
                category: category
            )
            mistakes.append(mistake)
        }

        invalidateCaches()
        saveMistakes()
    }
    
    /// 删除常错词
    func remove(_ mistake: CommonMistake) {
        mistakes.removeAll { $0.id == mistake.id }
        invalidateCaches()
        saveMistakes()
    }
    
    /// 删除多个常错词
    func remove(_ mistakes: [CommonMistake]) {
        let ids = Set(mistakes.map { $0.id })
        self.mistakes.removeAll { ids.contains($0.id) }
        invalidateCaches()
        saveMistakes()
    }
    
    /// 更新常错词
    func update(_ mistake: CommonMistake) {
        if let index = mistakes.firstIndex(where: { $0.id == mistake.id }) {
            mistakes[index] = mistake
            invalidateCaches()
            saveMistakes()
        }
    }
    
    /// 应用常错词修正
    func applyCorrections(to text: String) -> String {
        guard enableAutoCorrection, !mistakes.isEmpty, !text.isEmpty else { return text }
        
        var result = text
        
        // 使用缓存的排序结果，只处理启用的规则
        let sortedMistakes = getSortedMistakes().filter { $0.isEnabled }
        
        // 快速检查：如果文本中不包含任何错误词，直接返回（避免不必要的正则操作）
        let textLowercased = text.lowercased()
        let relevantMistakes = sortedMistakes.filter { mistake in
            textLowercased.contains(mistake.wrong.lowercased())
        }
        
        guard !relevantMistakes.isEmpty else { return text }
        
        // 限制处理的常错词数量，避免性能问题（最多处理前100个，因为包含内置规则）
        let mistakesToProcess = Array(relevantMistakes.prefix(100))
        
        for mistake in mistakesToProcess {
            // 只替换完整的词（避免误替换）
            // 术语类条目使用大小写不敏感匹配（"open ai" → "OpenAI"）
            let regex = getOrCreateRegex(for: mistake.wrong, caseInsensitive: mistake.category.isTerminology)
            let range = NSRange(location: 0, length: result.utf16.count)
            // 术语类还需要把正则模板中可能存在的 $1/$2 等转义掉（虽然术语极少含 $，但保险）
            let template = NSRegularExpression.escapedTemplate(for: mistake.correct)
            let newResult = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: template
            )

            // 如果替换成功，更新结果
            if newResult != result {
                result = newResult
            }
        }
        
        return result
    }
    
    /// 获取排序后的常错词（使用缓存）
    /// 术语类（.terminology）始终排在最前，确保 "OpenAI"/"GitHub" 这种专有名词
    /// 优先于一般的错字纠正生效；同类内部仍按 confidence 降序。
    private func getSortedMistakes() -> [CommonMistake] {
        if let cached = sortedMistakesCache {
            return cached
        }
        let sorted = mistakes.sorted { lhs, rhs in
            if lhs.category.isTerminology != rhs.category.isTerminology {
                return lhs.category.isTerminology
            }
            return lhs.confidence > rhs.confidence
        }
        sortedMistakesCache = sorted
        return sorted
    }

    /// 获取或创建正则表达式（使用缓存）。
    /// `caseInsensitive=true` 用于术语包：用户说 "open ai" / "Open AI" 都能命中术语 "OpenAI"。
    private func getOrCreateRegex(for pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        let cacheKey = caseInsensitive ? "ci::\(pattern)" : pattern
        if let cached = regexCache[cacheKey] {
            return cached
        }
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let hasASCIIToken = pattern.range(of: "[A-Za-z0-9_]", options: .regularExpression) != nil
        let escapedPattern = hasASCIIToken
            ? "(?<![A-Za-z0-9_])\(escaped)(?![A-Za-z0-9_])"
            : escaped
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        if let regex = try? NSRegularExpression(pattern: escapedPattern, options: options) {
            regexCache[cacheKey] = regex
            return regex
        }
        // 如果创建失败，返回一个不会匹配任何内容的正则
        return try! NSRegularExpression(pattern: "(?!.*)", options: [])
    }
    
    /// 获取统计信息
    func totalCount() -> Int {
        mistakes.count
    }
    
    /// 获取总修正次数
    func totalCorrections() -> Int {
        mistakes.reduce(0) { $0 + $1.frequency }
    }
    
    /// 切换内置规则的启用状态
    func toggleBuiltInRule(_ mistake: CommonMistake) {
        guard mistake.isBuiltIn else { return }
        
        if let index = mistakes.firstIndex(where: { $0.id == mistake.id }) {
            mistakes[index].isEnabled.toggle()
            invalidateCaches()
            saveMistakes()
        }
    }
    
    /// 获取内置规则数量
    func builtInRulesCount() -> Int {
        mistakes.filter { $0.isBuiltIn }.count
    }
    
    /// 获取自定义规则数量
    func customRulesCount() -> Int {
        mistakes.filter { !$0.isBuiltIn }.count
    }
    
    /// 获取启用的内置规则数量
    func enabledBuiltInRulesCount() -> Int {
        mistakes.filter { $0.isBuiltIn && $0.isEnabled }.count
    }
    
    /// 更新缓存
    private func updateCache() {
        correctionCache.removeAll()
        for mistake in mistakes {
            correctionCache[mistake.wrong] = mistake.correct
        }
    }
    
    /// 使缓存失效
    private func invalidateCaches() {
        updateCache()
        sortedMistakesCache = nil
        regexCache.removeAll()
    }
    
    // MARK: - Persistence
    
    private func saveMistakes() {
        if let encoded = try? JSONEncoder().encode(mistakes) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func loadMistakes() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            mistakes = []
            return
        }
        
        if let decoded = try? JSONDecoder().decode([CommonMistake].self, from: data) {
            mistakes = decoded
        } else {
            mistakes = []
        }
    }
    
    // MARK: - Built-in Rules
    
    /// 初始化内置规则（首次运行或从 v1 迁移时）
    private func initializeBuiltInRules() {
        let v3Key = "hasInitializedBuiltInRules_v3"
        let v2Key = "hasInitializedBuiltInRules_v2"
        let v1Key = "hasInitializedBuiltInRules_v1"

        if UserDefaults.standard.bool(forKey: v3Key) { return }

        if UserDefaults.standard.bool(forKey: v2Key) {
            let builtInRules = getBuiltInRules()
            let existingPairs = Set(mistakes.filter(\.isBuiltIn).map { "\($0.wrong)\u{0}\($0.correct)" })
            let newRules = builtInRules.filter { !existingPairs.contains("\($0.wrong)\u{0}\($0.correct)") }

            if !newRules.isEmpty {
                mistakes.append(contentsOf: newRules)
                saveMistakes()
                print("✅ [CommonMistakeManager] 已增量加入 \(newRules.count) 条 v3 内置中英混合术语规则")
            }

            UserDefaults.standard.set(true, forKey: v3Key)
            return
        }
        
        // 从 v1 迁移：移除旧的内置规则，应用精简后的规则（避免过度清理叠词、数字）
        if UserDefaults.standard.bool(forKey: v1Key) {
            mistakes.removeAll { $0.isBuiltIn }
            print("🔄 [CommonMistakeManager] 从 v1 迁移：已移除过度清理的重复词规则")
        }
        
        let builtInRules = getBuiltInRules()
        mistakes.append(contentsOf: builtInRules)
        
        UserDefaults.standard.set(true, forKey: v2Key)
        UserDefaults.standard.set(true, forKey: v3Key)
        UserDefaults.standard.set(true, forKey: v1Key) // 保持兼容
        saveMistakes()
        
        print("✅ [CommonMistakeManager] 已初始化 \(builtInRules.count) 条内置规则（v2 精简版）")
    }
    
    /// 获取所有内置规则
    private func getBuiltInRules() -> [CommonMistake] {
        var rules: [CommonMistake] = []
        
        // 重复词规则（v2 精简：移除会误伤合理叠词的规则，如谢谢、看看、说说、我看看、100 等）
        // 仅保留明显口吃/误识别的重复，不处理动词重叠（说说、看看、想想）、谢谢、连续数字
        let repetitionRules: [(String, String)] = [
            ("就就", "就"), ("这这", "这"), ("那那", "那"),
            ("的的", "的"), ("了了", "了"), ("在在", "在"),
            ("是是", "是"), ("有有", "有"), ("会会", "会"),
            ("能能", "能"), ("要要", "要"),
            ("卖卖", "卖"),
            ("对对", "对"), ("错错", "错"), ("好好", "好"),
            ("坏坏", "坏"), ("大大", "大"), ("小小", "小"),
            ("多多", "多"), ("少少", "少"), ("新新", "新"),
            ("旧旧", "旧"), ("快快", "快"), ("慢慢", "慢"),
            ("高高", "高"), ("低低", "低"), ("长长", "长"),
            ("短短", "短"), ("热热", "热"), ("冷冷", "冷"),
            ("开开", "开"), ("关关", "关"), ("上上", "上"),
            ("下下", "下"), ("前前", "前"), ("后后", "后"),
            ("左左", "左"), ("右右", "右"), ("里里", "里"),
            ("外外", "外"), ("中中", "中"), ("间间", "间"),
            ("就是就是", "就是"), ("然后然后", "然后"),
            ("所以所以", "所以"), ("但是但是", "但是"),
            ("因为因为", "因为"), ("如果如果", "如果"),
            ("虽然虽然", "虽然"), ("不过不过", "不过"),
            ("而且而且", "而且"), ("并且并且", "并且"),
            ("或者或者", "或者"), ("还是还是", "还是"),
            ("这个这个", ""), ("那个那个", ""),
            ("什么什么", "什么"), ("怎么怎么", "怎么"),
            ("为什么为什么", "为什么"), ("怎么样怎么样", "怎么样"),
            ("哪里哪里", "哪里"), ("哪个哪个", "哪个"),
            ("哪些哪些", "哪些"), ("多少多少", "多少"),
            ("很很", "很"), ("非常非常", "非常"),
            ("特别特别", "特别"), ("超级超级", "超级"),
            ("十分十分", "十分"), ("相当相当", "相当"),
            ("比较比较", "比较"), ("有点有点", "有点"),
            // 已移除：说说、做做、用用、去去、来来、走走、想想、听听、学学、写写、读读、买买、吃吃、喝喝、睡睡、玩玩、等等、帮帮（会误伤"谢谢""我看看"等合理叠词）
            // 已移除：看看看、说说说 等三连（会误伤"我看看"）
        ]
        
        for (wrong, correct) in repetitionRules {
            rules.append(CommonMistake(
                wrong: wrong,
                correct: correct,
                frequency: 0,
                confidence: 1.0,
                isBuiltIn: true,
                isEnabled: true,
                category: .repetition
            ))
        }
        
        // 填充词规则
        let fillerRules: [(String, String)] = [
            ("嗯", ""), ("啊", ""), ("呃", ""), ("哦", ""), ("哎", ""), ("诶", ""),
            ("额", ""), ("嗯嗯", ""), ("啊啊", ""), ("呃呃", ""), ("哦哦", ""),
            ("就是说", ""), ("然后呢", ""),
            ("嗯那个", ""), ("啊那个", ""), ("呃那个", ""),
            ("那个什么", ""), ("这个什么", ""),
            ("就是那个", ""), ("就是那个什么", ""),
            ("然后那个", ""), ("然后那个什么", ""),
            ("怎么说呢", ""), ("怎么说", ""),
            ("其实", ""), ("其实呢", ""), ("其实那个", ""),
            ("反正", ""), ("反正呢", ""), ("反正那个", ""),
            ("大概", ""), ("大概呢", ""), ("大概那个", ""),
            ("可能", ""), ("可能呢", ""), ("可能那个", ""),
            ("应该", ""), ("应该呢", ""), ("应该那个", ""),
            ("好像", ""), ("好像呢", ""), ("好像那个", ""),
            ("感觉", ""), ("感觉呢", ""), ("感觉那个", ""),
            ("觉得", ""), ("觉得呢", ""), ("觉得那个", ""),
            ("嗯啊", ""), ("啊嗯", ""), ("呃啊", ""),
            ("哦啊", ""), ("哎啊", ""), ("诶啊", ""),
            ("那个啥", ""), ("这个啥", ""),
            ("是吧", ""), ("对吧", ""),
        ]
        
        for (wrong, correct) in fillerRules {
            rules.append(CommonMistake(
                wrong: wrong,
                correct: correct,
                frequency: 0,
                confidence: 1.0,
                isBuiltIn: true,
                isEnabled: true,
                category: .filler
            ))
        }
        
        // 数字规则（仅单字重复口误，不处理阿拉伯数字如 100）
        let numberRules: [(String, String)] = [
            ("一一", "一"), ("二二", "二"), ("三三", "三"),
            ("四四", "四"), ("五五", "五"), ("六六", "六"),
            ("七七", "七"), ("八八", "八"), ("九九", "九"),
            ("十十", "十"), ("千千", "千"),
            // 已移除万万：会误伤"万万不可"等合理用法
        ]
        
        for (wrong, correct) in numberRules {
            rules.append(CommonMistake(
                wrong: wrong,
                correct: correct,
                frequency: 0,
                confidence: 1.0,
                isBuiltIn: true,
                isEnabled: true,
                category: .number
            ))
        }
        
        // 时间规则（移除"年年"：会误伤"年年有余"等）
        let timeRules: [(String, String)] = [
            ("月月", "月"), ("日日", "日"),
            ("时时", "时"), ("分分", "分"), ("秒秒", "秒"),
            ("周周", "周"), ("天天", "天"),
            ("今天今天", "今天"), ("明天明天", "明天"),
            ("昨天昨天", "昨天"), ("现在现在", "现在"),
            ("刚才刚才", "刚才"), ("以后以后", "以后"),
            ("以前以前", "以前"), ("之前之前", "之前"),
            ("之后之后", "之后"),
        ]
        
        for (wrong, correct) in timeRules {
            rules.append(CommonMistake(
                wrong: wrong,
                correct: correct,
                frequency: 0,
                confidence: 1.0,
                isBuiltIn: true,
                isEnabled: true,
                category: .time
            ))
        }
        
        // 地点规则
        let locationRules: [(String, String)] = [
            ("这里这里", "这里"), ("那里那里", "那里"),
            ("这边这边", "这边"), ("那边那边", "那边"),
            ("上面上面", "上面"), ("下面下面", "下面"),
            ("前面前面", "前面"), ("后面后面", "后面"),
        ]
        
        for (wrong, correct) in locationRules {
            rules.append(CommonMistake(
                wrong: wrong,
                correct: correct,
                frequency: 0,
                confidence: 1.0,
                isBuiltIn: true,
                isEnabled: true,
                category: .location
            ))
        }
        
        // 人称规则
        let pronounRules: [(String, String)] = [
            ("我我", "我"), ("你你", "你"), ("他他", "他"),
            ("她她", "她"), ("它它", "它"), ("我们我们", "我们"),
            ("你们你们", "你们"), ("他们他们", "他们"),
            ("她们她们", "她们"), ("它们它们", "它们"),
        ]
        
        for (wrong, correct) in pronounRules {
            rules.append(CommonMistake(
                wrong: wrong,
                correct: correct,
                frequency: 0,
                confidence: 1.0,
                isBuiltIn: true,
                isEnabled: true,
                category: .pronoun
            ))
        }

        let mixedLanguageTerminologyRules: [(String, String)] = [
            ("麦克 app", "Mac app"),
            ("麦克APP", "Mac app"),
            ("麦克应用", "Mac app"),
            ("麦克软件", "Mac app"),
            ("马克 app", "Mac app"),
            ("mac app", "Mac app"),
            ("麦克 OS", "macOS"),
            ("麦克OS", "macOS"),
            ("麦克系统", "macOS"),
            ("Mac OS", "macOS"),
            ("mac os", "macOS"),
            ("麦克电脑", "Mac"),
            ("open ai", "OpenAI"),
            ("chat gpt", "ChatGPT"),
            ("g p t", "GPT"),
            ("git hub", "GitHub"),
            ("github", "GitHub"),
            ("git lab", "GitLab"),
            ("type script", "TypeScript"),
            ("java script", "JavaScript"),
            ("node js", "Node.js"),
            ("react js", "React"),
            ("vue js", "Vue.js"),
            ("next js", "Next.js"),
            ("nuxt js", "Nuxt.js"),
            ("tail wind", "Tailwind CSS"),
            ("vs code", "VS Code"),
            ("visual studio code", "Visual Studio Code"),
            ("x code", "Xcode"),
            ("swift ui", "SwiftUI"),
            ("uikit", "UIKit"),
            ("app kit", "AppKit"),
            ("i o s", "iOS"),
            ("i pad o s", "iPadOS"),
            ("watch o s", "watchOS"),
            ("k 8 s", "Kubernetes"),
            ("k8s", "Kubernetes"),
            ("库伯内提斯", "Kubernetes"),
            ("docker", "Docker"),
            ("postgre sql", "PostgreSQL"),
            ("postgres", "PostgreSQL"),
            ("my sql", "MySQL"),
            ("sqlite", "SQLite"),
            ("mongo db", "MongoDB"),
            ("redis", "Redis"),
        ]

        for (wrong, correct) in mixedLanguageTerminologyRules {
            rules.append(CommonMistake(
                wrong: wrong,
                correct: correct,
                frequency: 0,
                confidence: 1.0,
                isBuiltIn: true,
                isEnabled: true,
                category: .terminology
            ))
        }
        
        // 标点规则
        let punctuationRules: [(String, String)] = [
            ("，，，", "，"), ("。。。", "。"),
            ("？？？", "？"), ("！！！", "！"),
        ]
        
        for (wrong, correct) in punctuationRules {
            rules.append(CommonMistake(
                wrong: wrong,
                correct: correct,
                frequency: 0,
                confidence: 1.0,
                isBuiltIn: true,
                isEnabled: true,
                category: .punctuation
            ))
        }
        
        return rules
    }
}
