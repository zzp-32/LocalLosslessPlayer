import CoreData
import SwiftUI
import UIKit

struct FunctionMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryViewModel
    @State private var page: MenuPage?

    enum MenuPage: String, Identifiable {
        case eq, timer, speed, info, theme
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PlayerPalette.background.ignoresSafeArea()
                List {
                    menuRow("slider.horizontal.3", "EQ 音效调节", .eq)
                    menuRow("timer", timerTitle, .timer)
                    menuRow("gauge.with.dots.needle.bottom.50percent", "播放速度", .speed)
                    menuRow("info.circle", "歌曲信息", .info)
                    menuRow("paintbrush", "主题切换", .theme)
                    menuRow("folder", "文件夹浏览", nil) { page = nil; dismiss() }
                    menuRow("trash", "清理无效文件", nil) { page = nil; dismiss() }
                    menuRow("questionmark.circle", "关于", nil) { page = nil; dismiss() }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("更多功能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }.foregroundStyle(PlayerPalette.green)
                }
            }
            .sheet(item: $page) { selected in
                switch selected {
                case .eq: EQView()
                case .timer: SleepTimerView()
                case .speed: PlaybackSpeedView()
                case .info: AudioInfoView()
                case .theme: ThemeView()
                }
            }
        }
        .environmentObject(player)
        .environmentObject(settings)
        .environmentObject(library)
        .preferredColorScheme(.dark)
    }

    private var timerTitle: String {
        guard let end = player.sleepTimerEnd else { return "定时关闭" }
        let seconds = max(0, Int(end.timeIntervalSinceNow))
        return "定时关闭（\(seconds / 60) 分钟）"
    }

    @ViewBuilder
    private func menuRow(_ icon: String, _ title: String, _ destination: MenuPage?, action: (() -> Void)? = nil) -> some View {
        Button {
            if let action { action() } else { page = destination }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium)).foregroundStyle(PlayerPalette.green).frame(width: 26)
                Text(title).foregroundStyle(PlayerPalette.primary)
                Spacer()
                if destination != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(PlayerPalette.secondary) }
            }
            .frame(height: 50)
        }
        .listRowBackground(PlayerPalette.surface)
        .listRowSeparatorTint(PlayerPalette.line)
    }
}

struct EQView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var player: PlayerViewModel
    private let frequencies = ["31", "62", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]

    var body: some View {
        NavigationStack {
            ZStack {
                PlayerPalette.background.ignoresSafeArea()
                VStack(spacing: 18) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(settings.equalizerGains.indices, id: \.self) { index in
                            VStack(spacing: 5) {
                                Text(String(format: "%+.0f", settings.equalizerGains[index])).font(.caption2.monospacedDigit()).foregroundStyle(PlayerPalette.secondary)
                                Slider(value: Binding(get: { settings.equalizerGains[index] }, set: { settings.equalizerGains[index] = $0; player.apply(settings: settings) }), in: -12...12)
                                    .tint(PlayerPalette.green).rotationEffect(.degrees(-90)).frame(width: 100, height: 26)
                                Text(frequencies[index]).font(.caption2).foregroundStyle(PlayerPalette.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 18)
                    .frame(height: 260)
                    VStack(spacing: 15) {
                        valueSlider("Preamp", value: Binding(get: { settings.preamp }, set: { settings.preamp = $0; player.apply(settings: settings) }), range: -12...12, suffix: " dB")
                        valueSlider("Balance", value: Binding(get: { settings.balance }, set: { settings.balance = $0; player.apply(settings: settings) }), range: -100...100, suffix: "")
                        Toggle(isOn: Binding(get: { settings.loudness }, set: { settings.loudness = $0; player.apply(settings: settings) })) { Label("Loudness", systemImage: "speaker.wave.2") }
                            .tint(PlayerPalette.green).foregroundStyle(PlayerPalette.primary)
                    }
                    .padding(.horizontal, 22)
                    Spacer()
                }
            }
            .navigationTitle("EQ 音效调节")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("重置") { settings.equalizerGains = Array(repeating: 0, count: 10); settings.preamp = 0; settings.balance = 0; settings.loudness = false; player.apply(settings: settings) }.foregroundStyle(PlayerPalette.green) } }
        }
        .preferredColorScheme(.dark)
    }

    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(spacing: 5) {
            HStack { Text(title).foregroundStyle(PlayerPalette.primary); Spacer(); Text(String(format: "%.0f%@", value.wrappedValue, suffix)).font(.caption.monospacedDigit()).foregroundStyle(PlayerPalette.secondary) }
            Slider(value: value, in: range).tint(PlayerPalette.green)
        }
    }
}

struct SleepTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerViewModel
    @State private var selected = 30
    private let options = [15, 30, 45, 60, 90, 120]

    var body: some View {
        NavigationStack {
            ZStack {
                PlayerPalette.background.ignoresSafeArea()
                VStack(spacing: 22) {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 42)).foregroundStyle(PlayerPalette.green).padding(.top, 35)
                    Text("播放结束后自动暂停").font(.headline).foregroundStyle(PlayerPalette.primary)
                    Picker("分钟", selection: $selected) { ForEach(options, id: \.self) { Text("\($0) 分钟").tag($0) } }.pickerStyle(.wheel).frame(height: 150)
                    Button("开始计时") { player.setSleepTimer(minutes: selected); dismiss() }.buttonStyle(.borderedProminent).tint(PlayerPalette.green)
                    if player.sleepTimerEnd != nil { Button("取消定时") { player.setSleepTimer(minutes: nil); dismiss() }.foregroundStyle(PlayerPalette.coral) }
                    Spacer()
                }
            }
            .navigationTitle("定时关闭")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}

struct PlaybackSpeedView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var player: PlayerViewModel
    private let speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        NavigationStack {
            List(speeds, id: \.self) { speed in
                Button { settings.playbackRate = speed; player.apply(settings: settings); dismiss() } label: {
                    HStack { Text(String(format: "%.2fx", speed)).foregroundStyle(PlayerPalette.primary); Spacer(); if abs(settings.playbackRate - speed) < 0.01 { Image(systemName: "checkmark").foregroundStyle(PlayerPalette.green) } }
                }.listRowBackground(PlayerPalette.surface)
            }
            .scrollContentBackground(.hidden)
            .background(PlayerPalette.background)
            .navigationTitle("播放速度")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}

private extension AppSettings.LyricsColor {
    var title: String {
        switch self {
        case .white: return "白色"
        case .green: return "绿色"
        case .cyan: return "青色"
        case .gold: return "金色"
        case .coral: return "珊瑚色"
        }
    }

    var color: Color {
        switch self {
        case .white: return .white
        case .green: return PlayerPalette.green
        case .cyan: return PlayerPalette.cyan
        case .gold: return PlayerPalette.gold
        case .coral: return PlayerPalette.coral
        }
    }
}

private extension AppSettings.LyricsAlignment {
    var title: String {
        switch self {
        case .left: return "左对齐"
        case .center: return "居中对齐"
        case .right: return "右对齐"
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}

private enum MoreSettingsPage: String, Identifiable {
    case eq, speed, lyrics
    var id: String { rawValue }
}

private struct MoreSettingsSheet: View {
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var page: MoreSettingsPage?

    var body: some View {
        NavigationStack {
            List {
                settingsRow("slider.horizontal.3", "音效") { page = .eq }
                settingsRow("gauge.with.dots.needle.bottom.50percent", "播放速度") { page = .speed }
                settingsRow("text.quote", "歌词设置") { page = .lyrics }
            }
            .scrollContentBackground(.hidden)
            .background(PlayerPalette.background)
            .navigationTitle("更多设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $page) { selected in
            Group {
                switch selected {
                case .eq: EQView()
                case .speed: PlaybackSpeedView()
                case .lyrics: LyricsSettingsView()
                }
            }
            .environmentObject(player)
            .environmentObject(settings)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func settingsRow(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .foregroundStyle(PlayerPalette.green)
                    .frame(width: 26)
                Text(title).foregroundStyle(PlayerPalette.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(PlayerPalette.secondary)
            }
            .frame(height: 52)
        }
        .listRowBackground(PlayerPalette.surface)
        .listRowSeparatorTint(PlayerPalette.line)
    }
}

private struct LyricsSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            List {
                Section("歌词基础样式") {
                    lyricSlider(title: "普通歌词大小", value: $settings.lyricFontSize, range: 14...32)
                    lyricSlider(title: "高亮歌词大小", value: $settings.lyricHighlightFontSize, range: 16...38)
                    Text("当前歌词预览")
                        .font(.system(size: settings.lyricHighlightFontSize, weight: .bold))
                        .foregroundStyle(settings.lyricHighlightColor.color)
                        .frame(maxWidth: .infinity, alignment: settings.lyricAlignment.frameAlignment)
                        .padding(.vertical, 8)
                }

                Section("歌词颜色") {
                    colorRow(title: "普通歌词颜色", selection: $settings.lyricColor)
                    colorRow(title: "高亮歌词颜色", selection: $settings.lyricHighlightColor)
                }

                Section("行间距设置") {
                    lyricSlider(title: "歌词行间距", value: $settings.lyricLineSpacing, range: 8...36)
                }

                Section("对齐方式") {
                    Picker("整体内容对齐", selection: $settings.lyricAlignment) {
                        ForEach(AppSettings.LyricsAlignment.allCases) { alignment in
                            Text(alignment.title).tag(alignment)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PlayerPalette.background)
            .navigationTitle("歌词设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private func lyricSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).foregroundStyle(PlayerPalette.primary)
                Spacer()
                Text(String(format: "%.0f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PlayerPalette.secondary)
            }
            Slider(value: value, in: range, step: 1).tint(PlayerPalette.green)
        }
        .padding(.vertical, 5)
    }

    private func colorRow(title: String, selection: Binding<AppSettings.LyricsColor>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).foregroundStyle(PlayerPalette.primary)
            HStack(spacing: 18) {
                ForEach(AppSettings.LyricsColor.allCases) { color in
                    Button { selection.wrappedValue = color } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 28, height: 28)
                            .overlay {
                                if selection.wrappedValue == color {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(color == .white ? .black : .white)
                                }
                            }
                    }
                    .accessibilityLabel(color.title)
                }
            }
        }
        .padding(.vertical, 5)
    }
}

struct ThemeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            List(AppSettings.Theme.allCases) { theme in
                Button { settings.theme = theme; dismiss() } label: {
                    HStack { Text(theme.title).foregroundStyle(PlayerPalette.primary); Spacer(); if settings.theme == theme { Image(systemName: "checkmark").foregroundStyle(PlayerPalette.green) } }
                }.listRowBackground(PlayerPalette.surface)
            }
            .scrollContentBackground(.hidden).background(PlayerPalette.background)
            .navigationTitle("主题切换").navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}

struct AudioInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                PlayerPalette.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    if let song = player.currentSong {
                        ArtworkTile(title: song.title, size: 150, large: true).padding(.top, 30)
                        infoRow("标题", song.title); infoRow("艺术家", song.artist.nilIfEmpty ?? "未知艺术家"); infoRow("专辑", song.album.nilIfEmpty ?? "未知专辑"); infoRow("格式", song.fileName.fileExtensionLabel); infoRow("时长", timeText(song.duration)); infoRow("文件", song.filePath)
                    } else { Text("当前没有播放歌曲").foregroundStyle(PlayerPalette.secondary) }
                    Spacer()
                }.padding(.horizontal, 20)
            }
            .navigationTitle("歌曲信息").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() }.foregroundStyle(PlayerPalette.green) } }
        }.preferredColorScheme(.dark)
    }

    private func infoRow(_ title: String, _ value: String) -> some View { HStack(alignment: .top) { Text(title).foregroundStyle(PlayerPalette.secondary).frame(width: 55, alignment: .leading); Text(value).foregroundStyle(PlayerPalette.primary).lineLimit(2); Spacer() }.padding(.top, 15) }
}

struct LyricLine {
    let time: Double?
    let text: String
}

enum LyricParser {
    static func parse(_ content: String) -> [LyricLine] {
        let rawLines = content.components(separatedBy: .newlines)
        var timedLines: [LyricLine] = []

        for rawLine in rawLines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = timestampExpression.matches(in: line, range: range)
            guard !matches.isEmpty else { continue }

            let lastMatch = matches[matches.count - 1]
            guard let textRange = Range(NSRange(location: NSMaxRange(lastMatch.range), length: range.length - NSMaxRange(lastMatch.range)), in: line) else { continue }
            let text = String(line[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            for match in matches {
                guard match.numberOfRanges == 3,
                      let minuteRange = Range(match.range(at: 1), in: line),
                      let secondRange = Range(match.range(at: 2), in: line),
                      let minute = Double(line[minuteRange]),
                      let second = Double(line[secondRange]) else { continue }
                timedLines.append(LyricLine(time: minute * 60 + second, text: text))
            }
        }

        if !timedLines.isEmpty {
            return timedLines.sorted { ($0.time ?? 0) < ($1.time ?? 0) }
        }

        return rawLines.compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !isMetadataLine(line) else { return nil }
            return LyricLine(time: nil, text: line)
        }
    }

    private static let timestampExpression = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{1,2}(?:\.\d{1,3})?)\]"#
    )

    private static func isMetadataLine(_ line: String) -> Bool {
        guard line.first == "[", line.last == "]", let colon = line.firstIndex(of: ":") else { return false }
        let key = line[line.index(after: line.startIndex)..<colon].lowercased()
        return ["ar", "ti", "al", "by", "offset", "re", "ve"].contains(key)
    }
}

struct LivePlaybackView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            PlayerPalette.background.ignoresSafeArea()
            if player.currentSong == nil {
                VStack(spacing: 14) {
                    Image(systemName: "play.circle").font(.system(size: 42)).foregroundStyle(PlayerPalette.green)
                    Text("还没有正在播放的歌曲").foregroundStyle(PlayerPalette.secondary)
                }
            } else {
                NowPlayingView()
                    .environmentObject(player)
                    .environmentObject(settings)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var displayMode: DisplayMode = .song
    @State private var metadataRevision = UUID()

    private enum DisplayMode {
        case song
        case lyrics
    }

    var body: some View {
        ZStack {
            PlayerPalette.background.ignoresSafeArea()
            if displayMode == .lyrics {
                LyricsArtworkBackground(artworkPath: player.currentSong?.artworkPath)
                    .id(metadataRevision)
                    .transition(.opacity)
            }
            VStack(spacing: 0) {
                nowPlayingHeader

                Group {
                    if displayMode == .song {
                        SongDisplayView()
                            .environmentObject(player)
                            .transition(.opacity)
                    } else {
                        InlineLyricsView()
                            .environmentObject(player)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(modeSwipeGesture)

                PlaybackControlsView()
                    .environmentObject(player)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { player.apply(settings: settings) }
        .onReceive(NotificationCenter.default.publisher(for: .songMetadataUpdated)) { notification in
            guard notification.object as? NSManagedObjectID == player.currentSong?.objectID else { return }
            metadataRevision = UUID()
        }
        .animation(.easeInOut(duration: 0.2), value: displayMode)
    }

    private var nowPlayingHeader: some View {
        HStack {
            Spacer()
            HStack(spacing: 14) {
                modeButton("歌曲", mode: .song)
                Text("|").foregroundStyle(Color.white.opacity(0.32))
                modeButton("歌词", mode: .lyrics)
            }
            Spacer()
        }
        .foregroundStyle(PlayerPalette.primary)
        .padding(.top, 4)
        .frame(height: 52)
    }

    private func modeButton(_ title: String, mode: DisplayMode) -> some View {
        Button {
            displayMode = mode
        } label: {
            Text(title)
                .font(.headline)
                .foregroundStyle(displayMode == mode ? PlayerPalette.primary : PlayerPalette.secondary)
                .frame(minWidth: 42, minHeight: 40)
        }
        .accessibilityAddTraits(displayMode == mode ? .isSelected : [])
    }

    private var modeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > 50, abs(horizontal) > abs(vertical) * 1.25 else { return }
                if horizontal < 0 {
                    displayMode = .lyrics
                } else {
                    displayMode = .song
                }
            }
    }
}

private struct SongDisplayView: View {
    @EnvironmentObject private var player: PlayerViewModel

    var body: some View {
        GeometryReader { proxy in
            let artworkSize = min(proxy.size.width - 48, min(340, max(190, proxy.size.height - 98)))
            VStack(spacing: 0) {
                Spacer(minLength: 8)
                ArtworkTile(
                    title: player.currentSong?.title ?? "",
                    size: artworkSize,
                    large: true,
                    artworkPath: player.currentSong?.artworkPath
                )
                Spacer(minLength: 14)
                VStack(alignment: .leading, spacing: 5) {
                    Text(player.currentSong?.title ?? "未播放")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(PlayerPalette.primary)
                        .lineLimit(1)
                    Text((player.currentSong?.artist).nilIfEmpty ?? "未知艺术家")
                        .font(.subheadline)
                        .foregroundStyle(PlayerPalette.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }
        }
    }
}

private struct InlineLyricsView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var lines: [LyricLine] = []
    @State private var currentIndex = 0
    @State private var isFollowingPlayback = true
    @State private var isMatching = false
    @State private var showingMoreSettings = false

    private var hasTimedLyrics: Bool {
        lines.contains { $0.time != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.currentSong?.title ?? "未播放")
                    .font(.headline)
                    .foregroundStyle(PlayerPalette.primary)
                    .lineLimit(1)
                Text((player.currentSong?.artist).nilIfEmpty ?? "未知艺术家")
                    .font(.subheadline)
                    .foregroundStyle(PlayerPalette.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)

            if lines.isEmpty {
                noLyricsView
            } else {
                lyricsScroller
            }
        }
        .onAppear { reloadLyrics() }
        .onChange(of: player.currentTime) { _ in syncCurrentLine() }
        .onChange(of: player.currentSong?.objectID) { _ in
            isFollowingPlayback = true
            reloadLyrics()
        }
        .onReceive(NotificationCenter.default.publisher(for: .songMetadataUpdated)) { notification in
            guard notification.object as? NSManagedObjectID == player.currentSong?.objectID else { return }
            reloadLyrics()
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 20) {
                Button { rematchLyrics() } label: {
                    if isMatching {
                        ProgressView().tint(PlayerPalette.primary)
                    } else {
                        Image(systemName: "magnifyingglass.circle")
                    }
                }
                .accessibilityLabel("重新匹配歌词")
                .disabled(isMatching)

                Button { showingMoreSettings = true } label: {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                }
                .accessibilityLabel("更多设置")
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(PlayerPalette.primary)
            .padding(.horizontal, 24)
            .padding(.bottom, 4)
        }
        .sheet(isPresented: $showingMoreSettings) {
            MoreSettingsSheet()
                .environmentObject(player)
                .environmentObject(settings)
        }
    }

    private var noLyricsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.quote")
                .font(.system(size: 34))
                .foregroundStyle(PlayerPalette.green)
            Text("暂无歌词")
                .font(.title3.weight(.semibold))
                .foregroundStyle(PlayerPalette.primary)
            Button {
                rematchLyrics()
            } label: {
                if isMatching {
                    ProgressView().tint(PlayerPalette.green)
                } else {
                    Label("重新匹配歌词", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .tint(PlayerPalette.green)
            .disabled(isMatching)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lyricsScroller: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: settings.lyricLineSpacing) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(line.text)
                                    .font(.system(size: hasTimedLyrics && index == currentIndex ? settings.lyricHighlightFontSize : settings.lyricFontSize, weight: hasTimedLyrics && index == currentIndex ? .bold : .semibold))
                                    .foregroundStyle(hasTimedLyrics && index == currentIndex ? settings.lyricHighlightColor.color : settings.lyricColor.color)
                                    .opacity(lineOpacity(at: index))
                                    .multilineTextAlignment(settings.lyricAlignment.textAlignment)
                                    .frame(width: max(0, geometry.size.width - 48), alignment: settings.lyricAlignment.frameAlignment)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .contentShape(Rectangle())
                                    .onTapGesture { seek(to: line, at: index, proxy: proxy) }
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 24)
                        .frame(width: geometry.size.width, alignment: .leading)
                        .padding(.vertical, max(72, geometry.size.height * 0.42))
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard abs(value.translation.height) > abs(value.translation.width),
                                      abs(value.translation.height) > 6 else { return }
                                isFollowingPlayback = false
                            }
                    )
                    .onChange(of: currentIndex) { index in
                        guard isFollowingPlayback else { return }
                        withAnimation(.easeInOut(duration: 0.32)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                    .onChange(of: lines.count) { _ in
                        DispatchQueue.main.async {
                            proxy.scrollTo(currentIndex, anchor: .center)
                        }
                    }

                    if !isFollowingPlayback {
                        Button {
                            isFollowingPlayback = true
                            syncCurrentLine()
                            withAnimation(.easeInOut(duration: 0.32)) {
                                proxy.scrollTo(currentIndex, anchor: .center)
                            }
                        } label: {
                            Label("回到正在播放", systemImage: "location.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(PlayerPalette.surface.opacity(0.92))
                                .cornerRadius(7)
                        }
                        .foregroundStyle(PlayerPalette.primary)
                        .padding(16)
                    }
                }
            }
        }
    }

    private func lineOpacity(at index: Int) -> Double {
        guard hasTimedLyrics else { return 0.76 }
        if index == currentIndex { return 1 }
        return abs(index - currentIndex) <= 2 ? 0.62 : 0.36
    }

    private func reloadLyrics() {
        guard let song = player.currentSong else {
            lines = []
            currentIndex = 0
            return
        }
        let url = song.lyricsPath.map { URL(fileURLWithPath: $0) }
            ?? SourceReference.sidecarURL(for: song, extension: "lrc")
        guard let url,
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            lines = []
            currentIndex = 0
            return
        }
        lines = LyricParser.parse(content)
        syncCurrentLine()
    }

    private func syncCurrentLine() {
        guard !lines.isEmpty, hasTimedLyrics else {
            currentIndex = 0
            return
        }
        currentIndex = max(0, lines.lastIndex(where: { ($0.time ?? .greatestFiniteMagnitude) <= player.currentTime }) ?? 0)
    }

    private func seek(to line: LyricLine, at index: Int, proxy: ScrollViewProxy) {
        guard let time = line.time else { return }
        player.seek(to: time)
        currentIndex = index
        isFollowingPlayback = true
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(index, anchor: .center)
        }
    }

    private func rematchLyrics() {
        guard let song = player.currentSong else { return }
        isMatching = true
        Task {
            await MetadataMatcher.shared.rematchLyrics(song: song)
            reloadLyrics()
            isMatching = false
        }
    }
}

private struct PlaybackControlsView: View {
    @EnvironmentObject private var player: PlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            Slider(
                value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                in: 0...max(player.duration, 1)
            )
            .tint(PlayerPalette.green)

            HStack {
                Text(timeText(player.currentTime))
                Spacer()
                Text(timeText(player.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(PlayerPalette.secondary)

            HStack {
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(player.isShuffled ? PlayerPalette.green : PlayerPalette.secondary)
                        .frame(width: 36, height: 36)
                }
                Spacer()
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                        .font(.title3)
                        .foregroundStyle(PlayerPalette.primary)
                        .frame(width: 46, height: 46)
                }
                Spacer()
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2.bold())
                        .foregroundStyle(PlayerPalette.background)
                        .frame(width: 64, height: 64)
                        .background(PlayerPalette.green)
                        .clipShape(Circle())
                }
                Spacer()
                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .foregroundStyle(PlayerPalette.primary)
                        .frame(width: 46, height: 46)
                }
                Spacer()
                Button { player.cycleRepeatMode() } label: {
                    Image(systemName: player.repeatMode.icon)
                        .foregroundStyle(player.repeatMode == .off ? PlayerPalette.secondary : PlayerPalette.green)
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }
}

private struct LyricsArtworkBackground: View {
    let artworkPath: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PlayerPalette.background
                if let artworkPath, let image = UIImage(contentsOfFile: artworkPath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .scaleEffect(1.18)
                        .blur(radius: 42)
                        .opacity(0.48)
                }
                Color.black.opacity(0.58)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }
}
