-- 邮件规则引擎模板
-- 定义标准规则函数接口，用于判断邮件的各种属性

--[[
规则函数说明：
- 所有规则函数接收一个 email 表作为参数
- email 表包含以下字段：
  - id: 邮件ID
  - accountId: 账号ID
  - folderId: 文件夹ID
  - subject: 主题
  - from: {name: 发件人名称, email: 发件人邮箱}
  - to: 收件人列表
  - cc: 抄送列表
  - textBody: 纯文本正文
  - htmlBody: HTML正文
  - preview: 预览文本
  - date: 发送时间（Unix时间戳）
  - isRead: 是否已读
  - hasAttachments: 是否有附件
  - tags: 标签列表
  
- 规则函数应返回布尔值或表
- 返回 true/false 表示是否匹配规则
- 返回表可以包含更多信息，如标签、优先级等
]]

-- 判断邮件是否重要
-- @param email: 邮件对象
-- @return boolean: 是否为重要邮件
function isImportant(email)
    -- 发件人白名单
    local importantSenders = {
        "boss@company.com",
        "hr@company.com",
        "manager@company.com"
    }
    
    for _, sender in ipairs(importantSenders) do
        if email.from.email == sender then
            return true
        end
    end
    
    -- 主题关键词
    local keywords = {"urgent", "紧急", "重要", "important", "asap", "立即"}
    local subjectLower = string.lower(email.subject or "")
    for _, keyword in ipairs(keywords) do
        if string.find(subjectLower, keyword) then
            return true
        end
    end
    
    -- 检查邮件正文中的关键词
    local body = email.textBody or email.preview or ""
    local bodyLower = string.lower(body)
    local bodyKeywords = {"deadline", "截止", "meeting", "会议", "review", "审核"}
    for _, keyword in ipairs(bodyKeywords) do
        if string.find(bodyLower, keyword) then
            return true
        end
    end
    
    return false
end

-- 判断邮件是否为垃圾邮件
-- @param email: 邮件对象
-- @return boolean: 是否为垃圾邮件
function isSpam(email)
    -- 检查发件人域名黑名单
    local spamDomains = {
        "spam.com",
        "ads.com",
        "promo.com"
    }
    
    local fromEmail = email.from.email or ""
    local domain = string.match(fromEmail, "@(.+)")
    if domain then
        domain = string.lower(domain)
        for _, spamDomain in ipairs(spamDomains) do
            if domain == spamDomain then
                return true
            end
        end
    end
    
    -- 检查主题中的垃圾邮件关键词
    local spamKeywords = {"free", "免费", "win", "获奖", "prize", "奖品", "click here", "立即点击"}
    local subjectLower = string.lower(email.subject or "")
    for _, keyword in ipairs(spamKeywords) do
        if string.find(subjectLower, keyword) then
            return true
        end
    end
    
    -- 检查发件人是否为 no-reply
    if string.find(string.lower(fromEmail), "noreply") or
       string.find(string.lower(fromEmail), "no-reply") then
        -- no-reply 不一定是垃圾邮件，但结合其他特征判断
        local body = email.textBody or email.preview or ""
        if string.len(body) < 100 then
            -- 短邮件且是 no-reply，可能是垃圾邮件
            return true
        end
    end
    
    return false
end

-- 判断邮件是否为订阅类邮件
-- @param email: 邮件对象
-- @return boolean: 是否为订阅邮件
function isSubscription(email)
    local subscriptionKeywords = {
        "unsubscribe", "退订", "订阅", "subscribe",
        "newsletter", "邮件列表", "mailing list"
    }
    
    local body = email.textBody or email.preview or ""
    local bodyLower = string.lower(body)
    
    for _, keyword in ipairs(subscriptionKeywords) do
        if string.find(bodyLower, keyword) then
            return true
        end
    end
    
    -- 检查发件人域名是否常见订阅服务
    local subscriptionDomains = {
        "mailchimp.com",
        "constantcontact.com",
        "campaign-monitor.com"
    }
    
    local fromEmail = email.from.email or ""
    local domain = string.match(fromEmail, "@(.+)")
    if domain then
        domain = string.lower(domain)
        for _, subDomain in ipairs(subscriptionDomains) do
            if string.find(domain, subDomain) then
                return true
            end
        end
    end
    
    return false
end

-- 生成邮件标签
-- @param email: 邮件对象
-- @return table: 标签列表
function generateTags(email)
    local tags = {}
    
    -- 根据主题生成标签
    local subjectLower = string.lower(email.subject or "")
    if string.find(subjectLower, "invoice") or string.find(subjectLower, "发票") then
        table.insert(tags, "发票")
    end
    if string.find(subjectLower, "receipt") or string.find(subjectLower, "收据") then
        table.insert(tags, "收据")
    end
    if string.find(subjectLower, "meeting") or string.find(subjectLower, "会议") then
        table.insert(tags, "会议")
    end
    
    -- 根据发件人生成标签
    local fromEmail = string.lower(email.from.email or "")
    if string.find(fromEmail, "github") then
        table.insert(tags, "GitHub")
    elseif string.find(fromEmail, "amazon") then
        table.insert(tags, "购物")
    elseif string.find(fromEmail, "bank") or string.find(fromEmail, "银行") then
        table.insert(tags, "银行")
    end
    
    -- 根据附件生成标签
    if email.hasAttachments then
        table.insert(tags, "附件")
    end
    
    return tags
end

-- 判断邮件优先级
-- @param email: 邮件对象
-- @return string: 优先级 ("low", "normal", "high", "urgent")
function getPriority(email)
    -- 如果已经标记为重要，返回高优先级
    if isImportant(email) then
        return "high"
    end
    
    -- 如果是垃圾邮件，返回低优先级
    if isSpam(email) then
        return "low"
    end
    
    -- 如果是订阅邮件，返回低优先级
    if isSubscription(email) then
        return "low"
    end
    
    -- 检查时间敏感关键词
    local urgentKeywords = {"asap", "立即", "urgent", "紧急", "deadline", "截止"}
    local subjectLower = string.lower(email.subject or "")
    local body = string.lower(email.textBody or email.preview or "")
    
    for _, keyword in ipairs(urgentKeywords) do
        if string.find(subjectLower, keyword) or string.find(body, keyword) then
            return "urgent"
        end
    end
    
    return "normal"
end

-- 主规则处理函数
-- 这个函数会被规则引擎调用，返回处理结果
-- @param email: 邮件对象
-- @return table: 处理结果，包含 isImportant, isSpam, isSubscription, tags, priority 等字段
function processEmail(email)
    local result = {
        isImportant = isImportant(email),
        isSpam = isSpam(email),
        isSubscription = isSubscription(email),
        tags = generateTags(email),
        priority = getPriority(email)
    }
    
    return result
end

