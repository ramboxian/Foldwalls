import AppKit
import SwiftUI

private enum AppDestination: String, CaseIterable, Identifiable {
    case home
    case explore
    case library

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .home: language.text("Home", "首页")
        case .explore: language.text("Explore", "探索")
        case .library: language.text("My", "我的")
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .explore: "safari.fill"
        case .library: "rectangle.stack.fill"
        }
    }
}

private enum WallpaperAutomationMode: String {
    case off
    case playlist
    case dayNight
    case appearance
}

private enum PlaylistOrder: String, CaseIterable, Identifiable, Codable {
    case sequential
    case shuffled

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .sequential: language.text("In order", "按顺序")
        case .shuffled: language.text("Shuffle", "随机播放")
        }
    }
}

private struct WallpaperPlaylist: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var wallpaperIDs: [UUID]
    var interval: Double
    var order: PlaylistOrder

    init(
        id: UUID = UUID(),
        name: String,
        wallpaperIDs: [UUID],
        interval: Double,
        order: PlaylistOrder
    ) {
        self.id = id
        self.name = name
        self.wallpaperIDs = wallpaperIDs
        self.interval = interval
        self.order = order
    }
}

private enum SavedMediaTab: String, CaseIterable, Identifiable {
    case favorites
    case history
    case uploaded

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .favorites: language.text("Liked", "喜欢")
        case .history: language.text("Used", "用过")
        case .uploaded: language.text("My Uploads", "我上传的")
        }
    }

    var symbol: String {
        switch self {
        case .favorites: "heart.fill"
        case .history: "clock.arrow.circlepath"
        case .uploaded: "square.and.arrow.up.fill"
        }
    }
}

private enum MediaPickerFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case history
    case uploaded

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .all: language.text("All", "全部")
        case .favorites: language.text("Liked", "喜欢")
        case .history: language.text("Used", "用过")
        case .uploaded: language.text("My Uploads", "我上传的")
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .favorites: "heart.fill"
        case .history: "clock.arrow.circlepath"
        case .uploaded: "square.and.arrow.up.fill"
        }
    }
}

private enum AutomationWallpaperSlot: String, Identifiable {
    case day
    case night
    case light
    case dark

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .day: language.text("Day wallpaper", "日间壁纸")
        case .night: language.text("Night wallpaper", "夜间壁纸")
        case .light: language.text("Light appearance wallpaper", "浅色模式壁纸")
        case .dark: language.text("Dark appearance wallpaper", "深色模式壁纸")
        }
    }

    var symbol: String {
        switch self {
        case .day: "sun.max.fill"
        case .night: "moon.stars.fill"
        case .light: "sun.min.fill"
        case .dark: "moon.fill"
        }
    }
}

private enum HomeCollection: String, Identifiable {
    case curated
    case latest
    case popular

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .curated: language.text("Featured", "精选")
        case .latest: language.text("Latest", "最新")
        case .popular: language.text("Popular", "热门")
        }
    }

    func subtitle(for language: AppLanguage) -> String {
        switch self {
        case .curated:
            language.text("Immersive motion selected for long focus", "适合长时间停留的沉浸动态画面")
        case .latest:
            language.text("The newest scenes, ordered by the studio", "按后台排序展示的最新画面")
        case .popular:
            language.text("Fresh picks from the studio's popular collection", "后台标记为热门的最新画面")
        }
    }

    func eyebrow(for language: AppLanguage) -> String {
        switch self {
        case .curated: language.text("CURATED COLLECTION", "编辑精选合集")
        case .latest: language.text("NEWEST FIRST", "最新内容优先")
        case .popular: language.text("POPULAR PICKS", "热门精选合集")
        }
    }
}

private enum ExploreOrdering: String, CaseIterable, Identifiable {
    case latest
    case popular

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .latest: language.text("Latest", "最新")
        case .popular: language.text("Popular", "最热")
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var library: WallpaperLibrary
    @EnvironmentObject private var engine: WallpaperEngine
    @EnvironmentObject private var updateManager: UpdateManager

    @State private var destination: AppDestination = .home
    @State private var selectedHomeCollection: HomeCollection?
    @State private var selectedItem: WallpaperItem?
    @State private var heroID: UUID?
    @State private var searchText = ""
    @State private var showsSearch = false
    @State private var showsNowPlaying = false
    @State private var showsMiniNowPlaying = false
    @State private var filter: LibraryFilter = .all
    @State private var selectedCategory = "全部"
    @State private var exploreOrdering: ExploreOrdering = .latest
    @State private var heroIsVisible = true
    @State private var homeStoryIsVisible = false
    @State private var homeScrollOffset: CGFloat = 0
    @State private var homeHeroOrder: [UUID] = []
    @State private var homeFeaturedOrder: [UUID] = []
    @State private var homeTrendingOrder: [UUID] = []
    @State private var homeMoodOrder: [UUID] = []
    @State private var homeRecentOrder: [UUID] = []
    @State private var homeVisitID = UUID()
    @State private var isInitialExperienceReady = false
    @State private var editingAutomationSlot: AutomationWallpaperSlot?
    @State private var showsPlaylistEditor = false
    @State private var editingPlaylistID: UUID?
    @State private var presentedPlaylistID: UUID?
    @State private var playlistPendingDeletionID: UUID?
    @State private var playlistDraftName = ""
    @State private var playlistDraftIDs: [UUID] = []
    @State private var playlistDraftInterval: Double = 900
    @State private var playlistDraftOrder = PlaylistOrder.sequential
    @State private var savedMediaTab = SavedMediaTab.favorites
    @State private var mediaPickerFilter = MediaPickerFilter.all
    @State private var lastAppliedAutomationKey = ""
    @FocusState private var searchFocused: Bool
    @AppStorage("appLanguage") private var languageRaw = AppLanguage.english.rawValue
    @AppStorage("wallpaperAutomationMode") private var automationModeRaw = WallpaperAutomationMode.off.rawValue
    @AppStorage("wallpaperPlaylistsJSON") private var playlistsJSON = ""
    @AppStorage("activeWallpaperPlaylistID") private var activePlaylistIDRaw = ""
    @AppStorage("wallpaperPlaylistIndex") private var playlistIndex = 0
    @AppStorage("wallpaperPlaylistLastSwitch") private var playlistLastSwitch: Double = 0
    @AppStorage("automationDayWallpaperID") private var automationDayWallpaperID = ""
    @AppStorage("automationNightWallpaperID") private var automationNightWallpaperID = ""
    @AppStorage("automationLightWallpaperID") private var automationLightWallpaperID = ""
    @AppStorage("automationDarkWallpaperID") private var automationDarkWallpaperID = ""

    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .english }

    private var categories: [String] {
        let available = Set(library.items.flatMap(\.categories))
        let preferred = ["自然", "城市", "太空", "抽象", "夜晚", "深色", "天空", "海洋", "森林", "动漫", "暖色", "蓝色", "静谧", "极简"]
        let known = preferred.filter(available.contains)
        let remaining = available.subtracting(known).sorted()
        return ["全部"] + known + remaining
    }

    private var cloudItems: [WallpaperItem] {
        library.items.filter { $0.remoteID != nil }
    }

    private func mediaItems(for tab: SavedMediaTab) -> [WallpaperItem] {
        switch tab {
        case .favorites:
            library.favorites
        case .history:
            library.recentlyUsedItems
        case .uploaded:
            library.personalItems
        }
    }

    private func mediaCount(for tab: SavedMediaTab) -> Int {
        mediaItems(for: tab).count
    }

    private func pickerMediaItems(for filter: MediaPickerFilter) -> [WallpaperItem] {
        switch filter {
        case .all:
            library.items
        case .favorites:
            library.favorites
        case .history:
            library.recentlyUsedItems
        case .uploaded:
            library.personalItems
        }
    }

    private var latestItems: [WallpaperItem] {
        cloudItems.sorted(by: latestFirst)
    }

    private var popularItems: [WallpaperItem] {
        cloudItems
            .filter { $0.isPopular == true }
            .sorted(by: submittedNewestFirst)
    }

    private var explorePopularItems: [WallpaperItem] {
        cloudItems.sorted { lhs, rhs in
            let leftIsPopular = lhs.isPopular == true
            let rightIsPopular = rhs.isPopular == true
            if leftIsPopular != rightIsPopular { return leftIsPopular }
            if leftIsPopular { return submittedNewestFirst(lhs, rhs) }
            return latestFirst(lhs, rhs)
        }
    }

    private var hero: WallpaperItem? {
        library.items.first { $0.id == heroID } ?? heroCandidates.first ?? library.items.first
    }

    private var heroCandidates: [WallpaperItem] {
        let recommended = cloudItems.filter { $0.isFeatured == true }
        return ordered(recommended.isEmpty ? latestItems : recommended, by: homeHeroOrder)
    }

    private var homeFeaturedItems: [WallpaperItem] {
        let curated = cloudItems.filter { $0.isCurated == true }.sorted(by: latestFirst)
        return ordered(curated, by: homeFeaturedOrder)
    }

    private var homeTrendingItems: [WallpaperItem] {
        ordered(popularItems, by: homeTrendingOrder)
    }

    private var homeMoodItems: [WallpaperItem] {
        ordered(library.items, by: homeMoodOrder)
    }

    private var homeRecentItems: [WallpaperItem] {
        ordered(latestItems, by: homeRecentOrder)
    }

    private var filteredItems: [WallpaperItem] {
        let source = exploreOrdering == .latest ? latestItems : explorePopularItems
        return source.filter { item in
            filter.includes(item)
                && (selectedCategory == "全部" || item.categories.contains(selectedCategory))
        }
    }

    private var searchResults: [WallpaperItem] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return library.items.filter { item in
            itemMatchesSearch(item, term: term)
        }.sorted { lhs, rhs in
            if lhs.remoteID != nil || rhs.remoteID != nil {
                if (lhs.remoteID != nil) != (rhs.remoteID != nil) { return lhs.remoteID != nil }
                return latestFirst(lhs, rhs)
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var exploreBackdropItem: WallpaperItem? {
        if let current = engine.currentItem {
            return library.items.first { $0.id == current.id } ?? current
        }
        return latestItems.first ?? library.items.first
    }

    private var hasSearchTerm: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func latestFirst(_ lhs: WallpaperItem, _ rhs: WallpaperItem) -> Bool {
        let leftOrder = lhs.sortOrder ?? 0
        let rightOrder = rhs.sortOrder ?? 0
        if leftOrder != rightOrder { return leftOrder > rightOrder }
        return submittedNewestFirst(lhs, rhs)
    }

    private func submittedNewestFirst(_ lhs: WallpaperItem, _ rhs: WallpaperItem) -> Bool {
        let leftDate = lhs.remoteCreatedAt ?? ""
        let rightDate = rhs.remoteCreatedAt ?? ""
        if leftDate != rightDate { return leftDate > rightDate }
        return lhs.createdAt > rhs.createdAt
    }

    private func itemMatchesSearch(_ item: WallpaperItem, term: String) -> Bool {
        item.title.localizedCaseInsensitiveContains(term)
            || item.titleEn?.localizedCaseInsensitiveContains(term) == true
            || item.subtitle.localizedCaseInsensitiveContains(term)
            || item.subtitleEn?.localizedCaseInsensitiveContains(term) == true
            || item.tags?.contains { $0.localizedCaseInsensitiveContains(term) } == true
            || item.categories.contains { $0.localizedCaseInsensitiveContains(term) }
            || item.author.localizedCaseInsensitiveContains(term)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ambientBackdrop

                Group {
                    if library.items.isEmpty && library.hasCompletedInitialCatalogLoad {
                        catalogUnavailableView(width: proxy.size.width)
                    } else if let selectedHomeCollection {
                        collectionView(selectedHomeCollection, width: proxy.size.width)
                    } else {
                        switch destination {
                        case .home:
                            homeView(width: proxy.size.width)
                        case .explore:
                            exploreView(width: proxy.size.width)
                        case .library:
                            libraryView(width: proxy.size.width)
                        }
                    }
                }
                .id(selectedHomeCollection?.id ?? destination.rawValue)

                if selectedHomeCollection == nil {
                    topBar
                }

                if showsSearch {
                    searchPage(width: proxy.size.width)
                        .zIndex(30)
                        .transition(.opacity)
                }

                if engine.currentItem != nil {
                    miniPlayer
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let selectedItem {
                    detailOverlay(selectedItem)
                        .zIndex(20)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }

                if let editingAutomationSlot {
                    automationWallpaperPicker(editingAutomationSlot, width: proxy.size.width)
                        .zIndex(40)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }

                if let playlist = presentedPlaylist {
                    playlistDetailOverlay(playlist, width: proxy.size.width)
                        .zIndex(42)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }

                if showsPlaylistEditor {
                    playlistEditor(width: proxy.size.width)
                        .zIndex(45)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }

                if let preparingItem = library.preparingItem {
                    wallpaperPreparationOverlay(preparingItem)
                        .zIndex(60)
                        .transition(.opacity)
                }

                if !isInitialExperienceReady {
                    launchPreparationView
                        .zIndex(100)
                        .transition(.opacity)
                }
            }
        }
        .frame(minWidth: 1_080, minHeight: 700)
        .preferredColorScheme(.dark)
        .alert(language.text("Import Failed", "导入失败"), isPresented: Binding(
            get: { library.importError != nil },
            set: { if !$0 { library.importError = nil } }
        )) {
            Button(language.text("OK", "知道了"), role: .cancel) { library.importError = nil }
        } message: {
            Text(library.importError ?? language.text("The file could not be read.", "无法读取该文件。"))
        }
        .confirmationDialog(
            language.text("Delete this playlist?", "删除这个播放列表？"),
            isPresented: Binding(
                get: { playlistPendingDeletionID != nil },
                set: { if !$0 { playlistPendingDeletionID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(language.text("Delete Playlist", "删除播放列表"), role: .destructive) {
                if let playlistPendingDeletionID {
                    deletePlaylist(id: playlistPendingDeletionID)
                }
            }
            Button(language.text("Cancel", "取消"), role: .cancel) {
                playlistPendingDeletionID = nil
            }
        } message: {
            Text(language.text("The wallpapers themselves will not be deleted.", "列表中的壁纸本身不会被删除。"))
        }
        .onAppear {
            reshuffleHomeContent()
            library.restoreActiveWallpaperIfNeeded()
            ensureAutomationSelections()
            evaluateWallpaperAutomation(force: true)
        }
        .task {
            await prepareInitialExperience()
        }
        .onChange(of: destination) { previous, current in
            if current == .home && previous != .home {
                reshuffleHomeContent()
            }
            Task { await library.refreshCatalog() }
        }
        .onChange(of: library.items.map { item in
            "\(item.id.uuidString)-\(item.isFeatured == true)-\(item.isCurated == true)-\(item.isPopular == true)-\(item.sortOrder ?? 0)-\(item.remoteUpdatedAt ?? "")"
        }) { _, _ in
            if destination == .home {
                reshuffleHomeContent()
            }
            ensureAutomationSelections()
            evaluateWallpaperAutomation(force: lastAppliedAutomationKey.isEmpty)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await library.refreshCatalog() }
            evaluateWallpaperAutomation()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            evaluateWallpaperAutomation()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(
            for: Notification.Name("AppleInterfaceThemeChangedNotification")
        )) { _ in
            evaluateWallpaperAutomation(force: true)
        }
        .task(id: heroRotationTaskID) {
            guard shouldRotateHero else { return }
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            guard !Task.isCancelled, shouldRotateHero else { return }
            advanceHero()
        }
    }

    private var launchPreparationView: some View {
        ZStack {
            WindowMaterialBackdrop()
            Color.black.opacity(0.82)
            LinearGradient(
                colors: [
                    Color(hex: "17243B").opacity(0.76),
                    CinematicTheme.deepCanvas.opacity(0.92),
                    Color.black,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [CinematicTheme.accent.opacity(0.18), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 360
            )

            VStack(spacing: 20) {
                BrandLogoImage()
                    .scaledToFill()
                    .frame(width: 86, height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                            .strokeBorder(CinematicTheme.specularEdge(intensity: 0.9), lineWidth: 0.9)
                    }
                    .shadow(color: .black.opacity(0.42), radius: 28, y: 14)

                VStack(spacing: 7) {
                    Text(language.brandName)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(
                        library.items.isEmpty && !library.hasCompletedInitialCatalogLoad
                            ? language.text("Loading your wallpaper collection", "正在读取壁纸目录")
                            : language.text("Preparing the first scenes", "正在准备首屏画面")
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CinematicTheme.secondaryText)
                }

                ProgressView()
                    .controlSize(.regular)
                    .tint(.white)
                    .frame(width: 42, height: 42)
                    .cinematicGlassCircle(interactive: false, tint: .white.opacity(0.04))
            }
        }
        .ignoresSafeArea()
    }

    private func catalogUnavailableView(width: CGFloat) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .semibold))
                .frame(width: 72, height: 72)
                .cinematicGlassCircle(interactive: false, tint: .white.opacity(0.04))

            VStack(spacing: 7) {
                Text(language.text("The collection is taking a little longer", "壁纸目录暂时没有准备好"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(language.text(
                    "Check your connection and try again. Your local wallpapers are still available.",
                    "请检查网络后重试，本地已有壁纸仍然可以正常使用。"
                ))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CinematicTheme.secondaryText)
                .multilineTextAlignment(.center)
            }

            Button {
                Task { await library.refreshCatalog() }
            } label: {
                HStack(spacing: 8) {
                    if library.isRefreshingCatalog {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(language.text("Try Again", "重新加载"))
                }
            }
            .buttonStyle(CinematicButtonStyle(prominent: true))
            .disabled(library.isRefreshingCatalog)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .padding(.top, 80)
    }

    private func wallpaperPreparationOverlay(_ item: WallpaperItem) -> some View {
        ZStack {
            Color.black.opacity(0.26)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

                VStack(spacing: 5) {
                    Text(language.text("Preparing wallpaper", "壁纸准备中"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(item.localizedTitle(for: language))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CinematicTheme.secondaryText)
                    Text(language.text("It will be applied automatically when ready", "准备完成后会自动应用"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CinematicTheme.tertiaryText)
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
            .cinematicGlassPanel(cornerRadius: 24, interactive: false, tint: .black.opacity(0.10))
            .shadow(color: .black.opacity(0.48), radius: 38, y: 18)
        }
        .contentShape(Rectangle())
        .onTapGesture { }
    }

    @MainActor
    private func prepareInitialExperience() async {
        guard !isInitialExperienceReady else { return }
        let startedAt = ContinuousClock.now
        await library.waitForInitialCatalogLoad()
        guard !Task.isCancelled else { return }

        reshuffleHomeContent()
        let firstScreenItems = [hero].compactMap { $0 }
            + Array(homeFeaturedItems.prefix(4))
            + Array(homeRecentItems.prefix(4))
        await library.prewarmArtwork(for: firstScreenItems, limit: 9)
        guard !Task.isCancelled else { return }

        let elapsed = startedAt.duration(to: .now)
        if elapsed < .milliseconds(650) {
            try? await Task.sleep(for: .milliseconds(650) - elapsed)
        }
        withAnimation(.easeOut(duration: 0.36)) {
            isInitialExperienceReady = true
        }
    }

    private var automationMode: WallpaperAutomationMode {
        WallpaperAutomationMode(rawValue: automationModeRaw) ?? .off
    }

    private var playlists: [WallpaperPlaylist] {
        guard let data = playlistsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([WallpaperPlaylist].self, from: data) else {
            return []
        }
        return decoded
    }

    private var activePlaylist: WallpaperPlaylist? {
        guard let id = UUID(uuidString: activePlaylistIDRaw) else { return nil }
        return playlists.first { $0.id == id }
    }

    private var presentedPlaylist: WallpaperPlaylist? {
        guard let presentedPlaylistID else { return nil }
        return playlists.first { $0.id == presentedPlaylistID }
    }

    private func playlistItems(for playlist: WallpaperPlaylist) -> [WallpaperItem] {
        let itemsByID = Dictionary(uniqueKeysWithValues: library.items.map { ($0.id, $0) })
        return playlist.wallpaperIDs.compactMap { itemsByID[$0] }
    }

    private func playlistIntervalLabel(_ interval: Double) -> String {
        switch interval {
        case 300: language.text("Every 5 minutes", "每 5 分钟")
        case 900: language.text("Every 15 minutes", "每 15 分钟")
        case 1_800: language.text("Every 30 minutes", "每 30 分钟")
        case 3_600: language.text("Every hour", "每 1 小时")
        default: language.text("Every 15 minutes", "每 15 分钟")
        }
    }

    private func persistPlaylists(_ value: [WallpaperPlaylist]) {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else { return }
        playlistsJSON = json
    }

    private var isLocalDaytime: Bool {
        let hour = Calendar.autoupdatingCurrent.component(.hour, from: Date())
        return (6..<18).contains(hour)
    }

    private var systemUsesDarkAppearance: Bool {
        let globalDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return (globalDomain?["AppleInterfaceStyle"] as? String) == "Dark"
    }

    private var activeAutomationSlot: AutomationWallpaperSlot? {
        switch automationMode {
        case .off: nil
        case .playlist: nil
        case .dayNight: isLocalDaytime ? .day : .night
        case .appearance: systemUsesDarkAppearance ? .dark : .light
        }
    }

    private func automationToggleBinding(for mode: WallpaperAutomationMode) -> Binding<Bool> {
        Binding(
            get: { automationMode == mode },
            set: { isEnabled in
                if isEnabled {
                    automationModeRaw = mode.rawValue
                    lastAppliedAutomationKey = ""
                    ensureAutomationSelections()
                    evaluateWallpaperAutomation(force: true)
                } else if automationMode == mode {
                    automationModeRaw = WallpaperAutomationMode.off.rawValue
                    lastAppliedAutomationKey = ""
                }
            }
        )
    }

    private func playlistToggleBinding(for playlist: WallpaperPlaylist) -> Binding<Bool> {
        Binding(
            get: {
                automationMode == .playlist && activePlaylistIDRaw == playlist.id.uuidString
            },
            set: { isEnabled in
                if isEnabled {
                    guard playlistItems(for: playlist).count >= 2 else {
                        openPlaylistEditor(playlist)
                        return
                    }
                    activePlaylistIDRaw = playlist.id.uuidString
                    automationModeRaw = WallpaperAutomationMode.playlist.rawValue
                    playlistIndex = 0
                    playlistLastSwitch = Date().timeIntervalSince1970
                    lastAppliedAutomationKey = ""
                    evaluateWallpaperAutomation(force: true)
                } else if automationMode == .playlist,
                          activePlaylistIDRaw == playlist.id.uuidString {
                    automationModeRaw = WallpaperAutomationMode.off.rawValue
                    lastAppliedAutomationKey = ""
                }
            }
        )
    }

    private func automationWallpaperID(for slot: AutomationWallpaperSlot) -> String {
        switch slot {
        case .day: automationDayWallpaperID
        case .night: automationNightWallpaperID
        case .light: automationLightWallpaperID
        case .dark: automationDarkWallpaperID
        }
    }

    private func setAutomationWallpaperID(_ id: String, for slot: AutomationWallpaperSlot) {
        switch slot {
        case .day: automationDayWallpaperID = id
        case .night: automationNightWallpaperID = id
        case .light: automationLightWallpaperID = id
        case .dark: automationDarkWallpaperID = id
        }
    }

    private func automationItem(for slot: AutomationWallpaperSlot) -> WallpaperItem? {
        guard let id = UUID(uuidString: automationWallpaperID(for: slot)) else { return nil }
        return library.items.first { $0.id == id }
    }

    private func ensureAutomationSelections() {
        guard !library.items.isEmpty else { return }
        let defaults = [
            library.items[0],
            library.items[min(1, library.items.count - 1)],
            library.items[min(2, library.items.count - 1)],
            library.items[min(3, library.items.count - 1)],
        ]
        for (slot, item) in zip(
            [AutomationWallpaperSlot.day, .night, .light, .dark],
            defaults
        ) where automationItem(for: slot) == nil {
            setAutomationWallpaperID(item.id.uuidString, for: slot)
        }
    }

    private func isCurrentAutomationSlot(_ slot: AutomationWallpaperSlot) -> Bool {
        activeAutomationSlot == slot
    }

    private func evaluateWallpaperAutomation(force: Bool = false) {
        if automationMode == .playlist {
            evaluatePlaylist(force: force)
            return
        }
        guard let slot = activeAutomationSlot,
              let item = automationItem(for: slot),
              library.preparingItemID == nil else {
            if automationMode == .off { lastAppliedAutomationKey = "" }
            return
        }
        let key = "\(automationMode.rawValue):\(slot.rawValue):\(item.id.uuidString)"
        guard force || key != lastAppliedAutomationKey else { return }
        lastAppliedAutomationKey = key
        if engine.currentItem?.id != item.id {
            library.apply(item)
        }
    }

    private func evaluatePlaylist(force: Bool = false) {
        guard let activePlaylist else { return }
        let items = playlistItems(for: activePlaylist)
        guard items.count >= 2, library.preparingItemID == nil else { return }

        let now = Date().timeIntervalSince1970
        var targetIndex = min(max(playlistIndex, 0), items.count - 1)
        let shouldAdvance = !force
            && playlistLastSwitch > 0
            && now - playlistLastSwitch >= activePlaylist.interval

        if shouldAdvance {
            switch activePlaylist.order {
            case .sequential:
                targetIndex = (targetIndex + 1) % items.count
            case .shuffled:
                let candidates = items.indices.filter { $0 != targetIndex }
                targetIndex = candidates.randomElement() ?? targetIndex
            }
            playlistIndex = targetIndex
        }

        let item = items[targetIndex]
        let key = "playlist:\(activePlaylist.id.uuidString):\(targetIndex):\(item.id.uuidString)"
        guard force || shouldAdvance || key != lastAppliedAutomationKey else { return }
        lastAppliedAutomationKey = key
        playlistLastSwitch = now
        if engine.currentItem?.id != item.id {
            library.apply(item)
        }
    }

    private func openPlaylistEditor(_ playlist: WallpaperPlaylist? = nil) {
        editingPlaylistID = playlist?.id
        playlistDraftName = playlist?.name ?? language.text("My Playlist", "我的播放列表")
        playlistDraftIDs = playlist?.wallpaperIDs ?? []
        playlistDraftInterval = playlist?.interval ?? 900
        playlistDraftOrder = playlist?.order ?? .sequential
        presentedPlaylistID = nil
        withAnimation(.snappy(duration: 0.26)) { showsPlaylistEditor = true }
    }

    private func savePlaylist() {
        let availableIDs = Set(library.items.map(\.id))
        let orderedIDs = playlistDraftIDs.filter(availableIDs.contains)
        guard orderedIDs.count >= 2 else { return }
        let resolvedName = playlistDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? language.text("My Playlist", "我的播放列表")
            : playlistDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = playlists
        let savedPlaylist = WallpaperPlaylist(
            id: editingPlaylistID ?? UUID(),
            name: resolvedName,
            wallpaperIDs: orderedIDs,
            interval: playlistDraftInterval,
            order: playlistDraftOrder
        )
        if let editingPlaylistID,
           let index = updated.firstIndex(where: { $0.id == editingPlaylistID }) {
            updated[index] = savedPlaylist
        } else {
            updated.append(savedPlaylist)
        }
        persistPlaylists(updated)
        lastAppliedAutomationKey = ""
        withAnimation(.easeOut(duration: 0.2)) {
            showsPlaylistEditor = false
            presentedPlaylistID = savedPlaylist.id
        }
        if automationMode == .playlist && activePlaylistIDRaw == savedPlaylist.id.uuidString {
            playlistIndex = 0
            playlistLastSwitch = Date().timeIntervalSince1970
            evaluateWallpaperAutomation(force: true)
        }
    }

    private func deletePlaylist(id: UUID) {
        var updated = playlists
        updated.removeAll { $0.id == id }
        persistPlaylists(updated)
        if activePlaylistIDRaw == id.uuidString {
            automationModeRaw = WallpaperAutomationMode.off.rawValue
            activePlaylistIDRaw = ""
            lastAppliedAutomationKey = ""
        }
        presentedPlaylistID = nil
        playlistPendingDeletionID = nil
    }

    private var glassModalBackdrop: some View {
        Rectangle()
            .fill(.thinMaterial)
            .overlay(Color.black.opacity(0.18))
            .ignoresSafeArea()
    }

    private func automationWallpaperPicker(_ slot: AutomationWallpaperSlot, width: CGFloat) -> some View {
        ZStack {
            glassModalBackdrop
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { editingAutomationSlot = nil }
                }

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: slot.symbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(CinematicTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(CinematicTheme.accent.opacity(0.10), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(slot.title(for: language))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text(language.text(
                            "Browse every wallpaper, or filter by liked, used, and uploaded",
                            "默认展示全部壁纸，也可筛选喜欢、用过和我上传的"
                        ))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CinematicTheme.secondaryText)
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { editingAutomationSlot = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 44, height: 44)
                            .cinematicGlassCircle(tint: .black.opacity(0.10))
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                }
                .padding(24)

                mediaPickerFilterBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)

                Divider().overlay(.white.opacity(0.10))

                ScrollView {
                    let visibleItems = pickerMediaItems(for: mediaPickerFilter)
                    if visibleItems.isEmpty {
                        mediaPickerEmptyState(for: mediaPickerFilter)
                            .padding(24)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 18)],
                            spacing: 18
                        ) {
                            ForEach(visibleItems) { item in
                                Button {
                                    setAutomationWallpaperID(item.id.uuidString, for: slot)
                                    lastAppliedAutomationKey = ""
                                    withAnimation(.easeOut(duration: 0.2)) { editingAutomationSlot = nil }
                                    evaluateWallpaperAutomation(force: true)
                                } label: {
                                    automationPickerTile(item, slot: slot)
                                }
                                .buttonStyle(CinematicInteractiveButtonStyle())
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .frame(width: min(width - 120, 1_040), height: 640)
            .cinematicGlassPanel(cornerRadius: 30, interactive: false, tint: .white.opacity(0.025))
            .shadow(color: .black.opacity(0.40), radius: 42, y: 22)
        }
        .ignoresSafeArea()
    }

    private func automationPickerTile(_ item: WallpaperItem, slot: AutomationWallpaperSlot) -> some View {
        let isSelected = automationWallpaperID(for: slot) == item.id.uuidString
        return ZStack(alignment: .bottomLeading) {
            ArtworkView(item: item, cornerRadius: 18)
            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(item.localizedTitle(for: language))
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .padding(13)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 26, height: 26)
                    .background(CinematicTheme.accent, in: Circle())
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? AnyShapeStyle(CinematicTheme.accent)
                        : AnyShapeStyle(CinematicTheme.specularEdge(intensity: 0.36)),
                    lineWidth: isSelected ? 2 : 0.7
                )
        }
    }

    private var ambientBackdrop: some View {
        ZStack {
            WindowMaterialBackdrop()
            Color.black.opacity(0.74)
            if let hero {
                LinearGradient(
                    colors: [
                        Color(hex: hero.palette.startHex).opacity(0.50),
                        Color(hex: hero.palette.middleHex).opacity(0.30),
                        Color(hex: hero.palette.endHex).opacity(0.18),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                    .id("ambient-\(hero.id)")
                    .transition(.opacity)

                RadialGradient(
                    colors: [Color(hex: hero.palette.middleHex).opacity(0.28), .clear],
                    center: .topTrailing,
                    startRadius: 40,
                    endRadius: 720
                )
            }
            LinearGradient(
                colors: [.black.opacity(0.12), CinematicTheme.deepCanvas.opacity(0.34), CinematicTheme.deepCanvas.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(min(max(homeScrollOffset / 520, 0), 0.82))
            LinearGradient(
                colors: [.white.opacity(0.035), .clear, .white.opacity(0.018)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.55), value: heroID)
    }

    private var topBar: some View {
        ZStack {
            HStack(spacing: 11) {
                HStack(spacing: 10) {
                    BrandLogoImage()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text(language.brandName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                .padding(.leading, 7)
                .padding(.trailing, 18)
                .frame(height: 62)
                .cinematicGlassCapsule(interactive: false, tint: .black.opacity(0.22))
                .shadow(color: .black.opacity(0.22), radius: 22, y: 10)

                Spacer()

                LiquidGlassGroup(spacing: 10) {
                    HStack(spacing: 10) {
                        if engine.currentItem != nil {
                            topCircleButton(symbol: engine.isPlaying ? "waveform" : "waveform.slash", tint: CinematicTheme.accent.opacity(0.12)) {
                                showsNowPlaying.toggle()
                            }
                            .popover(isPresented: $showsNowPlaying, arrowEdge: .top) {
                                NowPlayingPanelView()
                                    .environmentObject(library)
                                    .environmentObject(engine)
                            }
                        }

                        if updateManager.shouldShowToolbarButton {
                            Button {
                                updateManager.installAvailableUpdate()
                            } label: {
                                UpdateProgressGlyph(manager: updateManager, size: 23)
                                    .frame(width: 54, height: 54)
                                    .background(CinematicTheme.success.opacity(0.88), in: Circle())
                                    .overlay {
                                        Circle()
                                            .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                                    }
                                    .shadow(color: CinematicTheme.success.opacity(0.28), radius: 18, y: 8)
                            }
                            .buttonStyle(CinematicInteractiveButtonStyle())
                            .disabled(updateManager.isBusy)
                            .help(updateManager.statusText)
                        }

                        topCircleButton(symbol: showsSearch ? "xmark" : "magnifyingglass") {
                            if showsSearch {
                                closeSearch()
                            } else {
                                openSearch()
                            }
                        }

                        SettingsLink {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 54, height: 54)
                                .cinematicGlassCircle()
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                    }
                }
            }
            HStack(spacing: 4) {
                    ForEach(AppDestination.allCases) { item in
                        Button {
                            withAnimation(.snappy(duration: 0.38, extraBounce: 0.03)) {
                                if item == .home && destination == .home {
                                    reshuffleHomeContent()
                                    Task { await library.refreshCatalog() }
                                } else {
                                    destination = item
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(item.title(for: language))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                                .foregroundStyle(destination == item ? Color.black.opacity(0.86) : Color.white.opacity(0.82))
                                .padding(.horizontal, 20)
                                .frame(height: 48)
                                .background(destination == item ? .white.opacity(0.94) : .clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle(hoverScale: 1.02, pressedScale: 0.97))
                    }
            }
            .padding(7)
            .cinematicGlassCapsule(interactive: false, tint: .black.opacity(0.16))
            .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
        }
        .padding(.horizontal, CinematicTheme.pageGutter)
        .padding(.top, 18)
        .foregroundStyle(.white)
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.48), .black.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 126)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private func topCircleButton(symbol: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                        .font(.system(size: 18, weight: .bold))
                .frame(width: 54, height: 54)
                .cinematicGlassCircle(tint: tint)
        }
        .buttonStyle(CinematicInteractiveButtonStyle())
    }

    private func searchPage(width: CGFloat) -> some View {
        ZStack {
            WindowMaterialBackdrop()
                .ignoresSafeArea()

            if let backdrop = exploreBackdropItem {
                ArtworkView(item: backdrop, cornerRadius: 0)
                    .scaleEffect(1.08)
                    .blur(radius: 42)
                    .opacity(0.34)
                    .ignoresSafeArea()
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.52),
                    CinematicTheme.deepCanvas.opacity(0.72),
                    Color.black.opacity(0.82),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text("Search", "搜索"))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(language.text("Titles, descriptions, categories and tags", "可搜索名称、简介、分类与标签"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.52))
                    }

                    Spacer()

                    Button { closeSearch() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 54, height: 54)
                            .cinematicGlassCircle(tint: .black.opacity(0.10))
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                    .help(language.text("Close Search", "关闭搜索"))
                }
                .padding(.horizontal, CinematicTheme.pageGutter)
                .padding(.top, 22)

                HStack(spacing: 15) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.64))

                    TextField(language.text("Search wallpapers", "搜索壁纸关键词"), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .semibold))
                        .focused($searchFocused)
                        .onSubmit { searchFocused = false }

                    if !searchText.isEmpty {
                        Button { searchText = ""; searchFocused = true } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.52))
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                    }
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: 760, minHeight: 60)
                .cinematicGlassCapsule(tint: .white.opacity(0.035))
                .shadow(color: .black.opacity(0.34), radius: 34, y: 16)
                .padding(.top, 34)

                Group {
                    if !hasSearchTerm {
                        searchEmptyState(
                            symbol: "sparkle.magnifyingglass",
                            title: language.text("Find your next scene", "找到你的下一幅画面"),
                            subtitle: language.text("Try a mood, color, character or place.", "试试输入氛围、颜色、角色或地点。")
                        )
                    } else if searchResults.isEmpty {
                        searchEmptyState(
                            symbol: "magnifyingglass",
                            title: language.text("No results", "搜索无结果"),
                            subtitle: language.text("No wallpaper matches “\(searchText)”. Try another keyword.", "没有找到与“\(searchText)”匹配的壁纸，请换一个关键词。")
                        )
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 22) {
                                Text(language.text("\(searchResults.count) results", "找到 \(searchResults.count) 个结果"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.58))

                                LazyVGrid(columns: contentColumns(for: width), alignment: .leading, spacing: 26) {
                                    ForEach(searchResults) { item in
                                        WallpaperCard(
                                            item: item,
                                            isActive: engine.currentItem?.id == item.id,
                                            onSelect: {
                                                closeSearch()
                                                selectedItem = item
                                            },
                                            onApply: { library.apply(item) },
                                            onFavorite: { library.toggleFavorite(item) }
                                        )
                                    }
                                }
                                .padding(.bottom, 60)
                            }
                            .padding(.horizontal, CinematicTheme.pageGutter)
                            .padding(.top, 34)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
        .onExitCommand { closeSearch() }
    }

    private func searchEmptyState(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.white.opacity(0.62))
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: 660, minHeight: 250)
        .cinematicGlassPanel(cornerRadius: 32, interactive: false, tint: .white.opacity(0.025))
    }

    private func openSearch() {
        selectedItem = nil
        searchText = ""
        withAnimation(.easeInOut(duration: 0.24)) { showsSearch = true }
        DispatchQueue.main.async { searchFocused = true }
    }

    private func closeSearch() {
        searchFocused = false
        withAnimation(.easeInOut(duration: 0.20)) { showsSearch = false }
    }

    private func homeView(width: CGFloat) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: HomeScrollOffsetKey.self,
                        value: -proxy.frame(in: .named("homeScroll")).minY
                    )
                }
                .frame(height: 0)

                if let hero { heroView(hero, width: width) }

                VStack(alignment: .leading, spacing: CinematicTheme.sectionSpacing) {
                    mediaRail(
                        collection: .curated,
                        title: language.text("Featured", "精选"),
                        subtitle: language.text("Immersive motion, selected for long focus", "安静、清晰，适合长时间停留的画面"),
                        items: matching(homeFeaturedItems),
                        width: width
                    )

                    mediaRail(
                        collection: .latest,
                        title: language.text("Latest", "最新"),
                        subtitle: language.text("New uploads and the studio's newest order", "新上传内容默认靠前，也可在后台调整顺序"),
                        items: matching(homeRecentItems),
                        width: width
                    )

                    rankingSection(width: width)
                    categorySection(width: width)
                    homeStoryVideoSection(width: width)
                }
                .padding(.top, 58)
                .padding(.bottom, 20)
            }
        }
        .coordinateSpace(name: "homeScroll")
        .onPreferenceChange(HomeScrollOffsetKey.self) { homeScrollOffset = max(0, $0) }
        .ignoresSafeArea(edges: .top)
    }

    private func heroView(_ item: WallpaperItem, width: CGFloat) -> some View {
        let heroHeight = width * 9 / 16
        let selectorWidth = max(160, min(220, (width - CinematicTheme.pageGutter * 2 - 80) / 6))
        return ZStack {
            HeroMediaView(
                item: item,
                isPlaying: heroIsVisible && destination == .home && selectedItem == nil,
                videoAsset: .original
            )
                .frame(width: width, height: heroHeight)
                .clipped()
                .id(item.id)
                .transition(.opacity)
                .trackScrollVisibility { isVisible in
                    heroIsVisible = isVisible
                }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.18), location: 0),
                    .init(color: .clear, location: 0.43),
                    .init(color: Color(hex: item.palette.middleHex).opacity(0.16), location: 0.70),
                    .init(color: CinematicTheme.deepCanvas.opacity(0.72), location: 0.92),
                    .init(color: CinematicTheme.deepCanvas.opacity(0.92), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(colors: [.black.opacity(0.64), .clear], startPoint: .leading, endPoint: .center)

            HStack {
                VStack(alignment: .leading, spacing: 11) {
                        Text(language.text("FEATURED PREMIERE", "本周首映"))
                            .font(.system(size: 11, weight: .bold))
                            .tracking(2.2)
                            .foregroundStyle(.white.opacity(0.62))
                        Text(item.localizedTitle(for: language))
                            .font(.system(size: 50, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        Text(item.localizedSubtitle(for: language))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                        Text(item.metadataLine)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.48))

                        HStack(spacing: 10) {
                            Button { library.apply(item) } label: {
                                HStack(spacing: 8) {
                                    if library.isPreparing(item) {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: engine.currentItem?.id == item.id ? "checkmark" : "desktopcomputer")
                                    }
                                    Text(
                                        library.isPreparing(item)
                                            ? language.text("Preparing…", "正在准备…")
                                            : (engine.currentItem?.id == item.id ? language.text("Active", "正在播放") : language.text("Set Wallpaper", "设为壁纸"))
                                    )
                                }
                            }
                            .buttonStyle(CinematicButtonStyle(prominent: true))
                            .disabled(library.preparingItemID != nil)

                            Button { selectedItem = item } label: {
                                Label(language.text("View Details", "查看详情"), systemImage: "arrow.up.right")
                            }
                            .buttonStyle(CinematicButtonStyle(prominent: false))
                        }
                        .padding(.top, 5)
                }
                .frame(width: min(460, width * 0.40), alignment: .leading)
                Spacer()
            }
            .padding(.horizontal, CinematicTheme.pageGutter)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, max(170, heroHeight * 0.28))

            // The hero intentionally dissolves into the canvas instead of ending
            // on a hard horizontal edge. The material layer gives the transition
            // a quiet glass refraction while the long gradient carries the image's
            // palette into the first content section.
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color(hex: item.palette.middleHex).opacity(0.12), location: 0.32),
                        .init(color: CinematicTheme.deepCanvas.opacity(0.68), location: 0.78),
                        .init(color: CinematicTheme.deepCanvas, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.34)
                    .mask {
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.24), .white],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .frame(height: 320)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(heroCandidates) { candidate in
                        Button {
                            withAnimation(.easeInOut(duration: 0.52)) { heroID = candidate.id }
                        } label: {
                            ArtworkView(item: candidate, cornerRadius: 18)
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(
                                            CinematicTheme.specularEdge(intensity: candidate.id == item.id ? 1.5 : 0.5),
                                            lineWidth: candidate.id == item.id ? 1.8 : 0.8
                                        )
                                }
                                .shadow(color: .black.opacity(candidate.id == item.id ? 0.34 : 0), radius: 14, y: 7)
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle(hoverScale: 1.055, pressedScale: 0.97))
                        .frame(width: selectorWidth)
                    }
                }
                .padding(.horizontal, CinematicTheme.pageGutter)
                .padding(.vertical, 14)
            }
            .frame(height: selectorWidth * 9 / 16 + 28)
            .padding(.bottom, 20)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: heroHeight)
    }

    private func mediaRail(collection: HomeCollection, title: String, subtitle: String, items: [WallpaperItem], width: CGFloat) -> some View {
        let cardWidth = railCardWidth(for: width)
        return VStack(alignment: .leading, spacing: 18) {
            sectionHeader(title, subtitle: subtitle) { openCollection(collection) }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 22) {
                    ForEach(Array(items.prefix(8))) { item in
                        card(item)
                            .frame(width: cardWidth)
                    }
                }
                .padding(.horizontal, CinematicTheme.pageGutter)
                .padding(.vertical, 14)
            }
        }
    }

    private func homeStoryVideoSection(width: CGFloat) -> some View {
        Group {
            if let url = Bundle.main.url(forResource: "HomeStory", withExtension: "mp4") {
                HomeStoryVideoPlayer(
                    url: url,
                    isActive: homeStoryIsVisible
                        && destination == .home
                        && selectedHomeCollection == nil
                        && selectedItem == nil
                )
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(CinematicTheme.specularEdge(intensity: 0.72), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.38), radius: 34, y: 18)
                .accessibilityLabel(language.text("Foldwalls film", "浮岛桌面影片"))
                .trackScrollVisibility(threshold: 0.35) { isVisible in
                    homeStoryIsVisible = isVisible
                }
            }
        }
        .padding(.horizontal, CinematicTheme.pageGutter)
        .frame(maxWidth: width)
    }

    private func rankingSection(width: CGFloat) -> some View {
        let rankedItems = Array(matching(homeTrendingItems).prefix(8))
        let cardWidth = railCardWidth(for: width)
        return VStack(alignment: .leading, spacing: 18) {
            sectionHeader(language.text("Popular", "热门"), subtitle: language.text("Manually selected in the studio, newest submissions first", "后台手动勾选，按提交时间从新到旧")) { openCollection(.popular) }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 22) {
                    ForEach(Array(rankedItems.enumerated()), id: \.element.id) { index, item in
                        WallpaperCard(
                            item: item,
                            isActive: engine.currentItem?.id == item.id,
                            rank: index + 1,
                            onSelect: { selectedItem = item },
                            onApply: { library.apply(item) },
                            onFavorite: { library.toggleFavorite(item) }
                        )
                        .frame(width: cardWidth)
                    }
                }
                .padding(.horizontal, CinematicTheme.pageGutter)
                .padding(.vertical, 14)
            }
        }
    }

    private func categorySection(width: CGFloat) -> some View {
        let source = homeMoodItems
        let labels = ["自然", "城市", "太空", "抽象", "夜晚", "深色"]
        return VStack(alignment: .leading, spacing: 18) {
            sectionHeader(language.text("Explore by Mood", "按氛围探索"), subtitle: language.text("Start with a feeling, find a new desktop", "从场景开始寻找你的下一张壁纸")) { destination = .explore }
            LazyVGrid(columns: contentColumns(for: width), spacing: 22) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    if !source.isEmpty {
                        let item = source[index % source.count]
                        Button {
                            selectedCategory = label
                            destination = .explore
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                ArtworkView(item: item, cornerRadius: CinematicTheme.cardRadius)
                                    .aspectRatio(16 / 9, contentMode: .fit)
                                LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .center, endPoint: .bottom)
                                    .clipShape(RoundedRectangle(cornerRadius: CinematicTheme.cardRadius, style: .continuous))
                                Text(label.localizedCategory(for: language))
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(20)
                            }
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                    }
                }
            }
            .padding(.horizontal, CinematicTheme.pageGutter)
        }
    }

    private func collectionView(_ collection: HomeCollection, width: CGFloat) -> some View {
        let items = items(for: collection)
        let leadItem = items.first ?? library.items.first

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                collectionMasthead(collection, leadItem: leadItem, itemCount: items.count, width: width)

                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("All Scenes", "全部画面"))
                                .font(.system(size: 27, weight: .bold, design: .rounded))
                            Text(language.text(
                                "Browse the complete collection · \(items.count) scenes",
                                "浏览完整合集 · 共 \(items.count) 个画面"
                            ))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CinematicTheme.secondaryText)
                        }
                        Spacer()
                        Text(language.text("UPDATED LOCALLY", "本地实时更新"))
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(CinematicTheme.tertiaryText)
                    }

                    if items.isEmpty {
                        Button { library.presentImportPanel() } label: {
                            VStack(spacing: 14) {
                                Image(systemName: "plus.rectangle.on.rectangle")
                                    .font(.system(size: 34, weight: .light))
                                Text(language.text("Import your first wallpaper", "导入你的第一张壁纸"))
                                    .font(.system(size: 16, weight: .semibold))
                                Text(language.text("Images and videos stay private on this Mac", "图片和视频只保存在这台 Mac 上"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(CinematicTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, minHeight: 230)
                            .cinematicGlassPanel(cornerRadius: 30, interactive: true, tint: .black.opacity(0.05))
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                    } else {
                        LazyVGrid(columns: contentColumns(for: width), alignment: .leading, spacing: 24) {
                            ForEach(items) { item in
                                card(item)
                            }
                        }
                    }
                }
                .padding(.horizontal, CinematicTheme.pageGutter)
                .padding(.top, 34)
                .padding(.bottom, engine.currentItem == nil ? 90 : 160)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private func collectionMasthead(
        _ collection: HomeCollection,
        leadItem: WallpaperItem?,
        itemCount: Int,
        width: CGFloat
    ) -> some View {
        let height = min(560, max(420, width * 0.40))

        return ZStack(alignment: .topLeading) {
            if let leadItem {
                HeroMediaView(item: leadItem, isPlaying: selectedItem == nil)
                    .frame(width: width, height: height)
                    .clipped()

                LinearGradient(
                    colors: [
                        .black.opacity(0.34),
                        .clear,
                        Color(hex: leadItem.palette.middleHex).opacity(0.16),
                        CinematicTheme.deepCanvas,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [Color(hex: "25334A"), CinematicTheme.deepCanvas],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            LinearGradient(
                colors: [.black.opacity(0.64), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )

            Button {
                withAnimation(.snappy(duration: 0.34, extraBounce: 0.02)) {
                    selectedHomeCollection = nil
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 54, height: 54)
                    .cinematicGlassCircle(tint: .black.opacity(0.08))
            }
            .buttonStyle(CinematicInteractiveButtonStyle())
            .help(language.text("Back to Home", "返回首页"))
            .padding(.leading, CinematicTheme.pageGutter)
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 12) {
                Text(collection.eyebrow(for: language))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2.6)
                    .foregroundStyle(.white.opacity(0.62))
                Text(collection.title(for: language))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(collection.subtitle(for: language))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                HStack(spacing: 9) {
                    Image(systemName: "rectangle.stack.fill")
                    Text(language.text("\(itemCount) scenes", "\(itemCount) 个画面"))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))
                .padding(.horizontal, 13)
                .frame(height: 34)
                .cinematicGlassCapsule(interactive: false, tint: .black.opacity(0.08))
            }
            .padding(.horizontal, CinematicTheme.pageGutter)
            .padding(.bottom, 54)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: height)
    }

    private func exploreView(width: CGFloat) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                exploreMasthead(width: width)

                VStack(alignment: .leading, spacing: 28) {
                    filterShelf

                    LazyVGrid(columns: contentColumns(for: width, spacing: 28), alignment: .leading, spacing: 28) {
                        ForEach(filteredItems) { item in card(item) }
                    }
                }
                .padding(.horizontal, CinematicTheme.pageGutter)
                .padding(.top, 30)
                .padding(.bottom, engine.currentItem == nil ? 90 : 160)
            }
        }
        // The masthead finishes on this exact opaque color. Keeping the
        // archive on the same base prevents the ambient app backdrop from
        // showing through as a different band below the video.
        .background(CinematicTheme.deepCanvas)
        .ignoresSafeArea(edges: .top)
    }

    private func exploreMasthead(width: CGFloat) -> some View {
        let featured = exploreBackdropItem
        let height = min(610, max(470, width * 0.46))
        return Group {
            if let featured {
                ZStack {
                    HeroMediaView(item: featured, isPlaying: destination == .explore && selectedItem == nil)
                        .frame(height: height)
                        .clipped()

                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.30), location: 0),
                            .init(color: .black.opacity(0.08), location: 0.28),
                            .init(color: .clear, location: 0.52),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.42),
                            .init(color: Color(hex: featured.palette.middleHex).opacity(0.10), location: 0.58),
                            .init(color: CinematicTheme.deepCanvas.opacity(0.30), location: 0.70),
                            .init(color: CinematicTheme.deepCanvas.opacity(0.62), location: 0.82),
                            .init(color: CinematicTheme.deepCanvas.opacity(0.88), location: 0.92),
                            .init(color: CinematicTheme.deepCanvas, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(spacing: 14) {
                        Text(language.text("THE MOTION ARCHIVE", "动态影像馆"))
                            .font(.system(size: 11, weight: .bold))
                            .tracking(3)
                            .foregroundStyle(.white.opacity(0.64))
                        Text(language.text("Explore", "探索"))
                            .font(.system(size: 58, weight: .bold, design: .rounded))
                        Text(language.text("Find a scene that changes the feeling of your Mac.", "找到一幅真正改变 Mac 氛围的画面。"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))

                        Button { selectedItem = featured } label: {
                            Label(language.text("View Featured Scene", "查看本期精选"), systemImage: "arrow.up.right")
                        }
                        .buttonStyle(CinematicButtonStyle(prominent: false))
                        .padding(.top, 8)
                    }
                    .padding(.top, 42)
                }
                .frame(height: height)
                .contentShape(Rectangle())
            }
        }
    }

    private var filterShelf: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(language.text("Browse the archive", "浏览影像馆"))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(language.text(
                        "\(filteredItems.count) scenes match these filters",
                        "已筛选出 \(filteredItems.count) 个画面"
                    ))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CinematicTheme.secondaryText)
                }

                Spacer(minLength: 20)

                HStack(spacing: 4) {
                    ForEach(ExploreOrdering.allCases) { ordering in
                        Button {
                            withAnimation(.snappy(duration: 0.26, extraBounce: 0.02)) {
                                exploreOrdering = ordering
                            }
                        } label: {
                            Text(ordering.title(for: language))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(exploreOrdering == ordering ? .black.opacity(0.86) : .white.opacity(0.70))
                                .padding(.horizontal, 20)
                                .frame(height: 40)
                                .background(exploreOrdering == ordering ? .white.opacity(0.95) : .clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle(hoverScale: 1.02, pressedScale: 0.97))
                    }
                }
                .padding(5)
                .cinematicGlassCapsule(interactive: false, tint: .black.opacity(0.14))
            }

            HStack(spacing: 14) {
                Label(language.text("Category", "分类"), systemImage: "tag.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CinematicTheme.secondaryText)
                    .fixedSize()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(categories, id: \.self) { category in
                            filterChip(category.localizedCategory(for: language), selected: selectedCategory == category) {
                                withAnimation(.snappy(duration: 0.24)) { selectedCategory = category }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 24)
                    .overlay(.white.opacity(0.10))

                Menu {
                    ForEach(LibraryFilter.allCases) { item in
                        Button {
                            withAnimation(.snappy(duration: 0.24)) { filter = item }
                        } label: {
                            if filter == item {
                                Label(item.label(for: language), systemImage: "checkmark")
                            } else {
                                Text(item.label(for: language))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: libraryFilterSymbol(filter))
                            .font(.system(size: 12, weight: .semibold))
                        Text(filter.label(for: language))
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    .foregroundStyle(.white.opacity(0.80))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(.white.opacity(0.07), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.7)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 14)
            .frame(height: 64)
            .cinematicGlassPanel(cornerRadius: 22, interactive: false, tint: .black.opacity(0.08))
        }
        .padding(.vertical, 2)
    }

    private func libraryFilterSymbol(_ item: LibraryFilter) -> String {
        switch item {
        case .all: "rectangle.stack.fill"
        case .image: "photo.fill"
        case .video: "play.rectangle.fill"
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .black.opacity(0.84) : .white.opacity(0.72))
                .padding(.horizontal, selected ? 17 : 12)
                .frame(height: 40)
                .background(selected ? .white.opacity(0.94) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(CinematicInteractiveButtonStyle())
    }

    private func libraryView(width: CGFloat) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 58) {
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(language.text("My", "我的"))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                        Text(language.text(
                            "Build an automatic routine and keep your own wallpaper collection",
                            "管理自动切换方式，也收纳你自己的壁纸素材"
                        ))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CinematicTheme.secondaryText)
                    }

                    Spacer()

                    Button { library.presentImportPanel() } label: {
                        Label(language.text("Add Local Media", "添加本地素材"), systemImage: "plus")
                    }
                    .buttonStyle(CinematicButtonStyle(prominent: true))
                    .help(language.text("Import images or videos", "导入本地图片或视频"))
                }
                .padding(.top, 124)

                VStack(alignment: .leading, spacing: 22) {
                    librarySectionHeading(
                        title: language.text("Playlists", "播放列表"),
                        subtitle: language.text(
                            "Build different rotations for focus, rest, or any moment",
                            "为专注、休息或不同时段创建多个轮换列表"
                        )
                    )

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 270, maximum: 340), spacing: 20)],
                        alignment: .leading,
                        spacing: 20
                    ) {
                        ForEach(playlists) { playlist in
                            playlistGridCard(playlist)
                        }
                        playlistAddCard
                    }
                }

                VStack(alignment: .leading, spacing: 22) {
                    librarySectionHeading(
                        title: language.text("Smart Modes", "智能模式"),
                        subtitle: language.text(
                            "A playlist or one smart mode can run at a time; all can stay off",
                            "播放列表与两种智能模式互斥，也可全部关闭"
                        )
                    )
                    HStack(spacing: 22) {
                        automationCard(
                            mode: .dayNight,
                            title: language.text("Day / Night", "日间 / 夜间"),
                            subtitle: language.text("Switches with local day and night", "随本地日间与夜间自动切换"),
                            symbol: "sun.and.horizon.fill",
                            firstSlot: .day,
                            secondSlot: .night
                        )
                        automationCard(
                            mode: .appearance,
                            title: language.text("Light / Dark", "浅色 / 深色模式"),
                            subtitle: language.text("Follows the macOS appearance", "跟随 macOS 浅色与深色外观"),
                            symbol: "circle.lefthalf.filled",
                            firstSlot: .light,
                            secondSlot: .dark
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 18) {
                    librarySectionHeading(
                        title: language.text("Your Wallpapers", "你的壁纸"),
                        subtitle: language.text(
                            "Wallpapers you liked, used, or added from this Mac",
                            "你喜欢、用过，或从这台 Mac 添加的壁纸"
                        )
                    ) {
                        savedMediaTabs
                    }

                    let visibleItems = mediaItems(for: savedMediaTab)
                    if visibleItems.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: savedMediaTab.symbol)
                                .font(.system(size: 30, weight: .light))
                            Text(
                                mediaEmptyTitle(for: savedMediaTab)
                            )
                            .font(.system(size: 15, weight: .semibold))
                            Text(
                                mediaEmptySubtitle(for: savedMediaTab)
                            )
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CinematicTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 190)
                        .cinematicGlassPanel(cornerRadius: 28, tint: .black.opacity(0.04))
                    } else {
                        LazyVGrid(columns: contentColumns(for: width, spacing: 24), alignment: .leading, spacing: 24) {
                            ForEach(visibleItems) { item in card(item) }
                        }
                    }
                }
            }
            .padding(.horizontal, CinematicTheme.pageGutter)
            .padding(.bottom, engine.currentItem == nil ? 90 : 160)
        }
    }

    private func librarySectionHeading(title: String, subtitle: String) -> some View {
        librarySectionHeading(title: title, subtitle: subtitle) { EmptyView() }
    }

    private func librarySectionHeading<Trailing: View>(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CinematicTheme.secondaryText)
            }
            Spacer()
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var savedMediaTabs: some View {
        mediaTabs(selection: $savedMediaTab)
    }

    private func mediaTabs(selection: Binding<SavedMediaTab>) -> some View {
        HStack(spacing: 4) {
            ForEach(SavedMediaTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.24)) { selection.wrappedValue = tab }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tab.symbol)
                        Text(tab.title(for: language))
                        Text("\(mediaCount(for: tab))")
                            .foregroundStyle(selection.wrappedValue == tab ? .black.opacity(0.54) : .white.opacity(0.42))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selection.wrappedValue == tab ? .black.opacity(0.86) : .white.opacity(0.72))
                    .padding(.horizontal, 15)
                    .frame(height: 40)
                    .background(selection.wrappedValue == tab ? .white.opacity(0.94) : .clear, in: Capsule())
                }
                .buttonStyle(CinematicInteractiveButtonStyle())
            }
        }
        .padding(5)
        .cinematicGlassCapsule(interactive: false, tint: .black.opacity(0.10))
    }

    private func mediaEmptyTitle(for tab: SavedMediaTab) -> String {
        switch tab {
        case .favorites:
            language.text("No liked wallpapers yet", "还没有喜欢的壁纸")
        case .history:
            language.text("No wallpaper history yet", "还没有用过的壁纸")
        case .uploaded:
            language.text("No local media yet", "还没有上传的素材")
        }
    }

    private func mediaEmptySubtitle(for tab: SavedMediaTab) -> String {
        switch tab {
        case .favorites:
            language.text("Tap the heart on any wallpaper to keep it here", "在任意壁纸上点击喜欢，它就会出现在这里")
        case .history:
            language.text("A wallpaper appears here after you set it", "将壁纸设置到桌面后，它会自动记录在这里")
        case .uploaded:
            language.text("Use Add Local Media above to import images or videos", "使用上方的“添加本地素材”导入图片或视频")
        }
    }

    private var mediaPickerFilterBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                ForEach(MediaPickerFilter.allCases) { filter in
                    Button {
                        withAnimation(.snappy(duration: 0.24)) { mediaPickerFilter = filter }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: filter.symbol)
                            Text(filter.title(for: language))
                            Text("\(pickerMediaItems(for: filter).count)")
                                .foregroundStyle(
                                    mediaPickerFilter == filter
                                        ? .black.opacity(0.54)
                                        : .white.opacity(0.42)
                                )
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(mediaPickerFilter == filter ? .black.opacity(0.86) : .white.opacity(0.72))
                        .padding(.horizontal, 13)
                        .frame(height: 38)
                        .background(mediaPickerFilter == filter ? .white.opacity(0.94) : .clear, in: Capsule())
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                }
            }
            .padding(4)
            .cinematicGlassCapsule(interactive: false, tint: .black.opacity(0.10))
            Spacer()
            Text(language.text(
                "\(pickerMediaItems(for: mediaPickerFilter).count) available",
                "\(pickerMediaItems(for: mediaPickerFilter).count) 个可选"
            ))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(CinematicTheme.secondaryText)
        }
    }

    private func pickerEmptyTitle(for filter: MediaPickerFilter) -> String {
        switch filter {
        case .all:
            language.text("No wallpapers available", "暂无可用壁纸")
        case .favorites:
            mediaEmptyTitle(for: .favorites)
        case .history:
            mediaEmptyTitle(for: .history)
        case .uploaded:
            mediaEmptyTitle(for: .uploaded)
        }
    }

    private func pickerEmptySubtitle(for filter: MediaPickerFilter) -> String {
        switch filter {
        case .all:
            language.text("Refresh the catalog or add local media from My", "请刷新云端目录，或在“我的”中添加本地素材")
        case .favorites:
            mediaEmptySubtitle(for: .favorites)
        case .history:
            mediaEmptySubtitle(for: .history)
        case .uploaded:
            mediaEmptySubtitle(for: .uploaded)
        }
    }

    private func mediaPickerEmptyState(for filter: MediaPickerFilter) -> some View {
        VStack(spacing: 11) {
            Image(systemName: filter.symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.62))
            Text(pickerEmptyTitle(for: filter))
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(pickerEmptySubtitle(for: filter))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CinematicTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func playlistGridCard(_ playlist: WallpaperPlaylist) -> some View {
        let items = playlistItems(for: playlist)
        let isEnabled = automationMode == .playlist && activePlaylistIDRaw == playlist.id.uuidString
        return VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.snappy(duration: 0.24)) { presentedPlaylistID = playlist.id }
            } label: {
                playlistCoverStack(items)
                    .frame(height: 122)
            }
            .buttonStyle(CinematicInteractiveButtonStyle(hoverScale: 1.015, pressedScale: 0.985))

            HStack(alignment: .center, spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.24)) { presentedPlaylistID = playlist.id }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(playlist.name)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .lineLimit(1)
                            if isEnabled {
                                Text(language.text("ACTIVE", "运行中"))
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.black.opacity(0.82))
                                    .padding(.horizontal, 7)
                                    .frame(height: 18)
                                    .background(CinematicTheme.success, in: Capsule())
                            }
                        }
                        Text(language.text(
                            "\(items.count) scenes · \(playlistIntervalLabel(playlist.interval))",
                            "\(items.count) 张 · \(playlistIntervalLabel(playlist.interval))"
                        ))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CinematicTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button { openPlaylistEditor(playlist) } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(CinematicInteractiveButtonStyle())
                .help(language.text("Edit playlist", "编辑播放列表"))

                Toggle("", isOn: playlistToggleBinding(for: playlist))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(CinematicTheme.accent)
                    .scaleEffect(0.86)
            }
        }
        .padding(16)
        .frame(height: 214)
        .cinematicGlassPanel(
            cornerRadius: 24,
            tint: isEnabled ? CinematicTheme.accent.opacity(0.07) : .black.opacity(0.035)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isEnabled ? CinematicTheme.accent.opacity(0.72) : .clear, lineWidth: 1.2)
                .allowsHitTesting(false)
        }
    }

    private var playlistAddCard: some View {
        Button { openPlaylistEditor() } label: {
            HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.035))
                    .frame(width: 92, height: 52)
                    .offset(y: -8)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.055))
                    .frame(width: 104, height: 58)
                    .offset(y: 2)
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [CinematicTheme.accent.opacity(0.30), .white.opacity(0.065)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 116, height: 64)
                    .offset(y: 13)
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black.opacity(0.84))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.94), in: Circle())
                    .offset(y: 13)
            }
            .frame(width: 126, height: 92)

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Add Playlist", "添加播放列表"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(language.text(
                    "Choose wallpapers and create another rotation.",
                    "选择壁纸，创建一个新的轮换列表。"
                ))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CinematicTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 214, alignment: .leading)
            .background(.white.opacity(0.018), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [7, 7]))
            }
        }
        .buttonStyle(CinematicInteractiveButtonStyle())
    }

    private func playlistCoverStack(_ items: [WallpaperItem]) -> some View {
        ZStack {
            if items.isEmpty {
                LinearGradient(
                    colors: [Color(hex: "2C3342"), Color(hex: "11151D")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                if items.count > 2 {
                    ArtworkView(item: items[2], cornerRadius: 16)
                        .padding(.horizontal, 30)
                        .offset(y: -1)
                        .opacity(0.52)
                }
                if items.count > 1 {
                    ArtworkView(item: items[1], cornerRadius: 17)
                        .padding(.horizontal, 21)
                        .offset(y: 7)
                        .opacity(0.76)
                }
                ArtworkView(item: items[0], cornerRadius: 18)
                    .padding(.horizontal, 12)
                    .offset(y: 15)
            }

            if items.count > 3 {
                Text("+\(items.count - 3)")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 32, height: 26)
                    .background(.black.opacity(0.58), in: Capsule())
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .clipped()
    }

    private func playlistDetailOverlay(_ playlist: WallpaperPlaylist, width: CGFloat) -> some View {
        let items = playlistItems(for: playlist)
        let isEnabled = automationMode == .playlist && activePlaylistIDRaw == playlist.id.uuidString
        return ZStack {
            glassModalBackdrop
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { presentedPlaylistID = nil }
                }

            VStack(spacing: 0) {
                HStack(spacing: 15) {
                    Image(systemName: "rectangle.stack.badge.play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CinematicTheme.accent)
                        .frame(width: 46, height: 46)
                        .background(CinematicTheme.accent.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(playlist.name)
                                .font(.system(size: 25, weight: .bold, design: .rounded))
                            if isEnabled {
                                Text(language.text("ACTIVE", "运行中"))
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.black.opacity(0.84))
                                    .padding(.horizontal, 8)
                                    .frame(height: 19)
                                    .background(CinematicTheme.success, in: Capsule())
                            }
                        }
                        Text(language.text(
                            "\(items.count) wallpapers · \(playlistIntervalLabel(playlist.interval)) · \(playlist.order.title(for: .english))",
                            "\(items.count) 张壁纸 · \(playlistIntervalLabel(playlist.interval)) · \(playlist.order.title(for: .chinese))"
                        ))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CinematicTheme.secondaryText)
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { presentedPlaylistID = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 44, height: 44)
                            .cinematicGlassCircle(tint: .black.opacity(0.08))
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                }
                .padding(24)

                Divider().overlay(.white.opacity(0.10))

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ZStack(alignment: .bottomLeading) {
                                ArtworkView(item: item, cornerRadius: 17)
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.78)],
                                    startPoint: .center,
                                    endPoint: .bottom
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                HStack(spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.black)
                                        .frame(width: 22, height: 22)
                                        .background(.white.opacity(0.92), in: Circle())
                                    Text(item.localizedTitle(for: language))
                                        .font(.system(size: 11, weight: .bold))
                                        .lineLimit(1)
                                }
                                .padding(11)
                            }
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                    }
                    .padding(24)
                }

                Divider().overlay(.white.opacity(0.10))

                HStack(spacing: 12) {
                    Button {
                        playlistToggleBinding(for: playlist).wrappedValue.toggle()
                    } label: {
                        Label(
                            isEnabled
                                ? language.text("Stop Rotation", "停止轮换")
                                : language.text("Start Rotation", "开始轮换"),
                            systemImage: isEnabled ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(CinematicButtonStyle(prominent: true))

                    Button { openPlaylistEditor(playlist) } label: {
                        Label(language.text("Edit Playlist", "编辑列表"), systemImage: "pencil")
                    }
                    .buttonStyle(CinematicButtonStyle(prominent: false))

                    Spacer()

                    Button { playlistPendingDeletionID = playlist.id } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                    .foregroundStyle(.red.opacity(0.82))
                    .help(language.text("Delete playlist", "删除播放列表"))
                }
                .padding(20)
            }
            .frame(width: min(width - 140, 960), height: 620)
            .cinematicGlassPanel(cornerRadius: 30, interactive: false, tint: .white.opacity(0.025))
            .shadow(color: .black.opacity(0.42), radius: 42, y: 22)
        }
        .ignoresSafeArea()
    }

    private func playlistEditor(width: CGFloat) -> some View {
        let canSave = playlistDraftIDs.count >= 2
        return ZStack {
            glassModalBackdrop
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showsPlaylistEditor = false } }

            VStack(spacing: 0) {
                HStack(spacing: 15) {
                    Image(systemName: "rectangle.stack.badge.play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CinematicTheme.accent)
                        .frame(width: 46, height: 46)
                        .background(CinematicTheme.accent.opacity(0.10), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            editingPlaylistID == nil
                                ? language.text("New Playlist", "新建播放列表")
                                : language.text("Edit Playlist", "编辑播放列表")
                        )
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text(language.text(
                            "Select wallpapers and decide how the list should rotate",
                            "选择壁纸，并设置列表的轮换方式"
                        ))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CinematicTheme.secondaryText)
                    }
                    Spacer()
                    Button { withAnimation(.easeOut(duration: 0.2)) { showsPlaylistEditor = false } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 44, height: 44)
                            .cinematicGlassCircle(tint: .black.opacity(0.10))
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                }
                .padding(24)

                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(language.text("NAME", "名称"))
                            .font(.system(size: 9, weight: .bold)).tracking(1.2)
                            .foregroundStyle(CinematicTheme.tertiaryText)
                        TextField(language.text("My Playlist", "我的播放列表"), text: $playlistDraftName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .frame(width: 220)

                    playlistEditorOptions

                    Spacer()

                    VStack(alignment: .trailing, spacing: 7) {
                        Text(language.text("\(playlistDraftIDs.count) SELECTED", "已选 \(playlistDraftIDs.count) 张"))
                            .font(.system(size: 9, weight: .bold)).tracking(1.1)
                            .foregroundStyle(canSave ? CinematicTheme.success : CinematicTheme.tertiaryText)
                        Button { savePlaylist() } label: {
                            Label(language.text("Save Playlist", "保存列表"), systemImage: "checkmark")
                        }
                        .buttonStyle(CinematicButtonStyle(prominent: true))
                        .disabled(!canSave)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                mediaPickerFilterBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)

                Divider().overlay(.white.opacity(0.10))

                ScrollView {
                    let visibleItems = pickerMediaItems(for: mediaPickerFilter)
                    if visibleItems.isEmpty {
                        mediaPickerEmptyState(for: mediaPickerFilter)
                            .padding(24)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 190, maximum: 250), spacing: 16)],
                            spacing: 16
                        ) {
                            ForEach(visibleItems) { item in
                                Button {
                                    if playlistDraftIDs.contains(item.id) {
                                        playlistDraftIDs.removeAll { $0 == item.id }
                                    } else {
                                        playlistDraftIDs.append(item.id)
                                    }
                                } label: {
                                    playlistEditorTile(item)
                                }
                                .buttonStyle(CinematicInteractiveButtonStyle())
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .frame(width: min(width - 100, 1_100), height: 680)
            .cinematicGlassPanel(cornerRadius: 30, interactive: false, tint: .white.opacity(0.025))
            .shadow(color: .black.opacity(0.42), radius: 44, y: 22)
        }
        .ignoresSafeArea()
    }

    private var playlistEditorOptions: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(language.text("INTERVAL", "切换间隔"))
                    .font(.system(size: 9, weight: .bold)).tracking(1.2)
                    .foregroundStyle(CinematicTheme.tertiaryText)
                HStack(spacing: 4) {
                    ForEach([300.0, 900.0, 1_800.0, 3_600.0], id: \.self) { value in
                        Button {
                            playlistDraftInterval = value
                        } label: {
                            Text(playlistIntervalShortLabel(value))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(playlistDraftInterval == value ? .black.opacity(0.86) : .white.opacity(0.66))
                                .padding(.horizontal, 10)
                                .frame(height: 36)
                                .background(playlistDraftInterval == value ? .white.opacity(0.92) : .clear, in: Capsule())
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                    }
                }
                .padding(3)
                .background(.white.opacity(0.06), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(language.text("ORDER", "播放顺序"))
                    .font(.system(size: 9, weight: .bold)).tracking(1.2)
                    .foregroundStyle(CinematicTheme.tertiaryText)
                HStack(spacing: 4) {
                    ForEach(PlaylistOrder.allCases) { order in
                        Button { playlistDraftOrder = order } label: {
                            Text(order.title(for: language))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(playlistDraftOrder == order ? .black.opacity(0.86) : .white.opacity(0.66))
                                .padding(.horizontal, 11)
                                .frame(height: 36)
                                .background(playlistDraftOrder == order ? .white.opacity(0.92) : .clear, in: Capsule())
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                    }
                }
                .padding(3)
                .background(.white.opacity(0.06), in: Capsule())
            }
        }
    }

    private func playlistIntervalShortLabel(_ value: Double) -> String {
        switch value {
        case 300: language.text("5m", "5 分")
        case 900: language.text("15m", "15 分")
        case 1_800: language.text("30m", "30 分")
        case 3_600: language.text("1h", "1 小时")
        default: language.text("15m", "15 分")
        }
    }

    private func playlistEditorTile(_ item: WallpaperItem) -> some View {
        let selectionIndex = playlistDraftIDs.firstIndex(of: item.id)
        let isSelected = selectionIndex != nil
        return ZStack(alignment: .bottomLeading) {
            ArtworkView(item: item, cornerRadius: 16)
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(item.localizedTitle(for: language))
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .padding(11)
            ZStack {
                Circle().fill(isSelected ? CinematicTheme.accent : .black.opacity(0.52))
                if let selectionIndex {
                    Text("\(selectionIndex + 1)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
                .frame(width: 24, height: 24)
                .padding(9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? CinematicTheme.accent : .white.opacity(0.12), lineWidth: isSelected ? 2 : 0.7)
        }
    }

    private func automationCard(
        mode: WallpaperAutomationMode,
        title: String,
        subtitle: String,
        symbol: String,
        firstSlot: AutomationWallpaperSlot,
        secondSlot: AutomationWallpaperSlot
    ) -> some View {
        let isEnabled = automationMode == mode
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(CinematicTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16, weight: .bold))
                    Text(subtitle).font(.system(size: 10, weight: .medium)).foregroundStyle(CinematicTheme.secondaryText)
                }
                Spacer()
                Toggle("", isOn: automationToggleBinding(for: mode))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(CinematicTheme.accent)
                    .help(
                        isEnabled
                            ? language.text("Turn off this automation", "关闭这条自动规则")
                            : language.text("Enable this automation", "开启这条自动规则")
                    )
            }

            HStack(spacing: 12) {
                ForEach([firstSlot, secondSlot], id: \.rawValue) { slot in
                    let item = automationItem(for: slot)
                    Button { editingAutomationSlot = slot } label: {
                        ZStack(alignment: .bottomLeading) {
                            if let item {
                                ArtworkView(item: item, cornerRadius: 16)
                            } else {
                                LinearGradient(
                                    colors: [.white.opacity(0.08), .white.opacity(0.025)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            }

                            LinearGradient(
                                colors: [.clear, .black.opacity(0.78)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                            HStack(spacing: 7) {
                                Image(systemName: slot.symbol)
                                    .font(.system(size: 10, weight: .bold))
                                Text(slot.title(for: language))
                                    .font(.system(size: 11, weight: .bold))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Image(systemName: "pencil")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(11)
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    isCurrentAutomationSlot(slot) && isEnabled
                                        ? AnyShapeStyle(CinematicTheme.accent.opacity(0.88))
                                        : AnyShapeStyle(CinematicTheme.specularEdge(intensity: 0.38)),
                                    lineWidth: isCurrentAutomationSlot(slot) && isEnabled ? 1.5 : 0.7
                                )
                        }
                        .overlay(alignment: .topTrailing) {
                            if isCurrentAutomationSlot(slot) && isEnabled {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(width: 24, height: 24)
                                    .background(CinematicTheme.accent, in: Circle())
                                    .padding(8)
                            }
                        }
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                    .help(language.text("Choose \(slot.title(for: .english))", "选择\(slot.title(for: .chinese))"))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .cinematicGlassPanel(
            cornerRadius: 26,
            tint: isEnabled ? CinematicTheme.accent.opacity(0.055) : .black.opacity(0.05)
        )
    }

    private var miniPlayer: some View {
        Group {
            if let engineItem = engine.currentItem {
                let item = library.items.first { $0.id == engineItem.id } ?? engineItem
                HStack(spacing: 0) {
                    Button { selectedItem = item } label: {
                        ZStack(alignment: .leading) {
                            ArtworkView(item: item, cornerRadius: 0)
                                .mask {
                                    LinearGradient(
                                        colors: [.white, .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                }
                            LinearGradient(
                                colors: [.black.opacity(0.16), .black.opacity(0.08), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.localizedTitle(for: language))
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                HStack(spacing: 7) {
                                    Circle().fill(CinematicTheme.success).frame(width: 7, height: 7)
                                    Text(engine.activeDisplayNames.first ?? language.text("Desktop Wallpaper", "桌面壁纸"))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.64))
                                }
                            }
                            .padding(.leading, 24)
                        }
                        .frame(width: 300, height: 78)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 39, bottomLeadingRadius: 39, style: .continuous))
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle(hoverScale: 1.01, pressedScale: 0.985))
                    .help(language.text("View current wallpaper", "查看当前壁纸详情"))

                    Spacer(minLength: 12)

                    HStack(spacing: 14) {
                        Button { showsMiniNowPlaying.toggle() } label: {
                            Image(systemName: "switch.2").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 54)
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                        .popover(isPresented: $showsMiniNowPlaying, arrowEdge: .bottom) {
                            NowPlayingPanelView()
                                .environmentObject(library)
                                .environmentObject(engine)
                        }
                        .help(language.text("Now playing and displays", "当前播放与显示器"))

                        Button { library.toggleFavorite(item) } label: {
                            Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(item.isFavorite ? .pink : .white)
                                .frame(width: 44, height: 54)
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                        .help(item.isFavorite ? language.text("Remove Favorite", "取消收藏") : language.text("Add Favorite", "加入收藏"))

                        Button { engine.toggleMuted() } label: {
                            Image(systemName: engine.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(item.kind == .video ? .white : .white.opacity(0.30))
                                .frame(width: 44, height: 54)
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                        .disabled(item.kind != .video)
                        .help(engine.isMuted ? language.text("Unmute Wallpaper", "打开壁纸声音") : language.text("Mute Wallpaper", "静音壁纸"))

                        Button { library.playAdjacent(to: item, offset: -1) } label: {
                            Image(systemName: "backward.fill").font(.system(size: 20, weight: .semibold)).frame(width: 46, height: 54)
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                        .help(language.text("Previous", "上一张"))

                        Button {
                            item.kind == .video ? engine.togglePlayback() : library.apply(item)
                        } label: {
                            Image(systemName: item.kind == .video ? (engine.isPlaying ? "pause.fill" : "play.fill") : "photo.fill")
                                .font(.system(size: 27, weight: .bold))
                                .frame(width: 50, height: 54)
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                        .help(item.kind == .video ? (engine.isPlaying ? language.text("Pause", "暂停") : language.text("Resume", "继续播放")) : language.text("Reapply image wallpaper", "重新应用图片壁纸"))

                        Button { library.playAdjacent(to: item, offset: 1) } label: {
                            Image(systemName: "forward.fill").font(.system(size: 20, weight: .semibold)).frame(width: 46, height: 54)
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                        .help(language.text("Next", "下一张"))

                        Button { selectedItem = item } label: {
                            Image(systemName: "rectangle.stack.fill").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 54)
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                        .help(language.text("View Details", "查看详情"))

                        Button { engine.cyclePlaybackRate() } label: {
                            Text("\(engine.playbackRate.formatted(.number.precision(.fractionLength(engine.playbackRate == floor(engine.playbackRate) ? 0 : 1))))×")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(item.kind == .video ? .white.opacity(0.78) : .white.opacity(0.30))
                                .frame(width: 48, height: 54)
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                        .disabled(item.kind != .video)
                        .help(language.text("Change Playback Speed", "切换播放速度"))
                    }
                    .padding(.trailing, 22)
                }
                .frame(width: 900, height: 78)
                .cinematicGlassCapsule(interactive: false, tint: .black.opacity(0.26))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.42), radius: 34, y: 16)
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String, action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 25, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 11, weight: .medium)).foregroundStyle(CinematicTheme.secondaryText)
            }
            Spacer()
            if let action {
                Button(action: action) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.055), in: Circle())
                }
                .buttonStyle(CinematicInteractiveButtonStyle())
                .help(language.text("View All", "查看全部"))
            }
        }
        .padding(.horizontal, CinematicTheme.pageGutter)
    }

    private func card(_ item: WallpaperItem) -> some View {
        WallpaperCard(
            item: item,
            isActive: engine.currentItem?.id == item.id,
            onSelect: { selectedItem = item },
            onApply: { library.apply(item) },
            onFavorite: { library.toggleFavorite(item) }
        )
    }

    private func items(for collection: HomeCollection) -> [WallpaperItem] {
        switch collection {
        case .curated:
            matching(homeFeaturedItems)
        case .popular:
            matching(homeTrendingItems)
        case .latest:
            matching(homeRecentItems)
        }
    }

    private func openCollection(_ collection: HomeCollection) {
        showsSearch = false
        withAnimation(.snappy(duration: 0.38, extraBounce: 0.02)) {
            selectedHomeCollection = collection
        }
    }

    private func railCardWidth(for width: CGFloat) -> CGFloat {
        let columnCount: CGFloat = width >= 1_720 ? 4 : 3
        let totalSpacing = (columnCount - 1) * 22
        let availableWidth = width - CinematicTheme.pageGutter * 2 - totalSpacing
        return max(280, availableWidth / columnCount)
    }

    private func contentColumns(for width: CGFloat, spacing: CGFloat = 22) -> [GridItem] {
        // Keep cards cinematic but never let a wide window collapse into two
        // oversized tiles. Four columns become available on genuinely wide
        // windows; everything else uses a comfortable three-column rhythm.
        let columnCount = width >= 1_720 ? 4 : 3
        return Array(repeating: GridItem(.flexible(minimum: 0), spacing: spacing), count: columnCount)
    }

    private func detailOverlay(_ item: WallpaperItem) -> some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.22)) { selectedItem = nil }
                }

            WallpaperDetailView(itemID: item.id) {
                withAnimation(.easeOut(duration: 0.22)) { selectedItem = nil }
            }
            .environmentObject(library)
            .environmentObject(engine)
            .padding(20)
            .onTapGesture { }
        }
    }

    private func matching(_ items: [WallpaperItem]) -> [WallpaperItem] {
        items.filter { item in
            filter.includes(item)
        }
    }

    private func ordered(_ source: [WallpaperItem], by ids: [UUID]) -> [WallpaperItem] {
        guard !ids.isEmpty else { return source }
        let sourceByID = Dictionary(uniqueKeysWithValues: source.map { ($0.id, $0) })
        let orderedItems = ids.compactMap { sourceByID[$0] }
        let orderedIDs = Set(ids)
        return orderedItems + source.filter { !orderedIDs.contains($0.id) }
    }

    private func reshuffleHomeContent() {
        let all = cloudItems
        let recommended = all.filter { $0.isFeatured == true }
        let recommendedLead = recommended.isEmpty ? latestItems : recommended
        let curatedOrder = all.filter { $0.isCurated == true }.sorted(by: latestFirst).map(\.id)
        let popularOrder = popularItems.map(\.id)
        let latestOrder = latestItems.map(\.id)
        let heroOrder = shuffledIDs(from: recommendedLead, avoidingLeading: homeHeroOrder)
        let moodOrder = shuffledIDs(from: latestItems, avoidingLeading: popularOrder)

        homeHeroOrder = heroOrder
        homeFeaturedOrder = curatedOrder
        homeTrendingOrder = popularOrder
        homeMoodOrder = moodOrder
        homeRecentOrder = latestOrder
        heroID = heroOrder.first ?? latestItems.first?.id
        homeVisitID = UUID()
    }

    private var shouldRotateHero: Bool {
        destination == .home
            && selectedHomeCollection == nil
            && selectedItem == nil
            && heroIsVisible
            && heroCandidates.count > 1
    }

    private var heroRotationTaskID: String {
        [
            homeVisitID.uuidString,
            heroID?.uuidString ?? "none",
            destination.rawValue,
            selectedHomeCollection?.id ?? "root",
            selectedItem?.id.uuidString ?? "no-detail",
            heroIsVisible ? "visible" : "hidden",
        ].joined(separator: "-")
    }

    private func advanceHero() {
        let candidates = heroCandidates
        guard candidates.count > 1 else { return }
        let currentIndex = candidates.firstIndex { $0.id == heroID } ?? 0
        let next = candidates[(currentIndex + 1) % candidates.count]
        withAnimation(.easeInOut(duration: 0.52)) {
            heroID = next.id
        }
    }

    private func shuffledIDs(from items: [WallpaperItem], avoidingLeading previous: [UUID] = []) -> [UUID] {
        var candidate = items.map(\.id)
        guard candidate.count > 1 else { return candidate }

        let comparisonCount = min(4, candidate.count, previous.count)
        for _ in 0..<8 {
            candidate.shuffle()
            if comparisonCount == 0
                || Array(candidate.prefix(comparisonCount)) != Array(previous.prefix(comparisonCount)) {
                return candidate
            }
        }

        // Guarantee a visibly different leading order even in the unlikely
        // event that repeated random shuffles produce the same first cards.
        candidate.append(candidate.removeFirst())
        return candidate
    }

}

private struct HomeScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension View {
    @ViewBuilder
    func trackScrollVisibility(threshold: Double = 0.15, _ action: @escaping (Bool) -> Void) -> some View {
        if #available(macOS 15.0, *) {
            onScrollVisibilityChange(threshold: threshold, action)
        } else {
            onAppear { action(true) }
                .onDisappear { action(false) }
        }
    }
}
