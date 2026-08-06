import AppKit
import AVFoundation
import Combine
import ImageIO
import IOKit.ps
import UniformTypeIdentifiers

final class WallpaperWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class WallpaperEngine: NSObject, ObservableObject {
    @Published private(set) var currentItem: WallpaperItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var isMuted = true
    @Published private(set) var playbackRate: Float = 1
    @Published private(set) var activeDisplayCount = 0
    @Published private(set) var activeDisplayNames: [String] = []
    @Published private(set) var isSystemWallpaperSynced = false
    @Published private(set) var systemWallpaperSyncError: String?

    private final class RenderUnit {
        let window: WallpaperWindow
        let loopController: CrossfadeVideoLoopController?

        init(window: WallpaperWindow, loopController: CrossfadeVideoLoopController? = nil) {
            self.window = window
            self.loopController = loopController
        }
    }

    private var units: [RenderUnit] = []
    nonisolated(unsafe) private var policyTimer: Timer?
    private var systemWallpaperTask: Task<Void, Never>?
    private var userPaused = false
    private var systemPaused = false
    private let systemWallpaperDirectory: URL = {
        let environment = ProcessInfo.processInfo.environment
        if let overridePath = environment["FOLDWALLS_LIBRARY_ROOT"] ?? environment["CINEMATIC_LIBRARY_ROOT"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
                .appendingPathComponent("SystemWallpapers", isDirectory: true)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Foldwalls", isDirectory: true)
            .appendingPathComponent("SystemWallpapers", isDirectory: true)
    }()

    override init() {
        super.init()
        isMuted = UserDefaults.standard.object(forKey: "wallpaperMuted") as? Bool ?? true
        let savedRate = UserDefaults.standard.float(forKey: "playbackRate")
        playbackRate = [0.5, 1, 1.5, 2].contains(savedRate) ? savedRate : 1
        try? FileManager.default.createDirectory(at: systemWallpaperDirectory, withIntermediateDirectories: true)
        registerLifecycleObservers()
        policyTimer = Timer.scheduledTimer(
            timeInterval: 3,
            target: self,
            selector: #selector(evaluatePlaybackPolicy),
            userInfo: nil,
            repeats: true
        )
        policyTimer?.tolerance = 0.5
    }

    deinit {
        systemWallpaperTask?.cancel()
        policyTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func apply(_ item: WallpaperItem) {
        guard FileManager.default.fileExists(atPath: item.localPath) else { return }
        stopRendering(clearCurrentItem: false)
        currentItem = item
        UserDefaults.standard.set(item.id.uuidString, forKey: "activeWallpaperID")
        userPaused = false
        systemPaused = false

        let screens = targetScreens
        for screen in screens {
            switch item.kind {
            case .image:
                if let unit = makeImageUnit(item: item, screen: screen) {
                    units.append(unit)
                }
            case .video:
                units.append(makeVideoUnit(item: item, screen: screen))
            }
        }

        activeDisplayCount = units.count
        activeDisplayNames = screens.map(\.localizedName)
        revealWindows()
        synchronizeSystemWallpaper(for: item, screens: screens)
        evaluatePlaybackPolicy()
    }

    func stop() {
        stopRendering(clearCurrentItem: true)
        UserDefaults.standard.removeObject(forKey: "activeWallpaperID")
    }

    func togglePlayback() {
        if userPaused {
            userPaused = false
            evaluatePlaybackPolicy()
        } else {
            userPaused = true
            pausePlayers()
        }
    }

    func pause() {
        userPaused = true
        pausePlayers()
    }

    func resume() {
        userPaused = false
        evaluatePlaybackPolicy()
    }

    func refreshPolicy() {
        evaluatePlaybackPolicy()
    }

    func refreshSystemWallpaperSync() {
        guard UserDefaults.standard.object(forKey: "syncLockScreenWallpaper") as? Bool ?? true,
              let currentItem else {
            systemWallpaperTask?.cancel()
            isSystemWallpaperSynced = false
            systemWallpaperSyncError = nil
            return
        }
        synchronizeSystemWallpaper(for: currentItem, screens: targetScreens)
    }

    func toggleMuted() {
        isMuted.toggle()
        UserDefaults.standard.set(isMuted, forKey: "wallpaperMuted")
        for unit in units {
            unit.loopController?.setMuted(isMuted)
        }
    }

    func setMuted(_ muted: Bool) {
        guard muted != isMuted else { return }
        toggleMuted()
    }

    func cyclePlaybackRate() {
        let rates: [Float] = [0.5, 1, 1.5, 2]
        let currentIndex = rates.firstIndex(of: playbackRate) ?? 1
        setPlaybackRate(rates[(currentIndex + 1) % rates.count])
    }

    func setPlaybackRate(_ rate: Float) {
        guard [0.5, 1, 1.5, 2].contains(rate) else { return }
        playbackRate = rate
        UserDefaults.standard.set(playbackRate, forKey: "playbackRate")
        guard isPlaying else { return }
        for unit in units where unit.loopController != nil {
            unit.loopController?.setPlaybackRate(playbackRate)
        }
    }

    private func synchronizeSystemWallpaper(for item: WallpaperItem, screens: [NSScreen]) {
        systemWallpaperTask?.cancel()
        guard UserDefaults.standard.object(forKey: "syncLockScreenWallpaper") as? Bool ?? true,
              !screens.isEmpty else {
            isSystemWallpaperSynced = false
            systemWallpaperSyncError = nil
            return
        }

        isSystemWallpaperSynced = false
        systemWallpaperSyncError = nil

        let immediateURL: URL? = switch item.kind {
        case .image:
            item.localURL
        case .video:
            item.thumbnailURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        }
        if let immediateURL {
            applySystemWallpaperURL(immediateURL, to: screens)
        }

        let maximumPixelSize = screens.reduce(CGFloat(1_920)) { current, screen in
            max(
                current,
                max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor
            )
        }
        let itemID = item.id
        let kind = item.kind
        let sourceURL = item.localURL
        let destinationDirectory = systemWallpaperDirectory

        systemWallpaperTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshotURL = try await Self.prepareSystemWallpaperSnapshot(
                    itemID: itemID,
                    kind: kind,
                    sourceURL: sourceURL,
                    maximumPixelSize: maximumPixelSize,
                    destinationDirectory: destinationDirectory
                )
                try Task.checkCancellation()
                guard self.currentItem?.id == itemID else { return }
                self.applySystemWallpaperURL(snapshotURL, to: self.targetScreens)
            } catch is CancellationError {
                return
            } catch {
                if !self.isSystemWallpaperSynced {
                    self.systemWallpaperSyncError = error.localizedDescription
                }
            }
        }
    }

    private func applySystemWallpaperURL(_ url: URL, to screens: [NSScreen]) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let fitEntireImage = UserDefaults.standard.string(forKey: "wallpaperFit") == "fit"
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: !fitEntireImage,
            .fillColor: NSColor.black,
        ]

        var successfulDisplays = 0
        var firstError: Error?
        for screen in screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
                successfulDisplays += 1
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        isSystemWallpaperSynced = successfulDisplays == screens.count
        systemWallpaperSyncError = firstError?.localizedDescription
    }

    private nonisolated static func prepareSystemWallpaperSnapshot(
        itemID: UUID,
        kind: WallpaperKind,
        sourceURL: URL,
        maximumPixelSize: CGFloat,
        destinationDirectory: URL
    ) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let values = try? sourceURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        let fileSize = values?.fileSize ?? 0
        let pixelSize = max(1_280, Int(maximumPixelSize.rounded(.up)))
        let destination = destinationDirectory
            .appendingPathComponent("\(itemID.uuidString)-\(modified)-\(fileSize)-\(pixelSize)")
            .appendingPathExtension("jpg")
        if fileManager.fileExists(atPath: destination.path) {
            pruneSystemWallpaperSnapshots(in: destinationDirectory, keeping: destination, limit: 8)
            return destination
        }

        let image: CGImage
        switch kind {
        case .image:
            guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixelSize,
                  ] as CFDictionary) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            image = thumbnail

        case .video:
            let asset = AVURLAsset(url: sourceURL)
            let duration = try? await asset.load(.duration).seconds
            let seconds = duration.flatMap { value in
                value.isFinite && value > 0 ? min(0.5, max(0.1, value * 0.08)) : nil
            } ?? 0.25
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: pixelSize, height: pixelSize)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.12, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.12, preferredTimescale: 600)
            image = try await generator.image(
                at: CMTime(seconds: seconds, preferredTimescale: 600)
            ).image
        }

        let temporaryURL = destinationDirectory
            .appendingPathComponent("snapshot-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        guard let imageDestination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(
            imageDestination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
        )
        guard CGImageDestinationFinalize(imageDestination) else {
            try? fileManager.removeItem(at: temporaryURL)
            throw CocoaError(.fileWriteUnknown)
        }

        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporaryURL, to: destination)
        pruneSystemWallpaperSnapshots(in: destinationDirectory, keeping: destination, limit: 8)
        return destination
    }

    private nonisolated static func pruneSystemWallpaperSnapshots(
        in directory: URL,
        keeping currentURL: URL,
        limit: Int
    ) {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let sorted = urls
            .filter { $0.pathExtension.lowercased() == "jpg" && $0 != currentURL }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
        for staleURL in sorted.dropFirst(max(0, limit - 1)) {
            try? fileManager.removeItem(at: staleURL)
        }
    }

    private func makeImageUnit(item: WallpaperItem, screen: NSScreen) -> RenderUnit? {
        guard let image = NSImage(contentsOf: item.localURL) else { return nil }
        let window = makeWallpaperWindow(for: screen)
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.contents = image
        view.layer?.contentsGravity = imageGravity
        view.layer?.contentsScale = screen.backingScaleFactor
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        return RenderUnit(window: window)
    }

    private func makeVideoUnit(item: WallpaperItem, screen: NSScreen) -> RenderUnit {
        let window = makeWallpaperWindow(for: screen)
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.autoresizingMask = [.width, .height]
        window.contentView = view

        let loopController = CrossfadeVideoLoopController(
            url: item.localURL,
            containerLayer: view.layer!,
            videoGravity: videoGravity,
            isMuted: isMuted,
            playbackRate: playbackRate,
            shouldPlay: false
        )
        return RenderUnit(window: window, loopController: loopController)
    }

    private func makeWallpaperWindow(for screen: NSScreen) -> WallpaperWindow {
        let window = WallpaperWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        window.level = NSWindow.Level(rawValue: desktopIconLevel - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.canHide = false
        window.setFrame(screen.frame, display: false)
        return window
    }

    private func revealWindows() {
        let duration = UserDefaults.standard.double(forKey: "transitionDuration")

        for unit in units {
            unit.window.alphaValue = 0
            unit.window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                unit.window.animator().alphaValue = 1
            }
        }
    }

    private func stopRendering(clearCurrentItem: Bool) {
        for unit in units {
            unit.loopController?.stop()
            unit.window.orderOut(nil)
            unit.window.close()
        }
        units.removeAll()
        activeDisplayCount = 0
        activeDisplayNames = []
        isPlaying = false
        if clearCurrentItem { currentItem = nil }
    }

    private var imageGravity: CALayerContentsGravity {
        UserDefaults.standard.string(forKey: "wallpaperFit") == "fit" ? .resizeAspect : .resizeAspectFill
    }

    private var videoGravity: AVLayerVideoGravity {
        UserDefaults.standard.string(forKey: "wallpaperFit") == "fit" ? .resizeAspect : .resizeAspectFill
    }

    private func registerLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(systemWillSleep), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(systemDidWake), name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func screenParametersChanged() {
        guard let currentItem else { return }
        apply(currentItem)
    }

    @objc private func systemWillSleep() {
        systemPaused = true
        pausePlayers()
    }

    @objc private func systemDidWake() {
        guard UserDefaults.standard.object(forKey: "resumeAfterWake") as? Bool ?? true else { return }
        systemPaused = false
        units.forEach { $0.window.orderFrontRegardless() }
        evaluatePlaybackPolicy()
    }

    @objc private func evaluatePlaybackPolicy() {
        guard currentItem != nil else {
            isPlaying = false
            return
        }

        let defaults = UserDefaults.standard
        let pauseOnBattery = defaults.object(forKey: "pauseOnBattery") as? Bool ?? false
        let pauseOnLowPower = defaults.object(forKey: "pauseOnLowPower") as? Bool ?? true
        let pauseWhenFullscreen = defaults.object(forKey: "pauseWhenFullscreen") as? Bool ?? true
        let shouldPause = userPaused
            || systemPaused
            || (pauseOnBattery && isUsingBatteryPower)
            || (pauseOnLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled)
            || (pauseWhenFullscreen && hasFullscreenForegroundWindow)

        if shouldPause {
            pausePlayers()
        } else {
            playPlayers()
        }
    }

    private func playPlayers() {
        for unit in units {
            unit.loopController?.setPlaybackRate(playbackRate)
            unit.loopController?.setPlaying(true)
        }
        isPlaying = currentItem?.kind == .image || units.contains { $0.loopController != nil }
    }

    private func pausePlayers() {
        for unit in units {
            unit.loopController?.setPlaying(false)
        }
        isPlaying = currentItem?.kind == .image && !systemPaused && !userPaused
    }

    private var isUsingBatteryPower: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as? String else {
            return false
        }
        return type == kIOPSBatteryPowerValue
    }

    private var targetScreens: [NSScreen] {
        if UserDefaults.standard.string(forKey: "displayMode") == "primary",
           let main = NSScreen.main ?? NSScreen.screens.first {
            return [main]
        }
        return NSScreen.screens
    }

    private var hasFullscreenForegroundWindow: Bool {
        guard let windowInfo = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                as? [[String: Any]] else { return false }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let screenSizes = NSScreen.screens.map(\.frame.size)

        return windowInfo.contains { window in
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"],
                  let height = bounds["Height"] else { return false }

            return screenSizes.contains { size in
                width >= size.width - 4 && height >= size.height - 4
            }
        }
    }
}
