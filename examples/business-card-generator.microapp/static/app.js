// 名片数据
let cardData = {
  name: '',
  position: '',
  company: '',
  phone: '',
  email: '',
  address: '',
  website: '',
  logoUrl: null,
  themeColor: '#667eea',
  textColor: '#2d3748',
  layout: 'vertical',
  fontSize: 14
};

// 检查 row1 bridge 是否可用
if (!window.row1) {
  console.error('row1 bridge 未找到');
}

// 上传图片（使用 row1 平台提供的上传 API）
async function uploadImage(file) {
  try {
    // 使用 row1 平台提供的上传 API
    const imageUrl = await window.row1.uploadFile(file);
    console.log('Logo 上传成功，URL:', imageUrl);
    return imageUrl;
  } catch (error) {
    console.error('上传错误:', error);
    throw error;
  }
}

// 更新名片预览
function updateCardPreview() {
  const cardContent = document.getElementById('card-content');
  const hasData = cardData.name || cardData.company;
  
  if (!hasData) {
    cardContent.innerHTML = '<div class="card-placeholder"><p>填写左侧信息后，名片将在这里显示</p></div>';
    document.getElementById('download-btn').disabled = true;
    return;
  }
  
  document.getElementById('download-btn').disabled = false;
  
  // 根据布局生成 HTML
  let html = '';
  
  if (cardData.layout === 'horizontal') {
    html = `
      <div class="left-section">
        ${cardData.logoUrl ? `<div class="logo-container"><img src="${cardData.logoUrl}" alt="Logo"></div>` : ''}
        <div class="company" style="color: ${cardData.themeColor};">${cardData.company || ''}</div>
      </div>
      <div class="right-section">
        <div class="name" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize + 6}px;">${cardData.name || ''}</div>
        ${cardData.position ? `<div class="position" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize}px;">${cardData.position}</div>` : ''}
        <div class="contact-info">
          ${cardData.phone ? `<div class="contact-item" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize}px;">📞 ${cardData.phone}</div>` : ''}
          ${cardData.email ? `<div class="contact-item" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize}px;">✉️ ${cardData.email}</div>` : ''}
          ${cardData.address ? `<div class="contact-item" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize}px;">📍 ${cardData.address}</div>` : ''}
          ${cardData.website ? `<div class="contact-item" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize}px;">🌐 ${cardData.website}</div>` : ''}
        </div>
      </div>
    `;
  } else if (cardData.layout === 'centered') {
    html = `
      ${cardData.logoUrl ? `<div class="logo-container"><img src="${cardData.logoUrl}" alt="Logo"></div>` : ''}
      <div class="name" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize + 6}px;">${cardData.name || ''}</div>
      ${cardData.position ? `<div class="position" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize}px;">${cardData.position}</div>` : ''}
      <div class="company" style="color: ${cardData.themeColor}; font-size: ${cardData.fontSize + 2}px;">${cardData.company || ''}</div>
      <div class="contact-info">
        ${cardData.phone ? `<div class="contact-item" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize}px;">📞 ${cardData.phone}</div>` : ''}
        ${cardData.email ? `<div class="contact-item" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize}px;">✉️ ${cardData.email}</div>` : ''}
        ${cardData.address ? `<div class="contact-item" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize}px;">📍 ${cardData.address}</div>` : ''}
        ${cardData.website ? `<div class="contact-item" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize}px;">🌐 ${cardData.website}</div>` : ''}
      </div>
    `;
  } else {
    // vertical (默认)
    html = `
      ${cardData.logoUrl ? `<div class="logo-container"><img src="${cardData.logoUrl}" alt="Logo"></div>` : ''}
      <div class="name" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize + 6}px;">${cardData.name || ''}</div>
      ${cardData.position ? `<div class="position" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize}px;">${cardData.position}</div>` : ''}
      <div class="company" style="color: ${cardData.themeColor}; font-size: ${cardData.fontSize + 2}px;">${cardData.company || ''}</div>
      <div class="contact-info">
        ${cardData.phone ? `<div class="contact-item" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize}px;">📞 ${cardData.phone}</div>` : ''}
        ${cardData.email ? `<div class="contact-item" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize}px;">✉️ ${cardData.email}</div>` : ''}
        ${cardData.address ? `<div class="contact-item" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize}px;">📍 ${cardData.address}</div>` : ''}
        ${cardData.website ? `<div class="contact-item" style="color: ${cardData.textColor}; font-size: ${cardData.fontSize}px;">🌐 ${cardData.website}</div>` : ''}
      </div>
    `;
  }
  
  cardContent.className = `card-content layout-${cardData.layout}`;
  cardContent.style.borderTop = `4px solid ${cardData.themeColor}`;
  cardContent.innerHTML = html;
}

// 下载名片为图片
async function downloadCard() {
  const cardContent = document.getElementById('card-content');
  if (!cardContent || cardContent.querySelector('.card-placeholder')) {
    alert('请先填写名片信息');
    return;
  }
  
  try {
    // 使用 html2canvas 库（如果可用）或使用 Canvas API
    // 这里使用简单的 Canvas 方法
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    
    // 设置画布尺寸（标准名片尺寸：90mm x 50mm，按 300dpi 计算）
    const width = 1063; // 90mm at 300dpi
    const height = 591; // 50mm at 300dpi
    canvas.width = width;
    canvas.height = height;
    
    // 填充白色背景
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, width, height);
    
    // 绘制主题色边框
    ctx.fillStyle = cardData.themeColor;
    ctx.fillRect(0, 0, width, 20);
    
    // 设置文字样式
    ctx.fillStyle = cardData.textColor;
    ctx.font = `bold ${(cardData.fontSize + 6) * 2}px Arial`;
    
    let y = 80;
    
    // 绘制 Logo（如果有）
    if (cardData.logoUrl) {
      const logoImg = new Image();
      logoImg.crossOrigin = 'anonymous';
      await new Promise((resolve, reject) => {
        logoImg.onload = () => {
          const logoHeight = 120;
          const logoWidth = (logoImg.width / logoImg.height) * logoHeight;
          ctx.drawImage(logoImg, (width - logoWidth) / 2, y, logoWidth, logoHeight);
          y += logoHeight + 40;
          resolve();
        };
        logoImg.onerror = reject;
        logoImg.src = cardData.logoUrl;
      });
    }
    
    // 绘制姓名
    if (cardData.name) {
      ctx.font = `bold ${(cardData.fontSize + 6) * 2}px Arial`;
      ctx.fillStyle = cardData.textColor;
      ctx.textAlign = 'center';
      ctx.fillText(cardData.name, width / 2, y);
      y += 50;
    }
    
    // 绘制职位
    if (cardData.position) {
      ctx.font = `${cardData.fontSize * 2}px Arial`;
      ctx.fillText(cardData.position, width / 2, y);
      y += 40;
    }
    
    // 绘制公司
    if (cardData.company) {
      ctx.font = `bold ${(cardData.fontSize + 2) * 2}px Arial`;
      ctx.fillStyle = cardData.themeColor;
      ctx.fillText(cardData.company, width / 2, y);
      y += 60;
    }
    
    // 绘制联系信息
    ctx.font = `${cardData.fontSize * 2}px Arial`;
    ctx.fillStyle = cardData.textColor;
    ctx.textAlign = 'center';
    
    if (cardData.phone) {
      ctx.fillText(`📞 ${cardData.phone}`, width / 2, y);
      y += 40;
    }
    if (cardData.email) {
      ctx.fillText(`✉️ ${cardData.email}`, width / 2, y);
      y += 40;
    }
    if (cardData.address) {
      ctx.fillText(`📍 ${cardData.address}`, width / 2, y);
      y += 40;
    }
    if (cardData.website) {
      ctx.fillText(`🌐 ${cardData.website}`, width / 2, y);
    }
    
    // 下载图片
    canvas.toBlob((blob) => {
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${cardData.name || 'business-card'}-${Date.now()}.png`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      
      if (window.row1) {
        window.row1.showToast('名片下载成功！');
      }
    }, 'image/png');
  } catch (error) {
    console.error('下载失败:', error);
    alert('下载失败，请重试。错误: ' + error.message);
  }
}

// 绑定输入事件
document.getElementById('name').addEventListener('input', (e) => {
  cardData.name = e.target.value;
  updateCardPreview();
});

document.getElementById('position').addEventListener('input', (e) => {
  cardData.position = e.target.value;
  updateCardPreview();
});

document.getElementById('company').addEventListener('input', (e) => {
  cardData.company = e.target.value;
  updateCardPreview();
});

document.getElementById('phone').addEventListener('input', (e) => {
  cardData.phone = e.target.value;
  updateCardPreview();
});

document.getElementById('email').addEventListener('input', (e) => {
  cardData.email = e.target.value;
  updateCardPreview();
});

document.getElementById('address').addEventListener('input', (e) => {
  cardData.address = e.target.value;
  updateCardPreview();
});

document.getElementById('website').addEventListener('input', (e) => {
  cardData.website = e.target.value;
  updateCardPreview();
});

document.getElementById('theme-color').addEventListener('input', (e) => {
  cardData.themeColor = e.target.value;
  updateCardPreview();
});

document.getElementById('text-color').addEventListener('input', (e) => {
  cardData.textColor = e.target.value;
  updateCardPreview();
});

document.getElementById('layout').addEventListener('change', (e) => {
  cardData.layout = e.target.value;
  updateCardPreview();
});

document.getElementById('font-size').addEventListener('input', (e) => {
  cardData.fontSize = parseInt(e.target.value);
  document.getElementById('font-size-value').textContent = cardData.fontSize + 'px';
  updateCardPreview();
});

// Logo 上传
document.getElementById('logo-btn').addEventListener('click', () => {
  document.getElementById('logo-upload').click();
});

document.getElementById('logo-upload').addEventListener('change', async (e) => {
  const file = e.target.files[0];
  if (!file) return;
  
  // 显示文件名
  document.getElementById('logo-name').textContent = file.name;
  document.getElementById('remove-logo-btn').style.display = 'block';
  
  // 显示预览
  const reader = new FileReader();
  reader.onload = (e) => {
    const preview = document.getElementById('logo-preview');
    preview.src = e.target.result;
    preview.style.display = 'block';
  };
  reader.readAsDataURL(file);
  
  // 上传到云存储
  try {
    if (window.row1) {
      window.row1.showToast('正在上传 Logo...');
    }
    const logoUrl = await uploadImage(file);
    cardData.logoUrl = logoUrl;
    updateCardPreview();
    if (window.row1) {
      window.row1.showToast('Logo 上传成功！');
    }
  } catch (error) {
    console.error('上传失败:', error);
    alert('Logo 上传失败: ' + error.message);
  }
});

// 移除 Logo
document.getElementById('remove-logo-btn').addEventListener('click', () => {
  cardData.logoUrl = null;
  document.getElementById('logo-upload').value = '';
  document.getElementById('logo-name').textContent = '';
  document.getElementById('logo-preview').style.display = 'none';
  document.getElementById('remove-logo-btn').style.display = 'none';
  updateCardPreview();
});

// 下载按钮
document.getElementById('download-btn').addEventListener('click', downloadCard);

// 重置按钮
document.getElementById('reset-btn').addEventListener('click', () => {
  if (confirm('确定要重置所有信息吗？')) {
    cardData = {
      name: '',
      position: '',
      company: '',
      phone: '',
      email: '',
      address: '',
      website: '',
      logoUrl: null,
      themeColor: '#667eea',
      textColor: '#2d3748',
      layout: 'vertical',
      fontSize: 14
    };
    
    // 重置表单
    document.getElementById('name').value = '';
    document.getElementById('position').value = '';
    document.getElementById('company').value = '';
    document.getElementById('phone').value = '';
    document.getElementById('email').value = '';
    document.getElementById('address').value = '';
    document.getElementById('website').value = '';
    document.getElementById('theme-color').value = '#667eea';
    document.getElementById('text-color').value = '#2d3748';
    document.getElementById('layout').value = 'vertical';
    document.getElementById('font-size').value = 14;
    document.getElementById('font-size-value').textContent = '14px';
    document.getElementById('logo-upload').value = '';
    document.getElementById('logo-name').textContent = '';
    document.getElementById('logo-preview').style.display = 'none';
    document.getElementById('remove-logo-btn').style.display = 'none';
    
    updateCardPreview();
    
    if (window.row1) {
      window.row1.showToast('已重置');
    }
  }
});

// 初始化
updateCardPreview();

