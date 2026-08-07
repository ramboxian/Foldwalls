export interface CategoryDefinition {
  id: string
  zh: string
  en: string
  order: number
}

export const CATEGORY_DEFINITIONS: CategoryDefinition[] = [
  {id: 'nature', zh: '自然', en: 'Nature', order: 10},
  {id: 'city', zh: '城市', en: 'City', order: 20},
  {id: 'portrait', zh: '人像', en: 'Portrait', order: 30},
  {id: 'girl', zh: '女孩', en: 'Girls', order: 40},
  {id: 'pet', zh: '宠物', en: 'Pets', order: 50},
  {id: 'anime', zh: '动漫', en: 'Anime', order: 60},
  {id: 'movie', zh: '电影', en: 'Movies', order: 70},
  {id: 'game', zh: '游戏', en: 'Games', order: 80},
  {id: 'scifi', zh: '科幻', en: 'Sci-Fi', order: 90},
  {id: 'vehicle', zh: '车辆', en: 'Vehicles', order: 100},
  {id: 'space', zh: '太空', en: 'Space', order: 110},
  {id: 'abstract', zh: '抽象', en: 'Abstract', order: 120},
  {id: 'night', zh: '夜晚', en: 'Night', order: 130},
  {id: 'dark', zh: '深色', en: 'Dark', order: 140},
  {id: 'forest', zh: '森林', en: 'Forest', order: 150},
  {id: 'ocean', zh: '海洋', en: 'Ocean', order: 160},
  {id: 'sky', zh: '天空', en: 'Sky', order: 170},
  {id: 'warm', zh: '暖色', en: 'Warm', order: 180},
  {id: 'blue', zh: '蓝色', en: 'Blue', order: 190},
  {id: 'serene', zh: '静谧', en: 'Serene', order: 200},
  {id: 'minimal', zh: '极简', en: 'Minimal', order: 210},
]

export const CATEGORY_BY_ID = new Map(CATEGORY_DEFINITIONS.map((item) => [item.id, item]))
export const CATEGORY_BY_LABEL = new Map(
  CATEGORY_DEFINITIONS.flatMap((item) => [
    [item.id.toLocaleLowerCase(), item] as const,
    [item.zh.toLocaleLowerCase(), item] as const,
    [item.en.toLocaleLowerCase(), item] as const,
  ]),
)

export function categoryDocumentId(id: string): string {
  return `category.${id}`
}

export function resolveCategory(value: string): CategoryDefinition | undefined {
  return CATEGORY_BY_LABEL.get(value.trim().toLocaleLowerCase())
}
