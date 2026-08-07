import SwiftUI

struct UpdateProgressGlyph: View {
    @ObservedObject var manager: UpdateManager
    var size: CGFloat = 22
    var tint: Color = .white

    var body: some View {
        ZStack {
            if manager.isBusy {
                if let progress = manager.progress {
                    Circle()
                        .stroke(tint.opacity(0.22), lineWidth: 2.4)
                    Circle()
                        .trim(from: 0, to: max(progress, 0.025))
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.18), value: progress)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(tint)
                }
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: size * 0.56, weight: .black))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(manager.statusText)
    }
}

struct UpdateReleaseNotesView: View {
    @ObservedObject var manager: UpdateManager
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            WindowMaterialBackdrop()
            LinearGradient(
                colors: [Color(hex: "16251E").opacity(0.72), CinematicTheme.deepCanvas.opacity(0.86)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    UpdateProgressGlyph(manager: manager, size: 24)
                        .frame(width: 48, height: 48)
                        .background(CinematicTheme.success.opacity(0.88), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.text("Foldwalls Update", "Foldwalls 更新"))
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                        Text(versionLine)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CinematicTheme.secondaryText)
                    }

                    Spacer()

                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 34, height: 34)
                            .cinematicGlassCircle(tint: .black.opacity(0.08))
                    }
                    .buttonStyle(CinematicInteractiveButtonStyle())
                }

                ScrollView {
                    Text(manager.release?.notes ?? language.text(
                        "Release notes will appear here when a new version is available.",
                        "检测到新版本后，更新内容会显示在这里。"
                    ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CinematicTheme.primaryText.opacity(0.88))
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .frame(maxHeight: 220)
                .padding(16)
                .cinematicGlassPanel(cornerRadius: 18, interactive: false, tint: .black.opacity(0.06))

                HStack(spacing: 12) {
                    Text(localizedStatus)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(manager.phase == .failed ? Color.orange : CinematicTheme.secondaryText)
                        .lineLimit(2)

                    Spacer()

                    if manager.isUpdateAvailable || manager.isBusy {
                        Button {
                            manager.installAvailableUpdate()
                        } label: {
                            HStack(spacing: 9) {
                                UpdateProgressGlyph(manager: manager, size: 18, tint: .black)
                                Text(manager.isBusy
                                    ? language.text("Updating…", "正在更新…")
                                    : language.text("Update and Restart", "更新并重启"))
                            }
                            .frame(minWidth: 148)
                        }
                        .buttonStyle(CinematicButtonStyle(prominent: true))
                        .disabled(manager.isBusy)
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 430, height: 390)
        .preferredColorScheme(.dark)
    }

    private var versionLine: String {
        guard let release = manager.release else {
            return language.text("Current version ", "当前版本 ") + manager.currentVersion
        }
        var parts = [
            language.text("Version ", "版本 ") + release.version,
            language.text("Build ", "构建 ") + release.build,
        ]
        if let size = manager.formattedReleaseSize { parts.append(size) }
        return parts.joined(separator: "  ·  ")
    }

    private var localizedStatus: String {
        switch manager.phase {
        case .idle:
            return ""
        case .checking:
            return language.text("Checking for updates…", "正在检查更新…")
        case .available:
            return language.text(
                "Version \(manager.release?.version ?? "") is ready",
                "版本 \(manager.release?.version ?? "") 已可更新"
            )
        case .downloading:
            if let progress = manager.progress {
                return language.text(
                    "Downloading… \(Int(progress * 100))%",
                    "正在下载… \(Int(progress * 100))%"
                )
            }
            return language.text("Downloading update…", "正在下载更新…")
        case .extracting:
            return language.text("Preparing update…", "正在准备更新…")
        case .installing:
            return language.text("Installing and restarting…", "正在安装并重启…")
        case .upToDate:
            return language.text("You’re using the latest version", "当前已是最新版本")
        case .failed:
            return manager.lastError ?? language.text("Update failed", "更新失败")
        }
    }
}
