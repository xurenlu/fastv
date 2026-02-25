let currentImageUrl = null;
let resumeText = null;
let jobDescription = '';

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

document.getElementById('job-desc').addEventListener('input', (e) => {
  jobDescription = e.target.value;
});

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
      document.getElementById('screen-btn').disabled = false;
      document.getElementById('result').textContent = '';
      document.getElementById('evaluation-content').textContent = '';
      document.getElementById('questions-content').textContent = '';
      document.getElementById('evaluation-section').style.display = 'none';
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

document.getElementById('screen-btn').addEventListener('click', async () => {
  if (!currentImageUrl) {
    alert('请先选择并上传简历');
    return;
  }
  
  const resultDiv = document.getElementById('result');
  const evaluationDiv = document.getElementById('evaluation-content');
  
  resultDiv.textContent = '识别简历内容中...';
  resultDiv.style.color = '#718096';
  
  try {
    const recognitionResult = await window.row1.vision({
      imageUrl: currentImageUrl,
      prompt: '请识别这张简历中的所有文字内容，保持原有的格式和结构。'
    });
    
    resumeText = recognitionResult;
    resultDiv.textContent = '简历内容：\n' + recognitionResult;
    resultDiv.style.color = '#2d3748';
    
    evaluationDiv.textContent = '评估中...';
    evaluationDiv.style.color = '#718096';
    document.getElementById('evaluation-section').style.display = 'block';
    
    const evaluation = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是一位经验丰富的HR招聘专家，擅长分析简历并评估候选人匹配度。' 
        },
        { 
          role: 'user', 
          content: `请分析以下简历，并评估与岗位要求的匹配度：

岗位要求：
${jobDescription || '未填写岗位要求，请基于简历本身进行评估'}

简历内容：
${recognitionResult}

请提供以下评估：
1. 候选人基本信息（姓名、联系方式、工作年限等）
2. 教育背景
3. 工作经历（重点分析）
4. 技能特长
5. 与岗位要求的匹配度分析（匹配度评分：1-10分）
6. 优势亮点
7. 潜在风险或不足
8. 推荐建议（是否推荐面试）

请用清晰的格式组织内容，对匹配度进行重点说明。`
        }
      ],
      temperature: 0.7,
      maxTokens: 2000
    });
    
    evaluationDiv.textContent = evaluation;
    evaluationDiv.style.color = '#2d3748';
    
    window.row1.showToast('评估完成！');
  } catch (e) {
    console.error('评估失败:', e);
    resultDiv.textContent = '失败: ' + e.message;
    resultDiv.style.color = '#e53e3e';
  }
});

document.getElementById('questions-btn').addEventListener('click', async () => {
  const questionsDiv = document.getElementById('questions-content');
  questionsDiv.textContent = '生成问题中...';
  questionsDiv.style.color = '#718096';
  
  try {
    const questions = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是专业的HR面试官，擅长设计针对性的面试问题。' 
        },
        { 
          role: 'user', 
          content: `基于以下简历和岗位要求，请生成5-8个针对性的面试问题：

岗位要求：
${jobDescription || '通用岗位'}

简历内容：
${resumeText}

请生成：
1. 技术能力相关问题（2-3个）
2. 项目经验相关问题（2-3个）
3. 软技能相关问题（1-2个）
4. 职业规划相关问题（1个）

每个问题请包含：
- 问题内容
- 考察重点
- 预期回答要点

请用清晰的格式组织内容。`
        }
      ],
      temperature: 0.7,
      maxTokens: 1500
    });
    
    questionsDiv.textContent = questions;
    questionsDiv.style.color = '#2d3748';
    
    window.row1.showToast('面试问题已生成！');
  } catch (e) {
    console.error('生成问题失败:', e);
    questionsDiv.textContent = '生成失败: ' + e.message;
    questionsDiv.style.color = '#e53e3e';
  }
});

