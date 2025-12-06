if (!window.row1) {
  console.error('row1 bridge 未找到');
  document.body.innerHTML = '<div style="padding: 40px; text-align: center;"><h2>错误</h2><p>无法连接到 row1 平台</p></div>';
}

document.getElementById('analyze-btn').addEventListener('click', async () => {
  const textInput = document.getElementById('text-input').value.trim();
  if (!textInput) {
    alert('请输入英文内容');
    return;
  }
  
  const resultDiv = document.getElementById('result');
  resultDiv.textContent = '正在分析发音...';
  resultDiv.style.color = '#86868b';
  
  try {
    const result = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是一位专业的英语口语教练，擅长分析发音、语法和表达，并给出具体的改进建议。' 
        },
        { 
          role: 'user', 
          content: `请分析以下英文内容的发音、语法和表达，给出：
1. 发音评分（满分10分）和重点单词的音标
2. 语法检查（如有错误请指出）
3. 表达优化建议（更地道的说法）
4. 发音技巧提示

内容：${textInput}`
        }
      ],
      temperature: 0.7,
      maxTokens: 1000
    });
    
    resultDiv.textContent = result;
    resultDiv.style.color = '#1d1d1f';
    document.getElementById('practice-section').style.display = 'block';
    window.row1.showToast('分析完成！');
  } catch (e) {
    console.error('分析失败:', e);
    resultDiv.textContent = '分析失败: ' + e.message;
    resultDiv.style.color = '#ff3b30';
  }
});

document.getElementById('practice-btn').addEventListener('click', async () => {
  const textInput = document.getElementById('text-input').value.trim();
  if (!textInput) {
    alert('请先输入英文内容');
    return;
  }
  
  const practiceDiv = document.getElementById('practice-content');
  practiceDiv.textContent = '正在生成对话练习...';
  practiceDiv.style.color = '#86868b';
  
  try {
    const result = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是一位英语口语教练，擅长设计实用的对话练习场景。' 
        },
        { 
          role: 'user', 
          content: `基于以下内容，请设计3-5个相关的对话练习场景，每个场景包括：
1. 场景描述
2. 对话示例（包含用户和对方的对话）
3. 重点词汇和表达

用户内容：${textInput}`
        }
      ],
      temperature: 0.8,
      maxTokens: 1500
    });
    
    practiceDiv.textContent = result;
    practiceDiv.style.color = '#1d1d1f';
    window.row1.showToast('对话练习已生成！');
  } catch (e) {
    console.error('生成失败:', e);
    practiceDiv.textContent = '生成失败: ' + e.message;
    practiceDiv.style.color = '#ff3b30';
  }
});

