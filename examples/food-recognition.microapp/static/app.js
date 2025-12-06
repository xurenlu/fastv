let currentImageUrl = null;
let foodName = null;

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
      
      document.getElementById('recognize-btn').disabled = false;
      
      // 清空之前的结果
      document.getElementById('result').textContent = '';
      document.getElementById('nutrition-info').textContent = '';
      document.getElementById('nutrition-section').style.display = 'none';
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

// 识别美食
document.getElementById('recognize-btn').addEventListener('click', async () => {
  if (!currentImageUrl) {
    alert('请先选择并上传图片');
    return;
  }
  
  const resultDiv = document.getElementById('result');
  resultDiv.textContent = '识别中...';
  resultDiv.style.color = '#718096';
  
  try {
    const result = await window.row1.vision({
      imageUrl: currentImageUrl,
      prompt: '请识别这张图片中的美食，告诉我它的名称、主要食材和基本特征。请用简洁明了的语言描述。'
    });
    
    resultDiv.textContent = result;
    resultDiv.style.color = '#2d3748';
    
    // 简单提取美食名称（取第一行或前几个字）
    const lines = result.split('\n');
    foodName = lines[0].replace(/^[^：:]*[：:]?\s*/, '').trim();
    if (foodName.length > 30) {
      foodName = foodName.substring(0, 30);
    }
    
    // 显示营养分析按钮
    document.getElementById('nutrition-section').style.display = 'block';
    
    // 显示成功提示
    window.row1.showToast('识别成功！');
  } catch (e) {
    console.error('识别失败:', e);
    resultDiv.textContent = '识别失败: ' + e.message;
    resultDiv.style.color = '#e53e3e';
  }
});

// 获取营养分析
document.getElementById('nutrition-btn').addEventListener('click', async () => {
  const nutritionDiv = document.getElementById('nutrition-info');
  nutritionDiv.textContent = '分析中...';
  nutritionDiv.style.color = '#718096';
  
  try {
    const tips = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是专业的营养师和美食专家，擅长分析食物的营养成分和健康建议。请用清晰的结构和易懂的语言回答。' 
        },
        { 
          role: 'user', 
          content: `请给出「${foodName || '这道美食'}」的详细营养分析，包括以下方面：
1. 主要营养成分（蛋白质、脂肪、碳水化合物、纤维等）
2. 卡路里估算（每100克或每份）
3. 维生素和矿物质含量
4. 健康建议（适合人群、注意事项）
5. 减肥/健身建议（如果需要）
6. 搭配建议（推荐搭配的食物）

请用清晰的格式组织内容，数据尽量准确。`
        }
      ],
      temperature: 0.7,
      maxTokens: 1500
    });
    
    nutritionDiv.textContent = tips;
    nutritionDiv.style.color = '#2d3748';
    
    // 显示成功提示
    window.row1.showToast('营养分析已生成！');
  } catch (e) {
    console.error('获取营养分析失败:', e);
    nutritionDiv.textContent = '获取失败: ' + e.message;
    nutritionDiv.style.color = '#e53e3e';
  }
});

