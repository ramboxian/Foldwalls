import Foundation

enum WallpaperKind: String, Codable, CaseIterable, Sendable {
    case image
    case video

    func label(for language: AppLanguage = .current) -> String {
        switch self {
        case .image: language.text("Image", "图片")
        case .video: language.text("Motion", "动态")
        }
    }

    var symbolName: String {
        switch self {
        case .image: "photo"
        case .video: "play.fill"
        }
    }
}

enum WallpaperSource: String, Codable, Sendable {
    case curated
    case imported
    case downloaded
}

struct WallpaperPalette: Codable, Hashable, Sendable {
    let startHex: String
    let middleHex: String
    let endHex: String
}

struct WallpaperItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var subtitle: String
    var kind: WallpaperKind
    var source: WallpaperSource
    var localPath: String
    var thumbnailPath: String?
    var width: Int
    var height: Int
    var duration: TimeInterval?
    var fileSize: Int64
    var author: String
    var licenseName: String
    var sourceURL: URL?
    var categories: [String]
    var palette: WallpaperPalette
    var isFavorite: Bool
    var createdAt: Date
    /// Used by the folder synchronizer to detect replacements without hashing
    /// large video files on every launch. Optional keeps older manifests valid.
    var fileModifiedAt: Date? = nil
    /// Stable file-system identity lets a Finder rename retain favorites and ID.
    var fileSystemID: String? = nil
    /// Sanity document and CDN metadata. Optional fields keep manifests from
    /// older local-only builds fully decodable.
    var remoteID: String? = nil
    var remoteMediaURL: URL? = nil
    var remoteThumbnailURL: URL? = nil
    var remotePreviewVideoURL: URL? = nil
    var remotePreviewVideoSize: Int64? = nil
    var remoteUpdatedAt: String? = nil
    var remoteFileName: String? = nil
    var titleEn: String? = nil
    var subtitleEn: String? = nil
    var tags: [String]? = nil
    var isFeatured: Bool? = nil
    var isCurated: Bool? = nil
    var isPopular: Bool? = nil
    var sortOrder: Int? = nil
    var remoteCreatedAt: String? = nil

    var localURL: URL {
        URL(fileURLWithPath: localPath)
    }

    var thumbnailURL: URL? {
        thumbnailPath.map(URL.init(fileURLWithPath:))
    }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: localPath)
    }

    var resolutionLabel: String {
        guard width > 0, height > 0 else { return "—" }
        if width >= 3_840 || height >= 2_160 { return "4K" }
        if width >= 2_560 || height >= 1_440 { return "2K" }
        return "\(width)×\(height)"
    }

    var durationLabel: String? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var fileSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var metadataLine: String {
        [resolutionLabel, durationLabel, fileSize > 0 ? fileSizeLabel : nil]
            .compactMap { $0 }
            .joined(separator: "  •  ")
    }

    func localizedTitle(for language: AppLanguage) -> String {
        guard language == .english,
              let titleEn,
              !titleEn.isEmpty else { return title }
        return titleEn
    }

    func localizedSubtitle(for language: AppLanguage) -> String {
        guard language == .english,
              let subtitleEn,
              !subtitleEn.isEmpty else { return subtitle }
        return subtitleEn
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case image = "图片"
    case video = "动态"

    var id: String { rawValue }

    func label(for language: AppLanguage) -> String {
        switch self {
        case .all: language.text("All", "全部")
        case .image: language.text("Images", "图片")
        case .video: language.text("Motion", "动态")
        }
    }

    func includes(_ item: WallpaperItem) -> Bool {
        switch self {
        case .all: true
        case .image: item.kind == .image
        case .video: item.kind == .video
        }
    }
}
