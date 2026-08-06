import {createHash} from 'node:crypto'
import {createReadStream, existsSync, statSync} from 'node:fs'
import {basename, resolve} from 'node:path'
import {createRequire} from 'node:module'
import {getCliClient} from 'sanity/cli'

const require = createRequire(import.meta.url)
const XLSX = require('xlsx')

const projectRoot = resolve(import.meta.dirname, '..')
const workspaceRoot = resolve(projectRoot, '..')
const workbookPath = resolve(
  workspaceRoot,
  'outputs/019fd515-64ca-7961-aac4-648ef9aa37d3/Cinematic-Wall-现有58条壁纸批量导入.xlsx',
)
const localLibraryRoot = '/Users/bytedance/Library/Application Support/Foldwalls'
const mediaRoot = resolve(localLibraryRoot, 'Library')
const thumbnailRoot = resolve(localLibraryRoot, 'Thumbnails')
const dryRun = process.argv.includes('--dry-run')

const client = getCliClient({apiVersion: '2026-08-06'})

function value(row, key) {
  const result = row[key]
  return result == null ? '' : String(result).trim()
}

function numberValue(row, key) {
  const result = Number(row[key])
  return Number.isFinite(result) && result >= 0 ? result : undefined
}

function splitValues(input) {
  return [...new Set(String(input ?? '').split(/[,，\n]/).map((item) => item.trim()).filter(Boolean))]
}

function colorValue(input) {
  const raw = String(input ?? '').trim()
  if (!raw) return undefined
  const normalized = raw.startsWith('#') ? raw : `#${raw}`
  return /^#[0-9a-f]{6}$/i.test(normalized) ? normalized.toUpperCase() : undefined
}

function documentId(row, index) {
  const source = value(row, '导入ID') || value(row, '原文件名') || value(row, '封面文件名') || value(row, '名称') || String(index)
  const digest = createHash('sha256').update(source).digest('hex')
  return `wallpaper-import-${digest.slice(0, 32)}`
}

function assetReference(assetId, kind) {
  return {
    _type: kind,
    asset: {_type: 'reference', _ref: assetId},
  }
}

function getResourcePath(root, filename) {
  if (!filename) return undefined
  const candidate = resolve(root, basename(filename))
  return existsSync(candidate) ? candidate : undefined
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
      console.warn(`  ${label}失败，${Math.round(delay / 1000)} 秒后重试（${attempt}/${attempts}）：${error.message ?? error}`)
      await new Promise((resolveDelay) => setTimeout(resolveDelay, delay))
    }
  }
  throw lastError
}

async function findExistingAsset(assetType, filePath) {
  const filename = basename(filePath)
  const size = statSync(filePath).size
  return client.fetch(
    `*[_type == $assetType && originalFilename == $filename && size == $size][0]._id`,
    {assetType, filename, size},
  )
}

async function uploadAsset(assetKind, filePath) {
  const assetType = assetKind === 'image' ? 'sanity.imageAsset' : 'sanity.fileAsset'
  const existingId = await findExistingAsset(assetType, filePath)
  if (existingId) {
    console.log(`  复用已上传文件：${basename(filePath)}`)
    return existingId
  }
  const uploaded = await withRetries(`上传 ${basename(filePath)}`, () => client.assets.upload(
    assetKind,
    createReadStream(filePath),
    {filename: basename(filePath)},
  ))
  return uploaded._id
}

function makePayload(row, index, mediaAssetId, thumbnailAssetId) {
  const kind = value(row, '类型').toLowerCase() === 'image' ? 'image' : 'video'
  const status = ['hidden', '下架', '已下架'].includes(value(row, '状态').toLowerCase()) ? 'hidden' : 'published'
  const payload = {
    _id: documentId(row, index),
    _type: 'wallpaper',
    title: value(row, '名称') || basename(value(row, '原文件名')).replace(/\.[^.]+$/, '') || `未命名壁纸 ${index + 1}`,
    kind,
    status,
    featured: ['true', '1', 'yes', '是', '推荐'].includes(value(row, '首页推荐').toLowerCase()),
    sortOrder: Math.round(numberValue(row, '排序') ?? 100),
  }

  const optionalTextFields = [
    ['titleEn', '英文名称'],
    ['subtitle', '简介'],
    ['subtitleEn', '英文简介'],
    ['author', '作者'],
    ['licenseName', '授权说明'],
    ['sourceUrl', '来源链接'],
  ]
  for (const [field, column] of optionalTextFields) {
    const fieldValue = value(row, column)
    if (fieldValue) payload[field] = fieldValue
  }

  const categories = splitValues(row['分类'])
  const tags = splitValues(row['标签'])
  if (categories.length) payload.categories = categories
  if (tags.length) payload.tags = tags

  for (const [field, column] of [['width', '宽度'], ['height', '高度'], ['duration', '时长秒']]) {
    const fieldValue = numberValue(row, column)
    if (fieldValue !== undefined) payload[field] = field === 'duration' ? fieldValue : Math.round(fieldValue)
  }

  for (const [field, column] of [['paletteStart', '起点颜色'], ['paletteMiddle', '中点颜色'], ['paletteEnd', '终点颜色']]) {
    const fieldValue = colorValue(row[column])
    if (fieldValue) payload[field] = fieldValue
  }

  if (thumbnailAssetId) payload.thumbnail = assetReference(thumbnailAssetId, 'image')
  if (mediaAssetId) payload[kind === 'video' ? 'video' : 'image'] = assetReference(mediaAssetId, kind === 'video' ? 'file' : 'image')
  if (kind === 'image' && !thumbnailAssetId && mediaAssetId) payload.thumbnail = assetReference(mediaAssetId, 'image')
  return payload
}

async function main() {
  if (!existsSync(workbookPath)) throw new Error(`找不到导入表格：${workbookPath}`)
  const workbook = XLSX.readFile(workbookPath)
  const sheet = workbook.Sheets['壁纸导入'] ?? workbook.Sheets[workbook.SheetNames[0]]
  const rows = XLSX.utils.sheet_to_json(sheet, {defval: ''})
  if (rows.length !== 58) throw new Error(`表格应有 58 条，实际为 ${rows.length} 条`)

  const missing = []
  for (const row of rows) {
    const mediaName = value(row, '原文件名')
    const thumbnailName = value(row, '封面文件名')
    if (!getResourcePath(mediaRoot, mediaName)) missing.push(`原文件：${mediaName}`)
    if (!getResourcePath(thumbnailRoot, thumbnailName)) missing.push(`封面：${thumbnailName}`)
  }
  if (missing.length) throw new Error(`有 ${missing.length} 个资源缺失：\n${missing.slice(0, 10).join('\n')}`)

  console.log(`已校验 58 条记录、58 个原文件和 58 个封面。${dryRun ? '（仅检查）' : ''}`)
  if (dryRun) return

  let succeeded = 0
  const failures = []
  for (let index = 0; index < rows.length; index += 1) {
    const row = rows[index]
    const title = value(row, '名称') || `未命名壁纸 ${index + 1}`
    const id = documentId(row, index)
    const existing = await client.getDocument(id)
    console.log(`[${index + 1}/58] ${title}${existing ? '（续传/更新）' : ''}`)
    try {
      const kind = value(row, '类型').toLowerCase() === 'image' ? 'image' : 'video'
      const mediaPath = getResourcePath(mediaRoot, value(row, '原文件名'))
      const thumbnailPath = getResourcePath(thumbnailRoot, value(row, '封面文件名'))
      let mediaAssetId = kind === 'video' ? existing?.video?.asset?._ref : existing?.image?.asset?._ref
      let thumbnailAssetId = existing?.thumbnail?.asset?._ref
      if (!mediaAssetId) mediaAssetId = await uploadAsset(kind === 'image' ? 'image' : 'file', mediaPath)
      if (!thumbnailAssetId) thumbnailAssetId = await uploadAsset('image', thumbnailPath)
      await withRetries('写入壁纸记录', () => client.createOrReplace(makePayload(row, index, mediaAssetId, thumbnailAssetId)))
      succeeded += 1
      console.log(`  完成：${title}`)
    } catch (error) {
      failures.push({index: index + 1, title, error: error.message ?? String(error)})
      console.error(`  失败：${error.message ?? error}`)
    }
  }

  const summary = await client.fetch(`{
    "documents": count(*[_type == "wallpaper"]),
    "withMedia": count(*[_type == "wallpaper" && (defined(image.asset) || defined(video.asset))]),
    "withThumbnail": count(*[_type == "wallpaper" && defined(thumbnail.asset)]),
    "imageAssets": count(*[_type == "sanity.imageAsset"]),
    "fileAssets": count(*[_type == "sanity.fileAsset"])
  }`)
  console.log('\n导入结果：', JSON.stringify({succeeded, failed: failures.length, ...summary}, null, 2))
  if (failures.length) {
    console.error('失败明细：', JSON.stringify(failures, null, 2))
    process.exitCode = 1
  }
}

await main()
