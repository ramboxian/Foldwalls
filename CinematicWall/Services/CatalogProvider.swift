import Foundation

struct CatalogEntry: Codable, Sendable {
    let id: String
    let createdAt: String
    let updatedAt: String
    let title: String
    let titleEn: String?
    let subtitle: String
    let subtitleEn: String?
    let mediaURL: URL
    let mediaFallbackURL: URL?
    let thumbnailURL: URL
    let thumbnailFallbackURL: URL?
    let previewVideoURL: URL?
    let previewVideoFallbackURL: URL?
    let previewVideoSize: Int64?
    let mediaFileName: String
    let kind: WallpaperKind
    let width: Int
    let height: Int
    let duration: TimeInterval?
    let fileSize: Int64
    let author: String
    let licenseName: String
    let sourceURL: URL?
    let categories: [String]
    // Broken or unpublished Sanity references are returned as `null`. Keep
    // those individual values from invalidating the entire first-run catalog.
    let categoryDetails: [LocalizedTaxonomyTerm?]
    let tags: [String]
    let localizedTags: [LocalizedTaxonomyTerm?]
    let featured: Bool
    let curated: Bool
    let popular: Bool
    let sortOrder: Int
    let paletteStart: String
    let paletteMiddle: String
    let paletteEnd: String
    let usesR2Delivery: Bool
}

protocol WallpaperCatalogProvider: Sendable {
    func fetchCatalog() async throws -> [CatalogEntry]
}

/// Reads only lightweight metadata from Sanity's live query endpoint.
/// The referenced image and video bytes stay on Sanity's asset CDN until a
/// thumbnail becomes visible or the user chooses to apply a wallpaper.
struct SanityCatalogProvider: WallpaperCatalogProvider {
    let projectID: String
    let dataset: String
    let apiVersion: String

    init(
        projectID: String = "3huccpow",
        dataset: String = "production",
        apiVersion: String = "2026-08-06"
    ) {
        self.projectID = projectID
        self.dataset = dataset
        self.apiVersion = apiVersion
    }

    func fetchCatalog() async throws -> [CatalogEntry] {
        let query = #"""
        *[_type == "wallpaper" && status == "published"] | order(sortOrder desc, _createdAt desc) {
          "id": _id,
          "createdAt": _createdAt,
          "updatedAt": _updatedAt,
          "title": coalesce(title, "未命名壁纸"),
          titleEn,
          "subtitle": coalesce(subtitle, ""),
          subtitleEn,
          kind,
          "sanityMediaURL": select(kind == "video" => video.asset->url, image.asset->url),
          "sanityThumbnailURL": coalesce(thumbnail.asset->url, image.asset->url),
          "sanityPreviewVideoURL": previewVideo.asset->url,
          r2MediaUrl,
          r2ThumbnailUrl,
          r2PreviewVideoUrl,
          "r2DeliveryEnabled": coalesce(r2DeliveryEnabled, false),
          "previewVideoSize": previewVideo.asset->size,
          "mediaFileName": coalesce(select(kind == "video" => video.asset->originalFilename, image.asset->originalFilename), "wallpaper"),
          "width": coalesce(width, select(kind == "video" => video.asset->metadata.dimensions.width, image.asset->metadata.dimensions.width), 0),
          "height": coalesce(height, select(kind == "video" => video.asset->metadata.dimensions.height, image.asset->metadata.dimensions.height), 0),
          duration,
          "fileSize": coalesce(select(kind == "video" => video.asset->size, image.asset->size), 0),
          "author": coalesce(author, ""),
          "licenseName": coalesce(licenseName, ""),
          "sourceURL": sourceUrl,
          "categories": coalesce(categories, []),
          "categoryDetails": array::compact(coalesce(categoryRefs[]->{
            "id": coalesce(key, _id),
            "zh": coalesce(titleZh, ""),
            "en": coalesce(titleEn, titleZh, ""),
            order
          }, [])),
          "tags": coalesce(tags, []),
          "localizedTags": coalesce(localizedTags[]{
            "id": coalesce(_key, zh, en),
            "zh": coalesce(zh, ""),
            "en": coalesce(en, zh, "")
          }, []),
          "featured": coalesce(featured, false),
          "curated": coalesce(curated, false),
          "popular": coalesce(popular, false),
          "sortOrder": coalesce(sortOrder, 100),
          "paletteStart": coalesce(paletteStart, "#10141B"),
          "paletteMiddle": coalesce(paletteMiddle, "#202A38"),
          "paletteEnd": coalesce(paletteEnd, "#080B10")
        }
        """#

        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(projectID).api.sanity.io"
        components.path = "/v\(apiVersion)/data/query/\(dataset)"
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "perspective", value: "published"),
            URLQueryItem(name: "returnQuery", value: "false"),
        ]
        guard let endpoint = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let envelope = try JSONDecoder().decode(QueryEnvelope.self, from: data)
        let forceR2 = ProcessInfo.processInfo.environment["FOLDWALLS_PREFER_R2"] == "1"
        return envelope.result.compactMap { entry in
            let useR2 = (entry.r2DeliveryEnabled || forceR2)
                && entry.r2MediaUrl != nil
                && entry.r2ThumbnailUrl != nil
            guard let mediaURL = useR2 ? entry.r2MediaUrl : entry.sanityMediaURL,
                  let thumbnailURL = useR2 ? entry.r2ThumbnailUrl : entry.sanityThumbnailURL else {
                return nil
            }
            return CatalogEntry(
                id: entry.id,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt,
                title: entry.title,
                titleEn: entry.titleEn,
                subtitle: entry.subtitle,
                subtitleEn: entry.subtitleEn,
                mediaURL: mediaURL,
                mediaFallbackURL: useR2 ? entry.sanityMediaURL : entry.r2MediaUrl,
                thumbnailURL: thumbnailURL,
                thumbnailFallbackURL: useR2 ? entry.sanityThumbnailURL : entry.r2ThumbnailUrl,
                previewVideoURL: useR2 ? (entry.r2PreviewVideoUrl ?? entry.sanityPreviewVideoURL) : entry.sanityPreviewVideoURL,
                previewVideoFallbackURL: useR2 ? entry.sanityPreviewVideoURL : entry.r2PreviewVideoUrl,
                previewVideoSize: entry.previewVideoSize,
                mediaFileName: entry.mediaFileName,
                kind: entry.kind,
                width: entry.width,
                height: entry.height,
                duration: entry.duration,
                fileSize: entry.fileSize,
                author: entry.author,
                licenseName: entry.licenseName,
                sourceURL: entry.sourceURL,
                categories: entry.categories,
                categoryDetails: entry.categoryDetails,
                tags: entry.tags,
                localizedTags: entry.localizedTags,
                featured: entry.featured,
                curated: entry.curated,
                popular: entry.popular,
                sortOrder: entry.sortOrder,
                paletteStart: entry.paletteStart,
                paletteMiddle: entry.paletteMiddle,
                paletteEnd: entry.paletteEnd,
                usesR2Delivery: useR2
            )
        }
    }

    private struct QueryEnvelope: Decodable {
        let result: [RawCatalogEntry]
    }

    private struct RawCatalogEntry: Decodable {
        let id: String
        let createdAt: String
        let updatedAt: String
        let title: String
        let titleEn: String?
        let subtitle: String
        let subtitleEn: String?
        let sanityMediaURL: URL?
        let sanityThumbnailURL: URL?
        let sanityPreviewVideoURL: URL?
        let r2MediaUrl: URL?
        let r2ThumbnailUrl: URL?
        let r2PreviewVideoUrl: URL?
        let r2DeliveryEnabled: Bool
        let previewVideoSize: Int64?
        let mediaFileName: String
        let kind: WallpaperKind
        let width: Int
        let height: Int
        let duration: TimeInterval?
        let fileSize: Int64
        let author: String
        let licenseName: String
        let sourceURL: URL?
        let categories: [String]
        let categoryDetails: [LocalizedTaxonomyTerm?]
        let tags: [String]
        let localizedTags: [LocalizedTaxonomyTerm?]
        let featured: Bool
        let curated: Bool
        let popular: Bool
        let sortOrder: Int
        let paletteStart: String
        let paletteMiddle: String
        let paletteEnd: String
    }
}
