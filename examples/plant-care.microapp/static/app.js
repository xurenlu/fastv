let currentImageUrl = null;
let plantName = null;

// 检查 row1 bridge 是否可用
if (!window.row1) {
  console.error('row1 bridge 未找到');
  document.body.innerHTML = '<div style="padding: 40px; text-align: center;"><h2>错误</h2><p>无法连接到 row1 平台</p></div>';
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
      document.getElementById('care-tips').textContent = '';
      document.getElementById('care-section').style.display = 'none';
    };
    reader.readAsDataURL(file);
    
    // 上传文件到云存储（这里使用示例：imgur.com 作为演示）
    // 实际应用中，开发者需要实现自己的上传逻辑
    try {
      await uploadImage(file);
    } catch (error) {
      console.error('上传失败:', error);
      alert('图片上传失败，请检查网络连接或使用其他上传服务。错误: ' + error.message);
    }
  };
  input.click();
});

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
      prompt: '请识别这张图片中的植物，告诉我它的名称和基本特征。请用简洁明了的语言描述。'
    });
    
    resultDiv.textContent = result;
    resultDiv.style.color = '#2d3748';
    
    // 简单提取植物名称（取第一行或前几个字）
    const lines = result.split('\n');
    plantName = lines[0].replace(/^[^：:]*[：:]?\s*/, '').trim();
    if (plantName.length > 20) {
      plantName = plantName.substring(0, 20);
    }
    
    // 显示养护建议按钮
    document.getElementById('care-section').style.display = 'block';
    
    // 显示成功提示
    window.row1.showToast('识别成功！');
  } catch (e) {
    console.error('识别失败:', e);
    resultDiv.textContent = '识别失败: ' + e.message;
    resultDiv.style.color = '#e53e3e';
  }
});

document.getElementById('care-btn').addEventListener('click', async () => {
  const careTipsDiv = document.getElementById('care-tips');
  careTipsDiv.textContent = '获取养护建议中...';
  careTipsDiv.style.color = '#718096';
  
  try {
    const tips = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是专业的植物养护专家，擅长提供详细的植物养护指南。请用清晰的结构和易懂的语言回答。' 
        },
        { 
          role: 'user', 
          content: `请给出「${plantName || '这种植物'}」的详细养护指南，包括以下方面：
1. 浇水频率和方法
2. 光照需求
3. 温度要求
4. 土壤和施肥建议
5. 常见病虫害防治
6. 其他注意事项

请用清晰的格式组织内容。`
        }
      ],
      temperature: 0.7,
      maxTokens: 1500
    });
    
    careTipsDiv.textContent = tips;
    careTipsDiv.style.color = '#2d3748';
    
    // 显示成功提示
    window.row1.showToast('养护建议已生成！');
  } catch (e) {
    console.error('获取养护建议失败:', e);
    careTipsDiv.textContent = '获取失败: ' + e.message;
    careTipsDiv.style.color = '#e53e3e';
  }
});

