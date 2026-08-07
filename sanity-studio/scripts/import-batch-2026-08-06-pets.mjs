import {createReadStream, existsSync, statSync} from 'node:fs'
import {basename} from 'node:path'
import {getCliClient} from 'sanity/cli'

const client = getCliClient({apiVersion: '2026-08-06'})
const generatedRoot = '/tmp/CinematicWallBatch-20260806-pets'

const entries = [
  {
    id: 'wallpaper-20260806-black-cat-warm-sip',
    sourcePath: '/Users/bytedance/Downloads/猫咪灵动的看看屏幕眨眨眼，喝了一口水，非常的高兴，注意镜头不要发生变化，注意猫咪细节，毛发分明，超清8k细节，动作自然灵动敏捷，极其可爱.mp4',
    thumbnailPath: `${generatedRoot}/thumbnails/black-cat-warm-sip.jpg`,
    previewPath: `${generatedRoot}/previews/black-cat-warm-sip.m4v`,
    title: '暖饮小黑猫',
    titleEn: 'Black Cat’s Cozy Sip',
    subtitle: '圆眼小黑猫捧着白色杯子，眨眨眼、喝一口暖饮后露出满足神情。',
    subtitleEn: 'A bright-eyed black kitten cradles a white cup, blinks at the screen and looks delighted after a cozy sip.',
    categories: ['极简', '深色', '暖色'],
    tags: ['萌宠', '黑猫', '水杯', '眨眼', '暖饮', '3D动画', '可爱', '4K'],
    duration: 5.041667,
    paletteStart: '#02070B',
    paletteMiddle: '#153642',
    paletteEnd: '#F3E3C3',
  },
  {
    id: 'wallpaper-20260806-happy-tail-pup',
    sourcePath: '/Users/bytedance/Downloads/灵动的看看屏幕眨眨眼，摇头摇尾巴非常开心，注意镜头不要发生变化，注意狗狗细节，毛发分明，超清8k细节，动作自然灵动敏捷，极其可爱.mp4',
    thumbnailPath: `${generatedRoot}/thumbnails/happy-tail-pup.jpg`,
    previewPath: `${generatedRoot}/previews/happy-tail-pup.m4v`,
    title: '摇尾小伙伴',
    titleEn: 'Happy Little Tail',
    subtitle: '毛茸茸的小狗坐在清亮蓝色背景前，眨眼摇头，开心地摇起尾巴。',
    subtitleEn: 'A fluffy little pup blinks, tilts its head and wags its tail happily against a clear blue backdrop.',
    categories: ['极简', '蓝色', '暖色'],
    tags: ['萌宠', '小狗', '摇尾巴', '眨眼', '蓝色背景', '3D动画', '可爱', '4K'],
    duration: 5.041667,
    paletteStart: '#1B9DC0',
    paletteMiddle: '#D58A3B',
    paletteEnd: '#E5C89A',
  },
  {
    id: 'wallpaper-20260806-sleepy-black-cat',
    sourcePath: '/Users/bytedance/Downloads/jimeng-2026-08-06-7305-小猫趴在地上，懒的蠕动身子，卖萌的眨眨眼，打了一个哈欠，动作迅速灵动有活力，超清....mp4',
    thumbnailPath: `${generatedRoot}/thumbnails/sleepy-black-cat.jpg`,
    previewPath: `${generatedRoot}/previews/sleepy-black-cat.m4v`,
    title: '懒懒黑猫',
    titleEn: 'Sleepy Black Cat',
    subtitle: '琥珀眼黑猫懒洋洋地侧躺在明黄背景前，轻轻蠕动、眨眼并打了个哈欠。',
    subtitleEn: 'An amber-eyed black cat lounges against a sunny yellow backdrop, wriggles softly, blinks and lets out a tiny yawn.',
    categories: ['极简', '暖色', '深色'],
    tags: ['萌宠', '黑猫', '琥珀眼', '打哈欠', '趴卧', '黄色背景', '3D动画', '4K'],
    duration: 5.056009,
    paletteStart: '#D68A00',
    paletteMiddle: '#F4C443',
    paletteEnd: '#08090B',
  },
  {
    id: 'wallpaper-20260806-peekaboo-black-cat',
    sourcePath: '/Users/bytedance/Downloads/jimeng-2026-08-06-5450-小猫从底部钻出来，可爱的眨眨眼摇摇头，对着镜头卖萌，非常可爱，动作迅速灵动有活力.mp4',
    thumbnailPath: `${generatedRoot}/thumbnails/peekaboo-black-cat.jpg`,
    previewPath: `${generatedRoot}/previews/peekaboo-black-cat.m4v`,
    title: '探头小黑猫',
    titleEn: 'Peekaboo Black Cat',
    subtitle: '金色大眼的小黑猫从画面底部探出脑袋，眨眼摇头，好奇地望向镜头。',
    subtitleEn: 'A golden-eyed black kitten pops up from the bottom of the frame, blinking and tilting its head toward the camera.',
    categories: ['极简', '暖色', '深色'],
    tags: ['萌宠', '黑猫', '探头', '眨眼', '摇头', '黄色背景', '3D动画', '4K'],
    duration: 5.056009,
    paletteStart: '#E09B14',
    paletteMiddle: '#FFC443',
    paletteEnd: '#090A0B',
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

    await withRetries('写入壁纸记录', () => client.createOrReplace({
      _id: entry.id,
      _type: 'wallpaper',
      title: entry.title,
      titleEn: entry.titleEn,
      subtitle: entry.subtitle,
      subtitleEn: entry.subtitleEn,
      kind: 'video',
      categories: entry.categories,
      tags: entry.tags,
      width: 3840,
      height: 2160,
      duration: entry.duration,
      author: 'User Collection',
      licenseName: 'User-provided AI-generated asset',
      status: 'published',
      featured: false,
      curated: false,
      popular: false,
      sortOrder: existing?.sortOrder ?? batchSortBase + (entries.length - index),
      paletteStart: entry.paletteStart,
      paletteMiddle: entry.paletteMiddle,
      paletteEnd: entry.paletteEnd,
      thumbnail: assetReference(thumbnailAssetId, 'image'),
      video: assetReference(videoAssetId, 'file'),
      previewVideo: assetReference(previewAssetId, 'file'),
    }))
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
