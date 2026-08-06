# Foldwalls · 浮岛桌面 Sanity Studio

这是 Foldwalls（浮岛桌面）的免费云端壁纸管理后台，连接 Sanity 项目 `3huccpow` 的 `production` 数据集。

线上后台：<https://foldwalls-admin.sanity.studio/>

## 本地启动

```sh
export PATH="/Users/bytedance/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:/Users/bytedance/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/fallback:$PATH"
pnpm install
pnpm dev
```

浏览器访问 `http://localhost:3333`。

## 功能

- 中文壁纸资源表
- Excel / CSV 批量导入和当前云端数据导出
- 一次选择 Foldwalls 资料库文件夹，按文件名自动匹配原图、视频和封面
- 所有元数据字段均可留空；名称、类型、状态和排序会按文件或默认值自动补齐
- 支持只导数据，也支持连同资源文件一起上传
- 单条新增表单只显示常用字段，高级字段默认收起
- 新增、编辑、删除和搜索
- 上架、下架、首页推荐与运营排序
- 分类、标签、分辨率、作者和授权信息
- 静态图片、动态视频与列表封面分离

## 批量导入

1. 在线上后台点击“批量导入”。
2. 选择包含“壁纸导入”工作表的 `.xlsx` 文件，或选择同列名的 `.csv` 文件。
3. 如果需要同时上传图片和视频，再选择本机 `~/Library/Application Support/Foldwalls` 文件夹；浏览器会自动匹配 `Library` 和 `Thumbnails` 中的文件。
4. 核对识别数量后点击“开始导入”。重复提交同一份表格会更新同一批记录，不会重复创建文档。

只选择表格、不选择资源文件时，后台会先创建元数据记录，资源文件可以以后再补。

## 部署

登录 Sanity CLI 后运行：

```sh
pnpm deploy
```

部署过程中选择一个以英文字母开头的唯一地址，例如 `foldwalls-admin`。
