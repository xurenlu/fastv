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

// localStorage 键名
const STORAGE_KEY = 'businessCardData';

// 检查 row1 bridge 是否可用
if (!window.row1) {
  console.error('row1 bridge 未找到');
}

// 从 localStorage 加载数据
function loadFromStorage() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      const savedData = JSON.parse(saved);
      // 恢复数据到 cardData
      Object.assign(cardData, savedData);
      
      // 恢复表单值
      document.getElementById('name').value = cardData.name || '';
      document.getElementById('position').value = cardData.position || '';
      document.getElementById('company').value = cardData.company || '';
      document.getElementById('phone').value = cardData.phone || '';
      document.getElementById('email').value = cardData.email || '';
      document.getElementById('address').value = cardData.address || '';
      document.getElementById('website').value = cardData.website || '';
      document.getElementById('theme-color').value = cardData.themeColor || '#667eea';
      document.getElementById('text-color').value = cardData.textColor || '#2d3748';
      document.getElementById('layout').value = cardData.layout || 'vertical';
      document.getElementById('font-size').value = cardData.fontSize || 14;
      document.getElementById('font-size-value').textContent = (cardData.fontSize || 14) + 'px';
      
      // 恢复 Logo 预览
      if (cardData.logoUrl) {
        document.getElementById('logo-preview').src = cardData.logoUrl;
        document.getElementById('logo-preview').style.display = 'block';
        document.getElementById('remove-logo-btn').style.display = 'block';
        document.getElementById('logo-name').textContent = '已上传';
      }
      
      updateCardPreview();
    }
  } catch (error) {
    console.error('加载存储数据失败:', error);
  }
}

// 保存数据到 localStorage
function saveToStorage() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(cardData));
  } catch (error) {
    console.error('保存数据失败:', error);
  }
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

// 标准名片尺寸：90mm x 50mm (1.8:1 比例)，300dpi
const CARD_WIDTH = 1063;  // 90mm at 300dpi
const CARD_HEIGHT = 591;  // 50mm at 300dpi

// 生成50种随机样式配置（不依赖用户设置）
function generateRandomStyles(count = 50) {
  const colors = [
    '#667eea', '#f093fb', '#4facfe', '#43e97b', '#fa709a', '#fee140',
    '#30cfd0', '#a8edea', '#ff9a9e', '#fecfef', '#e74c3c', '#3498db',
    '#2ecc71', '#9b59b6', '#e67e22', '#16a085', '#c0392b', '#2c3e50',
    '#34495e', '#1a1a1a', '#f39c12', '#8e44ad', '#27ae60', '#2980b9'
  ];
  
  const textColors = ['#2d3748', '#ffffff', '#1a202c', '#4a5568', '#718096'];
  const layouts = ['vertical', 'horizontal', 'centered'];
  const borderStyles = ['top', 'bottom', 'left', 'right', 'full', 'none'];
  const fontSizes = [12, 13, 14, 15, 16, 17, 18];
  
  const styles = [];
  for (let i = 0; i < count; i++) {
    const themeColor = colors[Math.floor(Math.random() * colors.length)];
    const textColor = textColors[Math.floor(Math.random() * textColors.length)];
    const layout = layouts[Math.floor(Math.random() * layouts.length)];
    const borderStyle = borderStyles[Math.floor(Math.random() * borderStyles.length)];
    const fontSize = fontSizes[Math.floor(Math.random() * fontSizes.length)];
    const useGradient = Math.random() > 0.6;
    const useDark = Math.random() > 0.7;
    
    styles.push({
      themeColor,
      textColor,
      layout,
      borderStyle,
      fontSize,
      gradient: useGradient,
      dark: useDark,
      textAlign: layout === 'centered' ? 'center' : (layout === 'horizontal' ? 'left' : 'left')
    });
  }
  
  return styles;
}

// 根据样式配置生成名片 HTML
function generateCardHTML(style) {
  const { layout, themeColor, textColor, fontSize, borderStyle, gradient, dark } = style;
  
  let html = '';
  let cardStyle = '';
  
  // 设置背景
  if (gradient) {
    cardStyle += `background: linear-gradient(135deg, ${themeColor} 0%, ${adjustColor(themeColor, -30)} 100%); `;
  } else if (dark) {
    cardStyle += `background: ${themeColor}; `;
  } else {
    cardStyle += `background: white; `;
  }
  
  // 设置边框
  if (borderStyle === 'top') {
    cardStyle += `border-top: 4px solid ${themeColor}; `;
  } else if (borderStyle === 'bottom') {
    cardStyle += `border-bottom: 4px solid ${themeColor}; `;
  } else if (borderStyle === 'left') {
    cardStyle += `border-left: 4px solid ${themeColor}; `;
  } else if (borderStyle === 'full') {
    cardStyle += `border: 2px solid ${themeColor}; `;
  }
  
  if (layout === 'horizontal') {
    html = `
      <div class="left-section">
        ${cardData.logoUrl ? `<div class="logo-container"><img src="${cardData.logoUrl}" alt="Logo"></div>` : ''}
        <div class="company" style="color: ${themeColor};">${cardData.company || ''}</div>
      </div>
      <div class="right-section">
        <div class="name" style="color: ${textColor}; font-size: ${fontSize + 6}px;">${cardData.name || ''}</div>
        ${cardData.position ? `<div class="position" style="color: ${textColor}; font-size: ${fontSize}px;">${cardData.position}</div>` : ''}
        <div class="contact-info">
          ${cardData.phone ? `<div class="contact-item" style="color: ${textColor}; font-size: ${fontSize}px;">📞 ${cardData.phone}</div>` : ''}
          ${cardData.email ? `<div class="contact-item" style="color: ${textColor}; font-size: ${fontSize}px;">✉️ ${cardData.email}</div>` : ''}
          ${cardData.address ? `<div class="contact-item" style="color: ${textColor}; font-size: ${fontSize}px;">📍 ${cardData.address}</div>` : ''}
          ${cardData.website ? `<div class="contact-item" style="color: ${textColor}; font-size: ${fontSize}px;">🌐 ${cardData.website}</div>` : ''}
        </div>
      </div>
    `;
  } else if (layout === 'centered') {
    html = `
      ${cardData.logoUrl ? `<div class="logo-container"><img src="${cardData.logoUrl}" alt="Logo"></div>` : ''}
      <div class="name" style="color: ${textColor}; font-size: ${fontSize + 6}px;">${cardData.name || ''}</div>
      ${cardData.position ? `<div class="position" style="color: ${textColor}; font-size: ${fontSize}px;">${cardData.position}</div>` : ''}
      <div class="company" style="color: ${themeColor}; font-size: ${fontSize + 2}px;">${cardData.company || ''}</div>
      <div class="contact-info">
        ${cardData.phone ? `<div class="contact-item" style="color: ${textColor}; font-size: ${fontSize}px;">📞 ${cardData.phone}</div>` : ''}
        ${cardData.email ? `<div class="contact-item" style="color: ${textColor}; font-size: ${fontSize}px;">✉️ ${cardData.email}</div>` : ''}
        ${cardData.address ? `<div class="contact-item" style="color: ${textColor}; font-size: ${fontSize}px;">📍 ${cardData.address}</div>` : ''}
        ${cardData.website ? `<div class="contact-item" style="color: ${textColor}; font-size: ${fontSize}px;">🌐 ${cardData.website}</div>` : ''}
      </div>
    `;
  } else {
    // vertical (默认)
    html = `
      ${cardData.logoUrl ? `<div class="logo-container"><img src="${cardData.logoUrl}" alt="Logo"></div>` : ''}
      <div class="name" style="color: ${textColor}; font-size: ${fontSize + 6}px;">${cardData.name || ''}</div>
      ${cardData.position ? `<div class="position" style="color: ${textColor}; font-size: ${fontSize}px;">${cardData.position}</div>` : ''}
      <div class="company" style="color: ${themeColor}; font-size: ${fontSize + 2}px;">${cardData.company || ''}</div>
      <div class="contact-info">
        ${cardData.phone ? `<div class="contact-item" style="color: ${textColor}; font-size: ${fontSize}px;">📞 ${cardData.phone}</div>` : ''}
        ${cardData.email ? `<div class="contact-item" style="color: ${textColor}; font-size: ${fontSize}px;">✉️ ${cardData.email}</div>` : ''}
        ${cardData.address ? `<div class="contact-item" style="color: ${textColor}; font-size: ${fontSize}px;">📍 ${cardData.address}</div>` : ''}
        ${cardData.website ? `<div class="contact-item" style="color: ${textColor}; font-size: ${fontSize}px;">🌐 ${cardData.website}</div>` : ''}
      </div>
    `;
  }
  
  return { html, cardStyle };
}

// 调整颜色亮度
function adjustColor(color, amount) {
  const usePound = color[0] === '#';
  const col = usePound ? color.slice(1) : color;
  const num = parseInt(col, 16);
  let r = (num >> 16) + amount;
  let g = (num >> 8 & 0x00FF) + amount;
  let b = (num & 0x0000FF) + amount;
  r = r > 255 ? 255 : r < 0 ? 0 : r;
  g = g > 255 ? 255 : g < 0 ? 0 : g;
  b = b > 255 ? 255 : b < 0 ? 0 : b;
  return (usePound ? '#' : '') + (r << 16 | g << 8 | b).toString(16).padStart(6, '0');
}

// 更新名片预览
function updateCardPreview() {
  const cardContent = document.getElementById('card-content');
  const hasData = cardData.name || cardData.company;
  
  if (!hasData) {
    cardContent.innerHTML = '<div class="card-placeholder"><p>填写左侧信息后，名片将在这里显示</p></div>';
    document.getElementById('download-btn').disabled = true;
    document.getElementById('generate-all-btn').disabled = true;
    return;
  }
  
  document.getElementById('download-btn').disabled = false;
  document.getElementById('generate-all-btn').disabled = false;
  
  // 使用当前样式生成预览
  const style = {
    layout: cardData.layout,
    themeColor: cardData.themeColor,
    textColor: cardData.textColor,
    fontSize: cardData.fontSize,
    borderStyle: 'top'
  };
  
  const { html, cardStyle } = generateCardHTML(style);
  
  cardContent.className = `card-content layout-${cardData.layout}`;
  cardContent.style.cssText = cardStyle;
  cardContent.innerHTML = html;
  
  // 保存到 localStorage
  saveToStorage();
}

// 将 Canvas 转换为 base64
function canvasToBase64(canvas) {
  return canvas.toDataURL('image/png').split(',')[1];
}

// 生成单个名片图片（使用标准名片尺寸）
async function generateCardImage(style, index) {
  return new Promise((resolve, reject) => {
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    
    // 标准名片尺寸：90mm x 50mm (1.8:1)，300dpi
    canvas.width = CARD_WIDTH;
    canvas.height = CARD_HEIGHT;
    
    const { themeColor, textColor, fontSize, borderStyle, gradient, dark, layout, textAlign } = style;
    const width = CARD_WIDTH;
    const height = CARD_HEIGHT;
    
    // 填充背景
    if (gradient) {
      const gradientObj = ctx.createLinearGradient(0, 0, width, height);
      gradientObj.addColorStop(0, themeColor);
      gradientObj.addColorStop(1, adjustColor(themeColor, -30));
      ctx.fillStyle = gradientObj;
    } else if (dark) {
      ctx.fillStyle = themeColor;
    } else {
      ctx.fillStyle = '#ffffff';
    }
    ctx.fillRect(0, 0, width, height);
    
    // 绘制边框
    if (borderStyle === 'top') {
      ctx.fillStyle = themeColor;
      ctx.fillRect(0, 0, width, 20);
    } else if (borderStyle === 'bottom') {
      ctx.fillStyle = themeColor;
      ctx.fillRect(0, height - 20, width, 20);
    } else if (borderStyle === 'left') {
      ctx.fillStyle = themeColor;
      ctx.fillRect(0, 0, 20, height);
    } else if (borderStyle === 'right') {
      ctx.fillStyle = themeColor;
      ctx.fillRect(width - 20, 0, 20, height);
    } else if (borderStyle === 'full') {
      ctx.strokeStyle = themeColor;
      ctx.lineWidth = 4;
      ctx.strokeRect(2, 2, width - 4, height - 4);
    }
    
    // 根据布局设置对齐方式
    if (layout === 'horizontal') {
      // 水平布局：左侧 Logo/公司，右侧个人信息
      drawHorizontalLayout(ctx, width, height, style, () => {
        const base64 = canvasToBase64(canvas);
        resolve({ base64, index, style });
      });
    } else if (layout === 'centered') {
      // 居中布局
      drawCenteredLayout(ctx, width, height, style, () => {
        const base64 = canvasToBase64(canvas);
        resolve({ base64, index, style });
      });
    } else {
      // 垂直布局（默认）
      drawVerticalLayout(ctx, width, height, style, () => {
        const base64 = canvasToBase64(canvas);
        resolve({ base64, index, style });
      });
    }
  });
}

// 垂直布局绘制
function drawVerticalLayout(ctx, width, height, style, resolve) {
  const { themeColor, textColor, fontSize } = style;
  let y = 60;
  
  // Logo
  if (cardData.logoUrl) {
    const logoImg = new Image();
    logoImg.crossOrigin = 'anonymous';
    logoImg.onload = () => {
      const logoHeight = 100;
      const logoWidth = (logoImg.width / logoImg.height) * logoHeight;
      ctx.drawImage(logoImg, (width - logoWidth) / 2, y, logoWidth, logoHeight);
      y += logoHeight + 30;
      drawVerticalText(ctx, width, height, y, style);
      resolve();
    };
    logoImg.onerror = () => {
      drawVerticalText(ctx, width, height, y, style);
      resolve();
    };
    logoImg.src = cardData.logoUrl;
  } else {
    drawVerticalText(ctx, width, height, y, style);
    resolve();
  }
}

function drawVerticalText(ctx, width, height, startY, style) {
  const { themeColor, textColor, fontSize } = style;
  let y = startY;
  
  ctx.textAlign = 'center';
  
  if (cardData.name) {
    ctx.font = `bold ${Math.max(24, (fontSize + 6) * 1.5)}px Arial`;
    ctx.fillStyle = textColor;
    ctx.fillText(cardData.name, width / 2, y);
    y += 45;
  }
  
  if (cardData.position) {
    ctx.font = `${Math.max(14, fontSize * 1.2)}px Arial`;
    ctx.fillStyle = textColor;
    ctx.fillText(cardData.position, width / 2, y);
    y += 35;
  }
  
  if (cardData.company) {
    ctx.font = `bold ${Math.max(18, (fontSize + 2) * 1.3)}px Arial`;
    ctx.fillStyle = themeColor;
    ctx.fillText(cardData.company, width / 2, y);
    y += 50;
  }
  
  ctx.font = `${Math.max(12, fontSize * 1.1)}px Arial`;
  ctx.fillStyle = textColor;
  
  if (cardData.phone) {
    ctx.fillText(`📞 ${cardData.phone}`, width / 2, y);
    y += 35;
  }
  if (cardData.email) {
    ctx.fillText(`✉️ ${cardData.email}`, width / 2, y);
    y += 35;
  }
  if (cardData.address) {
    ctx.fillText(`📍 ${cardData.address}`, width / 2, y);
    y += 35;
  }
  if (cardData.website) {
    ctx.fillText(`🌐 ${cardData.website}`, width / 2, y);
  }
}

// 水平布局绘制
function drawHorizontalLayout(ctx, width, height, style, resolve) {
  const { themeColor, textColor, fontSize } = style;
  const leftWidth = width * 0.4;
  const rightWidth = width * 0.6;
  const padding = 30;
  
  // 左侧：Logo 和公司
  let leftY = padding + 20;
  
  const drawComplete = () => {
    // 左侧内容
    ctx.save();
    ctx.textAlign = 'center';
    if (cardData.logoUrl) {
      const logoImg = new Image();
      logoImg.crossOrigin = 'anonymous';
      logoImg.onload = () => {
        const logoHeight = 80;
        const logoWidth = Math.min(leftWidth - 40, (logoImg.width / logoImg.height) * logoHeight);
        ctx.drawImage(logoImg, padding + (leftWidth - logoWidth) / 2, leftY, logoWidth, logoHeight);
        leftY += logoHeight + 20;
        drawHorizontalLeft(ctx, leftWidth, leftY, padding, style);
        drawHorizontalRight(ctx, rightWidth, padding, style);
        ctx.restore();
        resolve();
      };
      logoImg.onerror = () => {
        drawHorizontalLeft(ctx, leftWidth, leftY, padding, style);
        drawHorizontalRight(ctx, rightWidth, padding, style);
        ctx.restore();
        resolve();
      };
      logoImg.src = cardData.logoUrl;
    } else {
      drawHorizontalLeft(ctx, leftWidth, leftY, padding, style);
      drawHorizontalRight(ctx, rightWidth, padding, style);
      ctx.restore();
      resolve();
    }
  };
  
  drawComplete();
}

function drawHorizontalLeft(ctx, leftWidth, startY, padding, style) {
  const { themeColor, textColor, fontSize } = style;
  
  ctx.textAlign = 'center';
  if (cardData.company) {
    ctx.font = `bold ${Math.max(18, (fontSize + 2) * 1.3)}px Arial`;
    ctx.fillStyle = themeColor;
    ctx.fillText(cardData.company, padding + leftWidth / 2, startY);
  }
}

function drawHorizontalRight(ctx, rightWidth, padding, style) {
  const { themeColor, textColor, fontSize } = style;
  const leftWidth = CARD_WIDTH * 0.4;
  const startX = padding + leftWidth + padding;
  let y = padding + 20;
  
  ctx.textAlign = 'left';
  
  if (cardData.name) {
    ctx.font = `bold ${Math.max(22, (fontSize + 6) * 1.4)}px Arial`;
    ctx.fillStyle = textColor;
    ctx.fillText(cardData.name, startX, y);
    y += 40;
  }
  
  if (cardData.position) {
    ctx.font = `${Math.max(14, fontSize * 1.2)}px Arial`;
    ctx.fillStyle = textColor;
    ctx.fillText(cardData.position, startX, y);
    y += 35;
  }
  
  ctx.font = `${Math.max(12, fontSize * 1.1)}px Arial`;
  ctx.fillStyle = textColor;
  
  if (cardData.phone) {
    ctx.fillText(`📞 ${cardData.phone}`, startX, y);
    y += 30;
  }
  if (cardData.email) {
    ctx.fillText(`✉️ ${cardData.email}`, startX, y);
    y += 30;
  }
  if (cardData.address) {
    ctx.fillText(`📍 ${cardData.address}`, startX, y);
    y += 30;
  }
  if (cardData.website) {
    ctx.fillText(`🌐 ${cardData.website}`, startX, y);
  }
}

// 居中布局绘制
function drawCenteredLayout(ctx, width, height, style, resolve) {
  const { themeColor, textColor, fontSize } = style;
  let y = 50;
  
  ctx.textAlign = 'center';
  
  if (cardData.logoUrl) {
    const logoImg = new Image();
    logoImg.crossOrigin = 'anonymous';
    logoImg.onload = () => {
      const logoHeight = 90;
      const logoWidth = (logoImg.width / logoImg.height) * logoHeight;
      ctx.drawImage(logoImg, (width - logoWidth) / 2, y, logoWidth, logoHeight);
      y += logoHeight + 25;
      drawCenteredText(ctx, width, y, style);
      resolve();
    };
    logoImg.onerror = () => {
      drawCenteredText(ctx, width, y, style);
      resolve();
    };
    logoImg.src = cardData.logoUrl;
  } else {
    drawCenteredText(ctx, width, y, style);
    resolve();
  }
}

function drawCenteredText(ctx, width, startY, style) {
  const { themeColor, textColor, fontSize } = style;
  let y = startY;
  
  if (cardData.name) {
    ctx.font = `bold ${Math.max(26, (fontSize + 6) * 1.6)}px Arial`;
    ctx.fillStyle = textColor;
    ctx.fillText(cardData.name, width / 2, y);
    y += 45;
  }
  
  if (cardData.position) {
    ctx.font = `${Math.max(15, fontSize * 1.3)}px Arial`;
    ctx.fillStyle = textColor;
    ctx.fillText(cardData.position, width / 2, y);
    y += 40;
  }
  
  if (cardData.company) {
    ctx.font = `bold ${Math.max(20, (fontSize + 2) * 1.4)}px Arial`;
    ctx.fillStyle = themeColor;
    ctx.fillText(cardData.company, width / 2, y);
    y += 50;
  }
  
  ctx.font = `${Math.max(13, fontSize * 1.15)}px Arial`;
  ctx.fillStyle = textColor;
  
  if (cardData.phone) {
    ctx.fillText(`📞 ${cardData.phone}`, width / 2, y);
    y += 35;
  }
  if (cardData.email) {
    ctx.fillText(`✉️ ${cardData.email}`, width / 2, y);
    y += 35;
  }
  if (cardData.address) {
    ctx.fillText(`📍 ${cardData.address}`, width / 2, y);
    y += 35;
  }
  if (cardData.website) {
    ctx.fillText(`🌐 ${cardData.website}`, width / 2, y);
  }
}

// 下载单个名片
async function downloadCard() {
  const cardContent = document.getElementById('card-content');
  if (!cardContent || cardContent.querySelector('.card-placeholder')) {
    alert('请先填写名片信息');
    return;
  }
  
  try {
    if (window.row1) {
      window.row1.showToast('正在生成名片...');
    }
    
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    
    // 标准名片尺寸：90mm x 50mm (1.8:1)，300dpi
    canvas.width = CARD_WIDTH;
    canvas.height = CARD_HEIGHT;
    const width = CARD_WIDTH;
    const height = CARD_HEIGHT;
    
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
    
    // 转换为 base64 并使用 row1 API 下载
    const base64 = canvasToBase64(canvas);
    const fileName = `${cardData.name || 'business-card'}-${Date.now()}.png`;
    
    if (window.row1 && window.row1.downloadFile) {
      const success = await window.row1.downloadFile(base64, fileName, 'image/png');
      if (success) {
        if (window.row1.showToast) {
          window.row1.showToast('名片下载成功！');
        }
      } else {
        alert('下载已取消');
      }
    } else {
      // 降级方案：使用传统下载方式
      canvas.toBlob((blob) => {
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = fileName;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
        
        if (window.row1 && window.row1.showToast) {
          window.row1.showToast('名片下载成功！');
        }
      }, 'image/png');
    }
  } catch (error) {
    console.error('下载失败:', error);
    alert('下载失败，请重试。错误: ' + error.message);
  }
}

// 当前生成的样式列表（用于重新生成）
let currentGeneratedStyles = [];

// 批量生成50种样式
async function generateAllStyles() {
  const cardContent = document.getElementById('card-content');
  if (!cardContent || cardContent.querySelector('.card-placeholder')) {
    alert('请先填写名片信息');
    return;
  }
  
  if (!confirm('将生成50种不同样式的名片，请先选择保存文件夹。')) {
    return;
  }
  
  try {
    // 选择保存文件夹
    let folderPath = '';
    if (window.row1 && window.row1.selectFolder) {
      folderPath = await window.row1.selectFolder();
      if (!folderPath) {
        alert('未选择文件夹，已取消');
        return;
      }
    } else {
      alert('当前环境不支持文件夹选择，请使用单个下载功能');
      return;
    }
    
    if (window.row1 && window.row1.showToast) {
      window.row1.showToast('正在生成50种样式，请稍候...');
    }
    
    // 生成50种随机样式（不依赖用户设置）
    currentGeneratedStyles = generateRandomStyles(50);
    
    // 生成所有样式并保存
    let successCount = 0;
    for (let i = 0; i < currentGeneratedStyles.length; i++) {
      const style = currentGeneratedStyles[i];
      try {
        const imageData = await generateCardImage(style, i + 1);
        const fileName = `${cardData.name || 'business-card'}-style-${String(i + 1).padStart(2, '0')}.png`;
        
        if (window.row1 && window.row1.saveFileToFolder) {
          const success = await window.row1.saveFileToFolder(
            imageData.base64,
            fileName,
            folderPath,
            'image/png'
          );
          if (success) {
            successCount++;
          }
        }
        
        // 每生成10个更新一次提示
        if ((i + 1) % 10 === 0 && window.row1 && window.row1.showToast) {
          window.row1.showToast(`已生成 ${i + 1}/50 种样式...`);
        }
      } catch (error) {
        console.error(`生成样式 ${i + 1} 失败:`, error);
      }
    }
    
    if (window.row1 && window.row1.showToast) {
      window.row1.showToast(`成功生成并保存了 ${successCount} 种名片样式！`);
    }
    
    // 更新按钮文字，显示可以重新生成
    const btn = document.getElementById('generate-all-btn');
    if (btn) {
      btn.textContent = '重新生成50种样式';
    }
  } catch (error) {
    console.error('批量生成失败:', error);
    alert('批量生成失败: ' + error.message);
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
    if (window.row1 && window.row1.showToast) {
      window.row1.showToast('正在上传 Logo...');
    }
    const logoUrl = await uploadImage(file);
    cardData.logoUrl = logoUrl;
    updateCardPreview();
    if (window.row1 && window.row1.showToast) {
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

// 批量生成按钮
document.getElementById('generate-all-btn').addEventListener('click', generateAllStyles);

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
    
    // 清除 localStorage
    localStorage.removeItem(STORAGE_KEY);
    
    updateCardPreview();
    
    if (window.row1 && window.row1.showToast) {
      window.row1.showToast('已重置');
    }
  }
});

// 初始化：加载存储的数据
loadFromStorage();
updateCardPreview();
