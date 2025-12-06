let currentImageUrl = null;
let outfitDescription = null;

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
      
      document.getElementById('analyze-btn').disabled = false;
      
      // 清空之前的结果
      document.getElementById('result').textContent = '';
      document.getElementById('advice-content').textContent = '';
      document.getElementById('advice-section').style.display = 'none';
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

// 分析穿搭
document.getElementById('analyze-btn').addEventListener('click', async () => {
  if (!currentImageUrl) {
    alert('请先选择并上传图片');
    return;
  }
  
  const resultDiv = document.getElementById('result');
  resultDiv.textContent = '分析中...';
  resultDiv.style.color = '#718096';
  
  try {
    const result = await window.row1.vision({
      imageUrl: currentImageUrl,
      prompt: '请详细分析这张穿搭照片，包括：1. 整体风格（如：休闲、正式、运动、复古等）2. 主要单品（上衣、下装、鞋子、配饰等）3. 颜色搭配分析 4. 风格特点。请用简洁明了的语言描述。'
    });
    
    resultDiv.textContent = result;
    resultDiv.style.color = '#2d3748';
    outfitDescription = result;
    
    // 显示搭配建议按钮
    document.getElementById('advice-section').style.display = 'block';
    
    // 显示成功提示
    window.row1.showToast('分析成功！');
  } catch (e) {
    console.error('分析失败:', e);
    resultDiv.textContent = '分析失败: ' + e.message;
    resultDiv.style.color = '#e53e3e';
  }
});

// 获取搭配建议
document.getElementById('advice-btn').addEventListener('click', async () => {
  const adviceDiv = document.getElementById('advice-content');
  adviceDiv.textContent = '生成建议中...';
  adviceDiv.style.color = '#718096';
  
  try {
    const advice = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是专业的时尚顾问和搭配师，擅长分析穿搭风格并提供专业的搭配建议。请用清晰的结构和易懂的语言回答。' 
        },
        { 
          role: 'user', 
          content: `基于以下穿搭分析，请给出专业的搭配建议：

${outfitDescription || '当前穿搭'}

请提供以下方面的建议：
1. 风格评价（优点和改进空间）
2. 场合适用性（适合什么场合，如：工作、约会、休闲等）
3. 改进建议（可以如何优化搭配）
4. 替代搭配方案（2-3个不同的搭配思路）
5. 配饰建议（推荐搭配的配饰）
6. 季节适应性（是否适合当前季节）

请用清晰的格式组织内容。`
        }
      ],
      temperature: 0.7,
      maxTokens: 1500
    });
    
    adviceDiv.textContent = advice;
    adviceDiv.style.color = '#2d3748';
    
    // 显示成功提示
    window.row1.showToast('搭配建议已生成！');
  } catch (e) {
    console.error('获取建议失败:', e);
    adviceDiv.textContent = '获取失败: ' + e.message;
    adviceDiv.style.color = '#e53e3e';
  }
});

