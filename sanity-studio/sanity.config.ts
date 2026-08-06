import {defineConfig} from 'sanity'
import {structureTool} from 'sanity/structure'
import {visionTool} from '@sanity/vision'
import {schemaTypes} from './schemas'
import {wallpaperTableTool} from './src/wallpaperTableTool'
import {wallpaperStructure} from './src/wallpaperStructure'

export default defineConfig({
  name: 'foldwalls',
  title: 'Foldwalls · 浮岛桌面壁纸后台',
  projectId: '3huccpow',
  dataset: 'production',
  plugins: [
    wallpaperTableTool(),
    structureTool({structure: wallpaperStructure}),
    visionTool({defaultApiVersion: '2026-08-06'}),
  ],
  schema: {
    types: schemaTypes,
  },
})
