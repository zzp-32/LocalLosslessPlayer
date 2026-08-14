import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var library: LibraryViewModel
    @State private var selectedTab = 0
    @State private var showingMenu = false
    @State private var showingSearch = false

    init() {
        _library = StateObject(wrappedValue: LibraryViewModel(context: PersistenceController.shared.container.viewContext))
    }

    var body: some View {
        ZStack {
            PlayerPalette.background.ignoresSafeArea()
            TabView(selection: $selectedTab) {
                libraryTab.tag(0)
                livePlayerTab.tag(1)
                soundEffectsTab.tag(2)
            }
            .tint(PlayerPalette.green)
            if library.isImporting {
                VStack(spacing: 12) {
                    ProgressView().tint(PlayerPalette.green)
                    Text(library.importProgress.isEmpty ? "正在导入音乐…" : library.importProgress)
                        .font(.footnote)
                        .foregroundStyle(PlayerPalette.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(PlayerPalette.surface)
                .cornerRadius(10)
                .shadow(radius: 12)
                .padding(32)
            }
        }
        .preferredColorScheme(settings.theme == .light ? .light : .dark)
        .onAppear { player.apply(settings: settings) }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await library.scanMusicFolder(reportStatus: false) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .songMetadataUpdated)) { _ in library.refresh() }
        .sheet(isPresented: $showingMenu) {
            FunctionMenuView()
                .environmentObject(player)
                .environmentObject(settings)
                .environmentObject(library)
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

    private var libraryTab: some View {
        NavigationStack {
            ZStack {
                PlayerPalette.background.ignoresSafeArea()
                LibraryHome(
                    library: library,
                    openFilesApp: openFilesApp,
                    scanMusicFolder: { Task { await library.scanMusicFolder() } }
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingMenu = true } label: { Image(systemName: "line.3.horizontal") }
                        .accessibilityLabel("更多功能")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingSearch = true } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("搜索")
                }
            }
            .toolbarBackground(PlayerPalette.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(isPresented: $showingSearch) {
                SearchView(library: library)
                    .navigationTitle("搜索")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(PlayerPalette.background, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
            }
        }
        .tabItem { Image(systemName: "rectangle.stack.fill") }
        .accessibilityLabel("媒体库")
    }

    private var livePlayerTab: some View {
        NavigationStack {
            LivePlaybackView().environmentObject(player).environmentObject(settings)
        }
        .tabItem { Image(systemName: "play.circle.fill") }
        .accessibilityLabel("正在播放")
    }

    private var soundEffectsTab: some View {
        SoundEffectsCenterView()
            .environmentObject(player)
            .environmentObject(settings)
            .tabItem { Image(systemName: "slider.horizontal.3") }
            .accessibilityLabel("音效中心")
    }

    private func messageBinding(for message: Binding<String?>) -> Binding<Bool> {
        Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })
    }

    private func openFilesApp() {
        _ = StorageConfiguration.mediaRootURL
        guard let url = URL(string: "shareddocuments://") else { return }
        UIApplication.shared.open(url)
    }
}

private struct LibraryHome: View {
    @EnvironmentObject private var player: PlayerViewModel
    @ObservedObject var library: LibraryViewModel
    @State private var sortByTitle = false
    let openFilesApp: () -> Void
    let scanMusicFolder: () -> Void

    private var songs: [Song] {
        sortByTitle
            ? library.songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            : library.songs
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("本地音乐").font(.system(size: 34, weight: .bold)).foregroundStyle(PlayerPalette.primary)
                        Text("\(library.songs.count) 首歌曲").font(.subheadline).foregroundStyle(PlayerPalette.secondary)
                    }
                    Spacer()
                    Menu {
                        Button(action: openFilesApp) { Label("打开“文件”App", systemImage: "folder") }
                        Button(action: scanMusicFolder) { Label("扫描 Music 文件夹", systemImage: "arrow.clockwise") }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 19, weight: .bold))
                            .foregroundStyle(PlayerPalette.background).frame(width: 42, height: 42)
                            .background(PlayerPalette.green).clipShape(Circle())
                    }
                    .accessibilityLabel("导入音乐")
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)

                HStack {
                    Text("全部歌曲").font(.headline).foregroundStyle(PlayerPalette.primary)
                    Spacer()
                    Button { sortByTitle.toggle() } label: { Image(systemName: sortByTitle ? "textformat.abc" : "clock").foregroundStyle(PlayerPalette.green) }
                        .accessibilityLabel(sortByTitle ? "按最近导入排序" : "按标题排序")
                }
                .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 8)

                if songs.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "waveform").font(.system(size: 38)).foregroundStyle(PlayerPalette.green)
                        Text("还没有音乐").font(.headline).foregroundStyle(PlayerPalette.primary)
                        Button("打开“文件”App", action: openFilesApp).buttonStyle(.borderedProminent).tint(PlayerPalette.green)
                    }.frame(maxWidth: .infinity).padding(.top, 100)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(songs, id: \.objectID) { song in
                            SongRow(song: song, current: player.currentSong == song) {
                                player.play(song, queue: songs)
                            }
                            Divider().overlay(PlayerPalette.line).padding(.leading, 82)
                        }
                    }.padding(.bottom, 24)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct SongRow: View {
    let song: Song
    let current: Bool
    let action: () -> Void

    private var isAvailable: Bool { SourceReference.isAvailable(song) }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) { ArtworkTile(title: song.title, size: 48, artworkPath: song.artworkPath) }.buttonStyle(.plain)
            Button(action: action) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title).font(.system(size: 16, weight: current ? .semibold : .regular)).foregroundStyle(current ? PlayerPalette.green : PlayerPalette.primary).lineLimit(1)
                    Text(isAvailable ? (song.artist.nilIfEmpty ?? "未知艺术家") : "文件不可用")
                        .font(.caption)
                        .foregroundStyle(isAvailable ? PlayerPalette.secondary : PlayerPalette.coral)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Text(timeText(song.duration)).font(.caption.monospacedDigit()).foregroundStyle(PlayerPalette.secondary)
        }
        .padding(.horizontal, 20).frame(height: 70)
    }
}

private struct SearchView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @ObservedObject var library: LibraryViewModel
    @State private var query = ""

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var songs: [Song] {
        guard !normalizedQuery.isEmpty else { return [] }
        return library.songs.filter {
            $0.title.localizedCaseInsensitiveContains(normalizedQuery) ||
            ($0.artist?.localizedCaseInsensitiveContains(normalizedQuery) ?? false) ||
            ($0.album?.localizedCaseInsensitiveContains(normalizedQuery) ?? false)
        }
    }

    private var artists: [ArtistGroup] {
        Dictionary(grouping: library.songs) { song in
            song.artist.nilIfEmpty ?? "未知艺术家"
        }
        .map { name, songs in
            ArtistGroup(
                name: name,
                songs: songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            PlayerPalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                searchBar
                if normalizedQuery.isEmpty {
                    artistList
                } else {
                    searchResults
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PlayerPalette.secondary)
            TextField("搜索歌曲、歌手或专辑", text: $query)
                .foregroundStyle(PlayerPalette.primary)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PlayerPalette.secondary)
                }
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(PlayerPalette.surface)
        .cornerRadius(7)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var artistList: some View {
        if artists.isEmpty {
            emptyState(icon: "person.2", title: "还没有已导入的歌手")
        } else {
            List {
                Section {
                    ForEach(artists) { artist in
                        NavigationLink {
                            ArtistSongsView(artist: artist)
                                .environmentObject(player)
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkTile(
                                    title: artist.name,
                                    size: 48,
                                    artworkPath: artist.songs.first?.artworkPath
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(artist.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(PlayerPalette.primary)
                                        .lineLimit(1)
                                    Text("\(artist.songs.count) 首歌曲")
                                        .font(.caption)
                                        .foregroundStyle(PlayerPalette.secondary)
                                }
                            }
                            .frame(height: 58)
                        }
                        .listRowBackground(PlayerPalette.background)
                        .listRowSeparatorTint(PlayerPalette.line)
                    }
                } header: {
                    Text("歌手")
                        .font(.headline)
                        .foregroundStyle(PlayerPalette.primary)
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if songs.isEmpty {
            emptyState(icon: "magnifyingglass", title: "没有找到歌曲")
        } else {
            List(songs, id: \.objectID) { song in
                Button { player.play(song, queue: songs) } label: {
                    SearchSongRow(song: song, isCurrent: player.currentSong == song)
                }
                .buttonStyle(.plain)
                .listRowBackground(PlayerPalette.background)
                .listRowSeparatorTint(PlayerPalette.line)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func emptyState(icon: String, title: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(PlayerPalette.green)
            Text(title)
                .foregroundStyle(PlayerPalette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ArtistGroup: Identifiable {
    let name: String
    let songs: [Song]
    var id: String { name }
}

private struct ArtistSongsView: View {
    @EnvironmentObject private var player: PlayerViewModel
    let artist: ArtistGroup

    var body: some View {
        List(artist.songs, id: \.objectID) { song in
            Button { player.play(song, queue: artist.songs) } label: {
                SearchSongRow(song: song, isCurrent: player.currentSong == song)
            }
            .buttonStyle(.plain)
            .listRowBackground(PlayerPalette.background)
            .listRowSeparatorTint(PlayerPalette.line)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PlayerPalette.background)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SearchSongRow: View {
    let song: Song
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            ArtworkTile(title: song.title, size: 48, artworkPath: song.artworkPath)
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? PlayerPalette.green : PlayerPalette.primary)
                    .lineLimit(1)
                Text(song.artist.nilIfEmpty ?? "未知艺术家")
                    .font(.caption)
                    .foregroundStyle(PlayerPalette.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(timeText(song.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(PlayerPalette.secondary)
        }
        .frame(height: 58)
        .contentShape(Rectangle())
    }
}
