let currentImageUrl = null;
let originalText = null;

// 检查 row1 bridge 是否可用
if (!window.row1) {
  console.error('row1 bridge 未找到');
  document.body.innerHTML = '<div style="padding: 40px; text-align: center;"><h2>错误</h2><p>无法连接到 row1 平台</p></div>';
}

// 上传图片（使用 row1 平台提供的上传 API）
async function uploadImage(file) {
  const resultDiv = document.getElementById('result');
  resultDiv.textContent = '正在上传图片...';
  resultDiv.style.color = '#718096';
  
  try {
    // 使用 row1 平台提供的上传 API
    const imageUrl = await window.row1.uploadFile(file);
    currentImageUrl = imageUrl;
    resultDiv.textContent = '图片上传成功！';
    resultDiv.style.color = '#48bb78';
    console.log('图片上传成功，URL:', currentImageUrl);
    return imageUrl;
  } catch (error) {
    console.error('上传错误:', error);
    resultDiv.textContent = '上传失败: ' + (error.message || error);
    resultDiv.style.color = '#e53e3e';
    throw error;
  }
}

// 文件选择和处理
document.getElementById('pick-btn').addEventListener('click', () => {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = 'image/*';
  input.onchange = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    
    // 显示预览
    const reader = new FileReader();
    reader.onload = (e) => {
      const preview = document.getElementById('preview');
      const placeholder = document.getElementById('placeholder');
      
      preview.src = e.target.result;
      preview.style.display = 'block';
      placeholder.style.display = 'none';
      
      document.getElementById('translate-btn').disabled = false;
      
      // 清空之前的结果
      document.getElementById('result').textContent = '';
      document.getElementById('translation-content').textContent = '';
      document.getElementById('translation-section').style.display = 'none';
    };
    reader.readAsDataURL(file);
    
    // 上传文件到云存储
    try {
      await uploadImage(file);
    } catch (error) {
      console.error('上传失败:', error);
      alert('图片上传失败，请检查网络连接。错误: ' + error.message);
    }
  };
  input.click();
});

// 识别并翻译
document.getElementById('translate-btn').addEventListener('click', async () => {
  if (!currentImageUrl) {
    alert('请先选择并上传图片');
    return;
  }
  
  const targetLang = document.getElementById('target-lang').value;
  const resultDiv = document.getElementById('result');
  const translationDiv = document.getElementById('translation-content');
  
  resultDiv.textContent = '识别文字中...';
  resultDiv.style.color = '#718096';
  
  try {
    // 第一步：识别图片中的文字
    const recognitionResult = await window.row1.vision({
      imageUrl: currentImageUrl,
      prompt: '请识别这张图片中的所有文字内容，保持原有的格式和换行。如果图片中没有文字，请说明。'
    });
    
    originalText = recognitionResult;
    resultDiv.textContent = '原文：\n' + recognitionResult;
    resultDiv.style.color = '#2d3748';
    
    // 第二步：翻译文字
    translationDiv.textContent = '翻译中...';
    translationDiv.style.color = '#718096';
    document.getElementById('translation-section').style.display = 'block';
    
    const translation = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是一个专业的翻译助手，擅长准确翻译各种语言的文本，保持原文的格式和语气。' 
        },
        { 
          role: 'user', 
          content: `请将以下文本翻译成${targetLang}，保持原有的格式、换行和结构：

${recognitionResult}

请只输出翻译结果，不要添加其他说明。`
        }
      ],
      temperature: 0.3,
      maxTokens: 2000
    });
    
    translationDiv.textContent = translation;
    translationDiv.style.color = '#2d3748';
    
    // 显示成功提示
    window.row1.showToast('翻译完成！');
  } catch (e) {
    console.error('识别或翻译失败:', e);
    resultDiv.textContent = '失败: ' + e.message;
    resultDiv.style.color = '#e53e3e';
    translationDiv.textContent = '翻译失败: ' + e.message;
    translationDiv.style.color = '#e53e3e';
  }
});

// 复制翻译结果
document.getElementById('copy-btn').addEventListener('click', async () => {
  const translationText = document.getElementById('translation-content').textContent;
  if (!translationText || translationText.includes('翻译结果将显示在这里')) {
    alert('没有可复制的内容');
    return;
  }
  
  try {
    await navigator.clipboard.writeText(translationText);
    window.row1.showToast('已复制到剪贴板！');
  } catch (e) {
    // 降级方案
    const textArea = document.createElement('textarea');
    textArea.value = translationText;
    textArea.style.position = 'fixed';
    textArea.style.opacity = '0';
    document.body.appendChild(textArea);
    textArea.select();
    try {
      document.execCommand('copy');
      window.row1.showToast('已复制到剪贴板！');
    } catch (err) {
      alert('复制失败，请手动复制');
    }
    document.body.removeChild(textArea);
  }
});

