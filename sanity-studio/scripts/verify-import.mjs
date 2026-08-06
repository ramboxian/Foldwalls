import {getCliClient} from 'sanity/cli'

const client = getCliClient({apiVersion: '2026-08-06'})

const result = await client.fetch(`{
  "documents": count(*[_type == "wallpaper"]),
  "videos": count(*[_type == "wallpaper" && kind == "video"]),
  "images": count(*[_type == "wallpaper" && kind == "image"]),
  "featured": count(*[_type == "wallpaper" && featured == true]),
  "published": count(*[_type == "wallpaper" && status == "published"]),
  "completeMedia": count(*[_type == "wallpaper" && defined(thumbnail.asset) && (defined(video.asset) || defined(image.asset))]),
  "previewVideos": count(*[_type == "wallpaper" && kind == "video" && defined(previewVideo.asset)]),
  "completeMetadata": count(*[_type == "wallpaper" && defined(title) && defined(titleEn) && defined(subtitle) && defined(subtitleEn) && count(categories) > 0 && count(tags) > 0]),
  "fileAssets": count(*[_type == "sanity.fileAsset"]),
  "imageAssets": count(*[_type == "sanity.imageAsset"]),
  "assetBytes": math::sum(*[_type in ["sanity.fileAsset", "sanity.imageAsset"]].size),
  "topFeatured": *[_type == "wallpaper" && featured == true] | order(sortOrder asc)[0...15]{title, sortOrder, "thumbnailUrl": thumbnail.asset->url},
  "sample": *[_type == "wallpaper"] | order(sortOrder asc)[0]{title, "mediaUrl": select(kind == "video" => video.asset->url, image.asset->url), "thumbnailUrl": thumbnail.asset->url}
}`)

const titles = await client.fetch(`*[_type == "wallpaper"].title`)
const duplicates = titles.filter((title, index) => titles.indexOf(title) !== index)
result.duplicateTitles = [...new Set(duplicates)]

console.log(JSON.stringify(result, null, 2))

const expected = {
  documents: 58,
  videos: 57,
  images: 1,
  featured: 14,
  published: 58,
  completeMedia: 58,
  previewVideos: 57,
  completeMetadata: 58,
  fileAssets: 114,
  imageAssets: 59,
}

for (const [key, expectedValue] of Object.entries(expected)) {
  if (result[key] !== expectedValue) throw new Error(`${key}: expected ${expectedValue}, got ${result[key]}`)
}
if (result.duplicateTitles.length) throw new Error(`Duplicate titles: ${result.duplicateTitles.join(', ')}`)
