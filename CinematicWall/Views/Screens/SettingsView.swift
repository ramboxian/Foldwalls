import AppKit
import ServiceManagement
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case playback
    case displays
    case library
    case about

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .playback: "play.square.stack"
        case .displays: "display.2"
        case .library: "externaldrive"
        case .about: "info.circle"
        }
    }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .general: language.text("General", "通用")
        case .playback: language.text("Playback", "播放")
        case .displays: language.text("Displays", "显示器")
        case .library: language.text("Library", "资料库")
        case .about: language.text("About", "关于")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: WallpaperLibrary
    @EnvironmentObject private var engine: WallpaperEngine
    @EnvironmentObject private var updateManager: UpdateManager

    @AppStorage("restoreLastWallpaper") private var restoreLastWallpaper = true
    @AppStorage("pauseOnBattery") private var pauseOnBattery = false
    @AppStorage("pauseOnLowPower") private var pauseOnLowPower = true
    @AppStorage("pauseWhenFullscreen") private var pauseWhenFullscreen = true
    @AppStorage("resumeAfterWake") private var resumeAfterWake = true
    @AppStorage("syncLockScreenWallpaper") private var syncLockScreenWallpaper = true
    @AppStorage("wallpaperFit") private var wallpaperFit = "fill"
    @AppStorage("displayMode") private var displayMode = "all"
    @AppStorage("transitionDuration") private var transitionDuration = 0.35
    @AppStorage("appLanguage") private var languageRaw = AppLanguage.english.rawValue

    @State private var launchAtLogin = false
    @State private var serviceError: String?
    @State private var showsUpdateNotes = false
    @State private var selectedPane = SettingsPane.general

    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .english }

    var body: some View {
        ZStack {
            settingsBackdrop

            VStack(spacing: 8) {
                settingsTabBar

                Group {
                    switch selectedPane {
                    case .general: generalSettings
                    case .playback: playbackSettings
                    case .displays: displaySettings
                    case .library: librarySettings
                    case .about: aboutSettings
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(10)
        }
        .frame(width: 480, height: 560)
        .background(WindowAppearanceConfigurator())
        .preferredColorScheme(.dark)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .alert(language.text("Unable to Update Login Item", "无法更新登录项"), isPresented: Binding(
            get: { serviceError != nil },
            set: { if !$0 { serviceError = nil } }
        )) {
            Button(language.text("OK", "知道了"), role: .cancel) { serviceError = nil }
        } message: {
            Text(serviceError ?? language.text("Move the app to Applications and try again.", "请将应用放入“应用程序”文件夹后重试。"))
        }
        .sheet(isPresented: $showsUpdateNotes) {
            UpdateReleaseNotesView(manager: updateManager, language: language)
        }
    }

    private var settingsTabBar: some View {
        HStack(spacing: 3) {
            ForEach(SettingsPane.allCases) { pane in
                Button {
                    withAnimation(.snappy(duration: 0.28, extraBounce: 0.02)) {
                        selectedPane = pane
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: pane.symbol)
                            .font(.system(size: 15, weight: .semibold))
                        Text(pane.title(for: language))
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selectedPane == pane ? Color.white : CinematicTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        selectedPane == pane ? Color.white.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(CinematicInteractiveButtonStyle(hoverScale: 1.015, pressedScale: 0.98))
            }
        }
        .padding(5)
        .cinematicGlassPanel(cornerRadius: 20, interactive: false, tint: .black.opacity(0.07))
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }

    private var settingsBackdrop: some View {
        ZStack {
            WindowMaterialBackdrop()

            LinearGradient(
                colors: [
                    Color(hex: "101824").opacity(0.58),
                    Color(hex: "090D14").opacity(0.38),
                    Color.black.opacity(0.28),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(CinematicTheme.accent.opacity(0.13))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: -190, y: -260)

            Circle()
                .fill(Color.pink.opacity(0.075))
                .frame(width: 260, height: 260)
                .blur(radius: 100)
                .offset(x: 220, y: 280)
        }
        .ignoresSafeArea()
    }

    private var generalSettings: some View {
        Form {
            Section(language.text("Startup", "启动")) {
                Picker(language.text("Language", "语言"), selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { option in Text(option.title).tag(option.rawValue) }
                }
                .pickerStyle(.segmented)
                Toggle(language.text("Launch when I log in", "登录 Mac 时自动启动"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        updateLaunchAtLogin(newValue)
                    }
                Toggle(language.text("Restore the last wallpaper on launch", "启动后恢复上次的壁纸"), isOn: $restoreLastWallpaper)
            }

            Section(language.text("Behavior", "使用习惯")) {
                Toggle(language.text("Resume after sleep or lock screen", "从休眠或锁屏返回后继续播放"), isOn: $resumeAfterWake)
                LabeledContent(language.text("Menu Bar Controls", "状态栏控制")) {
                    Text(language.text("Always Visible", "始终显示"))
                        .foregroundStyle(CinematicTheme.secondaryText)
                }
            }

        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.clear)
    }

    private var playbackSettings: some View {
        Form {
            Section(language.text("Smart Pause", "智能暂停")) {
                Toggle(language.text("Pause on battery power", "使用电池供电时暂停动态壁纸"), isOn: $pauseOnBattery)
                Toggle(language.text("Pause in Low Power Mode", "低电量模式下暂停"), isOn: $pauseOnLowPower)
                Toggle(language.text("Pause when an app is full screen", "前台应用全屏时暂停"), isOn: $pauseWhenFullscreen)
            }

            Section(language.text("Playback Behavior", "播放行为")) {
                Toggle(language.text("Allow wallpaper audio", "允许动态壁纸播放声音"), isOn: Binding(
                    get: { !engine.isMuted },
                    set: { engine.setMuted(!$0) }
                ))
                LabeledContent(language.text("Playback Speed", "播放速度")) {
                    Picker("", selection: Binding(
                        get: { engine.playbackRate },
                        set: { engine.setPlaybackRate($0) }
                    )) {
                        Text("0.5×").tag(Float(0.5))
                        Text("1×").tag(Float(1))
                        Text("1.5×").tag(Float(1.5))
                        Text("2×").tag(Float(2))
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                LabeledContent(language.text("Looping", "循环方式")) {
                    Text(language.text("Seamless Loop", "无缝循环"))
                        .foregroundStyle(CinematicTheme.secondaryText)
                }
                Text(language.text("The player releases decoding resources during sleep, lock screen, and energy-saving states.", "当屏幕休眠、锁屏或进入节能状态时，播放器会释放解码负载。"))
                    .font(.system(size: 11))
                    .foregroundStyle(CinematicTheme.secondaryText)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .onChange(of: pauseOnBattery) { _, _ in engine.refreshPolicy() }
        .onChange(of: pauseOnLowPower) { _, _ in engine.refreshPolicy() }
        .onChange(of: pauseWhenFullscreen) { _, _ in engine.refreshPolicy() }
    }

    private var displaySettings: some View {
        Form {
            Section(language.text("Display Scope", "显示范围")) {
                Picker(language.text("Play On", "播放位置"), selection: $displayMode) {
                    Text(language.text("All Displays", "所有显示器")).tag("all")
                    Text(language.text("Main Display Only", "仅主显示器")).tag("primary")
                }
                .pickerStyle(.segmented)
            }

            Section(language.text("Image", "画面")) {
                Toggle(
                    language.text("Sync the Lock Screen background", "同步锁屏背景"),
                    isOn: $syncLockScreenWallpaper
                )
                Text(language.text(
                    "Motion wallpapers use a matching high-resolution still frame while the Mac is locked.",
                    "动态壁纸会在 Mac 锁屏时使用同素材的高清静态画面。"
                ))
                .font(.system(size: 11))
                .foregroundStyle(CinematicTheme.secondaryText)

                Picker(language.text("Scaling", "缩放方式"), selection: $wallpaperFit) {
                    Text(language.text("Fill Screen", "填满屏幕")).tag("fill")
                    Text(language.text("Fit Entire Image", "完整显示")).tag("fit")
                }
                .pickerStyle(.segmented)

                LabeledContent(language.text("Transition", "切换过渡")) {
                    HStack(spacing: 10) {
                        Slider(value: $transitionDuration, in: 0...1.2, step: 0.05)
                            .frame(width: 230)
                        Text(transitionDuration == 0 ? language.text("Off", "无") : String(format: "%.2f s", transitionDuration))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(CinematicTheme.secondaryText)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }

            Section(language.text("Current Status", "当前状态")) {
                LabeledContent(language.text("Output", "正在输出")) {
                    Text(engine.activeDisplayNames.isEmpty ? language.text("Not Playing", "尚未播放") : engine.activeDisplayNames.joined(separator: "  ·  "))
                        .foregroundStyle(CinematicTheme.secondaryText)
                }
                LabeledContent(language.text("Lock Screen", "锁屏背景")) {
                    Text(lockScreenSyncStatus)
                        .foregroundStyle(CinematicTheme.secondaryText)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .onChange(of: wallpaperFit) { _, _ in reapplyCurrentWallpaper() }
        .onChange(of: displayMode) { _, _ in reapplyCurrentWallpaper() }
        .onChange(of: syncLockScreenWallpaper) { _, _ in engine.refreshSystemWallpaperSync() }
    }

    private var lockScreenSyncStatus: String {
        guard syncLockScreenWallpaper else { return language.text("Off", "已关闭") }
        if engine.isSystemWallpaperSynced { return language.text("Synced", "已同步") }
        if engine.systemWallpaperSyncError != nil { return language.text("Couldn’t Sync", "同步失败") }
        return engine.currentItem == nil
            ? language.text("Waiting for a wallpaper", "等待设置壁纸")
            : language.text("Preparing", "正在准备")
    }

    private var librarySettings: some View {
        Form {
            Section(language.text("Cloud Catalog", "云端目录")) {
                LabeledContent(language.text("Available", "可用壁纸")) {
                    Text("\(library.catalogItemCount)")
                        .foregroundStyle(CinematicTheme.secondaryText)
                }
                LabeledContent(language.text("Ready Offline", "离线可用")) {
                    Text("\(library.offlineReadyCatalogCount) / \(library.catalogItemCount)")
                        .foregroundStyle(CinematicTheme.secondaryText)
                }
                Button(language.text("Refresh Cloud Catalog", "刷新云端目录")) {
                    Task { await library.refreshCatalog() }
                }
                .disabled(library.isRefreshingCatalog)
                if library.isRefreshingCatalog {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(language.text("Checking for updates…", "正在检查更新…"))
                            .font(.system(size: 11))
                            .foregroundStyle(CinematicTheme.secondaryText)
                    }
                } else if let error = library.catalogError {
                    Text(language.text("Offline cache is active. ", "已启用离线缓存。") + error)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }

            Section(language.text("Storage", "存储")) {
                LabeledContent(language.text("Library Location", "资料库位置")) {
                    Text("Application Support / Foldwalls / Library")
                        .font(.system(size: 11))
                        .foregroundStyle(CinematicTheme.secondaryText)
                }
                LabeledContent(language.text("Library Size", "资料库大小")) {
                    Text(ByteCountFormatter.string(fromByteCount: libraryStorageSize, countStyle: .file))
                        .foregroundStyle(CinematicTheme.secondaryText)
                }
            }

            Section(language.text("Maintenance", "维护")) {
                Button(language.text("Open Library in Finder", "在 Finder 中打开资料库")) {
                    library.revealLibraryInFinder()
                }
                Button(language.text("Sync Library Folder Now", "立即同步素材文件夹")) {
                    library.synchronizeMediaFolder()
                }
                .disabled(library.isSynchronizingFolder)
                if library.isSynchronizingFolder {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(language.text("Scanning images and videos…", "正在扫描图片和视频…"))
                            .font(.system(size: 11))
                            .foregroundStyle(CinematicTheme.secondaryText)
                    }
                }
                Button(language.text("Rebuild Preview Cache", "重建预览缓存")) {
                    library.rebuildPreviewCache()
                }
                .disabled(library.isRebuildingPreviewCache)
                if library.isRebuildingPreviewCache {
                    HStack(spacing: 10) {
                        ProgressView(value: library.previewCacheProgress)
                            .frame(width: 220)
                        Text("\(Int(library.previewCacheProgress * 100))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(CinematicTheme.secondaryText)
                    }
                } else if let message = library.maintenanceMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CinematicTheme.success)
                }
                Text(language.text("Rebuilding previews never removes original images or videos.", "重建预览不会删除任何原始图片或视频。"))
                    .font(.system(size: 11))
                    .foregroundStyle(CinematicTheme.secondaryText)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.clear)
    }

    private var libraryStorageSize: Int64 {
        library.totalStorageBytes
    }

    private var aboutSettings: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 13) {
                    BrandLogoImage()
                        .scaledToFill()
                        .frame(width: 82, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 23, style: .continuous)
                                .strokeBorder(CinematicTheme.specularEdge(intensity: 0.8), lineWidth: 0.8)
                        }
                        .shadow(color: .black.opacity(0.34), radius: 24, y: 12)

                    Text(language.brandName)
                        .font(.system(size: 27, weight: .bold, design: .rounded))

                    Text(language.text(
                        "Make every Mac desktop feel like a living cinematic scene.",
                        "让每一块 Mac 桌面，都成为持续流动的电影画面。"
                    ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CinematicTheme.secondaryText)
                    .multilineTextAlignment(.center)

                    Text(language.text("Version", "版本") + " \(appVersion)  ·  Native macOS")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(CinematicTheme.tertiaryText)
                }
                .padding(.top, 12)

                updateSettingsCard

                VStack(spacing: 0) {
                    aboutRow(
                        title: language.text("Created by", "作者"),
                        value: "Rambox",
                        symbol: "person.crop.circle"
                    )

                    Divider().overlay(CinematicTheme.divider).padding(.leading, 45)

                    HStack(spacing: 13) {
                        Image(systemName: "envelope")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CinematicTheme.secondaryText)
                            .frame(width: 28)
                        Text(language.text("Contact", "联系邮箱"))
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Link("rambox@88.com", destination: URL(string: "mailto:rambox@88.com")!)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)

                    Divider().overlay(CinematicTheme.divider).padding(.leading, 45)

                    aboutRow(
                        title: language.text("Built for", "为谁而做"),
                        value: language.text("People who love beautiful desktops", "喜欢好看桌面的人"),
                        symbol: "heart"
                    )
                }
                .cinematicGlassPanel(cornerRadius: 20, interactive: false, tint: .black.opacity(0.05))

                Text(language.text(
                    "Foldwalls is built with SwiftUI, AppKit, and AVFoundation. Your imported media stays on this Mac.",
                    "Foldwalls 由 SwiftUI、AppKit 和 AVFoundation 构建。你导入的图片与视频始终保存在这台 Mac 上。"
                ))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CinematicTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

                Text("© 2026 Rambox")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CinematicTheme.tertiaryText)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
    }

    private var updateSettingsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                UpdateProgressGlyph(manager: updateManager, size: 20)
                    .frame(width: 38, height: 38)
                    .background(CinematicTheme.success.opacity(0.86), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(updateTitle)
                        .font(.system(size: 12, weight: .bold))
                    Text(localizedUpdateStatus)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(updateManager.phase == .failed ? Color.orange : CinematicTheme.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                if updateManager.isUpdateAvailable {
                    Button(language.text("Update", "立即更新")) {
                        updateManager.installAvailableUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CinematicTheme.success)
                } else {
                    Button(language.text("Check for Updates", "检查更新")) {
                        updateManager.checkForUpdates()
                    }
                    .disabled(updateManager.isBusy)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if updateManager.release != nil {
                Divider().overlay(CinematicTheme.divider).padding(.leading, 58)

                Button {
                    showsUpdateNotes = true
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(CinematicTheme.secondaryText)
                            .frame(width: 38)
                        Text(language.text("What’s New", "更新说明"))
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CinematicTheme.tertiaryText)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .cinematicGlassPanel(cornerRadius: 20, interactive: false, tint: CinematicTheme.success.opacity(0.035))
    }

    private var updateTitle: String {
        if let release = updateManager.release {
            return language.text("Foldwalls \(release.version) is available", "Foldwalls \(release.version) 可更新")
        }
        return language.text("Software Update", "软件更新")
    }

    private var localizedUpdateStatus: String {
        switch updateManager.phase {
        case .idle:
            language.text("Current version \(updateManager.currentVersion)", "当前版本 \(updateManager.currentVersion)")
        case .checking:
            language.text("Checking for updates…", "正在检查更新…")
        case .available:
            [
                language.text("Version \(updateManager.release?.version ?? "")", "版本 \(updateManager.release?.version ?? "")"),
                updateManager.formattedReleaseSize,
            ].compactMap { $0 }.joined(separator: "  ·  ")
        case .downloading:
            updateManager.progress.map {
                language.text("Downloading… \(Int($0 * 100))%", "正在下载… \(Int($0 * 100))%")
            } ?? language.text("Downloading update…", "正在下载更新…")
        case .extracting:
            language.text("Preparing update…", "正在准备更新…")
        case .installing:
            language.text("Installing and restarting…", "正在安装并重启…")
        case .upToDate:
            language.text("You’re using the latest version", "当前已是最新版本")
        case .failed:
            language.text(
                "Couldn’t check for updates. Please try again shortly.",
                "检查更新失败，请稍后再试。"
            )
        }
    }

    private func aboutRow(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CinematicTheme.secondaryText)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CinematicTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.0"
    }

    @MainActor
    private func updateLaunchAtLogin(_ enabled: Bool) {
        let isCurrentlyEnabled = SMAppService.mainApp.status == .enabled
        guard enabled != isCurrentlyEnabled else { return }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            serviceError = error.localizedDescription
        }
    }

    private func reapplyCurrentWallpaper() {
        if let current = engine.currentItem { engine.apply(current) }
    }
}

private enum NowPlayingPanelMode {
    case player
    case liked
}

struct NowPlayingPanelView: View {
    @EnvironmentObject private var library: WallpaperLibrary
    @EnvironmentObject private var engine: WallpaperEngine
    @AppStorage("appLanguage") private var languageRaw = AppLanguage.english.rawValue
    @State private var panelMode: NowPlayingPanelMode = .player

    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .english }

    private var current: WallpaperItem? {
        guard let id = engine.currentItem?.id else { return nil }
        return library.items.first { $0.id == id } ?? engine.currentItem
    }

    var body: some View {
        ZStack {
            CinematicTheme.deepCanvas

            if panelMode == .liked {
                queueBackdrop
                likedQueue
            } else if let item = current {
                ArtworkView(item: item, cornerRadius: 0)
                    .ignoresSafeArea()

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.18), location: 0),
                        .init(color: .clear, location: 0.36),
                        .init(color: CinematicTheme.deepCanvas.opacity(0.88), location: 0.78),
                        .init(color: CinematicTheme.deepCanvas, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                nowPlayingContent(item)
            } else {
                emptyState
            }
        }
        .frame(width: 420, height: 610)
        .foregroundStyle(CinematicTheme.primaryText)
        .tint(CinematicTheme.primaryText)
        .background(DarkPanelAppearanceConfigurator())
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .animation(.snappy(duration: 0.32, extraBounce: 0.02), value: panelMode)
    }

    private func nowPlayingContent(_ item: WallpaperItem) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text("Now Playing", "正在播放"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CinematicTheme.primaryText)
                    Text("\(language.brandName)  ·  \(item.kind.label(for: language))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                LiquidGlassGroup(spacing: 9) {
                    HStack(spacing: 9) {
                        Button {
                            openMainWindow()
                        } label: {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(CinematicTheme.primaryText)
                                .frame(width: 40, height: 40)
                                .cinematicGlassCircle()
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                        .help(language.text("Open Main Window", "打开主窗口"))

                        SettingsLink {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(CinematicTheme.primaryText)
                                .frame(width: 40, height: 40)
                                .cinematicGlassCircle()
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())

                        Button {
                            engine.stop()
                        } label: {
                            Image(systemName: "power")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(CinematicTheme.primaryText)
                                .frame(width: 40, height: 40)
                                .cinematicGlassCircle(tint: .red.opacity(0.13))
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                        .help(language.text("Stop Wallpaper", "停止壁纸"))
                    }
                }
            }

            Spacer()

            VStack(spacing: 8) {
                Text(item.localizedTitle(for: language))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(CinematicTheme.primaryText)
                    .lineLimit(1)
                Text(item.metadataLine)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            LiquidGlassGroup(spacing: 14) {
                HStack(spacing: 14) {
                    Button {
                        library.toggleFavorite(item)
                    } label: {
                        Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(item.isFavorite ? .pink : .white)
                            .frame(width: 46, height: 46)
                            .cinematicGlassCircle(tint: item.isFavorite ? .pink.opacity(0.14) : .black.opacity(0.05))
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                    .help(item.isFavorite ? language.text("Remove Favorite", "取消收藏") : language.text("Add Favorite", "加入收藏"))

                    Button {
                        library.playAdjacent(to: item, offset: -1)
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(CinematicTheme.primaryText)
                            .frame(width: 58, height: 58)
                            .cinematicGlassCircle(tint: .black.opacity(0.08))
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                    .help(language.text("Previous", "上一张"))

                    Button {
                        if item.kind == .video { engine.togglePlayback() }
                    } label: {
                        Image(systemName: item.kind == .video ? (engine.isPlaying ? "pause.fill" : "play.fill") : "photo.fill")
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 82, height: 82)
                            .cinematicGlassCircle(tint: .white.opacity(0.16))
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle(hoverScale: 1.025, pressedScale: 0.96))
                    .help(item.kind == .video ? (engine.isPlaying ? language.text("Pause", "暂停") : language.text("Resume", "继续播放")) : language.text("Image Wallpaper", "图片壁纸"))

                    Button {
                        library.playAdjacent(to: item, offset: 1)
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(CinematicTheme.primaryText)
                            .frame(width: 58, height: 58)
                            .cinematicGlassCircle(tint: .black.opacity(0.08))
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                    .help(language.text("Next", "下一张"))

                    Button {
                        panelMode = .liked
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(CinematicTheme.primaryText)
                            .frame(width: 46, height: 46)
                            .cinematicGlassCircle(tint: .black.opacity(0.05))
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                    .help(language.text("Liked Queue", "喜欢列表"))
                }
            }
            .padding(.top, 20)

            HStack(spacing: 8) {
                ForEach(engine.activeDisplayNames.prefix(2), id: \.self) { name in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(engine.isPlaying ? CinematicTheme.success : Color(red: 1.0, green: 0.72, blue: 0.18))
                            .frame(width: 7, height: 7)
                        Text(name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .cinematicGlassCapsule(interactive: false, tint: .black.opacity(0.08))
                }
            }
            .padding(.top, 24)
        }
        .padding(24)
    }

    private var queueBackdrop: some View {
        ZStack {
            WindowMaterialBackdrop()
            if let item = current {
                ArtworkView(item: item, cornerRadius: 0)
                    .scaleEffect(1.12)
                    .blur(radius: 34)
                    .opacity(0.26)
            }
            Color.black.opacity(0.48)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.035),
                    Color(hex: current?.palette.middleHex ?? "43374F").opacity(0.24),
                    CinematicTheme.deepCanvas.opacity(0.88),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var likedQueue: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                HStack {
                    Button {
                        panelMode = .player
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 46, height: 46)
                            .cinematicGlassCircle(tint: .black.opacity(0.06))
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                    .help(language.text("Back to Player", "返回播放器"))

                    Spacer()

                    SettingsLink {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 46, height: 46)
                            .cinematicGlassCircle(tint: .black.opacity(0.06))
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                }

                VStack(spacing: 3) {
                    Text(language.text("Queue", "播放列表"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(language.text("Your liked wallpapers", "你喜欢的壁纸"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                }
                .padding(.top, 4)
            }

            HStack {
                Label(language.text("Liked", "喜欢"), systemImage: "heart.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 15)
                    .frame(height: 38)
                    .cinematicGlassCapsule(interactive: false, tint: .pink.opacity(0.12))
                Spacer()
            }
            .padding(.top, 18)

            if library.favorites.isEmpty {
                VStack(spacing: 13) {
                    Image(systemName: "heart")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.white.opacity(0.52))
                    Text(language.text("No liked wallpapers yet", "还没有喜欢的壁纸"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(language.text("Tap the heart in the player to add one.", "在播放器中点击爱心即可添加。"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(library.favorites) { item in
                            Button {
                                library.apply(item)
                                panelMode = .player
                            } label: {
                                HStack(spacing: 12) {
                                    ArtworkView(item: item, cornerRadius: 13)
                                        .frame(width: 86, height: 52)
                                        .clipped()

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.localizedTitle(for: language))
                                            .font(.system(size: 12, weight: .semibold))
                                            .lineLimit(1)
                                        Text(item.metadataLine)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.46))
                                    }

                                    Spacer()

                                    Image(systemName: engine.currentItem?.id == item.id ? "waveform" : "play.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .frame(width: 34, height: 34)
                                        .cinematicGlassCircle(tint: engine.currentItem?.id == item.id ? CinematicTheme.accent.opacity(0.14) : .black.opacity(0.04))
                                }
                                .padding(8)
                                .cinematicGlassPanel(cornerRadius: 18, interactive: true, tint: .black.opacity(0.05))
                            }
                            .buttonStyle(CinematicInteractiveButtonStyle(hoverScale: 1.012, pressedScale: 0.985))
                        }
                    }
                    .padding(.vertical, 14)
                }
                .padding(.top, 6)
            }
        }
        .padding(24)
    }

    private var emptyState: some View {
        VStack(spacing: 17) {
            ZStack {
                BrandLogoImage()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .frame(width: 74, height: 74)

            Text(language.text("Your Desktop Is Waiting", "桌面正在等待一个画面"))
                .font(.system(size: 19, weight: .bold))
            Text(language.text("Choose from the Foldwalls collection,\nor import your own images and videos.", "从 Foldwalls 精选中选择，\n或导入你自己的图片与视频。"))
                .font(.system(size: 11))
                .foregroundStyle(CinematicTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Button {
                openMainWindow()
            } label: {
                Label(language.text("Open Foldwalls", "打开 Foldwalls"), systemImage: "arrow.up.right")
            }
            .buttonStyle(CinematicButtonStyle(prominent: true))

            Button(language.text("Import Files", "导入文件")) {
                library.presentImportPanel()
            }
            .buttonStyle(CinematicInteractiveButtonStyle())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(CinematicTheme.secondaryText)
        }
        .padding(32)
    }

    private func openMainWindow() {
        MainAppWindowController.shared.show()
    }
}
