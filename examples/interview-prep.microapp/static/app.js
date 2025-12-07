// 面试准备助手 v1.2.0

// 检查 bridge
if (!window.row1) {
  console.error('row1 bridge 未找到');
  document.body.innerHTML = `
    <div style="min-height: 100vh; display: flex; align-items: center; justify-content: center; background: #0f0f1a; color: #fff; font-family: system-ui;">
      <div style="text-align: center; padding: 40px;">
        <div style="font-size: 64px; margin-bottom: 24px;">⚠️</div>
        <h2 style="margin-bottom: 12px;">连接失败</h2>
        <p style="color: rgba(255,255,255,0.5);">无法连接到 row1 平台</p>
      </div>
    </div>
  `;
}

// DOM 元素
const textInput = document.getElementById('text-input');
const processBtn = document.getElementById('process-btn');
const resultSection = document.getElementById('result-section');
const resultDiv = document.getElementById('result');
const copyBtn = document.getElementById('copy-btn');
const tags = document.querySelectorAll('.tag');

// 快捷标签点击
tags.forEach(tag => {
  tag.addEventListener('click', () => {
    const value = tag.dataset.value;
    const currentText = textInput.value.trim();
    if (currentText) {
      textInput.value = `岗位：${value}\n\n${currentText}`;
    } else {
      textInput.value = `岗位：${value}\n\n请补充更多信息：\n• 目标公司：\n• 工作年限：\n• 技术/技能要求：\n• 其他要求：`;
    }
    textInput.focus();
  });
});

// 生成按钮点击
processBtn.addEventListener('click', async () => {
  const input = textInput.value.trim();
  if (!input) {
    shakeButton();
    textInput.focus();
    return;
  }
  
  // 设置加载状态
  setLoading(true);
  resultSection.classList.remove('show');
  
  try {
    const result = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: `你是一位资深的职业面试顾问，拥有丰富的招聘和面试经验。请根据用户提供的岗位信息，生成一份详细的面试准备材料。

输出格式要求：
1. 使用清晰的层级结构
2. 重点内容用【】标注
3. 每个部分之间空一行
4. 问题和答案要点分开列出` 
        },
        { 
          role: 'user', 
          content: `请为以下岗位生成面试准备材料：

${input}

请包含以下内容：

【一、岗位分析】
- 核心职责解读
- 关键能力要求

【二、常见面试问题】（10-15个）
- 自我介绍类
- 专业技能类
- 项目经验类
- 情景模拟类
- 职业规划类

【三、回答要点与技巧】
针对每类问题给出回答框架和要点

【四、可能的追问】
面试官可能的深入追问及应对

【五、你可以问面试官的问题】
展现专业度的反问建议（5个）

【六、面试注意事项】
着装、时间、心态等建议`
        }
      ],
      temperature: 0.7,
      maxTokens: 3000
    });
    
    // 显示结果
    resultDiv.textContent = result;
    resultSection.classList.add('show');
    
    // 滚动到结果区域
    setTimeout(() => {
      resultSection.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }, 100);
    
  } catch (e) {
    console.error('处理失败:', e);
    resultDiv.textContent = '生成失败，请稍后重试\n\n错误信息：' + (e.message || e);
    resultSection.classList.add('show');
  } finally {
    setLoading(false);
  }
});

// 复制按钮
copyBtn.addEventListener('click', async () => {
  const text = resultDiv.textContent;
  if (!text) return;
  
  try {
    await navigator.clipboard.writeText(text);
    const originalText = copyBtn.textContent;
    copyBtn.textContent = '✅ 已复制';
    setTimeout(() => {
      copyBtn.textContent = originalText;
    }, 2000);
  } catch (e) {
    console.error('复制失败:', e);
  }
});

// 设置加载状态
function setLoading(loading) {
  processBtn.disabled = loading;
  const btnText = processBtn.querySelector('.btn-text');
  
  if (loading) {
    btnText.innerHTML = '<span class="spinner"></span> 正在生成...';
  } else {
    btnText.innerHTML = '✨ 生成面试攻略';
  }
}

// 按钮抖动效果
function shakeButton() {
  processBtn.style.animation = 'shake 0.5s ease';
  setTimeout(() => {
    processBtn.style.animation = '';
  }, 500);
}

// 添加抖动动画
const style = document.createElement('style');
style.textContent = `
  @keyframes shake {
    0%, 100% { transform: translateX(0); }
    20%, 60% { transform: translateX(-8px); }
    40%, 80% { transform: translateX(8px); }
  }
`;
document.head.appendChild(style);
