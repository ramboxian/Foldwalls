import {getCliClient} from 'sanity/cli'

const enable = process.argv.includes('--enable')
const disable = process.argv.includes('--disable')
if (enable === disable) throw new Error('Pass exactly one of --enable or --disable')
if (enable && process.env.R2_CUTOVER_CONFIRM !== 'FOLDWALLS_R2_VERIFIED') {
  throw new Error('Refusing cutover. Set R2_CUTOVER_CONFIRM=FOLDWALLS_R2_VERIFIED after the new release is published and R2 smoke tests pass.')
}

const client = getCliClient({apiVersion: '2026-08-06'})
const filter = enable
  ? '_type == "wallpaper" && r2MigrationStatus == "verified" && defined(r2MediaUrl) && defined(r2ThumbnailUrl)'
  : '_type == "wallpaper" && r2DeliveryEnabled == true'
const documents = await client.fetch(`*[${filter}]{_id}`)
let transaction = client.transaction()
for (const document of documents) {
  transaction = transaction.patch(document._id, (patch) => patch.set({r2DeliveryEnabled: enable}))
}
if (documents.length) await transaction.commit()

const result = await client.fetch(`{
  "wallpapers": count(*[_type == "wallpaper"]),
  "r2Verified": count(*[_type == "wallpaper" && r2MigrationStatus == "verified"]),
  "r2Enabled": count(*[_type == "wallpaper" && r2DeliveryEnabled == true])
}`)
console.log(JSON.stringify({action: enable ? 'enable' : 'disable', changed: documents.length, ...result}, null, 2))
