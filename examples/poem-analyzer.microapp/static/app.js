let currentImageUrl = null;

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
    alert('请先选择并上传诗词图片');
    return;
  }
  
  const resultDiv = document.getElementById('result');
  resultDiv.textContent = '正在识别和分析诗词...';
  resultDiv.style.color = '#86868b';
  
  try {
    const result = await window.row1.vision({
      imageUrl: currentImageUrl,
      prompt: '请识别这张图片中的古诗词内容，然后提供：1. 诗词全文 2. 逐句翻译 3. 整体赏析（包括意境、情感、艺术手法）4. 作者背景和创作背景 5. 相关典故。请用清晰的结构组织内容。'
    });
    
    resultDiv.textContent = result;
    resultDiv.style.color = '#1d1d1f';
    window.row1.showToast('赏析完成！');
  } catch (e) {
    console.error('赏析失败:', e);
    resultDiv.textContent = '赏析失败: ' + e.message;
    resultDiv.style.color = '#ff3b30';
  }
});

