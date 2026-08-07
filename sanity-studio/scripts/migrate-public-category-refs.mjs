import {getCliClient} from 'sanity/cli'
import {CATEGORY_DEFINITIONS, categoryDocumentId, resolveCategory} from '../taxonomy.ts'

const client = getCliClient({apiVersion: '2026-08-06'})
const categoryById = new Map(CATEGORY_DEFINITIONS.map((category) => [category.id, category]))

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

const wallpapers = await client.fetch(`*[_type == "wallpaper"]{
  _id,
  categories,
  categoryRefs[]{_key, _ref}
}`)

let migrated = 0
for (const wallpaper of wallpapers) {
  const referencedIds = (wallpaper.categoryRefs ?? []).map((reference) =>
    reference._key || reference._ref?.replace(/^category[.-]/, ''),
  )
  const fallbackIds = (wallpaper.categories ?? []).map((label) => resolveCategory(label)?.id)
  const categoryIds = [...new Set([...referencedIds, ...fallbackIds])]
    .filter((id) => id && categoryById.has(id))
    .sort((left, right) => categoryById.get(left).order - categoryById.get(right).order)

  const categoryRefs = categoryIds.map((id) => ({
    _type: 'reference',
    _key: id,
    _ref: categoryDocumentId(id),
  }))
  const alreadyPublic = (wallpaper.categoryRefs ?? []).length === categoryRefs.length
    && categoryRefs.every((reference, index) =>
      wallpaper.categoryRefs[index]?._key === reference._key
      && wallpaper.categoryRefs[index]?._ref === reference._ref,
    )

  if (!alreadyPublic) {
    await client.patch(wallpaper._id).set({categoryRefs}).commit({autoGenerateArrayKeys: true})
    migrated += 1
  }
}

const verification = await client.fetch(`{
  "publicCategories": count(*[_type == "category" && _id in path("*")]),
  "wallpapers": count(*[_type == "wallpaper"]),
  "brokenReferences": count(*[_type == "wallpaper" && count(categoryRefs[!defined(@->)]) > 0])
}`)

if (verification.publicCategories !== CATEGORY_DEFINITIONS.length || verification.brokenReferences !== 0) {
  throw new Error(`分类引用迁移验证失败：${JSON.stringify(verification)}`)
}

console.log(JSON.stringify({...verification, migrated}, null, 2))
