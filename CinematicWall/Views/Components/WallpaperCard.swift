import AppKit
import SwiftUI

struct WallpaperCard: View {
    @EnvironmentObject private var library: WallpaperLibrary
    let item: WallpaperItem
    let isActive: Bool
    var showsText = true
    var rank: Int?
    let onSelect: () -> Void
    let onApply: () -> Void
    let onFavorite: () -> Void

    @State private var isHovering = false
    @State private var shouldPlayHoverPreview = false
    @State private var reflectionAngle: Angle = .degrees(-150)
    @AppStorage("appLanguage") private var languageRaw = AppLanguage.english.rawValue

    private var language: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .english }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                ArtworkView(item: item, cornerRadius: 0)
                if item.kind == .video && shouldPlayHoverPreview {
                    HeroMediaView(item: item, isPlaying: true, videoAsset: .compressedPreview)
                        .transition(.opacity)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.38),
                    .init(color: .black.opacity(isHovering ? 0.78 : 0.34), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if let rank {
                Text("\(rank)")
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(18)
                    .frame(maxHeight: .infinity, alignment: .top)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if item.kind == .video {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                    }
                    Text((item.primaryCategoryLabel(for: language) ?? item.kind.label(for: language)).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                    if isActive {
                        Circle().fill(CinematicTheme.success).frame(width: 6, height: 6)
                        Text(language.text("ACTIVE", "正在播放"))
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .foregroundStyle(isActive ? CinematicTheme.success : .white.opacity(0.67))

                Text(item.localizedTitle(for: language))
                    .font(.system(size: isHovering ? 23 : 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if isHovering {
                    Text(item.metadataLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(22)

            if isHovering {
                HStack(spacing: 8) {
                    Button(action: onFavorite) {
                        Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(item.isFavorite ? .pink : .white)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 46, height: 46)
                            .cinematicGlassCircle(tint: item.isFavorite ? .pink.opacity(0.18) : nil)
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())

                    Button(action: onApply) {
                        Group {
                            if library.isPreparing(item) {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: isActive ? "checkmark" : "desktopcomputer")
                                    .font(.system(size: 15, weight: .bold))
                            }
                        }
                        .foregroundStyle(.black)
                        .frame(width: 46, height: 46)
                        .background(.white, in: Circle())
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                    .disabled(library.preparingItemID != nil)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CinematicTheme.cardRadius, style: .continuous))
        .overlay {
            let outline = RoundedRectangle(cornerRadius: CinematicTheme.cardRadius, style: .continuous)
            if isActive || isHovering {
                outline.strokeBorder(
                    CinematicTheme.specularEdge(
                        intensity: isActive ? 1.35 : 1.0,
                        angle: reflectionAngle
                    ),
                    lineWidth: isActive ? 1.35 : 0.85
                )
            } else {
                outline.strokeBorder(.white.opacity(0.08), lineWidth: 0.75)
            }
        }
        .shadow(
            color: .black.opacity(isHovering ? 0.34 : 0),
            radius: isHovering ? 20 : 0,
            y: isHovering ? 11 : 0
        )
        .contentShape(RoundedRectangle(cornerRadius: CinematicTheme.cardRadius, style: .continuous))
        .onTapGesture(perform: onSelect)
        .scaleEffect(isHovering ? 1.024 : 1)
        .animation(.snappy(duration: 0.28, extraBounce: 0.02), value: isHovering)
        .task(id: "\(item.id.uuidString)-\(isHovering)") {
            guard item.kind == .video, isHovering else {
                shouldPlayHoverPreview = false
                return
            }

            do {
                try await Task.sleep(for: .seconds(1.5))
            } catch {
                return
            }

            guard !Task.isCancelled, isHovering else { return }
            shouldPlayHoverPreview = true
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                isHovering = true
                let progress = min(max(location.x / 620, 0), 1)
                reflectionAngle = .degrees(-175 + Double(progress) * 210)
                NSCursor.pointingHand.set()
            case .ended:
                isHovering = false
                shouldPlayHoverPreview = false
                NSCursor.arrow.set()
            }
        }
    }
}
