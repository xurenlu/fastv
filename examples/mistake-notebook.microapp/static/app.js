let currentImageUrl = null;
let mistakeInfo = null;

if (!window.row1) {
  console.error('row1 bridge 未找到');
  document.body.innerHTML = '<div style="padding: 40px; text-align: center;"><h2>错误</h2><p>无法连接到 row1 平台</p></div>';
}

document.getElementById('pick-btn').addEventListener('click', () => {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = 'image/*';
  input.onchange = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    
    const reader = new FileReader();
    reader.onload = (e) => {
      const preview = document.getElementById('preview');
      const placeholder = document.getElementById('placeholder');
      
      preview.src = e.target.result;
      preview.style.display = 'block';
      placeholder.style.display = 'none';
      
      document.getElementById('analyze-btn').disabled = false;
      
      document.getElementById('result').textContent = '';
      document.getElementById('plan-content').textContent = '';
      document.getElementById('plan-section').style.display = 'none';
    };
    reader.readAsDataURL(file);
    
    try {
      const imageUrl = await window.row1.uploadFile(file);
      currentImageUrl = imageUrl;
      window.row1.showToast('图片上传成功');
    } catch (error) {
      console.error('上传失败:', error);
      alert('图片上传失败: ' + error.message);
    }
  };
  input.click();
});

document.getElementById('analyze-btn').addEventListener('click', async () => {
  if (!currentImageUrl) {
    alert('请先选择并上传错题图片');
    return;
  }
  
  const resultDiv = document.getElementById('result');
  resultDiv.textContent = '正在分析错题...';
  resultDiv.style.color = '#86868b';
  
  try {
    const result = await window.row1.vision({
      imageUrl: currentImageUrl,
      prompt: '请识别这张错题图片，分析：1. 题目内容 2. 错误类型（计算错误/概念错误/方法错误等）3. 知识点分类 4. 正确解法。请用清晰的结构列出。'
    });
    
    mistakeInfo = result;
    resultDiv.textContent = result;
    resultDiv.style.color = '#1d1d1f';
    
    document.getElementById('plan-section').style.display = 'block';
    window.row1.showToast('分析完成！');
  } catch (e) {
    console.error('分析失败:', e);
    resultDiv.textContent = '分析失败: ' + e.message;
    resultDiv.style.color = '#ff3b30';
  }
});

document.getElementById('plan-btn').addEventListener('click', async () => {
  const planDiv = document.getElementById('plan-content');
  planDiv.textContent = '正在生成复习计划...';
  planDiv.style.color = '#86868b';
  
  try {
    const tips = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是一位经验丰富的学习规划师，擅长根据错题分析制定个性化的复习计划。' 
        },
        { 
          role: 'user', 
          content: `基于以下错题分析，请生成一份详细的复习计划，包括：
1. 错题分类整理
2. 薄弱知识点总结
3. 针对性练习建议
4. 复习时间安排（建议每天15-30分钟）
5. 相关题目推荐

错题分析：
${mistakeInfo || '未提供'}`
        }
      ],
      temperature: 0.7,
      maxTokens: 1500
    });
    
    planDiv.textContent = tips;
    planDiv.style.color = '#1d1d1f';
    window.row1.showToast('复习计划已生成！');
  } catch (e) {
    console.error('生成计划失败:', e);
    planDiv.textContent = '生成失败: ' + e.message;
    planDiv.style.color = '#ff3b30';
  }
});

