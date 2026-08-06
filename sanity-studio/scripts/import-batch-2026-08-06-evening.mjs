import {createReadStream, existsSync, statSync} from 'node:fs'
import {basename} from 'node:path'
import {getCliClient} from 'sanity/cli'

const client = getCliClient({apiVersion: '2026-08-06'})
const generatedRoot = '/tmp/CinematicWallBatch-20260806'

const entries = [
  {
    id: 'wallpaper-20260806-neon-rain-gaze',
    sourcePath: '/Users/bytedance/Downloads/背景车水马龙，美女魅惑看向镜头，头发随风飘动，注意人物质感，五官清晰可见，面部皮肤质感清晰，超清8k.mp4',
    thumbnailPath: `${generatedRoot}/thumbnails/neon-rain-gaze.jpg`,
    previewPath: `${generatedRoot}/previews/neon-rain-gaze.m4v`,
    title: '霓虹雨幕',
    titleEn: 'Neon Rain Gaze',
    subtitle: '红裙女子撑伞回望镜头，疾驰车流在潮湿街道上拉出红绿光轨。',
    subtitleEn: 'A woman in red looks back beneath a clear umbrella as traffic paints neon trails across the rain-soaked street.',
    categories: ['城市', '夜晚', '暖色'],
    tags: ['人像', '红裙', '雨夜', '霓虹', '透明伞', '车流', '街头', '4K'],
    width: 3840,
    height: 2160,
    duration: 5.041667,
    author: 'User Collection',
    licenseName: 'User-provided asset',
    featured: true,
    curated: true,
    popular: true,
    paletteStart: '#3A0B08',
    paletteMiddle: '#C63B12',
    paletteEnd: '#092B2A',
  },
  {
    id: 'wallpaper-20260806-dark-joker',
    sourcePath: '/Users/bytedance/Downloads/dark-joker-moewalls-com.mp4',
    thumbnailPath: `${generatedRoot}/thumbnails/dark-joker.jpg`,
    previewPath: `${generatedRoot}/previews/dark-joker.m4v`,
    title: '暗夜小丑',
    titleEn: 'Joker in the Dark',
    subtitle: '黑白小丑低首隐入深暗背景，飘落的白色光点让冷峻肖像缓慢呼吸。',
    subtitleEn: 'A monochrome Joker fades into darkness while drifting white particles give the brooding portrait a quiet pulse.',
    categories: ['深色', '夜晚', '极简'],
    tags: ['小丑', 'Joker', '黑白', '电影', '肖像', '暗黑', '粒子', '4K'],
    width: 3840,
    height: 2160,
    duration: 20.133333,
    author: 'MoeWalls',
    licenseName: 'Third-party wallpaper · verify rights before distribution',
    sourceUrl: 'https://moewalls.com/',
    featured: false,
    curated: false,
    popular: true,
    paletteStart: '#0A0A0B',
    paletteMiddle: '#4A4A4A',
    paletteEnd: '#030303',
  },
  {
    id: 'wallpaper-20260806-miles-winter',
    sourcePath: '/Users/bytedance/Downloads/miles-morales-lonely-winter-street-spiderman-moewalls-com.mp4',
    thumbnailPath: `${generatedRoot}/thumbnails/miles-winter.jpg`,
    previewPath: `${generatedRoot}/previews/miles-winter.m4v`,
    title: '迈尔斯·雪夜独行',
    titleEn: 'Miles Morales: Solitary Winter',
    subtitle: '迈尔斯披着积雪兜帽站在冬夜街头，暖色灯火与冷雨落雪映亮红黑战衣。',
    subtitleEn: 'Miles stands alone beneath a snow-covered hood as warm city lights cut through the cold rain and snow.',
    categories: ['动漫', '城市', '夜晚'],
    tags: ['蜘蛛侠', '迈尔斯', 'Miles Morales', '雪夜', '城市', '雨雪', '超级英雄', '4K'],
    width: 3840,
    height: 2160,
    duration: 25,
    author: 'MoeWalls',
    licenseName: 'Third-party wallpaper · verify rights before distribution',
    sourceUrl: 'https://moewalls.com/',
    featured: true,
    curated: true,
    popular: true,
    paletteStart: '#07131B',
    paletteMiddle: '#C83222',
    paletteEnd: '#5F7782',
  },
  {
    id: 'wallpaper-20260806-moonlit-winter-train',
    sourcePath: '/Users/bytedance/Downloads/winter-night-train-moewalls-com.mp4',
    thumbnailPath: `${generatedRoot}/thumbnails/moonlit-winter-train.jpg`,
    previewPath: `${generatedRoot}/previews/moonlit-winter-train.m4v`,
    title: '月下雪夜列车',
    titleEn: 'Moonlit Winter Train',
    subtitle: '粉紫列车穿过月光与落雪，水面倒影将安静冬夜延伸到远方。',
    subtitleEn: 'A rose-lit train glides beneath the moon and falling snow, its reflection stretching across the still winter water.',
    categories: ['夜晚', '天空', '静谧'],
    tags: ['列车', '雪夜', '月光', '倒影', '动画风', '粉蓝', '治愈', '4K'],
    width: 3840,
    height: 2160,
    duration: 15.25,
    author: 'MoeWalls',
    licenseName: 'Third-party wallpaper · verify rights before distribution',
    sourceUrl: 'https://moewalls.com/',
    featured: true,
    curated: true,
    popular: false,
    paletteStart: '#07162E',
    paletteMiddle: '#427FD0',
    paletteEnd: '#B73483',
  },
  {
    id: 'wallpaper-20260806-aurora-winter-pines',
    sourcePath: '/Users/bytedance/Downloads/aurora-forest-moewalls-com.mp4',
    thumbnailPath: `${generatedRoot}/thumbnails/aurora-winter-pines.jpg`,
    previewPath: `${generatedRoot}/previews/aurora-winter-pines.m4v`,
    title: '极光雪林',
    titleEn: 'Aurora over the Winter Pines',
    subtitle: '青绿色极光漫过积雪松林，星尘与薄雾在高耸树影之间缓慢流动。',
    subtitleEn: 'Teal aurora light rolls above snow-covered pines while stars and mist drift between the towering silhouettes.',
    categories: ['自然', '森林', '夜晚'],
    tags: ['极光', '雪林', '松树', '星空', '冬季', '青绿色', '自然', '4K'],
    width: 3840,
    height: 2160,
    duration: 13.95,
    author: 'MoeWalls',
    licenseName: 'Third-party wallpaper · verify rights before distribution',
    sourceUrl: 'https://moewalls.com/',
    featured: true,
    curated: true,
    popular: false,
    paletteStart: '#031525',
    paletteMiddle: '#087E86',
    paletteEnd: '#02070E',
  },
  {
    id: 'wallpaper-20260806-deep-blue-mustang',
    sourcePath: '/Users/bytedance/Downloads/170006-842348810_medium.mp4',
    thumbnailPath: `${generatedRoot}/thumbnails/deep-blue-mustang.jpg`,
    previewPath: `${generatedRoot}/previews/deep-blue-mustang.m4v`,
    title: '深蓝野马',
    titleEn: 'Mustang in Deep Blue',
    subtitle: '经典黑色野马停驻于深蓝水面，冷光勾勒车身线条与克制的机械质感。',
    subtitleEn: 'A classic black Mustang rests above deep blue water, cool light tracing its restrained mechanical silhouette.',
    categories: ['深色', '蓝色', '极简'],
    tags: ['汽车', '福特野马', 'Mustang', '经典车', '黑色', '深蓝', '机械', '2K'],
    width: 2560,
    height: 1440,
    duration: 6.038333,
    author: 'User Collection',
    licenseName: 'User-provided asset',
    featured: false,
    curated: false,
    popular: false,
    paletteStart: '#031421',
    paletteMiddle: '#0D5D82',
    paletteEnd: '#01060B',
  },
]

function assetReference(assetId, type) {
  return {_type: type, asset: {_type: 'reference', _ref: assetId}}
}

async function withRetries(label, operation, attempts = 4) {
  let lastError
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      return await operation()
    } catch (error) {
      lastError = error
      if (attempt === attempts) break
      const delay = Math.min(15_000, 1_500 * (2 ** (attempt - 1)))
      console.warn(`  ${label}失败，${Math.round(delay / 1000)} 秒后重试（${attempt}/${attempts}）`)
      await new Promise((resolve) => setTimeout(resolve, delay))
    }
  }
  throw lastError
}

async function uploadOrReuse(assetType, filePath, contentType) {
  if (!existsSync(filePath)) throw new Error(`找不到文件：${filePath}`)
  const filename = basename(filePath)
  const size = statSync(filePath).size
  const sanityType = assetType === 'image' ? 'sanity.imageAsset' : 'sanity.fileAsset'
  const existingAssetId = await client.fetch(
    `*[_type == $sanityType && originalFilename == $filename && size == $size][0]._id`,
    {sanityType, filename, size},
  )
  if (existingAssetId) return existingAssetId
  const uploaded = await withRetries(`上传 ${filename}`, () => client.assets.upload(
    assetType,
    createReadStream(filePath),
    {filename, contentType},
  ))
  return uploaded._id
}

const batchSortBase = Date.now()
const failures = []

for (let index = 0; index < entries.length; index += 1) {
  const entry = entries[index]
  console.log(`[${index + 1}/${entries.length}] ${entry.title}`)
  try {
    const existing = await client.getDocument(entry.id)
    const videoAssetId = existing?.video?.asset?._ref
      ?? await uploadOrReuse('file', entry.sourcePath, 'video/mp4')
    const thumbnailAssetId = existing?.thumbnail?.asset?._ref
      ?? await uploadOrReuse('image', entry.thumbnailPath, 'image/jpeg')
    const previewAssetId = existing?.previewVideo?.asset?._ref
      ?? await uploadOrReuse('file', entry.previewPath, 'video/x-m4v')

    const payload = {
      _id: entry.id,
      _type: 'wallpaper',
      title: entry.title,
      titleEn: entry.titleEn,
      subtitle: entry.subtitle,
      subtitleEn: entry.subtitleEn,
      kind: 'video',
      categories: entry.categories,
      tags: entry.tags,
      width: entry.width,
      height: entry.height,
      duration: entry.duration,
      author: entry.author,
      licenseName: entry.licenseName,
      status: 'published',
      featured: entry.featured,
      curated: entry.curated,
      popular: entry.popular,
      sortOrder: existing?.sortOrder ?? batchSortBase + (entries.length - index),
      paletteStart: entry.paletteStart,
      paletteMiddle: entry.paletteMiddle,
      paletteEnd: entry.paletteEnd,
      thumbnail: assetReference(thumbnailAssetId, 'image'),
      video: assetReference(videoAssetId, 'file'),
      previewVideo: assetReference(previewAssetId, 'file'),
    }
    if (entry.sourceUrl) payload.sourceUrl = entry.sourceUrl

    await withRetries('写入壁纸记录', () => client.createOrReplace(payload))
    console.log('  已上传原视频、封面、轻量预览和完整元数据')
  } catch (error) {
    failures.push({id: entry.id, title: entry.title, error: error.message ?? String(error)})
    console.error(`  失败：${error.message ?? error}`)
  }
}

const ids = entries.map((entry) => entry.id)
const imported = await client.fetch(`*[_id in $ids] | order(sortOrder desc) {
  _id, title, titleEn, status, featured, curated, popular, sortOrder,
  "videoUrl": video.asset->url,
  "thumbnailUrl": thumbnail.asset->url,
  "previewUrl": previewVideo.asset->url
}`, {ids})

console.log(JSON.stringify({requested: entries.length, imported: imported.length, failed: failures.length, documents: imported}, null, 2))
if (failures.length || imported.length !== entries.length) process.exitCode = 1
