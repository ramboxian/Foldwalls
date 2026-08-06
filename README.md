# Foldwalls · 浮岛桌面

Foldwalls（浮岛桌面）是一个原生 macOS 壁纸应用，用 SwiftUI、AppKit 和 AVFoundation 实现。当前版本为 0.2.0。

## 当前功能

- 图片与视频壁纸
- 本地批量导入，并复制到应用资料库
- 为每个显示器创建原生桌面窗口
- 视频无声循环播放
- 锁屏、休眠、电池供电和前台全屏时的播放策略
- 无侧边栏的沉浸式流媒体首页、发现、本地资料库和详情页
- macOS 26 原生 Liquid Glass 导航与控制，旧系统使用原生 Material 回退
- 以当前壁纸为背景的状态栏播放器，支持前后切换、收藏、停止与显示器状态
- 通用、播放、显示器和资料库四类设置
- 4K 原文件与轻量预览缩略图分离
- Sanity 云端目录同步（项目 `3huccpow`，`production` 数据集）
- 云端缩略图按需缓存，原图与视频仅在用户应用时下载
- 首页 Hero 自动缓存并播放轻量视频预览，其他视频卡片在悬停时加载；预览只下载一次
- 每次进入或再次点击首页都会重新打乱 Hero 精选顺序，并每 8 秒自动切换下一张
- 首页依次展示推荐轮播、精选、最新、热门与分类；推荐/精选/热门由 Sanity 独立勾选，最新按排序数字从大到小
- 探索页使用当前已应用壁纸作为背景（未设置时回退到最新壁纸），并支持最新/最热、分类与格式筛选
- 切换主导航或应用回到前台时会重新读取云端目录，无需关闭 App；搜索使用全屏 Liquid Glass 结果页
- 断网时继续使用本地目录、收藏记录和已经下载的壁纸
- 使用 Sparkle + GitHub Releases 检查并安装更新；顶部绿色箭头显示下载进度，关于页提供检查更新与更新说明

## 构建

1. 用 Xcode 打开 `CinematicWall.xcodeproj`。
2. 选择 `CinematicWall` scheme 和 `My Mac`。
3. 按 `Command-R` 运行。

也可以从命令行构建：

```sh
xcodebuild -project CinematicWall.xcodeproj \
  -scheme CinematicWall \
  -configuration Debug \
  -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO build
```

## 资料库与壁纸源

应用通过 `SanityCatalogProvider` 获取已发布壁纸的结构化元数据；Sanity Asset CDN 保存图片、视频与缩略图文件。数据库中只保存标题、分类、标签、尺寸、文件地址等元数据，不保存媒体二进制。

客户端使用 `library.json` 保存轻量的离线目录、收藏和下载状态，媒体文件保存在应用资料库的 `Library` 目录。启动时只请求目录；列表缩略图在可见时缓存；原始媒体仅在用户点击应用时下载，并在下载后校验文件大小再原子写入。已有本地素材会按云端 ID 或原始文件名合并，不会重复下载。

## 发布更新

更新清单为仓库根目录的 `appcast.xml`，安装包由 GitHub Releases 提供。发布工具会构建通用版 App、生成 ZIP/DMG、使用保存在 macOS 钥匙串中的 Sparkle EdDSA 私钥签名，并更新版本号与更新清单。

```sh
scripts/release.sh 0.3.0 release-notes/0.3.0.txt
scripts/release.sh 0.3.0 release-notes/0.3.0.txt --publish
```

详细说明见 `release-notes/README.md`。应用只打包工程资源，不会把 `Application Support/Foldwalls/Library` 中的用户壁纸放入安装包。
