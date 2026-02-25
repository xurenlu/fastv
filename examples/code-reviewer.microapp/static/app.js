if (!window.row1) {
  console.error('row1 bridge 未找到');
  document.body.innerHTML = '<div style="padding: 40px; text-align: center;"><h2>错误</h2><p>无法连接到 row1 平台</p></div>';
}

document.getElementById('process-btn').addEventListener('click', async () => {
  const textInput = document.getElementById('text-input').value.trim();
  if (!textInput) {
    alert('请输入内容');
    return;
  }
  
  const resultDiv = document.getElementById('result');
  resultDiv.textContent = '正在处理...';
  resultDiv.style.color = '#86868b';
  
  try {
    const result = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是一位专业的助手，擅长处理各类任务。' 
        },
        { 
          role: 'user', 
          content: `请审查以下代码，提供：1. 代码功能分析 2. 潜在问题（bug、性能、安全等）3. 代码风格建议 4. 优化方案 5. 改进后的代码示例。\n\n内容：${textInput}`
        }
      ],
      temperature: 0.7,
      maxTokens: 2000
    });
    
    resultDiv.textContent = result;
    resultDiv.style.color = '#1d1d1f';
    window.row1.showToast('处理完成！');
  } catch (e) {
    console.error('处理失败:', e);
    resultDiv.textContent = '处理失败: ' + e.message;
    resultDiv.style.color = '#ff3b30';
  }
});