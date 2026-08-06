import {createReadStream, existsSync, mkdirSync, statSync} from 'node:fs'
import {basename, extname, resolve} from 'node:path'
import {promisify} from 'node:util'
import {execFile} from 'node:child_process'
import {getCliClient} from 'sanity/cli'

const execFileAsync = promisify(execFile)
const client = getCliClient({apiVersion: '2026-08-06'})
const localMediaRoot = '/Users/bytedance/Library/Application Support/Foldwalls/Library'
const outputRoot = '/tmp/FoldwallsVideoPreviews'
const force = process.argv.includes('--force')

mkdirSync(outputRoot, {recursive: true})

function safeBaseName(name) {
  return basename(name, extname(name))
    .normalize('NFKC')
    .replace(/[^\p{L}\p{N}._-]+/gu, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80) || 'wallpaper'
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
      await new Promise((resolveDelay) => setTimeout(resolveDelay, delay))
    }
  }
  throw lastError
}

async function findExistingAsset(filePath) {
  const filename = basename(filePath)
  const size = statSync(filePath).size
  return client.fetch(
    `*[_type == "sanity.fileAsset" && originalFilename == $filename && size == $size][0]._id`,
    {filename, size},
  )
}

const documents = await client.fetch(`
  *[_type == "wallpaper" && kind == "video"] | order(sortOrder asc) {
    _id,
    title,
    duration,
    "originalFilename": video.asset->originalFilename,
    "previewAssetId": previewVideo.asset._ref
  }
`)

let completed = 0
let reused = 0
const failures = []

for (let index = 0; index < documents.length; index += 1) {
  const document = documents[index]
  console.log(`[${index + 1}/${documents.length}] ${document.title}`)
  try {
    if (document.previewAssetId && !force) {
      reused += 1
      console.log('  已有轻量预览，跳过')
      continue
    }
    const sourcePath = resolve(localMediaRoot, basename(document.originalFilename || ''))
    if (!document.originalFilename || !existsSync(sourcePath)) {
      throw new Error(`找不到原视频：${document.originalFilename || '未记录文件名'}`)
    }

    const outputName = `preview-${safeBaseName(document.originalFilename)}-${document._id.slice(-8)}.m4v`
    const outputPath = resolve(outputRoot, outputName)
    if (!existsSync(outputPath) || force) {
      const duration = Math.max(1, Math.min(8, Number(document.duration) || 8))
      await execFileAsync('/usr/bin/avconvert', [
        '--source', sourcePath,
        '--preset', 'Preset960x540',
        '--output', outputPath,
        '--duration', String(duration),
        '--replace',
        '--disableMetadataFilter',
      ], {maxBuffer: 2 * 1024 * 1024})
    }

    let assetId = await findExistingAsset(outputPath)
    if (!assetId) {
      const asset = await withRetries('上传轻量预览', () => client.assets.upload(
        'file',
        createReadStream(outputPath),
        {filename: outputName, contentType: 'video/x-m4v'},
      ))
      assetId = asset._id
    }
    await withRetries('关联壁纸记录', () => client
      .patch(document._id)
      .set({previewVideo: {_type: 'file', asset: {_type: 'reference', _ref: assetId}}})
      .commit())
    completed += 1
    console.log(`  完成：${(statSync(outputPath).size / 1024 / 1024).toFixed(2)} MB`)
  } catch (error) {
    failures.push({id: document._id, title: document.title, error: error.message ?? String(error)})
    console.error(`  失败：${error.message ?? error}`)
  }
}

const summary = await client.fetch(`{
  "videos": count(*[_type == "wallpaper" && kind == "video"]),
  "withPreview": count(*[_type == "wallpaper" && kind == "video" && defined(previewVideo.asset)]),
  "previewBytes": math::sum(*[_type == "wallpaper" && kind == "video" && defined(previewVideo.asset)].previewVideo.asset->size)
}`)
console.log(JSON.stringify({completed, reused, failed: failures.length, ...summary}, null, 2))
if (failures.length) {
  console.error(JSON.stringify(failures, null, 2))
  process.exitCode = 1
}
