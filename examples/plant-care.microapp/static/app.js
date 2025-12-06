let currentImage = null;
let plantName = null;

// 检查 row1 bridge 是否可用
if (!window.row1) {
  console.error('row1 bridge 未找到');
  document.body.innerHTML = '<div style="padding: 40px; text-align: center;"><h2>错误</h2><p>无法连接到 row1 平台</p></div>';
}

document.getElementById('pick-btn').addEventListener('click', async () => {
  try {
    const base64 = await window.row1.pickImage();
    if (base64 && base64.length > 0) {
      currentImage = base64;
      const preview = document.getElementById('preview');
      const placeholder = document.getElementById('placeholder');
      
      preview.src = base64;
      preview.style.display = 'block';
      placeholder.style.display = 'none';
      
      document.getElementById('recognize-btn').disabled = false;
      
      // 清空之前的结果
      document.getElementById('result').textContent = '';
      document.getElementById('care-tips').textContent = '';
      document.getElementById('care-section').style.display = 'none';
    }
  } catch (e) {
    console.error('选择图片失败:', e);
    alert('选择图片失败: ' + e.message);
  }
});

document.getElementById('recognize-btn').addEventListener('click', async () => {
  if (!currentImage) return;
  
  const resultDiv = document.getElementById('result');
  resultDiv.textContent = '识别中...';
  resultDiv.style.color = '#718096';
  
  try {
    const result = await window.row1.vision({
      imageBase64: currentImage,
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

