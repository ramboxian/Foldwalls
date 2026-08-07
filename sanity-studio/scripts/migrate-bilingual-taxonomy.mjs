import {getCliClient} from 'sanity/cli'
import {CATEGORY_DEFINITIONS, categoryDocumentId, resolveCategory} from '../taxonomy.ts'

const client = getCliClient({apiVersion: '2026-08-06'})

const translations = {
  '3D动画': '3D Animation', '上官婉儿': "Shangguan Wan'er", '东方Project': 'Touhou Project', '云海': 'Sea of Clouds',
  '云雾': 'Cloud Mist', '人像': 'Portrait', '便利店': 'Convenience Store', '倒影': 'Reflection', '光影': 'Light and Shadow',
  '冬夜': 'Winter Night', '冬季': 'Winter', '冰晶': 'Ice Crystals', '几何': 'Geometry', '列车': 'Train', '剑刃': 'Blade',
  '剑士': 'Swordsman', '动态壁纸': 'Live Wallpaper', '动漫少女': 'Anime Girl', '动画风': 'Animated Style', '午休': 'Siesta',
  '午后': 'Afternoon', '卡芙卡': 'Kafka', '原神': 'Genshin Impact', '双枪': 'Dual Pistols', '古典': 'Classical',
  '古堡': 'Old Manor', '古风': 'Ancient Chinese Style', '可爱': 'Cute', '哥特': 'Gothic', '地铁': 'Metro', '城市': 'City',
  '复古': 'Vintage', '复古车': 'Vintage Car', '夏日': 'Summer', '夜景': 'Nightscape', '天台': 'Rooftop', '奇点': 'Singularity',
  '宇宙': 'Cosmos', '宇航员': 'Astronaut', '室内': 'Interior', '家居': 'Home', '富士山': 'Mount Fuji', '对决': 'Showdown',
  '小丑': 'Joker', '小狗': 'Puppy', '小舟': 'Boat', '尘白禁区': 'Snowbreak', '山丘': 'Hills', '山川': 'Mountains',
  '山雾': 'Mountain Mist', '崩坏星穹铁道': 'Honkai: Star Rail', '引力': 'Gravity', '悬崖': 'Cliffs', '战斗': 'Battle',
  '户外': 'Outdoors', '打哈欠': 'Yawning', '探头': 'Peekaboo', '插画': 'Illustration', '摇头': 'Head Tilt', '摇尾巴': 'Tail Wagging',
  '旋涡': 'Vortex', '日落': 'Sunset', '时尚': 'Fashion', '星云': 'Nebula', '星眸': 'Starlit Eyes', '星空': 'Starry Sky',
  '星系': 'Galaxy', '星际穿越': 'Interstellar', '春天': 'Spring', '晚霞': 'Afterglow', '晨光': 'Morning Light',
  '晨雾': 'Morning Mist', '暖饮': 'Warm Drink', '暗黑': 'Dark', '暮色': 'Twilight', '月光': 'Moonlight', '月球': 'Moon',
  '未来': 'Future', '机械': 'Machinery', '机械少女': 'Android Girl', '机甲': 'Mecha', '松林': 'Pine Forest', '松树': 'Pine Trees',
  '极光': 'Aurora', '柔光': 'Soft Light', '柚叶': 'Yuzuha', '梦幻': 'Dreamy', '梦核': 'Dreamcore', '武士': 'Samurai',
  '比利奇德': 'Billy Kid', '水下': 'Underwater', '水光': 'Water Glow', '水杯': 'Cup', '汽车': 'Car', '沙漠': 'Desert',
  '治愈': 'Healing', '海岛': 'Island', '海岸': 'Coast', '海棠': 'Begonias', '海浪': 'Waves', '海滩': 'Beach',
  '深蓝': 'Deep Blue', '清新': 'Fresh', '游戏': 'Game', '湖畔': 'Lakeside', '溪流': 'Stream', '漫画': 'Comic',
  '王者荣耀': 'Honor of Kings', '琥珀眼': 'Amber Eyes', '电影': 'Movie', '电影感': 'Cinematic', '电锯人': 'Chainsaw Man',
  '疗愈': 'Soothing', '白云': 'White Clouds', '白色': 'White', '白裙': 'White Dress', '白鸟': 'White Birds', '真纪真': 'Makima',
  '眨眼': 'Blinking', '眼眸': 'Eyes', '礼服': 'Evening Gown', '福特野马': 'Ford Mustang', '科幻': 'Sci-Fi', '站台': 'Platform',
  '篝火': 'Campfire', '粉色': 'Pink', '粉蓝': 'Pink and Blue', '粒子': 'Particles', '紫眸': 'Violet Eyes', '紫色': 'Purple',
  '红色': 'Red', '红裙': 'Red Dress', '红酒': 'Wine', '经典车': 'Classic Car', '绝区零': 'Zenless Zone Zero',
  '缪斯冲刺': 'Muse Dash', '肖像': 'Portrait', '肴': 'Yao', '自然': 'Nature', '舞厅': 'Ballroom', '舞台': 'Stage',
  '舞蹈': 'Dance', '芦苇': 'Reeds', '花朵': 'Flowers', '花瓣': 'Petals', '花田': 'Flower Field', '英雄联盟': 'League of Legends',
  '草原': 'Grassland', '萌宠': 'Cute Pet', '落雪': 'Snowfall', '蓝天': 'Blue Sky', '蓝海': 'Blue Sea', '蓝红': 'Blue and Red',
  '蓝色': 'Blue', '蓝色背景': 'Blue Background', '蜘蛛侠': 'Spider-Man', '蝙蝠侠': 'Batman', '蝴蝶': 'Butterflies',
  '街头': 'Street', '赛博': 'Cyber', '赛博朋克': 'Cyberpunk', '超级英雄': 'Superhero', '趴卧': 'Lounging', '车流': 'Traffic',
  '车窗': 'Train Window', '迈尔斯': 'Miles Morales', '透明伞': 'Clear Umbrella', '金克丝': 'Jinx', '金字塔': 'Pyramid',
  '金色': 'Gold', '钓鱼': 'Fishing', '钢琴': 'Piano', '钢铁侠': 'Iron Man', '银色': 'Silver', '镜面': 'Mirrors',
  '闪钻': 'Rhinestones', '阳光': 'Sunlight', '雨夜': 'Rainy Night', '雨幕': 'Rain Curtain', '雨雪': 'Sleet', '雪原': 'Snowfield',
  '雪夜': 'Snowy Night', '雪山': 'Snow Mountains', '雪林': 'Snowy Forest', '雪湖': 'Frozen Lake', '雷电将军': 'Raiden Shogun',
  '雾气': 'Mist', '霓虹': 'Neon', '青绿色': 'Teal', '静态壁纸': 'Still Wallpaper', '静谧': 'Serene', '音乐': 'Music',
  '音游': 'Rhythm Game', '风景': 'Landscape', '鲜花': 'Flowers', '黄色背景': 'Yellow Background', '黑洞': 'Black Hole',
  '黑猫': 'Black Cat', '黑白': 'Black and White', '黑色': 'Black', '黑金': 'Black and Gold', '龙纹': 'Dragon Motif',
}

const categoryById = new Map(CATEGORY_DEFINITIONS.map((item) => [item.id, item]))

function textFor(doc) {
  return [doc.title, doc.titleEn, ...(doc.tags ?? [])].filter(Boolean).join(' ').toLocaleLowerCase()
}

function inferredCategoryIds(doc) {
  const ids = new Set((doc.categories ?? []).map((value) => resolveCategory(value)?.id).filter(Boolean))
  const text = textFor(doc)
  const addIf = (id, values) => { if (values.some((value) => text.includes(value.toLocaleLowerCase()))) ids.add(id) }

  addIf('pet', ['萌宠', '黑猫', '小猫', '小狗', '宠物', 'puppy', 'kitten', 'cat'])
  addIf('girl', ['人像', '少女', '婉儿', '真纪真', '金克丝', '卡芙卡', '雷电将军', '剑姬', '女孩', 'girl', 'woman'])
  addIf('portrait', ['人像', '肖像', '少女', '眼眸', '回眸', 'gaze', 'girl', 'woman', 'joker'])
  addIf('movie', ['电影', '电影感', '小丑', '蝙蝠侠', '钢铁侠', '星际穿越', 'joker', 'batman', 'iron man', 'interstellar'])
  addIf('game', ['游戏', '绝区零', '王者荣耀', '英雄联盟', '原神', '崩坏星穹铁道', '尘白禁区', '缪斯冲刺', 'game'])
  addIf('scifi', ['科幻', '赛博', '未来', '机甲', '机械', '奇点', '黑洞', '宇宙', '宇航员', 'ufo', 'cyber', 'android'])
  addIf('vehicle', ['汽车', '野马', '列车', '复古车', '车流', '车窗', 's13', 'mustang', 'train'])
  addIf('anime', ['动漫', '动画风', '漫画', '插画', 'anime'])
  return [...ids].filter((id) => categoryById.has(id)).sort((a, b) => categoryById.get(a).order - categoryById.get(b).order)
}

function englishTag(tag) {
  if (translations[tag]) return translations[tag]
  if (!/[\u3400-\u9fff]/u.test(tag)) return tag
  throw new Error(`缺少英文标签翻译：${tag}`)
}

for (const category of CATEGORY_DEFINITIONS) {
  await client.createIfNotExists({
    _id: categoryDocumentId(category.id),
    _type: 'category',
    key: category.id,
    titleZh: category.zh,
    titleEn: category.en,
    order: category.order,
    enabled: true,
  })
}

const wallpapers = await client.fetch(`*[_type == "wallpaper"]{_id, title, titleEn, categories, tags}`)
let migrated = 0

for (const wallpaper of wallpapers) {
  const categoryIds = inferredCategoryIds(wallpaper)
  const localizedTags = [...new Set(wallpaper.tags ?? [])].map((tag, index) => ({
    _type: 'localizedTag',
    _key: `tag-${String(index + 1).padStart(3, '0')}`,
    zh: tag,
    en: englishTag(tag),
  }))
  await client.patch(wallpaper._id).set({
    categoryRefs: categoryIds.map((id) => ({_type: 'reference', _key: id, _ref: categoryDocumentId(id)})),
    categories: categoryIds.map((id) => categoryById.get(id).zh),
    localizedTags,
    tags: localizedTags.map((tag) => tag.zh),
  }).commit({autoGenerateArrayKeys: true})
  migrated += 1
  console.log(`${migrated}/${wallpapers.length} ${wallpaper.title} → ${categoryIds.join(', ')}`)
}

console.log(JSON.stringify({categories: CATEGORY_DEFINITIONS.length, wallpapers: wallpapers.length, migrated}, null, 2))
