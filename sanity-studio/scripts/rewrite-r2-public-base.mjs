import {getCliClient} from 'sanity/cli'

const rawBaseURL = process.env.R2_PUBLIC_BASE_URL
if (!rawBaseURL) throw new Error('Missing R2_PUBLIC_BASE_URL')

const publicBaseURL = rawBaseURL.replace(/\/+$/, '')
const parsedBaseURL = new URL(publicBaseURL)
if (parsedBaseURL.protocol !== 'https:') {
  throw new Error('R2_PUBLIC_BASE_URL must use HTTPS')
}

const client = getCliClient({apiVersion: '2026-08-06'})
const documents = await client.fetch(`*[
  _type == "wallpaper" &&
  r2MigrationStatus == "verified" &&
  defined(r2MediaKey) &&
  defined(r2ThumbnailKey)
]{
  _id,
  r2MediaKey,
  r2ThumbnailKey,
  r2PreviewVideoKey,
  r2DeliveryEnabled
}`)

function publicURL(key) {
  return `${publicBaseURL}/${key.split('/').map(encodeURIComponent).join('/')}`
}

let transaction = client.transaction()
for (const document of documents) {
  const patch = {
    r2MediaUrl: publicURL(document.r2MediaKey),
    r2ThumbnailUrl: publicURL(document.r2ThumbnailKey),
    ...(document.r2PreviewVideoKey
      ? {r2PreviewVideoUrl: publicURL(document.r2PreviewVideoKey)}
      : {}),
  }
  transaction = transaction.patch(document._id, (builder) => builder.set(patch))
}
if (documents.length) await transaction.commit()

const result = await client.fetch(`{
  "wallpapers": count(*[_type == "wallpaper"]),
  "verified": count(*[_type == "wallpaper" && r2MigrationStatus == "verified"]),
  "enabled": count(*[_type == "wallpaper" && r2DeliveryEnabled == true]),
  "matchingMediaBase": count(*[_type == "wallpaper" && r2MediaUrl match $base]),
  "matchingThumbnailBase": count(*[_type == "wallpaper" && r2ThumbnailUrl match $base]),
  "matchingPreviewBase": count(*[_type == "wallpaper" && defined(r2PreviewVideoKey) && r2PreviewVideoUrl match $base])
}`, {base: `${publicBaseURL}*`})

console.log(JSON.stringify({publicBaseURL, changed: documents.length, ...result}, null, 2))
