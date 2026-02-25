let currentImageUrl = null;
let recordText = null;

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
    return imageUrl;
  } catch (error) {
    console.error('上传错误:', error);
    resultDiv.textContent = '上传失败: ' + (error.message || error);
    resultDiv.style.color = '#e53e3e';
    throw error;
  }
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
      document.getElementById('analysis-content').textContent = '';
      document.getElementById('summary-content').textContent = '';
      document.getElementById('analysis-section').style.display = 'none';
    };
    reader.readAsDataURL(file);
    
    try {
      await uploadImage(file);
    } catch (error) {
      alert('图片上传失败: ' + error.message);
    }
  };
  input.click();
});

document.getElementById('analyze-btn').addEventListener('click', async () => {
  if (!currentImageUrl) {
    alert('请先选择并上传图片');
    return;
  }
  
  const resultDiv = document.getElementById('result');
  const analysisDiv = document.getElementById('analysis-content');
  
  resultDiv.textContent = '识别病历内容中...';
  resultDiv.style.color = '#718096';
  
  try {
    const recognitionResult = await window.row1.vision({
      imageUrl: currentImageUrl,
      prompt: '请识别这张病历或检查报告中的所有文字内容，保持原有的格式和结构。'
    });
    
    recordText = recognitionResult;
    resultDiv.textContent = '原始内容：\n' + recognitionResult;
    resultDiv.style.color = '#2d3748';
    
    analysisDiv.textContent = '分析中...';
    analysisDiv.style.color = '#718096';
    document.getElementById('analysis-section').style.display = 'block';
    
    const analysis = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是一位经验丰富的医生，擅长解读病历和检查报告，能够识别关键医疗信息。' 
        },
        { 
          role: 'user', 
          content: `请分析以下病历或检查报告内容：

${recognitionResult}

请提取并整理以下信息：
1. 患者基本信息（姓名、年龄、性别等）
2. 主诉和现病史
3. 检查项目及结果（如血常规、影像检查等）
4. 诊断结果
5. 治疗方案或建议
6. 异常指标标注（如有）
7. 注意事项

请用清晰的格式组织内容，对异常值进行重点标注。`
        }
      ],
      temperature: 0.7,
      maxTokens: 2000
    });
    
    analysisDiv.textContent = analysis;
    analysisDiv.style.color = '#2d3748';
    
    window.row1.showToast('分析完成！');
  } catch (e) {
    console.error('分析失败:', e);
    resultDiv.textContent = '失败: ' + e.message;
    resultDiv.style.color = '#e53e3e';
  }
});

document.getElementById('summary-btn').addEventListener('click', async () => {
  const summaryDiv = document.getElementById('summary-content');
  summaryDiv.textContent = '生成摘要中...';
  summaryDiv.style.color = '#718096';
  
  try {
    const summary = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是专业的医疗文档整理助手，擅长将复杂的病历信息整理成简洁清晰的摘要。' 
        },
        { 
          role: 'user', 
          content: `请基于以下病历内容，生成一份简洁的病历摘要：

${recordText}

请包含：
1. 患者基本信息
2. 主要诊断
3. 关键检查结果
4. 治疗要点
5. 随访建议

请用简洁明了的语言，控制在200字以内。`
        }
      ],
      temperature: 0.7,
      maxTokens: 500
    });
    
    summaryDiv.textContent = summary;
    summaryDiv.style.color = '#2d3748';
    
    window.row1.showToast('摘要已生成！');
  } catch (e) {
    console.error('生成摘要失败:', e);
    summaryDiv.textContent = '生成失败: ' + e.message;
    summaryDiv.style.color = '#e53e3e';
  }
});

