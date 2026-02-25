let currentImageUrl = null;
let homeworkContent = null;

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
      
      document.getElementById('check-btn').disabled = false;
      
      document.getElementById('result').textContent = '';
      document.getElementById('score-content').textContent = '';
      document.getElementById('score-section').style.display = 'none';
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

document.getElementById('check-btn').addEventListener('click', async () => {
  if (!currentImageUrl) {
    alert('请先选择并上传作业图片');
    return;
  }
  
  const resultDiv = document.getElementById('result');
  resultDiv.textContent = '正在检查作业...';
  resultDiv.style.color = '#86868b';
  
  try {
    const result = await window.row1.vision({
      imageUrl: currentImageUrl,
      prompt: '请仔细检查这张作业图片，识别作业内容，指出错误和需要改进的地方。请用清晰的结构列出：1. 正确答案 2. 错误之处 3. 改进建议。'
    });
    
    homeworkContent = result;
    resultDiv.textContent = result;
    resultDiv.style.color = '#1d1d1f';
    
    document.getElementById('score-section').style.display = 'block';
    window.row1.showToast('检查完成！');
  } catch (e) {
    console.error('检查失败:', e);
    resultDiv.textContent = '检查失败: ' + e.message;
    resultDiv.style.color = '#ff3b30';
  }
});

document.getElementById('score-btn').addEventListener('click', async () => {
  const scoreDiv = document.getElementById('score-content');
  scoreDiv.textContent = '正在生成评分和建议...';
  scoreDiv.style.color = '#86868b';
  
  try {
    const tips = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是一位经验丰富的教师，擅长给学生作业评分并提供建设性的改进建议。请用鼓励的语气，给出具体的改进方向。' 
        },
        { 
          role: 'user', 
          content: `基于以下作业检查结果，请给出：
1. 综合评分（满分100分）
2. 优点总结
3. 需要改进的地方
4. 具体的学习建议

作业检查结果：
${homeworkContent || '未提供'}`
        }
      ],
      temperature: 0.7,
      maxTokens: 1500
    });
    
    scoreDiv.textContent = tips;
    scoreDiv.style.color = '#1d1d1f';
    window.row1.showToast('评分和建议已生成！');
  } catch (e) {
    console.error('获取评分失败:', e);
    scoreDiv.textContent = '获取失败: ' + e.message;
    scoreDiv.style.color = '#ff3b30';
  }
});

