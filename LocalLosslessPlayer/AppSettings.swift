import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var equalizerGains: [Double] { didSet { persist() } }
    @Published var preamp: Double { didSet { persist() } }
    @Published var balance: Double { didSet { persist() } }
    @Published var playbackRate: Double { didSet { persist() } }
    @Published var loudness: Bool { didSet { persist() } }
    @Published var theme: Theme { didSet { persist() } }
    @Published var libraryFolderBookmark: Data? { didSet { persist() } }
    @Published var libraryFolderDisplayName: String? { didSet { persist() } }

    enum Theme: String, CaseIterable, Identifiable {
        case dark, light, system
        var id: String { rawValue }
        var title: String {
            switch self { case .dark: return "深色"; case .light: return "浅色"; case .system: return "跟随系统" }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        equalizerGains = defaults.array(forKey: "eq.gains") as? [Double] ?? Array(repeating: 0, count: 10)
        preamp = defaults.object(forKey: "eq.preamp") as? Double ?? 0
        balance = defaults.object(forKey: "eq.balance") as? Double ?? 0
        playbackRate = defaults.object(forKey: "playback.rate") as? Double ?? 1
        loudness = defaults.object(forKey: "eq.loudness") as? Bool ?? false
        theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "dark") ?? .dark
        libraryFolderBookmark = defaults.data(forKey: "library.folder.bookmark")
        libraryFolderDisplayName = defaults.string(forKey: "library.folder.name")
    }

    private func persist() {
        defaults.set(equalizerGains, forKey: "eq.gains")
        defaults.set(preamp, forKey: "eq.preamp")
        defaults.set(balance, forKey: "eq.balance")
        defaults.set(playbackRate, forKey: "playback.rate")
        defaults.set(loudness, forKey: "eq.loudness")
        defaults.set(theme.rawValue, forKey: "theme")
        defaults.set(libraryFolderBookmark, forKey: "library.folder.bookmark")
        defaults.set(libraryFolderDisplayName, forKey: "library.folder.name")
    }
}
