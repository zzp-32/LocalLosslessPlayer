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
    @Published var lyricFontSize: Double { didSet { persist() } }
    @Published var lyricHighlightFontSize: Double { didSet { persist() } }
    @Published var lyricColor: LyricsColor { didSet { persist() } }
    @Published var lyricHighlightColor: LyricsColor { didSet { persist() } }
    @Published var lyricLineSpacing: Double { didSet { persist() } }
    @Published var lyricAlignment: LyricsAlignment { didSet { persist() } }
    @Published var lyricOffset: Double { didSet { persist() } }

    enum Theme: String, CaseIterable, Identifiable {
        case dark, light, system
        var id: String { rawValue }
        var title: String {
            switch self { case .dark: return "深色"; case .light: return "浅色"; case .system: return "跟随系统" }
        }
    }

    enum LyricsColor: String, CaseIterable, Identifiable {
        case white, green, cyan, gold, coral
        var id: String { rawValue }
    }

    enum LyricsAlignment: String, CaseIterable, Identifiable {
        case left, center, right
        var id: String { rawValue }
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
        lyricFontSize = defaults.object(forKey: "lyrics.fontSize") as? Double ?? 19
        lyricHighlightFontSize = defaults.object(forKey: "lyrics.highlightFontSize") as? Double ?? 25
        lyricColor = LyricsColor(rawValue: defaults.string(forKey: "lyrics.color") ?? "white") ?? .white
        lyricHighlightColor = LyricsColor(rawValue: defaults.string(forKey: "lyrics.highlightColor") ?? "green") ?? .green
        lyricLineSpacing = defaults.object(forKey: "lyrics.lineSpacing") as? Double ?? 20
        lyricAlignment = LyricsAlignment(rawValue: defaults.string(forKey: "lyrics.alignment") ?? "left") ?? .left
        lyricOffset = defaults.object(forKey: "lyrics.offset") as? Double ?? 0
    }

    private func persist() {
        defaults.set(equalizerGains, forKey: "eq.gains")
        defaults.set(preamp, forKey: "eq.preamp")
        defaults.set(balance, forKey: "eq.balance")
        defaults.set(playbackRate, forKey: "playback.rate")
        defaults.set(loudness, forKey: "eq.loudness")
        defaults.set(theme.rawValue, forKey: "theme")
        defaults.set(lyricFontSize, forKey: "lyrics.fontSize")
        defaults.set(lyricHighlightFontSize, forKey: "lyrics.highlightFontSize")
        defaults.set(lyricColor.rawValue, forKey: "lyrics.color")
        defaults.set(lyricHighlightColor.rawValue, forKey: "lyrics.highlightColor")
        defaults.set(lyricLineSpacing, forKey: "lyrics.lineSpacing")
        defaults.set(lyricAlignment.rawValue, forKey: "lyrics.alignment")
        defaults.set(lyricOffset, forKey: "lyrics.offset")
    }
}
