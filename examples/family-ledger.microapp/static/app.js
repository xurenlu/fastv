let currentImageUrl = null;

if (!window.row1) {
  console.error('row1 bridge 未找到');
  document.body.innerHTML = '<div style="padding: 40px; text-align: center;"><h2>错误</h2><p>无法连接到 row1 平台</p></div>';
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
      
      document.getElementById('process-btn').disabled = false;
      document.getElementById('result').textContent = '';
    };
    reader.readAsDataURL(file);
    
    try {
      const imageUrl = await window.row1.uploadFile(file);
      currentImageUrl = imageUrl;
      window.row1.showToast('图片上传成功');
    } catch (error) {
      console.error('上传失败:', error);
      alert('图片上传失败: ' + error.message);
    }
  };
  input.click();
});

document.getElementById('process-btn').addEventListener('click', async () => {
  if (!currentImageUrl) {
    alert('请先选择并上传图片');
    return;
  }
  
  const resultDiv = document.getElementById('result');
  resultDiv.textContent = '正在处理...';
  resultDiv.style.color = '#86868b';
  
  try {
    const result = await window.row1.vision({
      imageUrl: currentImageUrl,
      prompt: '请识别这张小票图片，提取：1. 商家名称 2. 购买日期和时间 3. 商品清单和价格 4. 总金额 5. 分类（餐饮、购物、交通等）。'
    });
    
    resultDiv.textContent = result;
    resultDiv.style.color = '#1d1d1f';
    window.row1.showToast('处理完成！');
  } catch (e) {
    console.error('处理失败:', e);
    resultDiv.textContent = '处理失败: ' + e.message;
    resultDiv.style.color = '#ff3b30';
  }
});