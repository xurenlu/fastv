let currentImageUrl = null;
let productInfo = {
  name: '',
  price: '',
  features: ''
};

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

// 更新商品信息
document.getElementById('product-name').addEventListener('input', (e) => {
  productInfo.name = e.target.value;
});

document.getElementById('product-price').addEventListener('input', (e) => {
  productInfo.price = e.target.value;
});

document.getElementById('product-features').addEventListener('input', (e) => {
  productInfo.features = e.target.value;
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
      document.getElementById('generate-btn').disabled = false;
      document.getElementById('result').textContent = '';
      document.getElementById('marketing-content').textContent = '';
      document.getElementById('reply-content').textContent = '';
      document.getElementById('marketing-section').style.display = 'none';
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

document.getElementById('generate-btn').addEventListener('click', async () => {
  if (!currentImageUrl) {
    alert('请先选择并上传商品图片');
    return;
  }
  
  const resultDiv = document.getElementById('result');
  const marketingDiv = document.getElementById('marketing-content');
  
  resultDiv.textContent = '识别商品信息中...';
  resultDiv.style.color = '#718096';
  
  try {
    // 第一步：识别商品图片
    const recognitionResult = await window.row1.vision({
      imageUrl: currentImageUrl,
      prompt: '请识别这张商品图片，描述商品的外观、特点、品牌等信息。'
    });
    
    resultDiv.textContent = '商品识别：\n' + recognitionResult;
    resultDiv.style.color = '#2d3748';
    
    // 第二步：生成营销文案
    marketingDiv.textContent = '生成文案中...';
    marketingDiv.style.color = '#718096';
    document.getElementById('marketing-section').style.display = 'block';
    
    const marketing = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是一位经验丰富的微商营销专家，擅长撰写吸引人的朋友圈营销文案和客户沟通话术。文案要生动有趣，能激发购买欲望，适合微信朋友圈发布。' 
        },
        { 
          role: 'user', 
          content: `请基于以下信息，生成微商营销文案：

商品名称：${productInfo.name || '未填写'}
价格：${productInfo.price || '未填写'}
商品特点：${productInfo.features || '未填写'}
商品图片描述：${recognitionResult}

请生成：
1. 朋友圈营销文案（2-3个版本，每个50-100字）
   - 版本1：突出性价比和优惠
   - 版本2：突出产品特点和优势
   - 版本3：营造紧迫感和限时优惠
2. 配文建议（适合配图的简短文字）
3. 话题标签建议（#标签）

文案要求：
- 语言生动，有感染力
- 使用表情符号增加吸引力
- 突出卖点和优惠
- 适合微信朋友圈风格
- 避免过度夸张，保持真实感`
        }
      ],
      temperature: 0.8,
      maxTokens: 1500
    });
    
    marketingDiv.textContent = marketing;
    marketingDiv.style.color = '#2d3748';
    
    window.row1.showToast('营销文案已生成！');
  } catch (e) {
    console.error('生成失败:', e);
    resultDiv.textContent = '失败: ' + e.message;
    resultDiv.style.color = '#e53e3e';
  }
});

// 复制文案
document.getElementById('copy-btn').addEventListener('click', async () => {
  const marketingText = document.getElementById('marketing-content').textContent;
  if (!marketingText || marketingText.includes('营销文案将显示在这里')) {
    alert('没有可复制的内容');
    return;
  }
  
  try {
    await navigator.clipboard.writeText(marketingText);
    window.row1.showToast('已复制到剪贴板！');
  } catch (e) {
    const textArea = document.createElement('textarea');
    textArea.value = marketingText;
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

// 生成回复话术
document.getElementById('reply-btn').addEventListener('click', async () => {
  const replyDiv = document.getElementById('reply-content');
  replyDiv.textContent = '生成话术中...';
  replyDiv.style.color = '#718096';
  
  try {
    const replies = await window.row1.chat({
      messages: [
        { 
          role: 'system', 
          content: '你是专业的微商客服，擅长回复客户咨询，促进成交。回复要专业、热情、有说服力。' 
        },
        { 
          role: 'user', 
          content: `请基于以下商品信息，生成常见的客户咨询回复话术：

商品名称：${productInfo.name || '商品'}
价格：${productInfo.price || '未填写'}
商品特点：${productInfo.features || '未填写'}

请生成以下场景的回复话术：
1. 客户问"这个多少钱？"的回复
2. 客户问"质量怎么样？"的回复
3. 客户问"有什么优惠吗？"的回复
4. 客户问"包邮吗？"的回复
5. 客户犹豫不决时的促单话术
6. 客户砍价时的回复话术
7. 客户询问发货时间的回复

每个回复要：
- 简洁有力（30-50字）
- 突出卖点
- 营造紧迫感
- 引导成交
- 使用适当的表情符号`
        }
      ],
      temperature: 0.8,
      maxTokens: 1500
    });
    
    replyDiv.textContent = replies;
    replyDiv.style.color = '#2d3748';
    
    window.row1.showToast('回复话术已生成！');
  } catch (e) {
    console.error('生成失败:', e);
    replyDiv.textContent = '生成失败: ' + e.message;
    replyDiv.style.color = '#e53e3e';
  }
});

