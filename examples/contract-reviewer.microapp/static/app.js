let currentImageUrl = null;
let contractText = null;

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
    
    const reader = new FileReader();
    reader.onload = (e) => {
      const preview = document.getElementById('preview');
      const placeholder = document.getElementById('placeholder');
      preview.src = e.target.result;
      preview.style.display = 'block';
      placeholder.style.display = 'none';
      document.getElementById('review-btn').disabled = false;
      document.getElementById('result').textContent = '';
      document.getElementById('review-content').textContent = '';
      document.getElementById('suggestions').textContent = '';
      document.getElementById('review-section').style.display = 'none';
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

// 审查合同
document.getElementById('review-btn').addEventListener('click', async () => {
  if (!currentImageUrl) {
    alert('请先选择并上传图片');
    return;
  }
  
  const resultDiv = document.getElementById('result');
  const reviewDiv = document.getElementById('review-content');
  
  resultDiv.textContent = '识别合同内容中...';
  resultDiv.style.color = '#718096';
  
  try {
    // 第一步：识别合同文字
    const recognitionResult = await window.row1.vision({
      imageUrl: currentImageUrl,
      prompt: '请识别这张合同图片中的所有文字内容，保持原有的格式和段落结构。'
    });
    
    contractText = recognitionResult;
    resultDiv.textContent = '合同内容：\n' + recognitionResult;
    resultDiv.style.color = '#2d3748';
    
    // 第二步：审查合同
    reviewDiv.textContent = '审查中...';
    reviewDiv.style.color = '#718096';
    document.getElementById('review-section').style.display = 'block';
    
    const review = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是一位经验丰富的法律专家，擅长合同审查和风险识别。请用专业但易懂的语言分析合同。' 
        },
        { 
          role: 'user', 
          content: `请审查以下合同内容，并提供专业的审查意见：

${recognitionResult}

请从以下方面进行审查：
1. 合同主体信息（双方身份、资质是否明确）
2. 关键条款识别（标的、价格、交付方式、付款方式等）
3. 风险点识别（对己方不利的条款、模糊表述、缺失条款）
4. 权利义务是否对等
5. 违约责任条款是否合理
6. 争议解决方式
7. 其他需要注意的事项

请用清晰的格式组织内容，对风险点进行重点标注。`
        }
      ],
      temperature: 0.7,
      maxTokens: 2000
    });
    
    reviewDiv.textContent = review;
    reviewDiv.style.color = '#2d3748';
    
    window.row1.showToast('审查完成！');
  } catch (e) {
    console.error('审查失败:', e);
    resultDiv.textContent = '失败: ' + e.message;
    resultDiv.style.color = '#e53e3e';
  }
});

// 获取修改建议
document.getElementById('suggest-btn').addEventListener('click', async () => {
  const suggestionsDiv = document.getElementById('suggestions');
  suggestionsDiv.textContent = '生成建议中...';
  suggestionsDiv.style.color = '#718096';
  
  try {
    const suggestions = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是专业的法律顾问，擅长提供合同修改建议和条款优化方案。' 
        },
        { 
          role: 'user', 
          content: `基于以下合同内容，请提供具体的修改建议和优化方案：

${contractText}

请提供：
1. 需要修改的具体条款
2. 建议的修改表述
3. 需要补充的条款
4. 修改后的完整条款示例

请用清晰的格式组织内容。`
        }
      ],
      temperature: 0.7,
      maxTokens: 2000
    });
    
    suggestionsDiv.textContent = suggestions;
    suggestionsDiv.style.color = '#2d3748';
    
    window.row1.showToast('修改建议已生成！');
  } catch (e) {
    console.error('生成建议失败:', e);
    suggestionsDiv.textContent = '生成失败: ' + e.message;
    suggestionsDiv.style.color = '#e53e3e';
  }
});

