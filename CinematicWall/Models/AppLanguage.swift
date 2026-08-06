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
        text("Foldwalls", "浮岛桌面")
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "en") ?? .english
    }
}

extension String {
    func localizedCategory(for language: AppLanguage) -> String {
        guard language == .english else { return self }
        return [
            "全部": "All", "自然": "Nature", "城市": "City", "太空": "Space",
            "抽象": "Abstract", "夜晚": "Night", "深色": "Dark", "静谧": "Serene",
            "动漫": "Anime", "森林": "Forest", "海洋": "Ocean", "玻璃": "Glass",
            "暖色": "Warm", "青色": "Teal", "极简": "Minimal", "天空": "Sky",
            "蓝色": "Blue", "我的壁纸": "My Wallpapers",
        ][self] ?? self
    }
}
