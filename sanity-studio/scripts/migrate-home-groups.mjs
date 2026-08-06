import {getCliClient} from 'sanity/cli'

const client = getCliClient({apiVersion: '2026-08-06'})
const documents = await client.fetch(`*[_type == "wallpaper"]{_id, featured, curated, popular}`)

let transaction = client.transaction()
for (const document of documents) {
  transaction = transaction.patch(document._id, (patch) => patch.setIfMissing({
    curated: document.featured === true,
    popular: document.featured === true,
  }))
}

if (documents.length) await transaction.commit()

const result = await client.fetch(`{
  "documents": count(*[_type == "wallpaper"]),
  "recommended": count(*[_type == "wallpaper" && featured == true]),
  "curated": count(*[_type == "wallpaper" && curated == true]),
  "popular": count(*[_type == "wallpaper" && popular == true])
}`)

console.log(JSON.stringify(result, null, 2))
