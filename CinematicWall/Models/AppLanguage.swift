import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: "English"
        case .chinese: "中文"
        }
    }

    func text(_ english: String, _ chinese: String) -> String {
        self == .chinese ? chinese : english
    }

    var brandName: String {
        "Foldwalls"
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "en") ?? .english
    }
}

extension String {
    var canonicalCategoryID: String {
        [
            "全部": "all", "自然": "nature", "城市": "city", "人像": "portrait",
            "女孩": "girl", "宠物": "pet", "动漫": "anime", "电影": "movie",
            "游戏": "game", "科幻": "scifi", "车辆": "vehicle", "太空": "space",
            "抽象": "abstract", "夜晚": "night", "深色": "dark", "森林": "forest",
            "海洋": "ocean", "天空": "sky", "暖色": "warm", "蓝色": "blue",
            "静谧": "serene", "极简": "minimal",
        ][self] ?? self.lowercased()
    }

    func localizedCategory(for language: AppLanguage) -> String {
        guard language == .english else { return self }
        return [
            "全部": "All", "自然": "Nature", "城市": "City", "太空": "Space",
            "抽象": "Abstract", "夜晚": "Night", "深色": "Dark", "静谧": "Serene",
            "动漫": "Anime", "森林": "Forest", "海洋": "Ocean", "玻璃": "Glass",
            "暖色": "Warm", "青色": "Teal", "极简": "Minimal", "天空": "Sky",
            "蓝色": "Blue", "人像": "Portrait", "女孩": "Girls", "宠物": "Pets",
            "电影": "Movies", "游戏": "Games", "科幻": "Sci-Fi", "车辆": "Vehicles",
            "我的壁纸": "My Wallpapers",
        ][self] ?? self
    }
}
