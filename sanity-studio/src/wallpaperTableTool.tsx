import {useCallback, useEffect, useMemo, useState} from 'react'
import {
  Badge,
  Box,
  Button,
  Card,
  Checkbox,
  Dialog,
  Flex,
  Heading,
  Label,
  Select,
  Spinner,
  Stack,
  Text,
  TextArea,
  TextInput,
  useToast,
} from '@sanity/ui'
import {definePlugin, useClient} from 'sanity'
import * as XLSX from 'xlsx'

const API_VERSION = '2026-08-06'

type WallpaperKind = 'image' | 'video'
type WallpaperStatus = 'published' | 'hidden'
type ImportRow = Record<string, unknown>

interface WallpaperRow {
  _id: string
  _updatedAt: string
  title?: string
  titleEn?: string
  subtitle?: string
  subtitleEn?: string
  kind?: WallpaperKind
  categories?: string[]
  tags?: string[]
  width?: number
  height?: number
  duration?: number
  author?: string
  licenseName?: string
  sourceUrl?: string
  featured?: boolean
  curated?: boolean
  popular?: boolean
  status?: WallpaperStatus
  sortOrder?: number
  paletteStart?: string
  paletteMiddle?: string
  paletteEnd?: string
  thumbnailUrl?: string
  thumbnailAssetId?: string
  thumbnailFileName?: string
  mediaUrl?: string
  mediaAssetId?: string
  mediaFileName?: string
  previewVideoAssetId?: string
  fileSize?: number
}

interface WallpaperForm {
  title: string
  titleEn: string
  subtitle: string
  subtitleEn: string
  kind: WallpaperKind
  categoriesText: string
  tagsText: string
  width: string
  height: string
  duration: string
  author: string
  licenseName: string
  sourceUrl: string
  featured: boolean
  curated: boolean
  popular: boolean
  status: WallpaperStatus
  sortOrder: string
  paletteStart: string
  paletteMiddle: string
  paletteEnd: string
}

const createEmptyForm = (): WallpaperForm => ({
  title: '',
  titleEn: '',
  subtitle: '',
  subtitleEn: '',
  kind: 'image',
  categoriesText: '',
  tagsText: '',
  width: '',
  height: '',
  duration: '',
  author: '',
  licenseName: '',
  sourceUrl: '',
  featured: false,
  curated: false,
  popular: false,
  status: 'published',
  sortOrder: String(Date.now()),
  paletteStart: '',
  paletteMiddle: '',
  paletteEnd: '',
})

const exportHeaders = [
  '名称', '原文件名', '封面文件名', '类型', '分类', '标签', '首页推荐', '精选', '热门', '状态', '排序',
  '宽度', '高度', '时长秒', '作者', '授权说明', '来源链接', '英文名称', '简介', '英文简介',
  '起点颜色', '中点颜色', '终点颜色', '导入ID',
]

const query = `*[_type == "wallpaper"] | order(sortOrder desc, _createdAt desc) {
  _id,
  _updatedAt,
  title,
  titleEn,
  subtitle,
  subtitleEn,
  kind,
  categories,
  tags,
  width,
  height,
  duration,
  author,
  licenseName,
  sourceUrl,
  featured,
  curated,
  popular,
  status,
  sortOrder,
  paletteStart,
  paletteMiddle,
  paletteEnd,
  "thumbnailUrl": thumbnail.asset->url,
  "thumbnailAssetId": thumbnail.asset->_id,
  "thumbnailFileName": thumbnail.asset->originalFilename,
  "mediaUrl": select(kind == "video" => video.asset->url, image.asset->url),
  "mediaAssetId": select(kind == "video" => video.asset->_id, image.asset->_id),
  "mediaFileName": select(kind == "video" => video.asset->originalFilename, image.asset->originalFilename),
  "previewVideoAssetId": previewVideo.asset->_id,
  "fileSize": select(kind == "video" => video.asset->size, image.asset->size)
}`

const directoryPickerProps = {
  webkitdirectory: '',
  directory: '',
  multiple: true,
} as React.InputHTMLAttributes<HTMLInputElement>

function splitValues(value: string): string[] {
  return [...new Set(value.split(/[,，\n]/).map((item) => item.trim()).filter(Boolean))]
}

function formatBytes(value?: number): string {
  if (!value) return '—'
  const units = ['B', 'KB', 'MB', 'GB']
  let amount = value
  let unit = 0
  while (amount >= 1024 && unit < units.length - 1) {
    amount /= 1024
    unit += 1
  }
  return `${amount.toFixed(unit >= 2 ? 1 : 0)} ${units[unit]}`
}

function basename(value: string): string {
  return value.replace(/\\/g, '/').split('/').pop() ?? value
}

function stem(value: string): string {
  return basename(value).replace(/\.[^.]+$/, '').replace(/[-_]+/g, ' ').trim()
}

function normalizeHeader(value: string): string {
  return value.trim().toLocaleLowerCase().replace(/[\s_\-()（）]/g, '')
}

function readCell(row: ImportRow, ...names: string[]): unknown {
  const wanted = new Set(names.map(normalizeHeader))
  const entry = Object.entries(row).find(([key]) => wanted.has(normalizeHeader(key)))
  return entry?.[1]
}

function textCell(row: ImportRow, ...names: string[]): string {
  const value = readCell(row, ...names)
  return value == null ? '' : String(value).trim()
}

function optionalNumber(value: unknown): number | undefined {
  if (value == null || value === '') return undefined
  const number = Number(value)
  return Number.isFinite(number) && number >= 0 ? number : undefined
}

function booleanValue(value: unknown): boolean {
  if (typeof value === 'boolean') return value
  return ['1', 'true', 'yes', 'y', '是', '推荐'].includes(String(value ?? '').trim().toLocaleLowerCase())
}

function inferKind(value: unknown, mediaName: string): WallpaperKind {
  const text = String(value ?? '').trim().toLocaleLowerCase()
  if (['video', '动态', '视频', 'motion'].includes(text)) return 'video'
  if (['image', '图片', '静态', 'photo'].includes(text)) return 'image'
  return /\.(mp4|mov|m4v|webm|avi|mkv)$/i.test(mediaName) ? 'video' : 'image'
}

function normalizedColor(value: string): string | undefined {
  if (!value) return undefined
  const color = value.startsWith('#') ? value : `#${value}`
  return /^#[0-9a-f]{6}$/i.test(color) ? color : undefined
}

function validSourceUrl(value: string): string | undefined {
  if (!value) return undefined
  try {
    const url = new URL(value)
    return ['http:', 'https:'].includes(url.protocol) ? value : undefined
  } catch {
    return undefined
  }
}

function fileLookup(files: File[]): Map<string, File> {
  const lookup = new Map<string, File>()
  files.forEach((file) => {
    lookup.set(file.name.toLocaleLowerCase(), file)
    if (file.webkitRelativePath) lookup.set(file.webkitRelativePath.toLocaleLowerCase(), file)
  })
  return lookup
}

function findResource(lookup: Map<string, File>, requestedName: string): File | undefined {
  if (!requestedName) return undefined
  const normalized = requestedName.replace(/\\/g, '/').toLocaleLowerCase()
  return lookup.get(normalized) ?? lookup.get(basename(normalized))
}

async function stableDocumentId(row: ImportRow, index: number, title: string, mediaName: string, thumbnailName: string) {
  const explicit = textCell(row, '导入ID', 'ID', '_id')
  if (explicit && /^[a-zA-Z0-9_.-]+$/.test(explicit) && !explicit.startsWith('drafts.')) return explicit
  const source = explicit || mediaName || thumbnailName || title || JSON.stringify(row) || String(index)
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(source))
  const hash = [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
  return `wallpaper-import-${hash.slice(0, 32)}`
}

function formFromRow(row: WallpaperRow): WallpaperForm {
  return {
    title: row.title ?? '',
    titleEn: row.titleEn ?? '',
    subtitle: row.subtitle ?? '',
    subtitleEn: row.subtitleEn ?? '',
    kind: row.kind ?? 'image',
    categoriesText: (row.categories ?? []).join('，'),
    tagsText: (row.tags ?? []).join('，'),
    width: row.width?.toString() ?? '',
    height: row.height?.toString() ?? '',
    duration: row.duration?.toString() ?? '',
    author: row.author ?? '',
    licenseName: row.licenseName ?? '',
    sourceUrl: row.sourceUrl ?? '',
    featured: row.featured ?? false,
    curated: row.curated ?? false,
    popular: row.popular ?? false,
    status: row.status ?? 'published',
    sortOrder: row.sortOrder?.toString() ?? String(Date.now()),
    paletteStart: row.paletteStart ?? '',
    paletteMiddle: row.paletteMiddle ?? '',
    paletteEnd: row.paletteEnd ?? '',
  }
}

function WallpaperTable() {
  const client = useClient({apiVersion: API_VERSION})
  const toast = useToast()
  const [rows, setRows] = useState<WallpaperRow[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [search, setSearch] = useState('')
  const [kindFilter, setKindFilter] = useState<'all' | WallpaperKind>('all')
  const [statusFilter, setStatusFilter] = useState<'all' | WallpaperStatus>('all')
  const [editorOpen, setEditorOpen] = useState(false)
  const [editing, setEditing] = useState<WallpaperRow | null>(null)
  const [form, setForm] = useState<WallpaperForm>(() => createEmptyForm())
  const [thumbnailFile, setThumbnailFile] = useState<File | null>(null)
  const [mediaFile, setMediaFile] = useState<File | null>(null)
  const [showAdvanced, setShowAdvanced] = useState(false)
  const [importOpen, setImportOpen] = useState(false)
  const [importRows, setImportRows] = useState<ImportRow[]>([])
  const [spreadsheetName, setSpreadsheetName] = useState('')
  const [resourceFiles, setResourceFiles] = useState<File[]>([])
  const [importError, setImportError] = useState('')
  const [importing, setImporting] = useState(false)
  const [importProgress, setImportProgress] = useState('')

  const loadRows = useCallback(async () => {
    try {
      const result = await client.fetch<WallpaperRow[]>(query)
      setRows(result)
    } catch (error) {
      toast.push({status: 'error', title: '壁纸列表加载失败', description: String(error)})
    } finally {
      setLoading(false)
    }
  }, [client, toast])

  useEffect(() => {
    void loadRows()
  }, [loadRows])

  const filteredRows = useMemo(() => {
    const keyword = search.trim().toLocaleLowerCase()
    return rows.filter((row) => {
      const matchesKeyword =
        !keyword ||
        (row.title ?? '').toLocaleLowerCase().includes(keyword) ||
        row.titleEn?.toLocaleLowerCase().includes(keyword) ||
        row.categories?.some((item) => item.toLocaleLowerCase().includes(keyword))
      const matchesKind = kindFilter === 'all' || (row.kind ?? 'image') === kindFilter
      const matchesStatus = statusFilter === 'all' || (row.status ?? 'published') === statusFilter
      return matchesKeyword && matchesKind && matchesStatus
    })
  }, [rows, search, kindFilter, statusFilter])

  const resources = useMemo(() => fileLookup(resourceFiles), [resourceFiles])
  const matchedMediaCount = useMemo(
    () => importRows.filter((row) => findResource(resources, textCell(row, '原文件名', '文件名', 'mediaFile', 'media'))).length,
    [importRows, resources],
  )
  const matchedThumbnailCount = useMemo(
    () => importRows.filter((row) => findResource(resources, textCell(row, '封面文件名', 'thumbnailFile', 'thumbnail'))).length,
    [importRows, resources],
  )

  const openNew = () => {
    setEditing(null)
    setForm(createEmptyForm())
    setThumbnailFile(null)
    setMediaFile(null)
    setShowAdvanced(false)
    setEditorOpen(true)
  }

  const openEdit = (row: WallpaperRow) => {
    setEditing(row)
    setForm(formFromRow(row))
    setThumbnailFile(null)
    setMediaFile(null)
    setShowAdvanced(false)
    setEditorOpen(true)
  }

  const resetImport = () => {
    setImportRows([])
    setSpreadsheetName('')
    setResourceFiles([])
    setImportError('')
    setImportProgress('')
  }

  const setField = <K extends keyof WallpaperForm>(key: K, value: WallpaperForm[K]) => {
    setForm((current) => ({...current, [key]: value}))
  }

  const parseSpreadsheet = async (file: File) => {
    setImportError('')
    setSpreadsheetName(file.name)
    try {
      const workbook = XLSX.read(await file.arrayBuffer(), {type: 'array'})
      const worksheet = workbook.Sheets['壁纸导入'] ?? workbook.Sheets[workbook.SheetNames[0]]
      if (!worksheet) throw new Error('工作簿中没有可读取的工作表')
      const parsed = XLSX.utils.sheet_to_json<ImportRow>(worksheet, {defval: ''}).filter((row) =>
        Object.values(row).some((value) => String(value ?? '').trim() !== ''),
      )
      if (!parsed.length) throw new Error('表格中没有数据行')
      setImportRows(parsed)
    } catch (error) {
      setImportRows([])
      setImportError(error instanceof Error ? error.message : String(error))
    }
  }

  const addResourceFiles = (files: FileList | null) => {
    if (!files) return
    setResourceFiles((current) => {
      const next = new Map(current.map((file) => [file.webkitRelativePath || file.name, file]))
      Array.from(files).forEach((file) => next.set(file.webkitRelativePath || file.name, file))
      return [...next.values()]
    })
  }

  const saveWallpaper = async () => {
    setSaving(true)
    try {
      let thumbnailAssetId = editing?.thumbnailAssetId
      let mediaAssetId = editing?.kind === form.kind ? editing.mediaAssetId : undefined

      if (thumbnailFile) {
        const uploaded = await client.assets.upload('image', thumbnailFile, {filename: thumbnailFile.name})
        thumbnailAssetId = uploaded._id
      }
      if (mediaFile) {
        const uploaded = await client.assets.upload(form.kind === 'image' ? 'image' : 'file', mediaFile, {filename: mediaFile.name})
        mediaAssetId = uploaded._id
      }

      const generatedTitle = stem(mediaFile?.name || thumbnailFile?.name || '') || '未命名壁纸'
      const payload: {_type: string; [key: string]: unknown} = {
        _type: 'wallpaper',
        title: form.title.trim() || generatedTitle,
        kind: form.kind,
        featured: form.featured,
        curated: form.curated,
        popular: form.popular,
        status: form.status,
        sortOrder: optionalNumber(form.sortOrder) ?? Date.now(),
      }
      const optionalText: Array<[string, string]> = [
        ['titleEn', form.titleEn], ['subtitle', form.subtitle], ['subtitleEn', form.subtitleEn],
        ['author', form.author], ['licenseName', form.licenseName],
      ]
      optionalText.forEach(([key, value]) => { if (value.trim()) payload[key] = value.trim() })
      const categories = splitValues(form.categoriesText)
      const tags = splitValues(form.tagsText)
      if (categories.length) payload.categories = categories
      if (tags.length) payload.tags = tags
      const width = optionalNumber(form.width)
      const height = optionalNumber(form.height)
      const duration = optionalNumber(form.duration)
      if (width) payload.width = Math.round(width)
      if (height) payload.height = Math.round(height)
      if (duration) payload.duration = duration
      const sourceUrl = validSourceUrl(form.sourceUrl.trim())
      if (sourceUrl) payload.sourceUrl = sourceUrl
      const paletteStart = normalizedColor(form.paletteStart.trim())
      const paletteMiddle = normalizedColor(form.paletteMiddle.trim())
      const paletteEnd = normalizedColor(form.paletteEnd.trim())
      if (paletteStart) payload.paletteStart = paletteStart
      if (paletteMiddle) payload.paletteMiddle = paletteMiddle
      if (paletteEnd) payload.paletteEnd = paletteEnd
      if (thumbnailAssetId) payload.thumbnail = {_type: 'image', asset: {_type: 'reference', _ref: thumbnailAssetId}}
      if (mediaAssetId) {
        payload[form.kind === 'video' ? 'video' : 'image'] = {
          _type: form.kind === 'video' ? 'file' : 'image',
          asset: {_type: 'reference', _ref: mediaAssetId},
        }
        if (form.kind === 'image' && !thumbnailAssetId) payload.thumbnail = payload.image
      }

      if (editing) {
        const clearable = ['titleEn', 'subtitle', 'subtitleEn', 'categories', 'tags', 'width', 'height', 'duration', 'author', 'licenseName', 'sourceUrl', 'paletteStart', 'paletteMiddle', 'paletteEnd']
        const unset = clearable.filter((key) => !(key in payload))
        unset.push(form.kind === 'video' ? 'image' : 'video')
        await client.patch(editing._id).set(payload).unset(unset).commit()
      } else {
        await client.create(payload)
      }

      toast.push({status: 'success', title: editing ? '壁纸已更新' : '壁纸已创建'})
      setEditorOpen(false)
      await loadRows()
    } catch (error) {
      toast.push({status: 'error', title: '保存失败', description: error instanceof Error ? error.message : String(error)})
    } finally {
      setSaving(false)
    }
  }

  const importBatch = async () => {
    if (!importRows.length) {
      toast.push({status: 'warning', title: '请先选择有数据的 Excel 或 CSV 表格'})
      return
    }
    setImporting(true)
    const failures: string[] = []
    let succeeded = 0
    try {
      for (let index = 0; index < importRows.length; index += 1) {
        const row = importRows[index]
        setImportProgress(`正在处理 ${index + 1} / ${importRows.length}`)
        try {
          const mediaName = textCell(row, '原文件名', '文件名', 'mediaFile', 'media')
          const thumbnailName = textCell(row, '封面文件名', 'thumbnailFile', 'thumbnail')
          const media = findResource(resources, mediaName)
          const thumbnail = findResource(resources, thumbnailName)
          const kind = inferKind(readCell(row, '类型', 'kind', 'type'), mediaName || media?.name || '')
          const title = textCell(row, '名称', '中文名称', 'title') || stem(mediaName || media?.name || thumbnailName) || `未命名壁纸 ${index + 1}`
          const documentId = await stableDocumentId(row, index, title, mediaName, thumbnailName)
          const existing = await client.getDocument<Record<string, any>>(documentId)
          let mediaAssetId = kind === 'video' ? existing?.video?.asset?._ref : existing?.image?.asset?._ref
          let thumbnailAssetId = existing?.thumbnail?.asset?._ref

          if (!mediaAssetId && media) {
            const uploaded = await client.assets.upload(kind === 'image' ? 'image' : 'file', media, {filename: media.name})
            mediaAssetId = uploaded._id
          }
          if (!thumbnailAssetId && thumbnail) {
            const uploaded = await client.assets.upload('image', thumbnail, {filename: thumbnail.name})
            thumbnailAssetId = uploaded._id
          }
          if (kind === 'image' && !thumbnailAssetId && mediaAssetId) thumbnailAssetId = mediaAssetId

          const statusText = textCell(row, '状态', 'status').toLocaleLowerCase()
          const payload: {_id: string; _type: string; [key: string]: unknown} = {
            _id: documentId,
            _type: 'wallpaper',
            title,
            kind,
            status: ['hidden', '下架', '已下架'].includes(statusText) ? 'hidden' : 'published',
            featured: booleanValue(readCell(row, '首页推荐', '推荐', 'featured')),
            curated: booleanValue(readCell(row, '精选', '精选分组', 'curated')),
            popular: booleanValue(readCell(row, '热门', '热门分组', 'popular')),
            sortOrder: Math.round(optionalNumber(readCell(row, '排序', 'sortOrder')) ?? existing?.sortOrder ?? (Date.now() + index)),
          }
          const optionalText: Array<[string, string]> = [
            ['titleEn', textCell(row, '英文名称', 'titleEn')],
            ['subtitle', textCell(row, '简介', '中文简介', 'subtitle')],
            ['subtitleEn', textCell(row, '英文简介', 'subtitleEn')],
            ['author', textCell(row, '作者', 'author')],
            ['licenseName', textCell(row, '授权说明', 'licenseName', 'license')],
          ]
          optionalText.forEach(([key, value]) => { if (value) payload[key] = value })
          const categories = splitValues(textCell(row, '分类', 'categories'))
          const tags = splitValues(textCell(row, '标签', 'tags'))
          if (categories.length) payload.categories = categories
          if (tags.length) payload.tags = tags
          const width = optionalNumber(readCell(row, '宽度', 'width'))
          const height = optionalNumber(readCell(row, '高度', 'height'))
          const duration = optionalNumber(readCell(row, '时长秒', '时长', 'duration'))
          if (width) payload.width = Math.round(width)
          if (height) payload.height = Math.round(height)
          if (duration) payload.duration = duration
          const sourceUrl = validSourceUrl(textCell(row, '来源链接', 'sourceUrl'))
          if (sourceUrl) payload.sourceUrl = sourceUrl
          const paletteStart = normalizedColor(textCell(row, '起点颜色', 'paletteStart'))
          const paletteMiddle = normalizedColor(textCell(row, '中点颜色', 'paletteMiddle'))
          const paletteEnd = normalizedColor(textCell(row, '终点颜色', 'paletteEnd'))
          if (paletteStart) payload.paletteStart = paletteStart
          if (paletteMiddle) payload.paletteMiddle = paletteMiddle
          if (paletteEnd) payload.paletteEnd = paletteEnd
          if (thumbnailAssetId) payload.thumbnail = {_type: 'image', asset: {_type: 'reference', _ref: thumbnailAssetId}}
          if (mediaAssetId) {
            payload[kind === 'video' ? 'video' : 'image'] = {
              _type: kind === 'video' ? 'file' : 'image',
              asset: {_type: 'reference', _ref: mediaAssetId},
            }
          }
          if (kind === 'video' && existing?.previewVideo?.asset?._ref) {
            payload.previewVideo = {_type: 'file', asset: {_type: 'reference', _ref: existing.previewVideo.asset._ref}}
          }
          await client.createOrReplace(payload)
          succeeded += 1
        } catch (error) {
          failures.push(`第 ${index + 2} 行：${error instanceof Error ? error.message : String(error)}`)
        }
      }
      await loadRows()
      if (failures.length) {
        setImportError(`成功 ${succeeded} 条，失败 ${failures.length} 条。${failures.slice(0, 3).join('；')}`)
        toast.push({status: 'warning', title: `批量导入完成：成功 ${succeeded}，失败 ${failures.length}`})
      } else {
        toast.push({status: 'success', title: `已成功导入 ${succeeded} 条壁纸`})
        setImportOpen(false)
        resetImport()
      }
    } finally {
      setImporting(false)
      setImportProgress('')
    }
  }

  const exportCurrentRows = () => {
    const data = rows.map((row) => [
      row.title ?? '', row.mediaFileName ?? '', row.thumbnailFileName ?? '', row.kind ?? '',
      (row.categories ?? []).join('，'), (row.tags ?? []).join('，'), row.featured ?? false, row.curated ?? false, row.popular ?? false,
      row.status ?? 'published', row.sortOrder ?? 100, row.width ?? '', row.height ?? '', row.duration ?? '',
      row.author ?? '', row.licenseName ?? '', row.sourceUrl ?? '', row.titleEn ?? '', row.subtitle ?? '', row.subtitleEn ?? '',
      row.paletteStart ?? '', row.paletteMiddle ?? '', row.paletteEnd ?? '', row._id,
    ])
    const worksheet = XLSX.utils.aoa_to_sheet([exportHeaders, ...data])
    const lastColumn = XLSX.utils.encode_col(exportHeaders.length - 1)
    worksheet['!autofilter'] = {ref: `A1:${lastColumn}${Math.max(data.length + 1, 1)}`}
    worksheet['!cols'] = exportHeaders.map((header, index) => ({wch: index < 3 ? 30 : Math.max(header.length + 4, 12)}))
    const workbook = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(workbook, worksheet, '壁纸导入')
    const bytes = XLSX.write(workbook, {bookType: 'xlsx', type: 'array'})
    const url = URL.createObjectURL(new Blob([bytes], {type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}))
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = `Foldwalls-云端壁纸-${new Date().toISOString().slice(0, 10)}.xlsx`
    anchor.click()
    URL.revokeObjectURL(url)
    toast.push({status: 'success', title: `已导出 ${rows.length} 条云端记录`})
  }

  const toggleStatus = async (row: WallpaperRow) => {
    const status: WallpaperStatus = (row.status ?? 'published') === 'published' ? 'hidden' : 'published'
    try {
      await client.patch(row._id).set({status}).commit()
      setRows((current) => current.map((item) => (item._id === row._id ? {...item, status} : item)))
      toast.push({status: 'success', title: status === 'published' ? '已上架' : '已下架'})
    } catch (error) {
      toast.push({status: 'error', title: '状态修改失败', description: String(error)})
    }
  }

  const toggleGroup = async (row: WallpaperRow, field: 'featured' | 'curated' | 'popular', checked: boolean) => {
    try {
      await client.patch(row._id).set({[field]: checked}).commit()
      setRows((current) => current.map((item) => (item._id === row._id ? {...item, [field]: checked} : item)))
    } catch (error) {
      toast.push({status: 'error', title: '分组修改失败', description: String(error)})
    }
  }

  const deleteWallpaper = async (row: WallpaperRow) => {
    if (!window.confirm(`确定永久删除“${row.title || '未命名壁纸'}”吗？数据记录、列表封面和壁纸原文件都会被删除。`)) return
    try {
      await client.delete(row._id)
      const assetIds = [...new Set([row.thumbnailAssetId, row.mediaAssetId, row.previewVideoAssetId].filter((id): id is string => Boolean(id)))]
      await Promise.all(assetIds.map(async (assetId) => {
        try { await client.delete(assetId) } catch { /* Shared assets stay protected by Sanity. */ }
      }))
      setRows((current) => current.filter((item) => item._id !== row._id))
      toast.push({status: 'success', title: '壁纸及其独占文件已删除'})
    } catch (error) {
      toast.push({status: 'error', title: '删除失败', description: String(error)})
    }
  }

  return (
    <Card height="fill" tone="transparent">
      <Card padding={4} borderBottom>
        <Flex align="center" justify="space-between" gap={4} wrap="wrap">
          <Stack space={2}>
            <Heading size={2}>壁纸资源表</Heading>
            <Text size={1} muted>共 {rows.length} 条 · 当前显示 {filteredRows.length} 条</Text>
          </Stack>
          <Flex gap={2} wrap="wrap">
            <Button text="刷新" mode="ghost" onClick={() => void loadRows()} />
            <Button text="导出表格" mode="ghost" onClick={exportCurrentRows} />
            <Button text="批量导入" tone="primary" onClick={() => { resetImport(); setImportOpen(true) }} />
            <Button text="＋ 单条新增" mode="ghost" onClick={openNew} />
          </Flex>
        </Flex>
        <Flex gap={2} marginTop={4} wrap="wrap">
          <Box style={{minWidth: 280, flex: '1 1 420px'}}>
            <TextInput value={search} onChange={(event) => setSearch(event.currentTarget.value)} placeholder="搜索名称或分类…" />
          </Box>
          <Box style={{width: 150}}>
            <Select value={kindFilter} onChange={(event) => setKindFilter(event.currentTarget.value as typeof kindFilter)}>
              <option value="all">全部类型</option><option value="image">静态图片</option><option value="video">动态视频</option>
            </Select>
          </Box>
          <Box style={{width: 150}}>
            <Select value={statusFilter} onChange={(event) => setStatusFilter(event.currentTarget.value as typeof statusFilter)}>
              <option value="all">全部状态</option><option value="published">已上架</option><option value="hidden">已下架</option>
            </Select>
          </Box>
        </Flex>
      </Card>

      <Box padding={4} style={{overflow: 'auto', height: 'calc(100% - 150px)'}}>
        {loading ? (
          <Flex align="center" justify="center" padding={6}><Spinner muted /></Flex>
        ) : filteredRows.length === 0 ? (
          <Card padding={6} radius={3} border>
            <Stack space={3} style={{textAlign: 'center'}}>
              <Heading size={1}>还没有云端壁纸</Heading>
              <Text muted>推荐使用“批量导入”，一次选择表格和资料库文件夹。</Text>
              <Box><Button text="批量导入第一批壁纸" tone="primary" onClick={() => { resetImport(); setImportOpen(true) }} /></Box>
            </Stack>
          </Card>
        ) : (
          <Card radius={3} border style={{overflow: 'hidden', minWidth: 1280}}>
            <table style={{borderCollapse: 'collapse', width: '100%'}}>
              <thead><tr style={{background: 'var(--card-muted-bg-color)'}}>
                {['封面', '名称', '类型', '分类', '分辨率', '大小', '推荐', '精选', '热门', '状态', '排序', '更新时间', '操作'].map((label) => (
                  <th key={label} style={{padding: '12px 10px', textAlign: 'left', borderBottom: '1px solid var(--card-border-color)', fontSize: 12}}>{label}</th>
                ))}
              </tr></thead>
              <tbody>{filteredRows.map((row) => (
                <tr key={row._id}>
                  <td style={cellStyle}>{row.thumbnailUrl ? <img src={`${row.thumbnailUrl}?w=240&h=140&fit=crop&auto=format`} alt="" style={{width: 92, height: 54, objectFit: 'cover', borderRadius: 7, display: 'block'}} /> : '—'}</td>
                  <td style={cellStyle}><Stack space={2}><Text weight="semibold" size={1}>{row.title || '未命名壁纸'}</Text>{row.titleEn && <Text size={1} muted>{row.titleEn}</Text>}</Stack></td>
                  <td style={cellStyle}><Badge tone={(row.kind ?? 'image') === 'video' ? 'suggest' : 'primary'}>{(row.kind ?? 'image') === 'video' ? '动态' : '图片'}</Badge></td>
                  <td style={cellStyle}><Text size={1}>{row.categories?.join('、') || '—'}</Text></td>
                  <td style={cellStyle}><Text size={1}>{row.width && row.height ? `${row.width}×${row.height}` : '—'}</Text></td>
                  <td style={cellStyle}><Text size={1}>{formatBytes(row.fileSize)}</Text></td>
                  <td style={cellStyle}><Checkbox checked={row.featured ?? false} onChange={(event) => void toggleGroup(row, 'featured', event.currentTarget.checked)} /></td>
                  <td style={cellStyle}><Checkbox checked={row.curated ?? false} onChange={(event) => void toggleGroup(row, 'curated', event.currentTarget.checked)} /></td>
                  <td style={cellStyle}><Checkbox checked={row.popular ?? false} onChange={(event) => void toggleGroup(row, 'popular', event.currentTarget.checked)} /></td>
                  <td style={cellStyle}><Button fontSize={1} padding={2} text={(row.status ?? 'published') === 'published' ? '已上架' : '已下架'} tone={(row.status ?? 'published') === 'published' ? 'positive' : 'caution'} mode="ghost" onClick={() => void toggleStatus(row)} /></td>
                  <td style={cellStyle}><Text size={1}>{row.sortOrder ?? 100}</Text></td>
                  <td style={cellStyle}><Text size={1}>{new Date(row._updatedAt).toLocaleDateString('zh-CN')}</Text></td>
                  <td style={cellStyle}><Flex gap={1}><Button text="编辑" fontSize={1} padding={2} mode="bleed" tone="primary" onClick={() => openEdit(row)} /><Button text="删除" fontSize={1} padding={2} mode="bleed" tone="critical" onClick={() => void deleteWallpaper(row)} /></Flex></td>
                </tr>
              ))}</tbody>
            </table>
          </Card>
        )}
      </Box>

      {importOpen && (
        <Dialog id="wallpaper-batch-import" header="批量导入壁纸" onClose={() => !importing && setImportOpen(false)} width={3}>
          <Box padding={4}><Stack space={5}>
            <Card padding={4} radius={3} tone="primary">
              <Stack space={2}><Text weight="semibold">所有字段都不是必填</Text><Text size={1}>只选表格就能导入数据；再选择 Foldwalls 资料库文件夹，系统会按文件名自动匹配并上传图片、视频和封面。</Text></Stack>
            </Card>
            <Field label="1. 选择 Excel 或 CSV 表格">
              <input type="file" accept=".xlsx,.xls,.csv" onChange={(event) => { const file = event.currentTarget.files?.[0]; if (file) void parseSpreadsheet(file) }} />
            </Field>
            <Text size={1} muted>{spreadsheetName ? `已读取：${spreadsheetName} · ${importRows.length} 条` : '支持本次导出的工作簿，也支持同列名的 CSV。'}</Text>
            <Field label="2. 选择 Foldwalls 资料库文件夹（可选，推荐）">
              <input type="file" {...directoryPickerProps} onChange={(event) => addResourceFiles(event.currentTarget.files)} />
            </Field>
            <Field label="需要时补选单个或多个资源文件（可选）">
              <input type="file" multiple accept="image/*,video/*" onChange={(event) => addResourceFiles(event.currentTarget.files)} />
            </Field>
            <Card padding={3} radius={2} border>
              <Flex gap={4} wrap="wrap"><Text size={1}>已选资源：{resourceFiles.length} 个</Text><Text size={1}>匹配原文件：{matchedMediaCount} / {importRows.length}</Text><Text size={1}>匹配封面：{matchedThumbnailCount} / {importRows.length}</Text></Flex>
            </Card>
            {importError && <Card padding={3} radius={2} tone="critical"><Text size={1}>{importError}</Text></Card>}
            {importProgress && <Text size={1}>{importProgress}</Text>}
            <Flex justify="flex-end" gap={2}><Button text="取消" mode="ghost" disabled={importing} onClick={() => setImportOpen(false)} /><Button text={importing ? '正在导入…' : importRows.length ? `开始导入 ${importRows.length} 条` : '开始导入'} tone="primary" loading={importing} disabled={!importRows.length} onClick={() => void importBatch()} /></Flex>
          </Stack></Box>
        </Dialog>
      )}

      {editorOpen && (
        <Dialog id="wallpaper-editor" header={editing ? `编辑：${editing.title || '未命名壁纸'}` : '单条新增壁纸'} onClose={() => !saving && setEditorOpen(false)} width={3}>
          <Box padding={4}><Stack space={5}>
            <Card padding={4} radius={3} tone="transparent" border>
              <Stack space={4}>
                <Text size={1} muted>所有项目都可留空；名称留空时会自动使用文件名。</Text>
                <Field label="名称（可选）"><TextInput value={form.title} onChange={(event) => setField('title', event.currentTarget.value)} placeholder="留空自动使用文件名" /></Field>
                <Field label="壁纸类型"><Select value={form.kind} onChange={(event) => setField('kind', event.currentTarget.value as WallpaperKind)}><option value="image">静态图片</option><option value="video">动态视频</option></Select></Field>
                <Field label={`${form.kind === 'video' ? '视频文件' : '壁纸原图'}（可选）`}><input type="file" accept={form.kind === 'video' ? 'video/*' : 'image/*'} onChange={(event) => setMediaFile(event.currentTarget.files?.[0] ?? null)} /></Field>
                <Field label="列表封面（可选）"><input type="file" accept="image/*" onChange={(event) => setThumbnailFile(event.currentTarget.files?.[0] ?? null)} /></Field>
                {editing?.thumbnailUrl && <img src={`${editing.thumbnailUrl}?w=500&auto=format`} alt="当前封面" style={{width: 220, borderRadius: 8}} />}
                <Field label="分类（可选，逗号分隔）"><TextInput value={form.categoriesText} onChange={(event) => setField('categoriesText', event.currentTarget.value)} placeholder="自然，电影感" /></Field>
                <Flex gap={3} wrap="wrap">
                  <Box flex={1}><Field label="上架状态"><Select value={form.status} onChange={(event) => setField('status', event.currentTarget.value as WallpaperStatus)}><option value="published">已上架</option><option value="hidden">已下架</option></Select></Field></Box>
                  <Flex align="center" gap={2} style={{minWidth: 120}}><Checkbox checked={form.featured} onChange={(event) => setField('featured', event.currentTarget.checked)} /><Text size={1}>推荐轮播</Text></Flex>
                  <Flex align="center" gap={2} style={{minWidth: 90}}><Checkbox checked={form.curated} onChange={(event) => setField('curated', event.currentTarget.checked)} /><Text size={1}>精选</Text></Flex>
                  <Flex align="center" gap={2} style={{minWidth: 90}}><Checkbox checked={form.popular} onChange={(event) => setField('popular', event.currentTarget.checked)} /><Text size={1}>热门</Text></Flex>
                </Flex>
              </Stack>
            </Card>
            <Box><Button text={showAdvanced ? '收起更多可选信息' : '展开更多可选信息'} mode="bleed" onClick={() => setShowAdvanced((value) => !value)} /></Box>
            {showAdvanced && <FormSection title="更多可选信息">
              <Field label="英文名称"><TextInput value={form.titleEn} onChange={(event) => setField('titleEn', event.currentTarget.value)} /></Field>
              <Field label="中文简介"><TextArea rows={2} value={form.subtitle} onChange={(event) => setField('subtitle', event.currentTarget.value)} /></Field>
              <Field label="英文简介"><TextArea rows={2} value={form.subtitleEn} onChange={(event) => setField('subtitleEn', event.currentTarget.value)} /></Field>
              <Field label="搜索标签（逗号分隔）"><TextInput value={form.tagsText} onChange={(event) => setField('tagsText', event.currentTarget.value)} /></Field>
              <Flex gap={3} wrap="wrap"><Box flex={1}><Field label="宽度"><TextInput type="number" value={form.width} onChange={(event) => setField('width', event.currentTarget.value)} /></Field></Box><Box flex={1}><Field label="高度"><TextInput type="number" value={form.height} onChange={(event) => setField('height', event.currentTarget.value)} /></Field></Box>{form.kind === 'video' && <Box flex={1}><Field label="时长（秒）"><TextInput type="number" value={form.duration} onChange={(event) => setField('duration', event.currentTarget.value)} /></Field></Box>}</Flex>
              <Field label="作者"><TextInput value={form.author} onChange={(event) => setField('author', event.currentTarget.value)} /></Field>
              <Field label="授权说明"><TextInput value={form.licenseName} onChange={(event) => setField('licenseName', event.currentTarget.value)} /></Field>
              <Field label="来源链接"><TextInput type="url" value={form.sourceUrl} onChange={(event) => setField('sourceUrl', event.currentTarget.value)} placeholder="https://" /></Field>
              <Field label="排序数字（越大越靠前；新增内容已自动设为最新）"><TextInput type="number" value={form.sortOrder} onChange={(event) => setField('sortOrder', event.currentTarget.value)} /></Field>
              <Flex gap={3} wrap="wrap"><Box flex={1}><Field label="起点颜色"><TextInput value={form.paletteStart} onChange={(event) => setField('paletteStart', event.currentTarget.value)} /></Field></Box><Box flex={1}><Field label="中点颜色"><TextInput value={form.paletteMiddle} onChange={(event) => setField('paletteMiddle', event.currentTarget.value)} /></Field></Box><Box flex={1}><Field label="终点颜色"><TextInput value={form.paletteEnd} onChange={(event) => setField('paletteEnd', event.currentTarget.value)} /></Field></Box></Flex>
            </FormSection>}
            <Flex justify="flex-end" gap={2}><Button text="取消" mode="ghost" disabled={saving} onClick={() => setEditorOpen(false)} /><Button text={saving ? '正在保存…' : '保存壁纸'} tone="primary" loading={saving} onClick={() => void saveWallpaper()} /></Flex>
          </Stack></Box>
        </Dialog>
      )}
    </Card>
  )
}

const cellStyle = {
  padding: '10px',
  borderBottom: '1px solid var(--card-border-color)',
  verticalAlign: 'middle',
} as const

function Field({label, children}: {label: string; children: React.ReactNode}) {
  return <Stack space={2}><Label size={1}>{label}</Label>{children}</Stack>
}

function FormSection({title, children}: {title: string; children: React.ReactNode}) {
  return <Card padding={4} radius={3} border><Stack space={4}><Heading size={1}>{title}</Heading>{children}</Stack></Card>
}

export const wallpaperTableTool = definePlugin({
  name: 'foldwalls-resource-table',
  tools: (previous) => [{name: 'wallpaper-table', title: '壁纸资源表', component: WallpaperTable}, ...previous],
})
