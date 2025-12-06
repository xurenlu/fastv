let currentImageUrl = null;
let contactInfo = {
  name: '',
  phone: '',
  email: '',
  company: '',
  position: '',
  address: '',
  website: '',
  fullText: ''
};

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
      
      document.getElementById('extract-btn').disabled = false;
      
      // 清空之前的结果
      document.getElementById('result').textContent = '';
      document.getElementById('info-content').textContent = '';
      document.getElementById('info-section').style.display = 'none';
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

// 提取名片信息
document.getElementById('extract-btn').addEventListener('click', async () => {
  if (!currentImageUrl) {
    alert('请先选择并上传图片');
    return;
  }
  
  const resultDiv = document.getElementById('result');
  const infoDiv = document.getElementById('info-content');
  
  resultDiv.textContent = '识别名片中...';
  resultDiv.style.color = '#718096';
  
  try {
    // 第一步：识别名片上的所有文字
    const recognitionResult = await window.row1.vision({
      imageUrl: currentImageUrl,
      prompt: '请识别这张名片上的所有文字内容，保持原有的格式和换行。如果图片中没有名片信息，请说明。'
    });
    
    resultDiv.textContent = '原始信息：\n' + recognitionResult;
    resultDiv.style.color = '#2d3748';
    
    // 第二步：结构化提取信息
    infoDiv.textContent = '提取信息中...';
    infoDiv.style.color = '#718096';
    document.getElementById('info-section').style.display = 'block';
    
    const structuredInfo = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是一个专业的联系人信息提取助手，擅长从名片文字中提取结构化的联系人信息。' 
        },
        { 
          role: 'user', 
          content: `请从以下名片文字中提取联系人信息，并按照以下格式输出：

${recognitionResult}

请提取以下信息（如果存在）：
- 姓名（Name）
- 职位（Position/Title）
- 公司（Company）
- 电话（Phone）
- 邮箱（Email）
- 地址（Address）
- 网站（Website）

请用以下格式输出：
姓名：[姓名]
职位：[职位]
公司：[公司]
电话：[电话]
邮箱：[邮箱]
地址：[地址]
网站：[网站]

如果某项信息不存在，请写"无"。请确保提取的信息准确无误。`
        }
      ],
      temperature: 0.3,
      maxTokens: 1000
    });
    
    infoDiv.textContent = structuredInfo;
    infoDiv.style.color = '#2d3748';
    
    // 解析提取的信息
    contactInfo.fullText = structuredInfo;
    const lines = structuredInfo.split('\n');
    lines.forEach(line => {
      if (line.includes('姓名：') || line.includes('Name：')) {
        contactInfo.name = line.split('：')[1]?.trim() || line.split(':')[1]?.trim() || '';
      } else if (line.includes('电话：') || line.includes('Phone：')) {
        contactInfo.phone = line.split('：')[1]?.trim() || line.split(':')[1]?.trim() || '';
      } else if (line.includes('邮箱：') || line.includes('Email：')) {
        contactInfo.email = line.split('：')[1]?.trim() || line.split(':')[1]?.trim() || '';
      } else if (line.includes('公司：') || line.includes('Company：')) {
        contactInfo.company = line.split('：')[1]?.trim() || line.split(':')[1]?.trim() || '';
      } else if (line.includes('职位：') || line.includes('Position：')) {
        contactInfo.position = line.split('：')[1]?.trim() || line.split(':')[1]?.trim() || '';
      }
    });
    
    // 显示成功提示
    window.row1.showToast('信息提取成功！');
  } catch (e) {
    console.error('识别或提取失败:', e);
    resultDiv.textContent = '失败: ' + e.message;
    resultDiv.style.color = '#e53e3e';
    infoDiv.textContent = '提取失败: ' + e.message;
    infoDiv.style.color = '#e53e3e';
  }
});

// 复制功能
async function copyToClipboard(text) {
  if (!text || text === '无') {
    window.row1.showToast('没有可复制的内容');
    return;
  }
  
  try {
    await navigator.clipboard.writeText(text);
    window.row1.showToast('已复制到剪贴板！');
  } catch (e) {
    // 降级方案
    const textArea = document.createElement('textarea');
    textArea.value = text;
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
}

// 复制全部信息
document.getElementById('copy-all-btn').addEventListener('click', () => {
  copyToClipboard(contactInfo.fullText);
});

// 复制姓名
document.getElementById('copy-name-btn').addEventListener('click', () => {
  copyToClipboard(contactInfo.name);
});

// 复制电话
document.getElementById('copy-phone-btn').addEventListener('click', () => {
  copyToClipboard(contactInfo.phone);
});

// 复制邮箱
document.getElementById('copy-email-btn').addEventListener('click', () => {
  copyToClipboard(contactInfo.email);
});

