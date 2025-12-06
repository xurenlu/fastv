let currentImageUrl = null;
let essayContent = null;

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
      
      document.getElementById('grade-btn').disabled = false;
      
      document.getElementById('result').textContent = '';
      document.getElementById('suggestions-content').textContent = '';
      document.getElementById('suggestions-section').style.display = 'none';
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

document.getElementById('grade-btn').addEventListener('click', async () => {
  if (!currentImageUrl) {
    alert('请先选择并上传作文图片');
    return;
  }
  
  const resultDiv = document.getElementById('result');
  resultDiv.textContent = '正在识别和批改作文...';
  resultDiv.style.color = '#86868b';
  
  try {
    const result = await window.row1.vision({
      imageUrl: currentImageUrl,
      prompt: '请识别这张作文图片，提取完整的作文内容，然后进行批改：1. 识别作文全文 2. 给出综合评分（满分100分）3. 指出优点 4. 指出需要改进的地方。请用清晰的结构列出。'
    });
    
    essayContent = result;
    resultDiv.textContent = result;
    resultDiv.style.color = '#1d1d1f';
    
    document.getElementById('suggestions-section').style.display = 'block';
    window.row1.showToast('批改完成！');
  } catch (e) {
    console.error('批改失败:', e);
    resultDiv.textContent = '批改失败: ' + e.message;
    resultDiv.style.color = '#ff3b30';
  }
});

document.getElementById('suggestions-btn').addEventListener('click', async () => {
  const suggestionsDiv = document.getElementById('suggestions-content');
  suggestionsDiv.textContent = '正在生成修改建议...';
  suggestionsDiv.style.color = '#86868b';
  
  try {
    const tips = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是一位经验丰富的语文教师，擅长批改作文并给出具体的修改建议。请用鼓励的语气，指出可以改进的具体地方，并给出修改示例。' 
        },
        { 
          role: 'user', 
          content: `基于以下作文批改结果，请给出详细的修改建议，包括：
1. 段落结构优化建议
2. 语言表达改进（给出具体修改示例）
3. 内容深化建议
4. 修辞手法运用建议
5. 错别字和标点符号修正

作文批改结果：
${essayContent || '未提供'}`
        }
      ],
      temperature: 0.7,
      maxTokens: 1500
    });
    
    suggestionsDiv.textContent = tips;
    suggestionsDiv.style.color = '#1d1d1f';
    window.row1.showToast('修改建议已生成！');
  } catch (e) {
    console.error('获取建议失败:', e);
    suggestionsDiv.textContent = '获取失败: ' + e.message;
    suggestionsDiv.style.color = '#ff3b30';
  }
});

