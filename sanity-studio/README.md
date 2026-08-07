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

## R2 媒体迁移与安全切换

Sanity 继续负责元数据和可视化后台；原图、封面与卡片悬停视频预览会复制到 Cloudflare R2。首页 Hero 始终播放 R2 原片，不降级为轻量预览。迁移脚本只在本机运行，R2 密钥不会进入 Studio 网页或 macOS 客户端。

1. macOS 开发机优先从系统钥匙串读取 `com.foldwalls.r2 / foldwalls-uploader`；`.env` 只需填写帐户 ID、桶名和公开地址。CI 或非 macOS 环境再使用环境变量提供访问密钥。
2. 先运行 `pnpm r2:migrate -- --dry-run` 检查对象 Key 和公开地址。
3. 运行 `pnpm r2:migrate` 上传并按文件大小逐个校验。这个步骤只写入 R2 地址，`r2DeliveryEnabled` 始终保持关闭，因此线上客户端不受影响。
4. Worker 域名变化时，运行 `R2_PUBLIC_BASE_URL=https://... pnpm r2:rewrite-base` 只改写公开地址，不切流量。
5. 使用 `FOLDWALLS_PREFER_R2=1` 启动候选版，验证目录、封面、预览和应用原片；R2 失败会自动回退 Sanity。
6. 新版发布并确认 Sparkle 可更新后，才运行：

```sh
R2_CUTOVER_CONFIRM=FOLDWALLS_R2_VERIFIED pnpm r2:cutover -- --enable
```

需要紧急回滚时运行 `pnpm r2:cutover -- --disable`。旧版客户端始终读取原有 Sanity 资源；不要删除 Sanity Asset，至少保留一个完整版本周期。
