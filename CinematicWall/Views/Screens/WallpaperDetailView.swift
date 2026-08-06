import SwiftUI

struct WallpaperDetailView: View {
    @EnvironmentObject private var library: WallpaperLibrary
    @EnvironmentObject private var engine: WallpaperEngine

    @State private var displayedID: UUID
    @AppStorage("appLanguage") private var languageRaw = AppLanguage.english.rawValue
    let onClose: () -> Void

    init(itemID: UUID, onClose: @escaping () -> Void = {}) {
        _displayedID = State(initialValue: itemID)
        self.onClose = onClose
    }

    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .english }
    private var item: WallpaperItem? { library.items.first { $0.id == displayedID } }

    private var similarItems: [WallpaperItem] {
        guard let item else { return [] }
        let sameMood = library.items.filter { candidate in
            candidate.id != item.id && !Set(candidate.categories).isDisjoint(with: Set(item.categories))
        }
        let rest = library.items.filter { candidate in
            candidate.id != item.id && !sameMood.contains(where: { $0.id == candidate.id })
        }
        return Array((sameMood + rest).prefix(6))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                WindowMaterialBackdrop()
                CinematicTheme.deepCanvas.opacity(0.72)

                if let item {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            hero(item, width: proxy.size.width)

                            if !similarItems.isEmpty {
                                VStack(alignment: .leading, spacing: 24) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(language.text("More Like This", "相似壁纸"))
                                            .font(.system(size: 30, weight: .bold, design: .rounded))
                                        Text(language.text("Selected to complement this scene", "根据画面氛围为你挑选"))
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(CinematicTheme.secondaryText)
                                    }

                                    LazyVGrid(columns: [
                                        GridItem(.flexible(), spacing: 24),
                                        GridItem(.flexible(), spacing: 24),
                                    ], spacing: 24) {
                                        ForEach(similarItems) { candidate in
                                            WallpaperCard(
                                                item: candidate,
                                                isActive: engine.currentItem?.id == candidate.id,
                                                onSelect: { withAnimation(.easeInOut(duration: 0.42)) { displayedID = candidate.id } },
                                                onApply: { library.apply(candidate) },
                                                onFavorite: { library.toggleFavorite(candidate) }
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal, 42)
                                .padding(.top, 42)
                                .padding(.bottom, 60)
                            }
                        }
                    }
                    .ignoresSafeArea(edges: .top)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 52, height: 52)
                            .cinematicGlassCircle(tint: .black.opacity(0.08))
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                    .help(language.text("Close", "关闭"))
                    .padding(24)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(CinematicTheme.specularEdge(intensity: 0.82), lineWidth: 0.9)
            }
            .shadow(color: .black.opacity(0.62), radius: 60, y: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    private func hero(_ item: WallpaperItem, width: CGFloat) -> some View {
        let height = min(760, max(620, width * 9 / 16))
        return ZStack(alignment: .bottom) {
            HeroMediaView(
                item: item,
                isPlaying: true,
                // A cloud item is not in the local library yet, so asking for
                // local-only playback leaves the detail hero on its poster.
                // Use the persistent lightweight preview immediately, then
                // prefer the full local original after Set Wallpaper finishes.
                videoAsset: item.isDownloaded ? .localOriginal : .compressedPreview
            )
                .frame(height: height)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.48),
                    .init(color: Color(hex: item.palette.middleHex).opacity(0.14), location: 0.68),
                    .init(color: CinematicTheme.deepCanvas.opacity(0.88), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LiquidGlassGroup(spacing: 14) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.localizedTitle(for: language))
                            .font(.system(size: 19, weight: .bold))
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            Label(item.width > 0 ? "\(item.width)×\(item.height)" : item.resolutionLabel, systemImage: "display")
                            if item.fileSize > 0 { Label(item.fileSizeLabel, systemImage: "doc") }
                            if let duration = item.durationLabel { Label(duration, systemImage: "clock") }
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                    }
                    .frame(width: 300, alignment: .leading)

                    Divider().frame(height: 34).overlay(.white.opacity(0.12))

                    if item.isDownloaded {
                        ShareLink(item: item.localURL) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                        .help(language.text("Share Wallpaper", "分享壁纸文件"))
                    }

                    Button { library.toggleFavorite(item) } label: {
                        Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(item.isFavorite ? .pink : .white)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                    .help(item.isFavorite ? language.text("Remove Favorite", "取消收藏") : language.text("Add Favorite", "加入收藏"))

                    if item.isDownloaded {
                        Button { library.revealInFinder(item) } label: {
                            Image(systemName: "folder").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                        }
                        .buttonStyle(CinematicInteractiveButtonStyle())
                        .help(language.text("Show in Finder", "在 Finder 中显示"))
                    }

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

                    if item.source != .curated {
                        Menu {
                            Button(language.text("Show in Finder", "在 Finder 中显示")) { library.revealInFinder(item) }
                            Divider()
                            Button(language.text("Remove from Library", "从资料库移除"), role: .destructive) {
                                library.remove(item)
                                onClose()
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 44, height: 44)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 12)
                .padding(.vertical, 12)
                .cinematicGlassCapsule(interactive: false, tint: Color(hex: item.palette.middleHex).opacity(0.10))
            }
            .padding(.bottom, 34)
            .shadow(color: .black.opacity(0.48), radius: 38, y: 18)
        }
        .frame(height: height)
        .id(item.id)
        .transition(.opacity)
    }
}
