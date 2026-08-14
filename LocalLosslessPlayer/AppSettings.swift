import Combine
import Foundation

struct ParametricEQBand: Codable, Identifiable, Equatable {
    enum FilterType: String, Codable, CaseIterable {
        case lowShelf
        case parametric
        case highShelf
        case lowPass
        case highPass
    }

    var id = UUID()
    var frequency: Double
    var gain: Double
    var q: Double
    var filterType: FilterType
    var isEnabled = true
}

@MainActor
final class AppSettings: ObservableObject {
    static let equalizerFrequencies: [Double] = [
        20, 25, 31.5, 40, 50, 63, 80, 100,
        125, 160, 200, 250, 315, 400, 500, 630,
        800, 1_000, 1_250, 1_600, 2_000, 2_500, 3_150, 4_000,
        5_000, 6_300, 8_000, 10_000, 12_500, 16_000, 18_000, 20_000
    ]

    @Published var equalizerGains: [Double] { didSet { persist() } }
    @Published var selectedEqualizerPreset: EqualizerPreset { didSet { persist() } }
    @Published var preamp: Double { didSet { persist() } }
    @Published var balance: Double { didSet { persist() } }
    @Published var bassBoost: Double { didSet { persist() } }
    @Published var trebleBoost: Double { didSet { persist() } }
    @Published var stereoExpansion: Double { didSet { persist() } }
    @Published var monoAudio: Bool { didSet { persist() } }
    @Published var playbackRate: Double { didSet { persist() } }
    @Published var loudness: Bool { didSet { persist() } }
    @Published var parametricBands: [ParametricEQBand] { didSet { persist() } }
    @Published var theme: Theme { didSet { persist() } }
    @Published var lyricFontSize: Double { didSet { persist() } }
    @Published var lyricHighlightFontSize: Double { didSet { persist() } }
    @Published var lyricColor: LyricsColor { didSet { persist() } }
    @Published var lyricHighlightColor: LyricsColor { didSet { persist() } }
    @Published var lyricLineSpacing: Double { didSet { persist() } }
    @Published var lyricAlignment: LyricsAlignment { didSet { persist() } }
    @Published var lyricOffset: Double { didSet { persist() } }

    enum EqualizerPreset: String, CaseIterable, Identifiable {
        case standard
        case pop
        case rock
        case classical
        case vocal
        case bassBoost
        case acoustic
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .standard: return "默认"
            case .pop: return "流行"
            case .rock: return "摇滚"
            case .classical: return "古典"
            case .vocal: return "人声"
            case .bassBoost: return "低音增强"
            case .acoustic: return "原声"
            case .custom: return "自定义"
            }
        }
    }

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
    private var customEqualizerGains: [Double]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedGains = defaults.array(forKey: "eq.gains") as? [Double] ?? []
        equalizerGains = Self.migratedGains(storedGains)
        customEqualizerGains = Self.migratedGains(defaults.array(forKey: "eq.customGains") as? [Double] ?? storedGains)
        selectedEqualizerPreset = EqualizerPreset(rawValue: defaults.string(forKey: "eq.preset") ?? "custom") ?? .custom
        preamp = defaults.object(forKey: "eq.preamp") as? Double ?? 0
        balance = defaults.object(forKey: "eq.balance") as? Double ?? 0
        bassBoost = defaults.object(forKey: "eq.bassBoost") as? Double ?? 0
        trebleBoost = defaults.object(forKey: "eq.trebleBoost") as? Double ?? 0
        stereoExpansion = defaults.object(forKey: "eq.stereoExpansion") as? Double ?? 0
        monoAudio = defaults.object(forKey: "eq.monoAudio") as? Bool ?? false
        playbackRate = defaults.object(forKey: "playback.rate") as? Double ?? 1
        loudness = defaults.object(forKey: "eq.loudness") as? Bool ?? false
        if let data = defaults.data(forKey: "eq.parametricBands"),
           let bands = try? JSONDecoder().decode([ParametricEQBand].self, from: data) {
            parametricBands = bands
        } else {
            parametricBands = []
        }
        theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "dark") ?? .dark
        lyricFontSize = defaults.object(forKey: "lyrics.fontSize") as? Double ?? 19
        lyricHighlightFontSize = defaults.object(forKey: "lyrics.highlightFontSize") as? Double ?? 25
        lyricColor = LyricsColor(rawValue: defaults.string(forKey: "lyrics.color") ?? "white") ?? .white
        lyricHighlightColor = LyricsColor(rawValue: defaults.string(forKey: "lyrics.highlightColor") ?? "green") ?? .green
        lyricLineSpacing = defaults.object(forKey: "lyrics.lineSpacing") as? Double ?? 20
        lyricAlignment = LyricsAlignment(rawValue: defaults.string(forKey: "lyrics.alignment") ?? "left") ?? .left
        lyricOffset = defaults.object(forKey: "lyrics.offset") as? Double ?? 0
    }

    func setEqualizerGain(_ value: Double, at index: Int) {
        guard equalizerGains.indices.contains(index) else { return }
        equalizerGains[index] = max(-12, min(12, value))
        customEqualizerGains = equalizerGains
        selectedEqualizerPreset = .custom
    }

    func applyEqualizerPreset(_ preset: EqualizerPreset) {
        selectedEqualizerPreset = preset
        if preset == .custom {
            equalizerGains = customEqualizerGains
        } else {
            equalizerGains = Self.equalizerFrequencies.map { presetGain(for: $0, preset: preset) }
        }
    }

    func resetAudioEffects() {
        selectedEqualizerPreset = .standard
        equalizerGains = Array(repeating: 0, count: Self.equalizerFrequencies.count)
        preamp = 0
        balance = 0
        bassBoost = 0
        trebleBoost = 0
        stereoExpansion = 0
        monoAudio = false
        loudness = false
        playbackRate = 1
    }

    private func persist() {
        defaults.set(equalizerGains, forKey: "eq.gains")
        defaults.set(customEqualizerGains, forKey: "eq.customGains")
        defaults.set(selectedEqualizerPreset.rawValue, forKey: "eq.preset")
        defaults.set(preamp, forKey: "eq.preamp")
        defaults.set(balance, forKey: "eq.balance")
        defaults.set(bassBoost, forKey: "eq.bassBoost")
        defaults.set(trebleBoost, forKey: "eq.trebleBoost")
        defaults.set(stereoExpansion, forKey: "eq.stereoExpansion")
        defaults.set(monoAudio, forKey: "eq.monoAudio")
        defaults.set(playbackRate, forKey: "playback.rate")
        defaults.set(loudness, forKey: "eq.loudness")
        if let data = try? JSONEncoder().encode(parametricBands) {
            defaults.set(data, forKey: "eq.parametricBands")
        }
        defaults.set(theme.rawValue, forKey: "theme")
        defaults.set(lyricFontSize, forKey: "lyrics.fontSize")
        defaults.set(lyricHighlightFontSize, forKey: "lyrics.highlightFontSize")
        defaults.set(lyricColor.rawValue, forKey: "lyrics.color")
        defaults.set(lyricHighlightColor.rawValue, forKey: "lyrics.highlightColor")
        defaults.set(lyricLineSpacing, forKey: "lyrics.lineSpacing")
        defaults.set(lyricAlignment.rawValue, forKey: "lyrics.alignment")
        defaults.set(lyricOffset, forKey: "lyrics.offset")
    }

    private static func migratedGains(_ stored: [Double]) -> [Double] {
        guard !stored.isEmpty else { return Array(repeating: 0, count: equalizerFrequencies.count) }
        guard stored.count != equalizerFrequencies.count else { return stored.map { max(-12, min(12, $0)) } }

        let oldFrequencies = [31.0, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
        guard stored.count == oldFrequencies.count else { return Array(repeating: 0, count: equalizerFrequencies.count) }
        return equalizerFrequencies.map { frequency in
            guard let upper = oldFrequencies.firstIndex(where: { $0 >= frequency }) else { return stored.last ?? 0 }
            guard upper > 0 else { return stored[0] }
            let lower = upper - 1
            let lowLog = log(oldFrequencies[lower])
            let highLog = log(oldFrequencies[upper])
            let fraction = (log(frequency) - lowLog) / (highLog - lowLog)
            return stored[lower] + (stored[upper] - stored[lower]) * fraction
        }
    }

    private func presetGain(for frequency: Double, preset: EqualizerPreset) -> Double {
        switch preset {
        case .standard, .custom:
            return 0
        case .pop:
            if frequency < 100 { return 2.5 }
            if frequency < 400 { return 1 }
            if frequency < 1_600 { return -0.8 }
            if frequency < 6_300 { return 2.4 }
            return 1.2
        case .rock:
            if frequency < 160 { return 3.5 }
            if frequency < 800 { return 0.5 }
            if frequency < 2_500 { return -1.2 }
            if frequency < 10_000 { return 3.2 }
            return 1.5
        case .classical:
            if frequency < 80 { return 0.5 }
            if frequency < 500 { return 1.8 }
            if frequency < 2_000 { return -0.4 }
            if frequency < 8_000 { return 1.4 }
            return 2.3
        case .vocal:
            if frequency < 125 { return -2.5 }
            if frequency < 500 { return -0.8 }
            if frequency < 4_000 { return 3.2 }
            if frequency < 8_000 { return 1.2 }
            return -0.5
        case .bassBoost:
            if frequency < 50 { return 6 }
            if frequency < 100 { return 5 }
            if frequency < 250 { return 3 }
            if frequency < 500 { return 1 }
            return 0
        case .acoustic:
            if frequency < 100 { return 1 }
            if frequency < 400 { return 2 }
            if frequency < 1_250 { return 0.5 }
            if frequency < 5_000 { return 2.5 }
            if frequency < 12_500 { return 1.5 }
            return 0
        }
    }
}
