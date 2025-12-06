if (!window.row1) {
  console.error('row1 bridge 未找到');
  document.body.innerHTML = '<div style="padding: 40px; text-align: center;"><h2>错误</h2><p>无法连接到 row1 平台</p></div>';
}

document.getElementById('generate-btn').addEventListener('click', async () => {
  const wordInput = document.getElementById('word-input').value.trim();
  if (!wordInput) {
    alert('请输入单词');
    return;
  }
  
  const words = wordInput.split(',').map(w => w.trim()).filter(w => w);
  
  const resultDiv = document.getElementById('result');
  resultDiv.textContent = '正在生成记忆卡片...';
  resultDiv.style.color = '#86868b';
  
  try {
    const result = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是一位英语教学专家，擅长制作单词记忆卡片。请为每个单词提供：1. 音标和发音 2. 中文释义 3. 英文例句（2-3个）4. 记忆技巧（词根、联想等）5. 相关词汇。请用清晰的格式组织，每个单词之间用分隔线分开。' 
        },
        { 
          role: 'user', 
          content: `请为以下单词生成记忆卡片：\n${words.join(', ')}`
        }
      ],
      temperature: 0.7,
      maxTokens: 2000
    });
    
    resultDiv.textContent = result;
    resultDiv.style.color = '#1d1d1f';
    window.row1.showToast('记忆卡片已生成！');
  } catch (e) {
    console.error('生成失败:', e);
    resultDiv.textContent = '生成失败: ' + e.message;
    resultDiv.style.color = '#ff3b30';
  }
});

