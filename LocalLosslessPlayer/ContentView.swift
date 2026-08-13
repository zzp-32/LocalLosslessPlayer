import SwiftUI
import UIKit

private enum PlayerPalette {
    static let background = Color(red: 0.035, green: 0.043, blue: 0.039)
    static let surface = Color(red: 0.075, green: 0.086, blue: 0.080)
    static let raised = Color(red: 0.11, green: 0.12, blue: 0.115)
    static let line = Color.white.opacity(0.10)
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.56)
    static let green = Color(red: 0.61, green: 0.91, blue: 0.24)
    static let coral = Color(red: 0.94, green: 0.34, blue: 0.31)
    static let cyan = Color(red: 0.25, green: 0.72, blue: 0.78)
    static let gold = Color(red: 0.95, green: 0.69, blue: 0.24)
}

private enum LibrarySort: String, CaseIterable, Identifiable {
    case recent = "最近导入"
    case title = "标题"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @StateObject private var library: LibraryViewModel
    @State private var showingImporter = false
    @State private var showingPlayer = false
    @State private var searchText = ""
    @State private var sort: LibrarySort = .recent

    init() {
        _library = StateObject(
            wrappedValue: LibraryViewModel(context: PersistenceController.shared.container.viewContext)
        )
    }

    private var displayedSongs: [Song] {
        let filtered = searchText.isEmpty ? library.songs : library.songs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.artist?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.album?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        switch sort {
        case .recent: return filtered.sorted { $0.createdAt > $1.createdAt }
        case .title: return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PlayerPalette.background.ignoresSafeArea()
                libraryContent
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.currentSong != nil {
                    MiniPlayer(onOpen: { showingPlayer = true })
                }
            }
            .overlay { importOverlay }
            .sheet(isPresented: $showingImporter) {
                DocumentPicker { urls in
                    showingImporter = false
                    Task { await library.importFiles(urls) }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showingPlayer) {
                NowPlayingView()
                    .environmentObject(player)
            }
            .alert("导入失败", isPresented: messageBinding(for: $library.errorMessage)) {
                Button("好") { library.errorMessage = nil }
            } message: { Text(library.errorMessage ?? "未知错误") }
            .alert("导入完成", isPresented: messageBinding(for: $library.statusMessage)) {
                Button("好") { library.statusMessage = nil }
            } message: { Text(library.statusMessage ?? "") }
            .alert("播放失败", isPresented: messageBinding(for: $player.errorMessage)) {
                Button("好") { player.errorMessage = nil }
            } message: { Text(player.errorMessage ?? "") }
        }
        .preferredColorScheme(.dark)
    }

    private var libraryContent: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                header
                searchBar
                libraryTools

                if displayedSongs.isEmpty {
                    emptyState
                } else {
                    songList
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("音乐库")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(PlayerPalette.primary)
                Text("\(library.songs.count) 首本地歌曲")
                    .font(.subheadline)
                    .foregroundStyle(PlayerPalette.secondary)
            }
            Spacer()
            Button { showingImporter = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(PlayerPalette.background)
                    .frame(width: 42, height: 42)
                    .background(PlayerPalette.green)
                    .clipShape(Circle())
            }
            .accessibilityLabel("导入音乐")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PlayerPalette.secondary)
            TextField("搜索歌曲、艺术家或专辑", text: $searchText)
                .foregroundStyle(PlayerPalette.primary)
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PlayerPalette.secondary)
                }
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(PlayerPalette.surface)
        .cornerRadius(7)
        .padding(.horizontal, 20)
    }

    private var libraryTools: some View {
        HStack {
            Text(searchText.isEmpty ? "全部歌曲" : "搜索结果")
                .font(.headline)
                .foregroundStyle(PlayerPalette.primary)
            Spacer()
            Picker("排序", selection: $sort) {
                ForEach(LibrarySort.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(PlayerPalette.green)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private var songList: some View {
        LazyVStack(spacing: 0) {
            ForEach(displayedSongs, id: \.objectID) { song in
                SongRow(song: song, isCurrent: player.currentSong == song) {
                    player.play(song, queue: displayedSongs)
                    showingPlayer = true
                }
                Divider()
                    .overlay(PlayerPalette.line)
                    .padding(.leading, 82)
            }
        }
        .padding(.bottom, 24)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: searchText.isEmpty ? "waveform" : "magnifyingglass")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(PlayerPalette.green)
                .frame(width: 72, height: 72)
                .background(PlayerPalette.surface)
                .cornerRadius(8)
            Text(searchText.isEmpty ? "还没有音乐" : "没有找到歌曲")
                .font(.headline)
                .foregroundStyle(PlayerPalette.primary)
            if searchText.isEmpty {
                Button("导入音乐") { showingImporter = true }
                    .buttonStyle(.borderedProminent)
                    .tint(PlayerPalette.green)
                    .foregroundStyle(PlayerPalette.background)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }

    @ViewBuilder
    private var importOverlay: some View {
        if library.isImporting {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView().tint(PlayerPalette.green)
                    Text("正在导入音乐")
                        .font(.headline)
                        .foregroundStyle(PlayerPalette.primary)
                    Text(library.importProgress)
                        .font(.caption)
                        .foregroundStyle(PlayerPalette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 240, height: 130)
                .background(PlayerPalette.raised)
                .cornerRadius(8)
            }
        }
    }

    private func messageBinding(for message: Binding<String?>) -> Binding<Bool> {
        Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )
    }
}

private struct SongRow: View {
    let song: Song
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ArtworkTile(title: song.title, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.system(size: 16, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? PlayerPalette.green : PlayerPalette.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(song.artist.nilIfEmpty ?? "未知艺术家")
                        Text("·")
                        Text(song.fileName.fileExtensionLabel)
                    }
                    .font(.caption)
                    .foregroundStyle(PlayerPalette.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(timeText(song.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PlayerPalette.secondary)
                Image(systemName: isCurrent ? "waveform" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCurrent ? PlayerPalette.green : PlayerPalette.secondary)
                    .frame(width: 16)
            }
            .padding(.horizontal, 20)
            .frame(height: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerViewModel
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: player.currentTime, total: max(player.duration, 1))
                .progressViewStyle(.linear)
                .tint(PlayerPalette.green)
                .scaleEffect(x: 1, y: 0.55, anchor: .center)
            HStack(spacing: 12) {
                Button(action: onOpen) {
                    HStack(spacing: 11) {
                        ArtworkTile(title: player.currentSong?.title ?? "", size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(player.currentSong?.title ?? "")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PlayerPalette.primary)
                                .lineLimit(1)
                            Text((player.currentSong?.artist).nilIfEmpty ?? "未知艺术家")
                                .font(.caption)
                                .foregroundStyle(PlayerPalette.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 6)
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(PlayerPalette.primary)
                        .frame(width: 38, height: 38)
                }
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PlayerPalette.primary)
                        .frame(width: 38, height: 38)
                }
                .accessibilityLabel("下一首")
            }
            .padding(.horizontal, 14)
            .frame(height: 66)
            .background(.ultraThinMaterial)
        }
        .background(PlayerPalette.surface)
    }
}

private struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerViewModel

    var body: some View {
        ZStack {
            PlayerPalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 18)
                ArtworkTile(title: player.currentSong?.title ?? "", size: min(UIScreen.main.bounds.width - 54, 330), large: true)
                Spacer(minLength: 22)
                metadata
                progress
                controls
                modeLabels
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("收起播放页")
            Spacer()
            VStack(spacing: 2) {
                Text("正在播放")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PlayerPalette.secondary)
                Text((player.currentSong?.album).nilIfEmpty ?? "本地音乐")
                    .font(.caption2)
                    .foregroundStyle(PlayerPalette.secondary)
            }
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .foregroundStyle(PlayerPalette.primary)
        .padding(.top, 4)
    }

    private var metadata: some View {
        HStack(alignment: .center) {
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
            Spacer()
            Text(player.currentSong?.fileName.fileExtensionLabel ?? "AUDIO")
                .font(.caption2.weight(.bold))
                .foregroundStyle(PlayerPalette.green)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(PlayerPalette.green.opacity(0.6)))
        }
        .padding(.bottom, 20)
    }

    private var progress: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                in: 0...max(player.duration, 1)
            )
            .tint(PlayerPalette.green)
            HStack {
                Text(timeText(player.currentTime))
                Spacer()
                Text("-\(timeText(max(0, player.duration - player.currentTime)))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(PlayerPalette.secondary)
        }
    }

    private var controls: some View {
        HStack {
            modeButton(
                icon: "shuffle",
                active: player.isShuffled,
                label: player.isShuffled ? "关闭随机播放" : "随机播放",
                action: player.toggleShuffle
            )
            Spacer()
            controlButton(icon: "backward.fill", label: "上一首", action: player.previous)
            Spacer()
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(PlayerPalette.background)
                    .frame(width: 68, height: 68)
                    .background(PlayerPalette.green)
                    .clipShape(Circle())
            }
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
            Spacer()
            controlButton(icon: "forward.fill", label: "下一首", action: player.next)
            Spacer()
            modeButton(
                icon: player.repeatMode.icon,
                active: player.repeatMode != .off,
                label: player.repeatMode.title,
                action: player.cycleRepeatMode
            )
        }
        .padding(.top, 20)
    }

    private var modeLabels: some View {
        HStack {
            Text(player.isShuffled ? "随机播放" : "顺序播放")
            Spacer()
            Text(player.repeatMode.title)
        }
        .font(.caption2)
        .foregroundStyle(PlayerPalette.secondary)
        .padding(.top, 12)
    }

    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(PlayerPalette.primary)
                .frame(width: 42, height: 42)
        }
        .accessibilityLabel(label)
    }

    private func modeButton(icon: String, active: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(active ? PlayerPalette.green : PlayerPalette.secondary)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel(label)
    }
}

private struct ArtworkTile: View {
    let title: String
    let size: CGFloat
    var large = false

    private var color: Color {
        let palette = [PlayerPalette.green, PlayerPalette.coral, PlayerPalette.cyan, PlayerPalette.gold]
        let value = title.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % palette.count }
        return palette[value]
    }

    var body: some View {
        ZStack {
            PlayerPalette.raised
            Rectangle()
                .fill(color.opacity(0.76))
                .frame(width: size * 0.67, height: size * 0.67)
                .rotationEffect(.degrees(large ? 12 : 8))
            Circle()
                .fill(PlayerPalette.background)
                .frame(width: size * 0.34, height: size * 0.34)
            Circle()
                .fill(color)
                .frame(width: size * 0.10, height: size * 0.10)
            Image(systemName: "waveform")
                .font(.system(size: large ? 30 : 12, weight: .bold))
                .foregroundStyle(PlayerPalette.primary.opacity(0.9))
                .offset(y: size * 0.32)
        }
        .frame(width: size, height: size)
        .clipped()
        .cornerRadius(large ? 8 : 6)
        .overlay(RoundedRectangle(cornerRadius: large ? 8 : 6).stroke(Color.white.opacity(0.08)))
    }
}

private func timeText(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

private extension String {
    var fileExtensionLabel: String {
        let value = (self as NSString).pathExtension.uppercased()
        return value.isEmpty ? "AUDIO" : value
    }
}
