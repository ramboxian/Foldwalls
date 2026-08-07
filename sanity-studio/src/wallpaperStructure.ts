import type {StructureResolver} from 'sanity/structure'

export const wallpaperStructure: StructureResolver = (S) =>
  S.list()
    .title('内容管理')
    .items([
      S.documentTypeListItem('wallpaper').title('全部壁纸'),
      S.listItem()
        .title('分类字典（中英对应）')
        .child(
          S.documentList()
            .title('分类字典（中英对应）')
            .schemaType('category')
            .filter('_type == "category" && _id in path("*")')
            .defaultOrdering([{field: 'order', direction: 'asc'}]),
        ),
      S.divider(),
      S.listItem()
        .title('已上架')
        .child(
          S.documentList()
            .title('已上架壁纸')
            .schemaType('wallpaper')
            .filter('_type == "wallpaper" && status == "published"')
            .defaultOrdering([{field: 'sortOrder', direction: 'desc'}]),
        ),
      S.listItem()
        .title('已下架')
        .child(
          S.documentList()
            .title('已下架壁纸')
            .schemaType('wallpaper')
            .filter('_type == "wallpaper" && status == "hidden"')
            .defaultOrdering([{field: '_updatedAt', direction: 'desc'}]),
        ),
      S.listItem()
        .title('首页推荐（轮播）')
        .child(
          S.documentList()
            .title('首页推荐轮播')
            .schemaType('wallpaper')
            .filter('_type == "wallpaper" && featured == true && status == "published"')
            .defaultOrdering([{field: '_createdAt', direction: 'desc'}]),
        ),
      S.listItem()
        .title('精选')
        .child(
          S.documentList()
            .title('首页精选')
            .schemaType('wallpaper')
            .filter('_type == "wallpaper" && curated == true && status == "published"')
            .defaultOrdering([{field: 'sortOrder', direction: 'desc'}]),
        ),
      S.listItem()
        .title('热门')
        .child(
          S.documentList()
            .title('热门壁纸')
            .schemaType('wallpaper')
            .filter('_type == "wallpaper" && popular == true && status == "published"')
            .defaultOrdering([{field: '_createdAt', direction: 'desc'}]),
        ),
      S.listItem()
        .title('最新')
        .child(
          S.documentList()
            .title('最新壁纸')
            .schemaType('wallpaper')
            .filter('_type == "wallpaper" && status == "published"')
            .defaultOrdering([{field: 'sortOrder', direction: 'desc'}]),
        ),
    ])
