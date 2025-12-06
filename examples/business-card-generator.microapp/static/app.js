// 名片数据
let cardData = {
  name: '',
  position: '',
  company: '',
  phone: '',
  email: '',
  address: '',
  website: '',
  logoUrl: null
};

// localStorage 键名
const STORAGE_KEY = 'businessCardData';

// 标准名片尺寸：90mm x 54mm (国际标准)
const CARD_WIDTH = 450;  // 显示宽度
const CARD_HEIGHT = 270; // 显示高度 (90:54 = 5:3 比例)

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
      Object.assign(cardData, savedData);
      
      // 恢复表单值
      document.getElementById('name').value = cardData.name || '';
      document.getElementById('position').value = cardData.position || '';
      document.getElementById('company').value = cardData.company || '';
      document.getElementById('phone').value = cardData.phone || '';
      document.getElementById('email').value = cardData.email || '';
      document.getElementById('address').value = cardData.address || '';
      document.getElementById('website').value = cardData.website || '';
      
      // 恢复 Logo 预览
      if (cardData.logoUrl) {
        document.getElementById('logo-preview').src = cardData.logoUrl;
        document.getElementById('logo-preview').style.display = 'block';
        document.getElementById('remove-logo-btn').style.display = 'block';
        document.getElementById('logo-name').textContent = '已上传';
      }
      
      updateGenerateButton();
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

// 更新生成按钮状态
function updateGenerateButton() {
  const hasData = cardData.name || cardData.company;
  document.getElementById('generate-btn').disabled = !hasData;
}

// 上传图片
async function uploadImage(file) {
  try {
    if (window.row1 && window.row1.uploadFile) {
      const imageUrl = await window.row1.uploadFile(file);
      console.log('Logo 上传成功，URL:', imageUrl);
      return imageUrl;
    } else {
      // 降级：使用 base64
      return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = (e) => resolve(e.target.result);
        reader.onerror = reject;
        reader.readAsDataURL(file);
      });
    }
  } catch (error) {
    console.error('上传错误:', error);
    throw error;
  }
}

// 名片风格列表
const CARD_STYLES = [
  { name: '简约商务', colors: '深蓝色和白色', layout: '左对齐，信息分层清晰' },
  { name: '创意设计', colors: '渐变紫色到粉色', layout: '大胆的几何图形装饰' },
  { name: '科技未来', colors: '深色背景配霓虹蓝', layout: '科技感线条和光效' },
  { name: '优雅经典', colors: '金色和黑色', layout: '对称布局，衬线字体风格' },
  { name: '活力时尚', colors: '明亮的橙色和黄色', layout: '动感斜线分割' },
  { name: '自然清新', colors: '绿色和米白色', layout: '圆润的边角和自然元素' },
  { name: '极简主义', colors: '纯白背景黑色文字', layout: '大量留白，极简排版' },
  { name: '复古怀旧', colors: '棕色和米色', layout: '复古纹理和经典字体' },
  { name: '高端奢华', colors: '黑金配色', layout: '精致边框和装饰线' },
  { name: '清新文艺', colors: '淡蓝色和白色', layout: '手写风格元素' },
  { name: '热情活力', colors: '红色和橙色渐变', layout: '动感曲线' },
  { name: '冷静专业', colors: '灰色和蓝色', layout: '网格化布局' },
  { name: '梦幻浪漫', colors: '粉紫渐变', layout: '柔和的光晕效果' },
  { name: '工业风格', colors: '深灰和橙色点缀', layout: '硬朗的直线条' },
  { name: '东方韵味', colors: '朱红和金色', layout: '中式装饰纹样' }
];

// 构建 AI 提示词（带指定风格）
function buildPrompt(styleIndex) {
  const style = CARD_STYLES[styleIndex % CARD_STYLES.length];
  
  const info = {
    name: cardData.name || '张三',
    position: cardData.position || '',
    company: cardData.company || '某某公司',
    phone: cardData.phone || '',
    email: cardData.email || '',
    address: cardData.address || '',
    website: cardData.website || '',
    hasLogo: !!cardData.logoUrl
  };
  
  return `设计一张【${style.name}】风格的名片 HTML。

用户信息：
- 姓名：${info.name}
- 职位：${info.position || '(无)'}
- 公司：${info.company}
- 电话：${info.phone || '(无)'}
- 邮箱：${info.email || '(无)'}
- 地址：${info.address || '(无)'}
- 网站：${info.website || '(无)'}
${info.hasLogo ? '- Logo：用户已上传（请预留 logo 位置，使用 class="user-logo" 的 img 标签）' : ''}

风格要求：
- 风格：${style.name}
- 配色：${style.colors}
- 布局特点：${style.layout}

技术要求：
1. 输出完整的名片 HTML 片段（不需要 html/head/body 标签）
2. 尺寸固定：width: 450px; height: 270px（标准名片比例）
3. 使用内联样式 (style="...")
4. 字体：-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif
5. 只输出 HTML 代码，不要解释
6. 确保文字不溢出

直接输出 HTML：`;
}

// 调用 AI 生成名片 HTML（带风格索引）
async function generateCardHTML(styleIndex) {
  if (!window.row1 || !window.row1.chat) {
    throw new Error('AI 服务不可用');
  }
  
  const prompt = buildPrompt(styleIndex);
  
  const response = await window.row1.chat({
    messages: [
      {
        role: 'system',
        content: '你是一个专业的名片设计师。根据指定的风格设计独特的名片。只输出 HTML 代码，不要任何解释。'
      },
      {
        role: 'user',
        content: prompt
      }
    ]
  });
  
  // 提取 HTML 代码（去除可能的 markdown 代码块标记）
  let html = response.trim();
  if (html.startsWith('```html')) {
    html = html.slice(7);
  } else if (html.startsWith('```')) {
    html = html.slice(3);
  }
  if (html.endsWith('```')) {
    html = html.slice(0, -3);
  }
  
  return html.trim();
}

// 渲染名片到容器
function renderCard(html, index, styleName = '') {
  const cardWrapper = document.createElement('div');
  cardWrapper.className = 'card-wrapper';
  cardWrapper.setAttribute('data-index', index);
  
  // 添加风格标签
  if (styleName) {
    const styleLabel = document.createElement('div');
    styleLabel.className = 'style-label';
    styleLabel.textContent = styleName;
    cardWrapper.appendChild(styleLabel);
  }
  
  const cardContainer = document.createElement('div');
  cardContainer.className = 'generated-card';
  cardContainer.style.width = CARD_WIDTH + 'px';
  cardContainer.style.height = CARD_HEIGHT + 'px';
  cardContainer.style.overflow = 'hidden';
  cardContainer.style.position = 'relative';
  cardContainer.innerHTML = html;
  
  // 如果有 Logo，替换 logo 占位符
  if (cardData.logoUrl) {
    const logoImg = cardContainer.querySelector('.user-logo');
    if (logoImg) {
      logoImg.src = cardData.logoUrl;
      logoImg.style.maxHeight = '50px';
      logoImg.style.maxWidth = '100px';
      logoImg.style.objectFit = 'contain';
    }
  }
  
  // 添加下载按钮
  const downloadBtn = document.createElement('button');
  downloadBtn.className = 'card-download-btn';
  downloadBtn.innerHTML = '📥 下载';
  downloadBtn.onclick = (e) => {
    e.stopPropagation();
    downloadCardAsImage(cardContainer, index);
  };
  
  cardWrapper.appendChild(cardContainer);
  cardWrapper.appendChild(downloadBtn);
  
  // 点击名片也可以下载
  cardContainer.onclick = () => downloadCardAsImage(cardContainer, index);
  cardContainer.style.cursor = 'pointer';
  
  return cardWrapper;
}

// 将名片转换为图片并下载
async function downloadCardAsImage(cardElement, index) {
  try {
    // 添加下载中的视觉反馈
    cardElement.style.opacity = '0.7';
    
    // 使用 html2canvas 将 HTML 转换为 canvas
    const canvas = await html2canvas(cardElement, {
      scale: 2, // 2倍分辨率，更清晰
      useCORS: true,
      allowTaint: true,
      backgroundColor: null,
      width: CARD_WIDTH,
      height: CARD_HEIGHT
    });
    
    // 恢复透明度
    cardElement.style.opacity = '1';
    
    // 转换为 base64
    const base64 = canvas.toDataURL('image/png').split(',')[1];
    const fileName = `${cardData.name || 'business-card'}-style-${index + 1}.png`;
    
    // 使用 row1 API 下载
    if (window.row1 && window.row1.downloadFile) {
      await window.row1.downloadFile(base64, fileName, 'image/png');
    } else {
      // 降级方案
      const link = document.createElement('a');
      link.download = fileName;
      link.href = canvas.toDataURL('image/png');
      link.click();
    }
  } catch (error) {
    console.error('下载失败:', error);
    cardElement.style.opacity = '1';
    alert('下载失败: ' + error.message);
  }
}

// 当前使用的风格索引（用于换一批时选择不同风格）
let currentStyleOffset = 0;

// 更新加载状态文字
function updateLoadingText(text) {
  const loadingText = document.querySelector('.loading-indicator p');
  if (loadingText) {
    loadingText.textContent = text;
  }
}

// 生成多个名片
async function generateCards(count = 3) {
  const container = document.getElementById('cards-container');
  const loading = document.getElementById('loading-indicator');
  const actions = document.getElementById('preview-actions');
  
  // 显示加载状态
  container.innerHTML = '';
  loading.style.display = 'flex';
  actions.style.display = 'none';
  
  const cards = [];
  
  // 随机选择起始风格索引，确保每次换一批都不同
  const startIndex = currentStyleOffset;
  currentStyleOffset = (currentStyleOffset + count) % CARD_STYLES.length;
  
  for (let i = 0; i < count; i++) {
    try {
      // 更新加载提示（不用弹窗）
      const styleIndex = (startIndex + i) % CARD_STYLES.length;
      const styleName = CARD_STYLES[styleIndex].name;
      updateLoadingText(`正在生成第 ${i + 1}/${count} 个名片（${styleName}风格）...`);
      
      const html = await generateCardHTML(styleIndex);
      const cardElement = renderCard(html, i, styleName);
      cards.push(cardElement);
    } catch (error) {
      console.error(`生成名片 ${i + 1} 失败:`, error);
      // 创建错误占位
      const errorCard = document.createElement('div');
      errorCard.className = 'card-wrapper card-error';
      errorCard.innerHTML = `
        <div class="generated-card" style="width: ${CARD_WIDTH}px; height: ${CARD_HEIGHT}px; display: flex; align-items: center; justify-content: center; background: #f8f8f8; border: 2px dashed #ccc; border-radius: 8px;">
          <p style="color: #999;">生成失败，请重试</p>
        </div>
      `;
      cards.push(errorCard);
    }
  }
  
  // 隐藏加载状态，显示名片
  loading.style.display = 'none';
  updateLoadingText('AI 正在设计名片...');
  
  cards.forEach(card => container.appendChild(card));
  actions.style.display = 'block';
}

// 绑定输入事件
document.getElementById('name').addEventListener('input', (e) => {
  cardData.name = e.target.value;
  saveToStorage();
  updateGenerateButton();
});

document.getElementById('position').addEventListener('input', (e) => {
  cardData.position = e.target.value;
  saveToStorage();
});

document.getElementById('company').addEventListener('input', (e) => {
  cardData.company = e.target.value;
  saveToStorage();
  updateGenerateButton();
});

document.getElementById('phone').addEventListener('input', (e) => {
  cardData.phone = e.target.value;
  saveToStorage();
});

document.getElementById('email').addEventListener('input', (e) => {
  cardData.email = e.target.value;
  saveToStorage();
});

document.getElementById('address').addEventListener('input', (e) => {
  cardData.address = e.target.value;
  saveToStorage();
});

document.getElementById('website').addEventListener('input', (e) => {
  cardData.website = e.target.value;
  saveToStorage();
});

// Logo 上传
document.getElementById('logo-btn').addEventListener('click', () => {
  document.getElementById('logo-upload').click();
});

document.getElementById('logo-upload').addEventListener('change', async (e) => {
  const file = e.target.files[0];
  if (!file) return;
  
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
  
  // 上传
  try {
    const logoUrl = await uploadImage(file);
    cardData.logoUrl = logoUrl;
    saveToStorage();
    console.log('Logo 上传成功');
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
  saveToStorage();
});

// 生成按钮
document.getElementById('generate-btn').addEventListener('click', () => {
  generateCards(3);
});

// 换一批按钮
document.getElementById('refresh-btn').addEventListener('click', () => {
  generateCards(3);
});

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
      logoUrl: null
    };
    
    // 重置表单
    document.getElementById('name').value = '';
    document.getElementById('position').value = '';
    document.getElementById('company').value = '';
    document.getElementById('phone').value = '';
    document.getElementById('email').value = '';
    document.getElementById('address').value = '';
    document.getElementById('website').value = '';
    document.getElementById('logo-upload').value = '';
    document.getElementById('logo-name').textContent = '';
    document.getElementById('logo-preview').style.display = 'none';
    document.getElementById('remove-logo-btn').style.display = 'none';
    
    // 清除名片预览
    document.getElementById('cards-container').innerHTML = `
      <div class="cards-placeholder">
        <p>👈 填写左侧信息后，点击「AI 生成名片」</p>
        <p style="margin-top: 8px; font-size: 14px;">AI 将为您生成 3 种不同风格的名片</p>
      </div>
    `;
    document.getElementById('preview-actions').style.display = 'none';
    
    localStorage.removeItem(STORAGE_KEY);
    updateGenerateButton();
  }
});

// 初始化
loadFromStorage();
updateGenerateButton();
