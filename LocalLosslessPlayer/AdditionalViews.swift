import SwiftUI

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
    private let speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

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

struct LyricsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerViewModel
    @State private var lines: [LyricLine] = []
    @State private var currentIndex = 0

    var body: some View {
        ZStack {
            PlayerPalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack { Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 40, height: 40) }; Spacer(); Text("歌词").font(.headline).foregroundStyle(PlayerPalette.primary); Spacer(); Color.clear.frame(width: 40, height: 40) }.foregroundStyle(PlayerPalette.primary)
                if let song = player.currentSong {
                    VStack(spacing: 14) { Spacer(); Image(systemName: "text.quote").font(.system(size: 34)).foregroundStyle(PlayerPalette.green); Text("暂未找到歌词").font(.title3.weight(.semibold)).foregroundStyle(PlayerPalette.primary); Text(song.title).font(.subheadline).foregroundStyle(PlayerPalette.secondary); Text("支持内嵌歌词和同名 .lrc 文件").font(.caption).foregroundStyle(PlayerPalette.secondary); Spacer() }.multilineTextAlignment(.center)
                } else { Spacer(); Text("开始播放后显示歌词").foregroundStyle(PlayerPalette.secondary); Spacer() }
            }.padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
        .onAppear { loadLyrics() }
        .onChange(of: player.currentTime) { _ in updateCurrentLine() }
        .onChange(of: player.currentSong?.objectID) { _ in loadLyrics() }
    }

    private func loadLyrics() {
        guard let song = player.currentSong else { lines = []; return }
        let url = song.lyricsPath.map { URL(fileURLWithPath: $0) } ?? SourceReference.sidecarURL(for: song, extension: "lrc")
        guard let url else { lines = []; return }
        lines = (try? String(contentsOf: url, encoding: .utf8)).map(LyricParser.parse) ?? []
        currentIndex = 0
    }

    private func updateCurrentLine() {
        guard !lines.isEmpty else { return }
        currentIndex = max(0, lines.lastIndex(where: { $0.time <= player.currentTime }) ?? 0)
    }
}

struct LyricLine { let time: Double; let text: String }

enum LyricParser {
    static func parse(_ content: String) -> [LyricLine] {
        content.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = String(raw)
            guard let close = line.firstIndex(of: "]"), line.first == "[" else { return nil }
            let stamp = String(line[line.index(after: line.startIndex)..<close])
            let parts = stamp.split(separator: ":")
            guard parts.count == 2, let minute = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
            let text = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            return LyricLine(time: minute * 60 + seconds, text: text)
        }.sorted { $0.time < $1.time }
    }
}

struct RealLyricsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerViewModel
    @State private var lines: [LyricLine] = []
    @State private var currentIndex = 0

    var body: some View {
        ZStack {
            PlayerPalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 40, height: 40) }
                    Spacer(); Text("歌词").font(.headline); Spacer(); Color.clear.frame(width: 40, height: 40)
                }.foregroundStyle(PlayerPalette.primary)
                if lines.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "text.quote").font(.system(size: 34)).foregroundStyle(PlayerPalette.green)
                        Text("暂未找到歌词").font(.title3.weight(.semibold)).foregroundStyle(PlayerPalette.primary)
                        Text("请将同名 .lrc 文件和歌曲一起导入").font(.caption).foregroundStyle(PlayerPalette.secondary)
                    }.multilineTextAlignment(.center)
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 18) {
                                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                    Text(line.text)
                                        .font(index == currentIndex ? .title3.weight(.bold) : .body)
                                        .foregroundStyle(index == currentIndex ? PlayerPalette.green : PlayerPalette.secondary)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                        .id(index)
                                }
                            }.padding(.vertical, 120)
                        }
                        .onChange(of: currentIndex) { index in withAnimation { proxy.scrollTo(index, anchor: .center) } }
                    }
                }
            }.padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .songMetadataUpdated)) { _ in reload() }
        .onChange(of: player.currentTime) { _ in sync() }
        .onChange(of: player.currentSong?.objectID) { _ in reload() }
    }

    private func reload() {
        guard let song = player.currentSong else { lines = []; return }
        let url = song.lyricsPath.map { URL(fileURLWithPath: $0) } ?? SourceReference.sidecarURL(for: song, extension: "lrc")
        guard let url else { lines = []; return }
        lines = (try? String(contentsOf: url, encoding: .utf8)).map(LyricParser.parse) ?? []
        currentIndex = 0
    }

    private func sync() {
        guard !lines.isEmpty else { return }
        currentIndex = max(0, lines.lastIndex(where: { $0.time <= player.currentTime }) ?? 0)
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
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var showingLyrics = false

    var body: some View {
        ZStack {
            PlayerPalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 40, height: 40) }
                    Spacer()
                    Button { showingLyrics = true } label: { Image(systemName: "text.quote").frame(width: 40, height: 40) }.accessibilityLabel("打开歌词")
                }
                .foregroundStyle(PlayerPalette.primary)
                .padding(.top, 4)

                Spacer(minLength: 16)
                ArtworkTile(title: player.currentSong?.title ?? "", size: min(UIScreen.main.bounds.width - 48, 340), large: true, artworkPath: player.currentSong?.artworkPath)
                Spacer(minLength: 22)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(player.currentSong?.title ?? "未播放").font(.title3.weight(.bold)).foregroundStyle(PlayerPalette.primary).lineLimit(1)
                        Text((player.currentSong?.artist).nilIfEmpty ?? "未知艺术家").font(.subheadline).foregroundStyle(PlayerPalette.secondary).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.bottom, 18)

                Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }), in: 0...max(player.duration, 1)).tint(PlayerPalette.green)
                HStack { Text(timeText(player.currentTime)); Spacer(); Text("-\(timeText(max(0, player.duration - player.currentTime)))") }.font(.caption2.monospacedDigit()).foregroundStyle(PlayerPalette.secondary)

                HStack {
                    Button { player.toggleShuffle() } label: { Image(systemName: "shuffle").foregroundStyle(player.isShuffled ? PlayerPalette.green : PlayerPalette.secondary).frame(width: 36, height: 36) }
                    Spacer()
                    Button { player.previous() } label: { Image(systemName: "backward.fill").font(.title3).foregroundStyle(PlayerPalette.primary).frame(width: 46, height: 46) }
                    Spacer()
                    Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2.bold()).foregroundStyle(PlayerPalette.background).frame(width: 68, height: 68).background(PlayerPalette.green).clipShape(Circle()) }
                    Spacer()
                    Button { player.next() } label: { Image(systemName: "forward.fill").font(.title3).foregroundStyle(PlayerPalette.primary).frame(width: 46, height: 46) }
                    Spacer()
                    Button { player.cycleRepeatMode() } label: { Image(systemName: player.repeatMode.icon).foregroundStyle(player.repeatMode == .off ? PlayerPalette.secondary : PlayerPalette.green).frame(width: 36, height: 36) }
                }
                .padding(.top, 22)
                Spacer(minLength: 18)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .onAppear { player.apply(settings: settings) }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.width < -50 { showingLyrics = true }
        })
        .sheet(isPresented: $showingLyrics) { RealLyricsView().environmentObject(player) }
    }
}
