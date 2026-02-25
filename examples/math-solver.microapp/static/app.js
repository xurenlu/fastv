let currentImageUrl = null;
let problemDescription = null;

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
      
      document.getElementById('solve-btn').disabled = false;
      
      // 清空之前的结果
      document.getElementById('result').textContent = '';
      document.getElementById('solution-content').textContent = '';
      document.getElementById('solution-section').style.display = 'none';
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

// 识别题目
document.getElementById('solve-btn').addEventListener('click', async () => {
  if (!currentImageUrl) {
    alert('请先选择并上传图片');
    return;
  }
  
  const resultDiv = document.getElementById('result');
  resultDiv.textContent = '识别题目中...';
  resultDiv.style.color = '#718096';
  
  try {
    const result = await window.row1.vision({
      imageUrl: currentImageUrl,
      prompt: '请识别这张图片中的数学题目，包括题目内容、已知条件、要求解的问题。请用清晰的语言描述题目。如果图片中没有数学题目，请说明。'
    });
    
    problemDescription = result;
    resultDiv.textContent = '题目：\n' + result;
    resultDiv.style.color = '#2d3748';
    
    // 显示详细讲解按钮
    document.getElementById('solution-section').style.display = 'block';
    
    // 显示成功提示
    window.row1.showToast('题目识别成功！');
  } catch (e) {
    console.error('识别失败:', e);
    resultDiv.textContent = '识别失败: ' + e.message;
    resultDiv.style.color = '#e53e3e';
  }
});

// 获取详细解题步骤
document.getElementById('explain-btn').addEventListener('click', async () => {
  const solutionDiv = document.getElementById('solution-content');
  solutionDiv.textContent = '解题中...';
  solutionDiv.style.color = '#718096';
  
  try {
    const solution = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是一位经验丰富的数学老师，擅长用清晰易懂的方式讲解数学题目，提供详细的解题步骤和知识点说明。' 
        },
        { 
          role: 'user', 
          content: `请解答以下数学题目，并提供详细的讲解：

${problemDescription || '当前题目'}

请按照以下格式提供解答：
1. 题目分析（理解题意，明确已知条件和求解目标）
2. 解题思路（解题的关键思路和方法）
3. 详细解题步骤（每一步都要详细说明，包括使用的公式、定理等）
4. 答案（最终答案）
5. 知识点总结（这道题涉及的主要知识点）
6. 举一反三（提供1-2道类似的练习题，帮助学生巩固）

请用清晰的格式组织内容，确保学生能够理解每一步。`
        }
      ],
      temperature: 0.7,
      maxTokens: 2000
    });
    
    solutionDiv.textContent = solution;
    solutionDiv.style.color = '#2d3748';
    
    // 显示成功提示
    window.row1.showToast('解题完成！');
  } catch (e) {
    console.error('解题失败:', e);
    solutionDiv.textContent = '解题失败: ' + e.message;
    solutionDiv.style.color = '#e53e3e';
  }
});

