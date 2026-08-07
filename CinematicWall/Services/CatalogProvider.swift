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
    let thumbnailURL: URL
    let previewVideoURL: URL?
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
    let categoryDetails: [LocalizedTaxonomyTerm]
    let tags: [String]
    let localizedTags: [LocalizedTaxonomyTerm]
    let featured: Bool
    let curated: Bool
    let popular: Bool
    let sortOrder: Int
    let paletteStart: String
    let paletteMiddle: String
    let paletteEnd: String
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
          "mediaURL": select(kind == "video" => video.asset->url, image.asset->url),
          "thumbnailURL": coalesce(thumbnail.asset->url, image.asset->url),
          "previewVideoURL": previewVideo.asset->url,
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
          "categoryDetails": coalesce(categoryRefs[]->{
            "id": coalesce(key, _id),
            "zh": coalesce(titleZh, ""),
            "en": coalesce(titleEn, titleZh, ""),
            order
          }, []),
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
        return envelope.result.filter { !$0.mediaURL.absoluteString.isEmpty && !$0.thumbnailURL.absoluteString.isEmpty }
    }

    private struct QueryEnvelope: Decodable {
        let result: [CatalogEntry]
    }
}
