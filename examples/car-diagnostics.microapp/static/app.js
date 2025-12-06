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
          content: `请根据故障描述进行分析，包括：1. 可能的故障原因 2. 严重程度 3. 应急处理方法 4. 是否需要立即维修 5. 维修建议和注意事项。\n\n内容：${textInput}`
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