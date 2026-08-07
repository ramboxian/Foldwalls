import AVFoundation
import ImageIO
import QuartzCore
import SwiftUI

private struct DecodedArtwork: @unchecked Sendable {
    let image: NSImage
    let cost: Int
}

private func decodeArtwork(at url: URL, maxPixelSize: Int = 1_920) -> DecodedArtwork? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

    let thumbnailOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else { return nil }

    let image = NSImage(
        cgImage: cgImage,
        size: NSSize(width: cgImage.width, height: cgImage.height)
    )
    return DecodedArtwork(image: image, cost: cgImage.bytesPerRow * cgImage.height)
}

@MainActor
private final class ArtworkImageCache {
    static let shared = ArtworkImageCache()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlightLoads: [String: Task<DecodedArtwork?, Never>] = [:]

    private init() {
        cache.countLimit = 96
        cache.totalCostLimit = 192 * 1_024 * 1_024
    }

    func image(for url: URL, maxPixelSize: Int) async -> NSImage? {
        let key = cacheKey(for: url, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let existingLoad = inFlightLoads[key] {
            return await existingLoad.value?.image
        }

        let load = Task.detached(priority: .utility) {
            decodeArtwork(at: url, maxPixelSize: maxPixelSize)
        }
        inFlightLoads[key] = load
        let decoded = await load.value
        inFlightLoads[key] = nil

        guard let decoded else { return nil }
        cache.setObject(decoded.image, forKey: key as NSString, cost: decoded.cost)
        return decoded.image
    }

    private func cacheKey(for url: URL, maxPixelSize: Int) -> String {
        "\(url.standardizedFileURL.absoluteString)#\(maxPixelSize)"
    }
}

struct ArtworkView: View {
    @EnvironmentObject private var library: WallpaperLibrary
    @Environment(\.displayScale) private var displayScale
    let item: WallpaperItem
    var cornerRadius: CGFloat = CinematicTheme.cardRadius

    @State private var image: NSImage?
    @State private var loadedSourceKey = ""

    var body: some View {
        GeometryReader { proxy in
            let pixelSize = decodePixelSize(for: proxy.size)
            let sourceKey = item.thumbnailPath ?? item.remoteThumbnailURL?.absoluteString ?? item.localPath

            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: item.palette.startHex),
                        Color(hex: item.palette.middleHex),
                        Color(hex: item.palette.endHex),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .task(id: "\(item.id.uuidString)-\(sourceKey)-\(pixelSize)") {
                if loadedSourceKey != sourceKey {
                    image = nil
                    loadedSourceKey = sourceKey
                }

                guard let artworkURL = await library.resolvedArtworkURL(for: item),
                      !Task.isCancelled else { return }
                let loadedImage = await ArtworkImageCache.shared.image(
                    for: artworkURL,
                    maxPixelSize: pixelSize
                )
                guard !Task.isCancelled, let loadedImage else { return }
                image = loadedImage
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func decodePixelSize(for size: CGSize) -> Int {
        let requested = max(1, Int(ceil(max(size.width, size.height) * displayScale)))
        return [512, 768, 1_024, 1_280, 1_600, 1_920].first(where: { requested <= $0 }) ?? 1_920
    }
}

enum VideoPlaybackAsset: String {
    /// The full-resolution wallpaper video, either from the local library or
    /// directly from Sanity's original asset URL.
    case original
    /// The lightweight, persistently cached video generated for card previews.
    case compressedPreview
    /// Only play an original that is already present in the local library.
    case localOriginal
}

struct HeroMediaView: View {
    @EnvironmentObject private var library: WallpaperLibrary
    @Environment(\.scenePhase) private var scenePhase
    let item: WallpaperItem
    var isPlaying = true
    var videoAsset: VideoPlaybackAsset = .localOriginal

    @State private var resolvedVideoURL: URL?
    @State private var videoIsReady = false

    var body: some View {
        ZStack {
            ArtworkView(item: item, cornerRadius: 0)

            if item.kind == .video, let playableURL {
                LoopingVideoPreview(url: playableURL, isPlaying: isPlaying && scenePhase == .active) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        videoIsReady = true
                    }
                }
                .opacity(videoIsReady ? 1 : 0)
            }
        }
        .onChange(of: playableURL) { _, _ in
            videoIsReady = false
        }
        .task(id: "\(item.id.uuidString)-\(item.remotePreviewVideoURL?.absoluteString ?? item.remoteMediaURL?.absoluteString ?? item.localPath)-\(videoAsset.rawValue)-\(isPlaying)-\(scenePhase)") {
            guard item.kind == .video, isPlaying, scenePhase == .active else {
                resolvedVideoURL = nil
                return
            }
            resolvedVideoURL = nil

            switch videoAsset {
            case .original:
                // Start the full-resolution stream immediately, then populate
                // the persistent original cache without holding up playback.
                let immediateURL = library.immediateHeroVideoURL(for: item)
                resolvedVideoURL = immediateURL
                guard immediateURL?.isFileURL != true else { return }
                let cachedURL = await library.resolvedOriginalVideoURL(for: item)
                guard !Task.isCancelled else { return }
                if !videoIsReady, let cachedURL { resolvedVideoURL = cachedURL }
            case .compressedPreview:
                // The first hover streams the small preview immediately while
                // the same asset is cached for subsequent hovers.
                let immediateURL = library.immediateVideoPreviewURL(for: item)
                resolvedVideoURL = immediateURL
                guard immediateURL?.isFileURL != true else { return }
                let cachedURL = await library.resolvedVideoPreviewURL(for: item)
                guard !Task.isCancelled else { return }
                if !videoIsReady, let cachedURL { resolvedVideoURL = cachedURL }
            case .localOriginal:
                resolvedVideoURL = item.isDownloaded ? item.localURL : nil
            }
        }
    }

    private var playableURL: URL? {
        guard item.kind == .video else { return nil }
        switch videoAsset {
        case .original:
            return item.isDownloaded ? item.localURL : resolvedVideoURL
        case .compressedPreview:
            return resolvedVideoURL
        case .localOriginal:
            return item.isDownloaded ? item.localURL : nil
        }
    }
}

/// A non-looping, silent player for the closing film on Home. The player holds
/// its final decoded frame when playback ends. Leaving the visible scroll area
/// rewinds it, so the next visit starts cleanly from frame zero.
struct HomeStoryVideoPlayer: NSViewRepresentable {
    let url: URL
    let isActive: Bool

    func makeNSView(context: Context) -> HomeStoryPlayerView {
        HomeStoryPlayerView(url: url)
    }

    func updateNSView(_ view: HomeStoryPlayerView, context: Context) {
        view.setActive(isActive)
    }

    static func dismantleNSView(_ view: HomeStoryPlayerView, coordinator: Void) {
        view.stop()
    }
}

@MainActor
final class HomeStoryPlayerView: NSView {
    private let player: AVPlayer
    private let playerLayer: AVPlayerLayer
    private var isActive = false
    private var playbackGeneration = 0

    init(url: URL) {
        player = AVPlayer(url: url)
        playerLayer = AVPlayerLayer(player: player)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspectFill
        player.actionAtItemEnd = .pause
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        playbackGeneration += 1
        let generation = playbackGeneration

        player.pause()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      self.isActive,
                      self.playbackGeneration == generation else { return }
                self.player.playImmediately(atRate: 1)
            }
        }
    }

    func stop() {
        isActive = false
        playbackGeneration += 1
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

/// Plays two synchronized copies of the same movie and crossfades from the tail
/// of one into the head of the other. AVPlayerLooper removes transport gaps, but
/// it cannot hide a visual mismatch between the last and first frames; this
/// controller smooths that content boundary for previews and desktop playback.
@MainActor
final class CrossfadeVideoLoopController {
    private let url: URL
    private weak var containerLayer: CALayer?
    private let videoGravity: AVLayerVideoGravity
    private var players: [AVPlayer] = []
    private var playerLayers: [AVPlayerLayer] = []
    private var activeIndex = 0
    private var duration: CMTime = .invalid
    private var fadeDuration: TimeInterval = 0.72
    private var timeObserver: Any?
    private weak var observedPlayer: AVPlayer?
    private var preparationTask: Task<Void, Never>?
    private var standbyPreparationTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var firstFrameReadinessTask: Task<Void, Never>?
    private var isTransitioning = false
    private var standbyReady = false
    private var standbyPreparationGeneration = 0
    private var shouldPlay: Bool
    private var isMuted: Bool
    private var playbackRate: Float
    private var stopped = false
    private let onFirstFrameReady: @MainActor () -> Void

    init(
        url: URL,
        containerLayer: CALayer,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        isMuted: Bool = true,
        playbackRate: Float = 1,
        shouldPlay: Bool = true,
        onFirstFrameReady: @escaping @MainActor () -> Void = {}
    ) {
        self.url = url
        self.containerLayer = containerLayer
        self.videoGravity = videoGravity
        self.isMuted = isMuted
        self.playbackRate = playbackRate
        self.shouldPlay = shouldPlay
        self.onFirstFrameReady = onFirstFrameReady
        prepare()
    }

    func setPlaying(_ playing: Bool) {
        shouldPlay = playing
        guard !players.isEmpty else { return }
        if playing {
            players[activeIndex].playImmediately(atRate: playbackRate)
        } else {
            transitionTask?.cancel()
            transitionTask = nil
            isTransitioning = false
            players.forEach { $0.pause() }
            normalizeLayers()
            prepareStandbyPlayer()
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        for player in players {
            player.isMuted = muted
            player.volume = muted ? 0 : 1
        }
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        guard shouldPlay else { return }
        for (index, player) in players.enumerated() where index == activeIndex || isTransitioning {
            player.playImmediately(atRate: rate)
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        standbyPreparationGeneration += 1
        preparationTask?.cancel()
        standbyPreparationTask?.cancel()
        transitionTask?.cancel()
        firstFrameReadinessTask?.cancel()
        removeTimeObserver()
        for player in players {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        playerLayers.forEach {
            $0.player = nil
            $0.removeFromSuperlayer()
        }
        players.removeAll()
        playerLayers.removeAll()
    }

    private func prepare() {
        preparationTask = Task { [weak self] in
            guard let self else { return }
            let asset = AVURLAsset(url: url)
            guard let loadedDuration = try? await asset.load(.duration),
                  loadedDuration.isNumeric,
                  loadedDuration.seconds > 0.2,
                  !Task.isCancelled,
                  !stopped else { return }

            duration = loadedDuration
            fadeDuration = min(0.72, max(0.18, loadedDuration.seconds * 0.10))
            installPlayers(using: asset)
        }
    }

    private func installPlayers(using asset: AVAsset) {
        guard let containerLayer, !stopped else { return }

        for index in 0..<2 {
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 1
            item.preferredMaximumResolution = CGSize(width: 3_840, height: 2_160)

            let player = AVPlayer(playerItem: item)
            player.isMuted = isMuted
            player.volume = isMuted ? 0 : 1
            player.actionAtItemEnd = .pause
            player.automaticallyWaitsToMinimizeStalling = true
            player.preventsDisplaySleepDuringVideoPlayback = false

            let layer = AVPlayerLayer(player: player)
            layer.frame = containerLayer.bounds
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer.videoGravity = videoGravity
            layer.backgroundColor = NSColor.black.cgColor
            layer.opacity = index == 0 ? 1 : 0
            containerLayer.addSublayer(layer)

            players.append(player)
            playerLayers.append(layer)
        }

        observeActivePlayer()
        waitForFirstFrame()
        prepareStandbyPlayer()
        if shouldPlay {
            players[activeIndex].playImmediately(atRate: playbackRate)
        }
    }

    private func waitForFirstFrame() {
        firstFrameReadinessTask?.cancel()
        firstFrameReadinessTask = Task { [weak self] in
            for _ in 0..<250 {
                guard let self, !Task.isCancelled, !self.stopped else { return }
                if self.playerLayers.first?.isReadyForDisplay == true {
                    self.onFirstFrameReady()
                    self.firstFrameReadinessTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    private func observeActivePlayer() {
        removeTimeObserver()
        guard players.indices.contains(activeIndex) else { return }
        let player = players[activeIndex]
        observedPlayer = player
        let interval = CMTime(seconds: 1.0 / 24.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.handleTime(time)
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        observedPlayer = nil
    }

    private func handleTime(_ time: CMTime) {
        guard shouldPlay,
              !isTransitioning,
              duration.isNumeric,
              time.isNumeric else { return }

        let remaining = duration.seconds - time.seconds
        let incomingIndex = 1 - activeIndex
        if remaining <= fadeDuration,
           standbyReady,
           playerLayers.indices.contains(incomingIndex),
           playerLayers[incomingIndex].isReadyForDisplay {
            beginCrossfade()
        } else if remaining <= 0.08 {
            restartActivePlayerDirectly()
        }
    }

    private func beginCrossfade() {
        guard players.count == 2, playerLayers.count == 2, !isTransitioning else { return }
        isTransitioning = true

        let outgoingIndex = activeIndex
        let incomingIndex = 1 - outgoingIndex
        let incomingPlayer = players[incomingIndex]
        let outgoingLayer = playerLayers[outgoingIndex]
        let incomingLayer = playerLayers[incomingIndex]
        let realDuration = fadeDuration / max(Double(playbackRate), 0.1)

        standbyReady = false
        standbyPreparationGeneration += 1
        if let containerLayer {
            incomingLayer.removeFromSuperlayer()
            containerLayer.addSublayer(incomingLayer)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outgoingLayer.opacity = 1
        incomingLayer.opacity = 0
        CATransaction.commit()

        incomingPlayer.playImmediately(atRate: playbackRate)

        // Keep the outgoing frame fully opaque and dissolve only the prepared
        // incoming layer over it. Fading both layers at once exposes the black
        // backing layer at mid-transition and creates a visible brightness dip.
        CATransaction.begin()
        CATransaction.setAnimationDuration(realDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        incomingLayer.opacity = 1
        CATransaction.commit()

        transitionTask?.cancel()
        transitionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(realDuration))
            guard !Task.isCancelled else { return }
            self?.finishCrossfade(outgoingIndex: outgoingIndex, incomingIndex: incomingIndex)
        }
    }

    private func finishCrossfade(outgoingIndex: Int, incomingIndex: Int) {
        guard players.indices.contains(outgoingIndex), players.indices.contains(incomingIndex) else { return }
        players[outgoingIndex].pause()
        activeIndex = incomingIndex
        isTransitioning = false
        transitionTask = nil
        normalizeLayers()
        observeActivePlayer()
        prepareStandbyPlayer()
        if shouldPlay {
            players[activeIndex].playImmediately(atRate: playbackRate)
        }
    }

    private func prepareStandbyPlayer() {
        guard players.count == 2, !isTransitioning, !stopped else { return }
        let standbyIndex = 1 - activeIndex
        let player = players[standbyIndex]
        let rate = playbackRate

        standbyPreparationGeneration += 1
        let generation = standbyPreparationGeneration
        standbyReady = false
        standbyPreparationTask?.cancel()
        player.pause()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] finished in
            guard finished, let player else { return }
            Task { @MainActor [weak self, weak player] in
                guard let self, let player else { return }
                self.waitUntilStandbyIsReady(
                    player,
                    index: standbyIndex,
                    rate: rate,
                    generation: generation
                )
            }
        }
    }

    private func waitUntilStandbyIsReady(
        _ player: AVPlayer,
        index: Int,
        rate: Float,
        generation: Int
    ) {
        standbyPreparationTask?.cancel()
        standbyPreparationTask = Task { [weak self, weak player] in
            for _ in 0..<100 {
                guard let self,
                      let player,
                      !Task.isCancelled,
                      !self.stopped,
                      !self.isTransitioning,
                      generation == self.standbyPreparationGeneration,
                      index == 1 - self.activeIndex else { return }

                if player.status == .readyToPlay {
                    player.preroll(atRate: rate) { ready in
                        Task { @MainActor [weak self] in
                            guard let self,
                                  !self.stopped,
                                  !self.isTransitioning,
                                  generation == self.standbyPreparationGeneration,
                                  index == 1 - self.activeIndex else { return }
                            self.standbyReady = ready
                            self.standbyPreparationTask = nil
                        }
                    }
                    return
                }

                if player.status == .failed { return }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    private func restartActivePlayerDirectly() {
        guard players.indices.contains(activeIndex) else { return }
        let player = players[activeIndex]
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] finished in
            guard finished, let player else { return }
            Task { @MainActor [weak self] in
                guard let self, self.shouldPlay, !self.stopped else { return }
                player.playImmediately(atRate: self.playbackRate)
                self.prepareStandbyPlayer()
            }
        }
    }

    private func normalizeLayers() {
        guard playerLayers.count == 2 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayers[activeIndex].opacity = 1
        playerLayers[1 - activeIndex].opacity = 0
        CATransaction.commit()
    }
}

private struct LoopingVideoPreview: NSViewRepresentable {
    let url: URL
    let isPlaying: Bool
    let onReady: @MainActor () -> Void

    func makeNSView(context: Context) -> PreviewPlayerView {
        PreviewPlayerView(url: url, isPlaying: isPlaying, onReady: onReady)
    }

    func updateNSView(_ view: PreviewPlayerView, context: Context) {
        view.setOnReady(onReady)
        view.setPlaying(isPlaying)
        view.load(url: url)
    }

    static func dismantleNSView(_ view: PreviewPlayerView, coordinator: ()) {
        view.stop()
    }
}

private final class PreviewPlayerView: NSView {
    private var loopController: CrossfadeVideoLoopController?
    private var loadedURL: URL?
    private var shouldPlay: Bool
    private var onReady: @MainActor () -> Void

    init(url: URL, isPlaying: Bool, onReady: @escaping @MainActor () -> Void) {
        shouldPlay = isPlaying
        self.onReady = onReady
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        load(url: url)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
    }

    func setOnReady(_ callback: @escaping @MainActor () -> Void) {
        onReady = callback
    }

    func load(url: URL) {
        guard loadedURL != url else { return }
        stop()
        loadedURL = url

        if let layer {
            loopController = CrossfadeVideoLoopController(
                url: url,
                containerLayer: layer,
                videoGravity: .resizeAspectFill,
                isMuted: true,
                shouldPlay: shouldPlay,
                onFirstFrameReady: { [weak self] in self?.onReady() }
            )
        }
    }

    func setPlaying(_ isPlaying: Bool) {
        shouldPlay = isPlaying
        loopController?.setPlaying(isPlaying)
    }

    func stop() {
        loopController?.stop()
        loopController = nil
        loadedURL = nil
    }
}

struct WallpaperKindBadge: View {
    let item: WallpaperItem
    @AppStorage("appLanguage") private var languageRaw = AppLanguage.english.rawValue

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: item.kind.symbolName)
                .font(.system(size: 9, weight: .bold))
            Text(item.kind == .video ? (item.durationLabel ?? (AppLanguage(rawValue: languageRaw) ?? .english).text("Motion", "动态")) : item.resolutionLabel)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.black.opacity(0.52), in: Capsule())
        .overlay {
            Capsule().strokeBorder(CinematicTheme.specularEdge(intensity: 0.42), lineWidth: 0.7)
        }
    }
}
