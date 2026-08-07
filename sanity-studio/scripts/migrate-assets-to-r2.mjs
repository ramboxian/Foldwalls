import {getCliClient} from 'sanity/cli'
import {HeadObjectCommand, PutObjectCommand, S3Client} from '@aws-sdk/client-s3'
import {execFileSync} from 'node:child_process'

const requiredEnvironment = [
  'R2_ACCOUNT_ID',
  'R2_BUCKET',
  'R2_PUBLIC_BASE_URL',
]
const missing = requiredEnvironment.filter((name) => !process.env[name])
if (missing.length) throw new Error(`Missing R2 environment variables: ${missing.join(', ')}`)

function loadCredentials() {
  if (process.env.R2_ACCESS_KEY_ID && process.env.R2_SECRET_ACCESS_KEY) {
    return {
      accessKeyId: process.env.R2_ACCESS_KEY_ID,
      secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
    }
  }

  if (process.platform === 'darwin') {
    try {
      const stored = execFileSync('/usr/bin/security', [
        'find-generic-password',
        '-w',
        '-s',
        'com.foldwalls.r2',
        '-a',
        'foldwalls-uploader',
      ], {encoding: 'utf8'}).trim()
      const credentials = JSON.parse(stored)
      if (credentials.accessKeyId && credentials.secretAccessKey) return credentials
    } catch {
      // Fall through to the actionable error below.
    }
  }

  throw new Error('Missing R2 credentials. Set R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY, or install the Foldwalls uploader credential in macOS Keychain.')
}

const credentials = loadCredentials()

const dryRun = process.argv.includes('--dry-run')
const documentArgument = process.argv.find((value) => value.startsWith('--document-id='))
const documentID = documentArgument?.slice('--document-id='.length)
const client = getCliClient({apiVersion: '2026-08-06'})
const r2 = new S3Client({
  region: 'auto',
  endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials,
})
const bucket = process.env.R2_BUCKET
const publicBaseURL = process.env.R2_PUBLIC_BASE_URL.replace(/\/+$/, '')

const documents = await client.fetch(`*[_type == "wallpaper"${documentID ? ' && _id == $documentID' : ''}] | order(_createdAt asc) {
  _id,
  title,
  kind,
  "media": select(kind == "video" => video.asset->{_id, url, size, mimeType, originalFilename}, image.asset->{_id, url, size, mimeType, originalFilename}),
  "thumbnail": thumbnail.asset->{_id, url, size, mimeType, originalFilename},
  "preview": previewVideo.asset->{_id, url, size, mimeType, originalFilename},
  r2MigrationStatus,
  r2DeliveryEnabled
}`, documentID ? {documentID} : {})

function safeFileName(value) {
  return (value || 'asset').normalize('NFKC').replace(/[\\/?%*:|"<>\u0000-\u001F]/g, '-').replace(/\s+/g, '-').slice(-160)
}

function objectKey(asset) {
  const assetID = asset._id.replace(/^image-|^file-/, '').replace(/-[^-]+$/, '')
  return `assets/${assetID}/${safeFileName(asset.originalFilename)}`
}

function publicURL(key) {
  return `${publicBaseURL}/${key.split('/').map(encodeURIComponent).join('/')}`
}

async function objectMatches(asset, key) {
  try {
    const response = await r2.send(new HeadObjectCommand({Bucket: bucket, Key: key}))
    return Number(response.ContentLength) === Number(asset.size)
  } catch (error) {
    if (error?.$metadata?.httpStatusCode === 404 || error?.name === 'NotFound') return false
    throw error
  }
}

async function uploadAsset(asset) {
  if (!asset?.url || !asset?.size) return null
  const key = objectKey(asset)
  if (await objectMatches(asset, key)) return {key, url: publicURL(key), size: asset.size}
  if (dryRun) return {key, url: publicURL(key), size: asset.size}

  let lastError
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await fetch(asset.url)
      if (!response.ok || !response.body) throw new Error(`Sanity download failed: ${response.status} ${asset.url}`)
      const body = Buffer.from(await response.arrayBuffer())
      await r2.send(new PutObjectCommand({
        Bucket: bucket,
        Key: key,
        Body: body,
        ContentLength: body.length,
        ContentType: asset.mimeType || response.headers.get('content-type') || 'application/octet-stream',
        CacheControl: 'public, max-age=31536000, immutable',
      }))
      if (!(await objectMatches({...asset, size: body.length}, key))) throw new Error(`R2 size verification failed for ${key}`)
      return {key, url: publicURL(key), size: body.length}
    } catch (error) {
      lastError = error
      if (attempt < 3) await new Promise((resolve) => setTimeout(resolve, attempt * 1500))
    }
  }
  throw lastError
}

let migrated = 0
let failed = 0
for (const [index, document] of documents.entries()) {
  process.stdout.write(`[${index + 1}/${documents.length}] ${document.title || document._id}\n`)
  try {
    const [media, thumbnail, preview] = await Promise.all([
      uploadAsset(document.media),
      uploadAsset(document.thumbnail),
      uploadAsset(document.preview),
    ])
    if (!media || !thumbnail) throw new Error('Wallpaper is missing its original media or thumbnail')
    const patch = {
      r2MigrationStatus: 'verified',
      r2MediaUrl: media.url,
      r2MediaKey: media.key,
      r2MediaSize: media.size,
      r2ThumbnailUrl: thumbnail.url,
      r2ThumbnailKey: thumbnail.key,
      r2ThumbnailSize: thumbnail.size,
      ...(preview ? {
        r2PreviewVideoUrl: preview.url,
        r2PreviewVideoKey: preview.key,
        r2PreviewVideoSize: preview.size,
      } : {}),
    }
    if (!dryRun) {
      await client.patch(document._id).set(patch).setIfMissing({r2DeliveryEnabled: false}).commit()
    }
    migrated += 1
  } catch (error) {
    failed += 1
    if (!dryRun) await client.patch(document._id).set({r2MigrationStatus: 'failed'}).commit()
    console.error(`  FAILED: ${error instanceof Error ? error.message : String(error)}`)
  }
}

console.log(JSON.stringify({dryRun, documents: documents.length, migrated, failed, deliveryEnabled: false}, null, 2))
if (failed) process.exitCode = 1
