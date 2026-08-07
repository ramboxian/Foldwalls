import AppKit
import AVFoundation
import Combine
import CoreImage
import CoreGraphics
import CryptoKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WallpaperLibrary: ObservableObject {
    @Published private(set) var items: [WallpaperItem] = []
    @Published var isImporting = false
    @Published var importError: String?
    @Published private(set) var isRebuildingPreviewCache = false
    @Published private(set) var previewCacheProgress: Double = 0
    @Published private(set) var isSynchronizingFolder = false
    @Published var maintenanceMessage: String?
    @Published private(set) var isRefreshingCatalog = false
    @Published private(set) var hasCompletedInitialCatalogLoad = false
    @Published private(set) var catalogError: String?
    @Published private(set) var lastCatalogRefresh: Date?
    @Published private(set) var preparingItemID: UUID?
    @Published private(set) var previewLoadingItemIDs: Set<UUID> = []
    @Published private(set) var recentlyUsedIDs: [UUID] = []

    let engine: WallpaperEngine

    private let fileManager = FileManager.default
    private let catalogProvider: any WallpaperCatalogProvider
    private let rootDirectory: URL
    private let mediaDirectory: URL
    private let cloudMediaDirectory: URL
    private let thumbnailDirectory: URL
    private let videoPreviewDirectory: URL
    private let originalVideoDirectory: URL
    private let manifestURL: URL
    private var didAttemptRestore = false
    private var mediaDirectoryWatcher: DispatchSourceFileSystemObject?
    private var folderSynchronizationTask: Task<Void, Never>?
    private var thumbnailTasks: [UUID: Task<URL?, Never>] = [:]
    private var pendingThumbnailPaths: [UUID: String] = [:]
    private var thumbnailPersistenceTask: Task<Void, Never>?
    private var videoPreviewTasks: [UUID: Task<URL?, Never>] = [:]
    private var originalVideoTasks: [UUID: Task<URL?, Never>] = [:]

    init(engine: WallpaperEngine, catalogProvider: any WallpaperCatalogProvider = SanityCatalogProvider()) {
        self.engine = engine
        self.catalogProvider = catalogProvider

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let environment = ProcessInfo.processInfo.environment
        let overridePath = environment["FOLDWALLS_LIBRARY_ROOT"] ?? environment["CINEMATIC_LIBRARY_ROOT"]
        if let overridePath, !overridePath.isEmpty {
            rootDirectory = URL(fileURLWithPath: overridePath, isDirectory: true)
        } else {
            let foldwallsDirectory = appSupport.appendingPathComponent("Foldwalls", isDirectory: true)
            let legacyDirectory = appSupport.appendingPathComponent("CinematicWall", isDirectory: true)
            var selectedDirectory = foldwallsDirectory
            if !fileManager.fileExists(atPath: foldwallsDirectory.path),
               fileManager.fileExists(atPath: legacyDirectory.path) {
                do {
                    try fileManager.moveItem(at: legacyDirectory, to: foldwallsDirectory)
                } catch {
                    // Keep using the existing library if migration is temporarily
                    // blocked, so a rebrand can never make user media disappear.
                    selectedDirectory = legacyDirectory
                }
            }
            rootDirectory = selectedDirectory
        }
        mediaDirectory = rootDirectory.appendingPathComponent("Library", isDirectory: true)
        cloudMediaDirectory = mediaDirectory.appendingPathComponent("Cloud", isDirectory: true)
        thumbnailDirectory = rootDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
        videoPreviewDirectory = rootDirectory.appendingPathComponent("VideoPreviews", isDirectory: true)
        originalVideoDirectory = rootDirectory.appendingPathComponent("OriginalVideos", isDirectory: true)
        manifestURL = rootDirectory.appendingPathComponent("library.json")

        recentlyUsedIDs = (UserDefaults.standard.stringArray(forKey: "recentlyUsedWallpaperIDs") ?? [])
            .compactMap(UUID.init(uuidString:))

        prepareDirectories()
        loadLibrary()
        migrateMissingThumbnails()
        migrateWallpaperPalettes()
        importDevelopmentShowcaseIfRequested()
        startWatchingMediaDirectory()
        scheduleFolderSynchronization(delay: .milliseconds(100))
        Task {
            await refreshCatalog()
#if DEBUG
            if ProcessInfo.processInfo.environment["CINEMATIC_SMOKE_APPLY_FIRST"] == "1",
               let first = curatedItems.first {
                apply(first)
            }
            if ProcessInfo.processInfo.environment["CINEMATIC_SMOKE_PREVIEW_FIRST"] == "1",
               let firstVideo = curatedItems.first(where: { $0.kind == .video }) {
                _ = await resolvedVideoPreviewURL(for: firstVideo)
            }
#endif
        }
    }

    var curatedItems: [WallpaperItem] {
        items.filter { $0.source == .curated }
    }

    var personalItems: [WallpaperItem] {
        items.filter { $0.source != .curated }
    }

    var favorites: [WallpaperItem] {
        items.filter(\.isFavorite)
    }

    var recentlyUsedItems: [WallpaperItem] {
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return recentlyUsedIDs.compactMap { itemsByID[$0] }
    }

    var totalStorageBytes: Int64 {
        items.reduce(0) { total, item in
            guard item.isDownloaded else { return total }
            let measured = (try? item.localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            return total + (measured ?? item.fileSize)
        }
    }

    var catalogItemCount: Int { curatedItems.count }

    var offlineReadyCatalogCount: Int { curatedItems.filter(\.isDownloaded).count }

    var preparingItem: WallpaperItem? {
        guard let preparingItemID else { return nil }
        return items.first { $0.id == preparingItemID }
    }

    var libraryDirectoryURL: URL { mediaDirectory }

    private func importDevelopmentShowcaseIfRequested() {
#if DEBUG
        guard let list = ProcessInfo.processInfo.environment["CINEMATIC_SEED_MEDIA"], !list.isEmpty else { return }
        let existingTitles = Set(items.map { $0.title.localizedLowercase })
        let urls = list
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) }
            .filter { fileManager.fileExists(atPath: $0.path) }
            .filter { !existingTitles.contains(displayTitle(for: $0.deletingPathExtension().lastPathComponent).localizedLowercase) }

        guard !urls.isEmpty else { return }
        Task { await importFiles(urls) }
#endif
    }

    func presentImportPanel() {
        let language = AppLanguage.current
        let panel = NSOpenPanel()
        panel.title = language.text("Import Wallpaper", "导入壁纸")
        panel.message = language.text("Choose images or videos. Files will be copied into your private Foldwalls library.", "选择图片或视频，文件会复制到 Foldwalls 的私人资料库。")
        panel.prompt = language.text("Import", "导入")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie, .mpeg4Movie, .quickTimeMovie]

        guard panel.runModal() == .OK else { return }
        Task { await importFiles(panel.urls) }
    }

    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        importError = nil

        defer { isImporting = false }

        do {
            for sourceURL in urls {
                let item = try await importFile(sourceURL)
                items.insert(item, at: 0)
            }
            saveLibrary()
            scheduleFolderSynchronization()
        } catch {
            importError = error.localizedDescription
        }
    }

    func apply(_ item: WallpaperItem) {
        if item.isDownloaded {
            engine.apply(item)
            recordUsage(of: item)
            return
        }
        guard item.remoteMediaURL != nil,
              preparingItemID == nil else { return }

        preparingItemID = item.id
        maintenanceMessage = AppLanguage.current.text(
            "Preparing \(item.localizedTitle(for: .english))…",
            "正在准备\(item.localizedTitle(for: .chinese))…"
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.preparingItemID = nil }
            do {
                let downloaded = try await self.downloadMedia(for: item)
                self.maintenanceMessage = AppLanguage.current.text("Wallpaper applied", "壁纸已应用")
                self.engine.apply(downloaded)
                self.recordUsage(of: downloaded)
            } catch {
                self.catalogError = error.localizedDescription
                self.maintenanceMessage = AppLanguage.current.text("Couldn’t prepare wallpaper", "壁纸准备失败")
            }
        }
    }

    private func recordUsage(of item: WallpaperItem) {
        recentlyUsedIDs.removeAll { $0 == item.id }
        recentlyUsedIDs.insert(item.id, at: 0)
        if recentlyUsedIDs.count > 80 {
            recentlyUsedIDs.removeLast(recentlyUsedIDs.count - 80)
        }
        UserDefaults.standard.set(recentlyUsedIDs.map(\.uuidString), forKey: "recentlyUsedWallpaperIDs")
    }

    func clearRecentlyUsed() {
        recentlyUsedIDs.removeAll()
        UserDefaults.standard.removeObject(forKey: "recentlyUsedWallpaperIDs")
    }

    func isPreparing(_ item: WallpaperItem) -> Bool {
        preparingItemID == item.id
    }

    func isLoadingVideoPreview(_ item: WallpaperItem) -> Bool {
        previewLoadingItemIDs.contains(item.id)
    }

    func playAdjacent(to item: WallpaperItem, offset: Int) {
        guard !items.isEmpty,
              let currentIndex = items.firstIndex(where: { $0.id == item.id }) else { return }
        let nextIndex = (currentIndex + offset + items.count) % items.count
        apply(items[nextIndex])
    }

    func toggleFavorite(_ item: WallpaperItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isFavorite.toggle()
        saveLibrary()
    }

    func remove(_ item: WallpaperItem) {
        guard item.source != .curated else { return }
        if engine.currentItem?.id == item.id {
            engine.stop()
        }
        try? fileManager.removeItem(at: item.localURL)
        if let thumbnailURL = item.thumbnailURL {
            try? fileManager.removeItem(at: thumbnailURL)
        }
        items.removeAll { $0.id == item.id }
        saveLibrary()
    }

    func revealInFinder(_ item: WallpaperItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.localURL])
    }

    func revealLibraryInFinder() {
        NSWorkspace.shared.open(mediaDirectory)
    }

    func refreshCatalog() async {
        guard !isRefreshingCatalog else { return }
        isRefreshingCatalog = true
        catalogError = nil
        defer {
            isRefreshingCatalog = false
            hasCompletedInitialCatalogLoad = true
        }

        do {
            let entries = try await catalogProvider.fetchCatalog()
            mergeCatalog(entries)
            lastCatalogRefresh = Date()
            maintenanceMessage = AppLanguage.current.text(
                "Cloud catalog updated: \(entries.count) wallpapers",
                "云端目录已更新：\(entries.count) 张壁纸"
            )
        } catch {
            catalogError = error.localizedDescription
            if curatedItems.isEmpty {
                maintenanceMessage = AppLanguage.current.text(
                    "Cloud is unavailable. Your local library still works offline.",
                    "云端暂时无法连接，本地资料库仍可离线使用。"
                )
            }
        }
    }

    func waitForInitialCatalogLoad() async {
        // A saved catalog is already enough to build a complete first screen.
        // Do not make returning users wait for the network on every launch;
        // refreshCatalog() continues independently in the background.
        guard items.isEmpty else { return }
        while !hasCompletedInitialCatalogLoad {
            if !isRefreshingCatalog {
                await refreshCatalog()
            } else {
                do {
                    try await Task.sleep(for: .milliseconds(80))
                } catch {
                    return
                }
            }
        }
    }

    func prewarmArtwork(for candidates: [WallpaperItem], limit: Int = 10) async {
        let uniqueItems = candidates.reduce(into: [WallpaperItem]()) { result, item in
            if !result.contains(where: { $0.id == item.id }) { result.append(item) }
        }
        let tasks = uniqueItems.prefix(limit).map { item in
            Task { @MainActor [weak self] in
                await self?.resolvedArtworkURL(for: item)
            }
        }
        for task in tasks { _ = await task.value }
    }

    /// Returns a local preview URL. Cloud thumbnails are small and cached on
    /// disk the first time a card becomes visible; repeated views are offline.
    func resolvedArtworkURL(for item: WallpaperItem) async -> URL? {
        if let thumbnailURL = item.thumbnailURL,
           fileManager.fileExists(atPath: thumbnailURL.path) {
            return thumbnailURL
        }
        if item.kind == .image && item.isDownloaded { return item.localURL }
        guard let remoteURL = item.remoteThumbnailURL else { return nil }

        if let existingTask = thumbnailTasks[item.id] {
            return await existingTask.value
        }

        let destination = thumbnailCacheDestination(for: item, remoteURL: remoteURL)
        if fileManager.fileExists(atPath: destination.path) {
            updateThumbnailPath(destination.path, for: item.id)
            return destination
        }

        let task = Task<URL?, Never> {
            do {
                var request = URLRequest(url: remoteURL)
                request.cachePolicy = .useProtocolCachePolicy
                request.timeoutInterval = 30
                let (temporaryURL, response) = try await URLSession.shared.download(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else { return nil }
                try? self.fileManager.removeItem(at: destination)
                try self.fileManager.moveItem(at: temporaryURL, to: destination)
                return destination
            } catch {
                return nil
            }
        }
        thumbnailTasks[item.id] = task
        let result = await task.value
        thumbnailTasks.removeValue(forKey: item.id)
        if let result { updateThumbnailPath(result.path, for: item.id) }
        return result
    }

    /// Returns a persistent local URL for card motion previews. Sanity stores a
    /// short, lightweight preview separately from the original 4K wallpaper;
    /// after the first hover load, subsequent card playback is fully local.
    /// Cloud cards deliberately never fall back to downloading the original.
    func resolvedVideoPreviewURL(for item: WallpaperItem) async -> URL? {
        guard item.kind == .video else { return nil }
        guard let remoteURL = item.remotePreviewVideoURL else {
            return item.isDownloaded ? item.localURL : nil
        }

        let destination = videoPreviewCacheDestination(for: item, remoteURL: remoteURL)
        if validCachedVideoPreview(at: destination, for: item, remoteURL: remoteURL) {
            return destination
        }
        if let existingTask = videoPreviewTasks[item.id] {
            return await existingTask.value
        }

        previewLoadingItemIDs.insert(item.id)
        let task = Task<URL?, Never> {
            do {
                var request = URLRequest(url: remoteURL)
                request.cachePolicy = .reloadRevalidatingCacheData
                request.timeoutInterval = 180
                let (temporaryURL, response) = try await URLSession.shared.download(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else { return nil }
                let expectedSize = expectedVideoPreviewSize(for: item, remoteURL: remoteURL)
                if expectedSize > 0,
                   let downloadedSize = try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   downloadedSize != Int(expectedSize) {
                    return nil
                }
                try? self.fileManager.removeItem(at: destination)
                try self.fileManager.moveItem(at: temporaryURL, to: destination)
                return destination
            } catch {
                return nil
            }
        }
        videoPreviewTasks[item.id] = task
        let result = await task.value
        videoPreviewTasks.removeValue(forKey: item.id)
        previewLoadingItemIDs.remove(item.id)
        return result
    }

    /// Returns the full-resolution video used exclusively by the Home hero.
    /// Originals and compressed card previews live in separate persistent
    /// caches so revisiting a hero never substitutes the lightweight asset or
    /// repeatedly downloads the original.
    func resolvedOriginalVideoURL(for item: WallpaperItem) async -> URL? {
        guard item.kind == .video else { return nil }
        if item.isDownloaded { return item.localURL }
        guard let remoteURL = item.remoteMediaURL else { return nil }

        let destination = originalVideoCacheDestination(for: item, remoteURL: remoteURL)
        if validCachedOriginalVideo(at: destination, for: item) {
            return destination
        }
        if let existingTask = originalVideoTasks[item.id] {
            return await existingTask.value
        }

        let task = Task<URL?, Never> {
            do {
                var request = URLRequest(url: remoteURL)
                request.cachePolicy = .reloadRevalidatingCacheData
                request.timeoutInterval = 300
                let (temporaryURL, response) = try await URLSession.shared.download(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else { return nil }
                if item.fileSize > 0,
                   let downloadedSize = try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   downloadedSize != Int(item.fileSize) {
                    return nil
                }
                try? self.fileManager.removeItem(at: destination)
                try self.fileManager.moveItem(at: temporaryURL, to: destination)
                return destination
            } catch {
                return nil
            }
        }
        originalVideoTasks[item.id] = task
        let result = await task.value
        originalVideoTasks.removeValue(forKey: item.id)
        return result
    }

    /// Starts a Home hero immediately from the original Sanity asset. If that
    /// original is already cached locally, use the cache instead. Card previews
    /// continue to use their separate compressed and persistent preview files.
    func immediateHeroVideoURL(for item: WallpaperItem) -> URL? {
        guard item.kind == .video else { return nil }
        if item.isDownloaded { return item.localURL }
        guard let remoteURL = item.remoteMediaURL else { return nil }
        let cachedURL = originalVideoCacheDestination(for: item, remoteURL: remoteURL)
        return validCachedOriginalVideo(at: cachedURL, for: item) ? cachedURL : remoteURL
    }

    /// Reconciles the user-maintained Library folder with the manifest. This is
    /// public so Settings (and future diagnostics) can request an immediate pass.
    func synchronizeMediaFolder() {
        scheduleFolderSynchronization(delay: .milliseconds(10))
    }

    func rebuildPreviewCache() {
        guard !isRebuildingPreviewCache else { return }
        isRebuildingPreviewCache = true
        previewCacheProgress = 0
        maintenanceMessage = nil
        try? fileManager.removeItem(at: thumbnailDirectory)
        try? fileManager.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        for index in items.indices { items[index].thumbnailPath = nil }

        Task {
            let count = max(items.count, 1)
            for index in items.indices {
                let item = items[index]
                if item.isDownloaded {
                    switch item.kind {
                    case .image:
                        items[index].thumbnailPath = try? createImageThumbnail(
                            for: item.localURL,
                            fileName: item.id.uuidString
                        ).path
                    case .video:
                        items[index].thumbnailPath = try? await createVideoThumbnail(
                            for: item.localURL,
                            id: item.id
                        ).path
                    }
                } else {
                    _ = await resolvedArtworkURL(for: item)
                }
                previewCacheProgress = Double(index + 1) / Double(count)
            }
            saveLibrary()
            isRebuildingPreviewCache = false
            maintenanceMessage = AppLanguage.current.text("Preview cache rebuilt", "预览缓存已重建")
        }
    }

    private func prepareDirectories() {
        try? fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: cloudMediaDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: videoPreviewDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: originalVideoDirectory, withIntermediateDirectories: true)
    }

    private func mergeCatalog(_ entries: [CatalogEntry]) {
        let existingItems = items
        let existingByRemoteID = Dictionary(
            existingItems.compactMap { item in item.remoteID.map { ($0, item) } },
            uniquingKeysWith: { current, _ in current }
        )
        let existingByFileName = Dictionary(
            existingItems.map { ($0.localURL.lastPathComponent.localizedLowercase, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        var consumedIDs = Set<UUID>()
        var remoteItems: [WallpaperItem] = []

        for entry in entries {
            let existing = existingByRemoteID[entry.id]
                ?? existingByFileName[entry.mediaFileName.localizedLowercase]
            if let existing { consumedIDs.insert(existing.id) }

            let id = existing?.id ?? stableUUID(for: entry.id)
            let cloudDestination = cloudMediaDestination(remoteID: entry.id, fileName: entry.mediaFileName, fallbackID: id)
            let localPath = existing?.isDownloaded == true ? existing!.localPath : cloudDestination.path
            let cachedThumbnail = existing?.thumbnailURL.flatMap { fileManager.fileExists(atPath: $0.path) ? $0.path : nil }
                ?? existingThumbnailPath(for: id, remoteID: entry.id, remoteURL: entry.thumbnailURL)
            let palette = WallpaperPalette(
                startHex: entry.paletteStart.replacingOccurrences(of: "#", with: ""),
                middleHex: entry.paletteMiddle.replacingOccurrences(of: "#", with: ""),
                endHex: entry.paletteEnd.replacingOccurrences(of: "#", with: "")
            )

            remoteItems.append(WallpaperItem(
                id: id,
                title: entry.title,
                subtitle: entry.subtitle,
                kind: entry.kind,
                source: .curated,
                localPath: localPath,
                thumbnailPath: cachedThumbnail,
                width: entry.width,
                height: entry.height,
                duration: entry.duration,
                fileSize: entry.fileSize,
                author: entry.author,
                licenseName: entry.licenseName,
                sourceURL: entry.sourceURL,
                categories: entry.categories,
                categoryDetails: entry.categoryDetails.compactMap { $0 },
                palette: palette,
                isFavorite: existing?.isFavorite ?? false,
                createdAt: existing?.createdAt ?? Date(),
                fileModifiedAt: existing?.fileModifiedAt,
                fileSystemID: existing?.fileSystemID,
                remoteID: entry.id,
                remoteMediaURL: entry.mediaURL,
                remoteThumbnailURL: entry.thumbnailURL,
                remotePreviewVideoURL: entry.previewVideoURL,
                remotePreviewVideoSize: entry.previewVideoSize,
                remoteUpdatedAt: entry.updatedAt,
                remoteFileName: entry.mediaFileName,
                titleEn: entry.titleEn,
                subtitleEn: entry.subtitleEn,
                tags: entry.tags,
                localizedTags: entry.localizedTags.compactMap { $0 },
                isFeatured: entry.featured,
                isCurated: entry.curated,
                isPopular: entry.popular,
                sortOrder: entry.sortOrder,
                remoteCreatedAt: entry.createdAt
            ))
        }

        remoteItems.sort { lhs, rhs in
            let leftOrder = lhs.sortOrder ?? 100
            let rightOrder = rhs.sortOrder ?? 100
            return leftOrder == rightOrder ? (lhs.remoteCreatedAt ?? "") > (rhs.remoteCreatedAt ?? "") : leftOrder > rightOrder
        }
        let personal = existingItems
            .filter { !consumedIDs.contains($0.id) && $0.source != .curated }
            .sorted { $0.createdAt > $1.createdAt }
        items = remoteItems + personal
        saveLibrary()
        pruneObsoleteVideoPreviews(referencedBy: remoteItems)
        pruneObsoleteOriginalVideos(referencedBy: remoteItems)
    }

    private func stableUUID(for value: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func cloudMediaDestination(remoteID: String, fileName: String, fallbackID: UUID) -> URL {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension
        let safeID = remoteID.replacingOccurrences(of: "/", with: "-")
        let base = safeID.isEmpty ? fallbackID.uuidString : safeID
        return fileExtension.isEmpty
            ? cloudMediaDirectory.appendingPathComponent(base)
            : cloudMediaDirectory.appendingPathComponent(base).appendingPathExtension(fileExtension)
    }

    private func thumbnailCacheDestination(for item: WallpaperItem, remoteURL: URL) -> URL {
        let fileExtension = remoteURL.pathExtension.isEmpty ? "jpg" : remoteURL.pathExtension
        let key = item.remoteID ?? item.id.uuidString
        return thumbnailDirectory
            .appendingPathComponent("cloud-\(key.replacingOccurrences(of: "/", with: "-"))")
            .appendingPathExtension(fileExtension)
    }

    private func videoPreviewCacheDestination(for item: WallpaperItem, remoteURL: URL) -> URL {
        let fileExtension = remoteURL.pathExtension.isEmpty ? "mp4" : remoteURL.pathExtension
        let remoteKey = item.remoteID ?? item.id.uuidString
        let urlDigest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
        let safeKey = remoteKey.replacingOccurrences(of: "/", with: "-")
        return videoPreviewDirectory
            .appendingPathComponent("preview-\(safeKey)-\(urlDigest)")
            .appendingPathExtension(fileExtension)
    }

    private func originalVideoCacheDestination(for item: WallpaperItem, remoteURL: URL) -> URL {
        let namedExtension = item.remoteFileName.map { URL(fileURLWithPath: $0).pathExtension } ?? ""
        let fileExtension = namedExtension.isEmpty
            ? (remoteURL.pathExtension.isEmpty ? "mp4" : remoteURL.pathExtension)
            : namedExtension
        let remoteKey = item.remoteID ?? item.id.uuidString
        let urlDigest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
        let safeKey = remoteKey.replacingOccurrences(of: "/", with: "-")
        return originalVideoDirectory
            .appendingPathComponent("original-\(safeKey)-\(urlDigest)")
            .appendingPathExtension(fileExtension)
    }

    private func expectedVideoPreviewSize(for item: WallpaperItem, remoteURL: URL) -> Int64 {
        if remoteURL == item.remotePreviewVideoURL { return item.remotePreviewVideoSize ?? 0 }
        return item.fileSize
    }

    private func validCachedVideoPreview(at url: URL, for item: WallpaperItem, remoteURL: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let expectedSize = expectedVideoPreviewSize(for: item, remoteURL: remoteURL)
        guard expectedSize > 0 else { return true }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(expectedSize)
    }

    private func validCachedOriginalVideo(at url: URL, for item: WallpaperItem) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        guard item.fileSize > 0 else { return true }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(item.fileSize)
    }

    private func pruneObsoleteVideoPreviews(referencedBy items: [WallpaperItem]) {
        let referenced = Set(items.compactMap { item -> String? in
            guard item.kind == .video,
                  let remoteURL = item.remotePreviewVideoURL else { return nil }
            return canonicalPath(for: videoPreviewCacheDestination(for: item, remoteURL: remoteURL))
        })
        guard let urls = try? fileManager.contentsOfDirectory(
            at: videoPreviewDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in urls where !referenced.contains(canonicalPath(for: url)) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func pruneObsoleteOriginalVideos(referencedBy items: [WallpaperItem]) {
        let referenced = Set(items.compactMap { item -> String? in
            guard item.kind == .video,
                  let remoteURL = item.remoteMediaURL else { return nil }
            return canonicalPath(for: originalVideoCacheDestination(for: item, remoteURL: remoteURL))
        })
        guard let urls = try? fileManager.contentsOfDirectory(
            at: originalVideoDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in urls where !referenced.contains(canonicalPath(for: url)) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func existingThumbnailPath(for id: UUID, remoteID: String, remoteURL: URL) -> String? {
        let placeholder = WallpaperItem(
            id: id,
            title: "",
            subtitle: "",
            kind: .image,
            source: .curated,
            localPath: "",
            thumbnailPath: nil,
            width: 0,
            height: 0,
            duration: nil,
            fileSize: 0,
            author: "",
            licenseName: "",
            sourceURL: nil,
            categories: [],
            palette: WallpaperPalette(startHex: "10141B", middleHex: "202A38", endHex: "080B10"),
            isFavorite: false,
            createdAt: Date(),
            remoteID: remoteID
        )
        let candidate = thumbnailCacheDestination(for: placeholder, remoteURL: remoteURL)
        return fileManager.fileExists(atPath: candidate.path) ? candidate.path : nil
    }

    private func updateThumbnailPath(_ path: String, for id: UUID) {
        guard items.contains(where: { $0.id == id && $0.thumbnailPath != path }) else { return }
        pendingThumbnailPaths[id] = path
        guard thumbnailPersistenceTask == nil else { return }

        thumbnailPersistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.flushPendingThumbnailPaths()
        }
    }

    private func flushPendingThumbnailPaths() {
        thumbnailPersistenceTask = nil
        guard !pendingThumbnailPaths.isEmpty else { return }

        let pending = pendingThumbnailPaths
        pendingThumbnailPaths.removeAll(keepingCapacity: true)
        var updatedItems = items
        var didChange = false
        for index in updatedItems.indices {
            guard let path = pending[updatedItems[index].id],
                  updatedItems[index].thumbnailPath != path else { continue }
            updatedItems[index].thumbnailPath = path
            didChange = true
        }
        guard didChange else { return }
        items = updatedItems
        saveLibrary()
    }

    private func downloadMedia(for item: WallpaperItem) async throws -> WallpaperItem {
        if item.isDownloaded { return item }
        guard let remoteURL = item.remoteMediaURL else { throw URLError(.badURL) }
        let destination = cloudMediaDestination(
            remoteID: item.remoteID ?? item.id.uuidString,
            fileName: item.remoteFileName ?? remoteURL.lastPathComponent,
            fallbackID: item.id
        )
        if fileManager.fileExists(atPath: destination.path) {
            return updateDownloadedItem(item, destination: destination)
        }

        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 300
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if item.fileSize > 0,
           let downloadedSize = try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           downloadedSize != Int(item.fileSize) {
            throw CocoaError(.fileReadCorruptFile)
        }

        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return updateDownloadedItem(item, destination: destination)
    }

    private func updateDownloadedItem(_ item: WallpaperItem, destination: URL) -> WallpaperItem {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return item }
        items[index].localPath = destination.path
        if let values = try? destination.resourceValues(forKeys: [.contentModificationDateKey, .fileResourceIdentifierKey]) {
            items[index].fileModifiedAt = values.contentModificationDate
            items[index].fileSystemID = values.fileResourceIdentifier.map { String(describing: $0) }
        }
        let updated = items[index]
        saveLibrary()
        return updated
    }

    private func startWatchingMediaDirectory() {
        mediaDirectoryWatcher?.cancel()
        mediaDirectoryWatcher = nil

        prepareDirectories()
        let descriptor = open(mediaDirectory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib, .link, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if !self.fileManager.fileExists(atPath: self.mediaDirectory.path) {
                // Cancel first and reopen on the next run-loop pass. This lets
                // the old descriptor close before the OS can reuse its integer.
                self.mediaDirectoryWatcher?.cancel()
                self.mediaDirectoryWatcher = nil
                DispatchQueue.main.async { [weak self] in
                    self?.startWatchingMediaDirectory()
                    self?.scheduleFolderSynchronization()
                }
            } else {
                self.scheduleFolderSynchronization()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        mediaDirectoryWatcher = source
        source.resume()
    }

    private func scheduleFolderSynchronization(delay: Duration = .milliseconds(900)) {
        folderSynchronizationTask?.cancel()
        folderSynchronizationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.reconcileMediaDirectory()
        }
    }

    private struct MediaFileSnapshot {
        let url: URL
        let kind: WallpaperKind
        let fileSize: Int64
        let modifiedAt: Date
        let fileSystemID: String?
    }

    private func reconcileMediaDirectory() async {
        guard !isSynchronizingFolder else { return }
        if isImporting || isRebuildingPreviewCache {
            scheduleFolderSynchronization()
            return
        }

        isSynchronizingFolder = true
        defer { isSynchronizingFolder = false }

        prepareDirectories()
        let snapshots = discoverMediaFiles()
        let discoveredPaths = Set(snapshots.map { canonicalPath(for: $0.url) })
        var existingByPath: [String: WallpaperItem] = [:]
        var existingByFileID: [String: WallpaperItem] = [:]
        for item in items {
            existingByPath[canonicalPath(for: item.localURL)] = item
            if let fileSystemID = item.fileSystemID {
                existingByFileID[fileSystemID] = item
            }
        }

        var nextItems: [WallpaperItem] = []
        var didChange = false
        var changedCount = 0
        var refreshedActiveItem: WallpaperItem?
        var matchedExistingIDs = Set<UUID>()

        for snapshot in snapshots {
            guard !Task.isCancelled else { return }
            let path = canonicalPath(for: snapshot.url)
            let pathMatch = existingByPath.removeValue(forKey: path)
            let identityMatch = snapshot.fileSystemID.flatMap { existingByFileID[$0] }
            let existing = pathMatch ?? identityMatch

            if let existing {
                matchedExistingIDs.insert(existing.id)
                existingByPath.removeValue(forKey: canonicalPath(for: existing.localURL))
                let samePath = canonicalPath(for: existing.localURL) == path
                let modificationChanged = existing.fileModifiedAt.map {
                    abs($0.timeIntervalSince(snapshot.modifiedAt)) > 0.01
                } ?? false
                let contentChanged = existing.fileSize != snapshot.fileSize || modificationChanged || existing.kind != snapshot.kind

                if contentChanged || !samePath {
                    do {
                        let refreshed = try await indexedItem(
                            from: snapshot,
                            preserving: existing,
                            derivePresentationFromFilename: !samePath
                        )
                        nextItems.append(refreshed)
                        didChange = true
                        changedCount += 1
                        if engine.currentItem?.id == existing.id { refreshedActiveItem = refreshed }
                    } catch {
                        // A large Finder copy may briefly be visible before it is
                        // complete. Keep the previous item; Finder's next write
                        // event will request another reconciliation.
                        nextItems.append(existing)
                    }
                } else {
                    var enriched = existing
                    if enriched.fileModifiedAt == nil || enriched.fileSystemID == nil {
                        enriched.fileModifiedAt = snapshot.modifiedAt
                        enriched.fileSystemID = snapshot.fileSystemID
                        didChange = true
                    }
                    nextItems.append(enriched)
                }
            } else {
                do {
                    let item = try await indexedItem(from: snapshot)
                    nextItems.append(item)
                    didChange = true
                    changedCount += 1
                } catch {
                    // Ignore incomplete files. Finder emits another write event
                    // when the copy is complete, without creating a retry loop
                    // for permanently corrupt media.
                }
            }
            await Task.yield()
        }

        // Preserve entries outside the managed folder. For managed entries,
        // deleting the original in Finder is the explicit removal action.
        for item in items where !discoveredPaths.contains(canonicalPath(for: item.localURL)) && !matchedExistingIDs.contains(item.id) {
            // A cloud catalog item is allowed to point at a not-yet-downloaded
            // destination. It must remain in the catalog while offline.
            if item.source == .curated {
                nextItems.append(item)
                continue
            }
            guard canonicalPath(for: item.localURL).hasPrefix(canonicalPath(for: mediaDirectory) + "/") else {
                nextItems.append(item)
                continue
            }
            if engine.currentItem?.id == item.id { engine.stop() }
            if let thumbnailURL = item.thumbnailURL { try? fileManager.removeItem(at: thumbnailURL) }
            didChange = true
            changedCount += 1
        }

        guard didChange else { return }
        // Catalog refresh and folder reconciliation both start shortly after a
        // cold launch. If the catalog wins while this scan is yielding for
        // media inspection, do not let the scan's older snapshot erase the
        // freshly merged Sanity fields (or a concurrently changed favorite).
        let latestByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        nextItems = nextItems.map { scanned in
            guard let latest = latestByID[scanned.id] else { return scanned }
            guard latest.remoteID != nil else {
                var updated = scanned
                updated.isFavorite = latest.isFavorite
                return updated
            }

            var updated = latest
            updated.localPath = scanned.localPath
            updated.fileModifiedAt = scanned.fileModifiedAt
            updated.fileSystemID = scanned.fileSystemID
            return updated
        }
        nextItems.sort { lhs, rhs in
            if lhs.source == .curated || rhs.source == .curated {
                if lhs.source != rhs.source { return lhs.source == .curated }
                let leftOrder = lhs.sortOrder ?? 100
                let rightOrder = rhs.sortOrder ?? 100
                return leftOrder == rightOrder
                    ? (lhs.remoteCreatedAt ?? "") > (rhs.remoteCreatedAt ?? "")
                    : leftOrder > rightOrder
            }
            return lhs.createdAt > rhs.createdAt
        }
        items = nextItems
        saveLibrary()
        removeOrphanedThumbnails(referencedBy: nextItems)
        if let refreshedActiveItem { engine.apply(refreshedActiveItem) }
        if changedCount > 0 {
            maintenanceMessage = AppLanguage.current.text(
                "Library folder synchronized",
                "素材文件夹已同步"
            )
        }
    }

    private func canonicalPath(for url: URL) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(url.path, &buffer) != nil {
            return decodedPath(from: buffer)
        }

        // The file may already have been deleted. Resolve its still-existing
        // parent so aliases such as /tmp and /private/tmp compare consistently.
        let parent = url.deletingLastPathComponent()
        if realpath(parent.path, &buffer) != nil {
            return URL(fileURLWithPath: decodedPath(from: buffer), isDirectory: true)
                .appendingPathComponent(url.lastPathComponent)
                .standardizedFileURL.path
        }
        return url.standardizedFileURL.path
    }

    private func decodedPath(from buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func removeOrphanedThumbnails(referencedBy items: [WallpaperItem]) {
        let referencedPaths = Set(items.compactMap(\.thumbnailURL).map { canonicalPath(for: $0) })
        guard let urls = try? fileManager.contentsOfDirectory(
            at: thumbnailDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in urls where !referencedPaths.contains(canonicalPath(for: url)) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func discoverMediaFiles() -> [MediaFileSnapshot] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .contentTypeKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: mediaDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [MediaFileSnapshot] = []
        for case let url as URL in enumerator {
            let legacyStarterNames = ["starter-0.jpg", "starter-1.jpg", "starter-2.jpg"]
            guard !legacyStarterNames.contains(url.lastPathComponent.localizedLowercase) else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let contentType = values.contentType else { continue }
            let kind: WallpaperKind
            if contentType.conforms(to: .image) {
                kind = .image
            } else if contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
                kind = .video
            } else {
                continue
            }
            let fileSystemID = values.fileResourceIdentifier.map { String(describing: $0) }
            results.append(MediaFileSnapshot(
                url: url,
                kind: kind,
                fileSize: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast,
                fileSystemID: fileSystemID
            ))
        }
        return results.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    private func loadLibrary() {
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([WallpaperItem].self, from: data) else { return }
        // Keep temporarily missing entries until reconciliation. Finder can
        // represent a rename as remove/add, and this preserves ID and favorites.
        items = decoded
    }

    private func saveLibrary() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func importFile(_ sourceURL: URL) async throws -> WallpaperItem {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let type = try sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType
        let kind: WallpaperKind
        if type?.conforms(to: .image) == true {
            kind = .image
        } else if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true {
            kind = .video
        } else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let id = UUID()
        let destination = uniqueMediaDestination(for: sourceURL)
        try fileManager.copyItem(at: sourceURL, to: destination)

        let values = try destination.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
        ])
        let fileSize = Int64(values.fileSize ?? 0)
        var width = 0
        var height = 0
        var duration: TimeInterval?
        var thumbnailPath: String?

        switch kind {
        case .image:
            if let source = CGImageSourceCreateWithURL(destination as CFURL, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
                height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            }
            thumbnailPath = try createImageThumbnail(for: destination, fileName: id.uuidString).path
        case .video:
            let metadata = try await inspectVideo(at: destination)
            width = metadata.width
            height = metadata.height
            duration = metadata.duration
            thumbnailPath = try await createVideoThumbnail(for: destination, id: id).path
        }

        let originalTitle = sourceURL.deletingPathExtension().lastPathComponent
        let isShowcaseVideo = originalTitle.localizedCaseInsensitiveContains("moewalls-com")
        let extractedPalette = thumbnailPath
            .flatMap { paletteFromImage(at: URL(fileURLWithPath: $0)) }
            ?? WallpaperPalette(startHex: "10141B", middleHex: "202A38", endHex: "080B10")

        return WallpaperItem(
            id: id,
            title: displayTitle(for: originalTitle),
            subtitle: isShowcaseVideo ? "Cinematic Motion Selection" : (kind == .video ? "Your motion wallpaper" : "Your image wallpaper"),
            kind: kind,
            source: .imported,
            localPath: destination.path,
            thumbnailPath: thumbnailPath,
            width: width,
            height: height,
            duration: duration,
            fileSize: fileSize,
            author: isShowcaseVideo ? "MoeWalls" : "My Library",
            licenseName: "User Import",
            sourceURL: nil,
            categories: isShowcaseVideo ? showcaseCategories(for: originalTitle) : ["我的壁纸"],
            palette: extractedPalette,
            isFavorite: false,
            createdAt: Date(),
            fileModifiedAt: values.contentModificationDate,
            fileSystemID: values.fileResourceIdentifier.map { String(describing: $0) }
        )
    }

    private func uniqueMediaDestination(for sourceURL: URL) -> URL {
        let originalName = sourceURL.lastPathComponent
        var candidate = mediaDirectory.appendingPathComponent(originalName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = sourceURL.pathExtension
        var index = 2
        repeat {
            let name = fileExtension.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(fileExtension)"
            candidate = mediaDirectory.appendingPathComponent(name)
            index += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    private func indexedItem(
        from snapshot: MediaFileSnapshot,
        preserving existing: WallpaperItem? = nil,
        derivePresentationFromFilename: Bool = true
    ) async throws -> WallpaperItem {
        let id = existing?.id ?? UUID()

        var width = 0
        var height = 0
        var duration: TimeInterval?
        var thumbnailPath: String?
        switch snapshot.kind {
        case .image:
            guard let source = CGImageSourceCreateWithURL(snapshot.url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
            height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            thumbnailPath = try createImageThumbnail(
                for: snapshot.url,
                fileName: id.uuidString,
                replacingExisting: existing != nil
            ).path
        case .video:
            let metadata = try await inspectVideo(at: snapshot.url)
            width = metadata.width
            height = metadata.height
            duration = metadata.duration
            thumbnailPath = try await createVideoThumbnail(for: snapshot.url, id: id).path
        }

        let originalTitle = snapshot.url.deletingPathExtension().lastPathComponent
        let isShowcaseVideo = originalTitle.localizedCaseInsensitiveContains("moewalls-com")
        let extractedPalette = thumbnailPath
            .flatMap { paletteFromImage(at: URL(fileURLWithPath: $0)) }
            ?? WallpaperPalette(startHex: "10141B", middleHex: "202A38", endHex: "080B10")
        let derivedSubtitle = isShowcaseVideo
            ? "Cinematic Motion Selection"
            : (snapshot.kind == .video ? "Your motion wallpaper" : "Your image wallpaper")

        return WallpaperItem(
            id: id,
            title: derivePresentationFromFilename ? displayTitle(for: originalTitle) : (existing?.title ?? displayTitle(for: originalTitle)),
            subtitle: derivePresentationFromFilename ? derivedSubtitle : (existing?.subtitle ?? derivedSubtitle),
            kind: snapshot.kind,
            source: existing?.source ?? .imported,
            localPath: snapshot.url.path,
            thumbnailPath: thumbnailPath,
            width: width,
            height: height,
            duration: duration,
            fileSize: snapshot.fileSize,
            author: derivePresentationFromFilename ? (isShowcaseVideo ? "MoeWalls" : "My Library") : (existing?.author ?? "My Library"),
            licenseName: existing?.licenseName ?? "User Import",
            sourceURL: existing?.sourceURL,
            categories: derivePresentationFromFilename
                ? (isShowcaseVideo ? showcaseCategories(for: originalTitle) : ["My Wallpapers"])
                : (existing?.categories ?? ["My Wallpapers"]),
            palette: extractedPalette,
            isFavorite: existing?.isFavorite ?? false,
            createdAt: existing?.createdAt ?? Date(),
            fileModifiedAt: snapshot.modifiedAt,
            fileSystemID: snapshot.fileSystemID,
            remoteID: existing?.remoteID,
            remoteMediaURL: existing?.remoteMediaURL,
            remoteThumbnailURL: existing?.remoteThumbnailURL,
            remoteUpdatedAt: existing?.remoteUpdatedAt,
            remoteFileName: existing?.remoteFileName,
            titleEn: existing?.titleEn,
            subtitleEn: existing?.subtitleEn,
            tags: existing?.tags,
            isFeatured: existing?.isFeatured,
            isCurated: existing?.isCurated,
            isPopular: existing?.isPopular,
            sortOrder: existing?.sortOrder,
            remoteCreatedAt: existing?.remoteCreatedAt
        )
    }

    private func displayTitle(for fileName: String) -> String {
        let cleaned = fileName
            .replacingOccurrences(of: "-moewalls-com", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return cleaned.capitalized
    }

    private func showcaseCategories(for fileName: String) -> [String] {
        let value = fileName.localizedLowercase
        if ["black-hole", "ufo", "cosmic", "singularity", "astronaut"].contains(where: value.contains) {
            return ["太空", "深色"]
        }
        if ["mist", "pines", "begonia", "flower", "underwater"].contains(where: value.contains) {
            return ["自然", "静谧"]
        }
        if ["rainy", "cityscape", "train", "nissan"].contains(where: value.contains) {
            return ["城市", "夜晚"]
        }
        return ["动漫", "深色"]
    }

    private func inspectVideo(at url: URL) async throws -> (width: Int, height: Int, duration: TimeInterval) {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { return (0, 0, duration) }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = CGRect(origin: .zero, size: size).applying(transform)
        return (Int(abs(transformed.width)), Int(abs(transformed.height)), duration)
    }

    private func createVideoThumbnail(for url: URL, id: UUID) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_280, height: 720)
        let time = CMTime(seconds: 0.25, preferredTimescale: 600)
        let image = try await generator.image(at: time).image
        let destination = thumbnailDirectory.appendingPathComponent("\(id.uuidString).jpg")
        try? fileManager.removeItem(at: destination)
        try writeJPEG(image, to: destination, quality: 0.86)
        return destination
    }

    private func migrateMissingThumbnails() {
        var didChange = false

        for index in items.indices where items[index].thumbnailPath == nil && items[index].kind == .image && items[index].isDownloaded {
            if let thumbnailURL = try? createImageThumbnail(
                for: items[index].localURL,
                fileName: items[index].id.uuidString
            ) {
                items[index].thumbnailPath = thumbnailURL.path
                didChange = true
            }
        }

        if didChange { saveLibrary() }
    }

    private func migrateWallpaperPalettes() {
        var didChange = false
        for index in items.indices {
            let palette = items[index].palette
            let usesLegacyPalette = palette.startHex == "151921" && palette.middleHex == "303747" && palette.endHex == "0A0C11"
            let previewURL = items[index].thumbnailURL ?? (items[index].kind == .image ? items[index].localURL : nil)
            guard usesLegacyPalette, let previewURL,
                  fileManager.fileExists(atPath: previewURL.path),
                  let extracted = paletteFromImage(at: previewURL) else { continue }
            items[index].palette = extracted
            didChange = true
        }
        if didChange { saveLibrary() }
    }

    private func paletteFromImage(at url: URL) -> WallpaperPalette? {
        guard let image = CIImage(contentsOf: url), !image.extent.isEmpty,
              let output = CIFilter(
                name: "CIAreaAverage",
                parameters: [kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: image.extent)]
              )?.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let average = NSColor(
            deviceRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let restrainedSaturation = min(max(saturation, 0.30), 0.68)

        return WallpaperPalette(
            startHex: colorHex(hue: hue, saturation: restrainedSaturation * 0.72, brightness: 0.10),
            middleHex: colorHex(hue: hue, saturation: restrainedSaturation, brightness: 0.22),
            endHex: colorHex(hue: hue, saturation: restrainedSaturation * 0.55, brightness: 0.055)
        )
    }

    private func colorHex(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> String {
        let color = NSColor(deviceHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return "10141B" }
        return String(
            format: "%02X%02X%02X",
            Int(rgb.redComponent * 255),
            Int(rgb.greenComponent * 255),
            Int(rgb.blueComponent * 255)
        )
    }

    func restoreActiveWallpaperIfNeeded() {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        guard UserDefaults.standard.object(forKey: "restoreLastWallpaper") as? Bool ?? true else { return }
        guard let rawID = UserDefaults.standard.string(forKey: "activeWallpaperID"),
              let id = UUID(uuidString: rawID),
              let item = items.first(where: { $0.id == id }) else { return }
        apply(item)
    }

    private func createImageThumbnail(for sourceURL: URL, fileName: String, replacingExisting: Bool = false) throws -> URL {
        let destination = thumbnailDirectory.appendingPathComponent(fileName).appendingPathExtension("jpg")
        if fileManager.fileExists(atPath: destination.path) && !replacingExisting { return destination }

        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_280,
              ] as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        if replacingExisting { try? fileManager.removeItem(at: destination) }
        try writeJPEG(thumbnail, to: destination, quality: 0.84)
        return destination
    }

    private func writeJPEG(_ image: CGImage, to url: URL, quality: CGFloat) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
