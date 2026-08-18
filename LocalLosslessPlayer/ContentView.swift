import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var library: LibraryViewModel
    @AppStorage("navigation.selectedTab") private var selectedTab = 0
    @State private var showingReport = false
    @State private var showingSearch = false

    init() {
        _library = StateObject(wrappedValue: LibraryViewModel(context: PersistenceController.shared.container.viewContext))
    }

    var body: some View {
        ZStack {
            AlbumArtworkBackground(artworkPath: player.currentSong?.artworkPath)
            TabView(selection: $selectedTab) {
                libraryTab.tag(0)
                livePlayerTab.tag(1)
                soundEffectsTab.tag(2)
            }
            .tint(PlayerPalette.green)
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BottomNavigationBar(selection: $selectedTab)
            }
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
        .onAppear {
            player.apply(settings: settings)
            player.setPlayerScreenVisible(selectedTab == 1)
            player.restoreLastSession(from: library.songs)
        }
        .onChange(of: selectedTab) { tab in
            player.setPlayerScreenVisible(tab == 1)
        }
        .onChange(of: library.songs.count) { _ in
            player.restoreLastSession(from: library.songs)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                player.setAppInBackground(false)
                player.setPlayerScreenVisible(selectedTab == 1)
                Task { await library.scanMusicFolder(reportStatus: false) }
            } else if phase == .inactive || phase == .background {
                player.setAppInBackground(true)
                player.persistPlaybackSession()
                settings.flush()
                MetadataMatcher.shared.cancelPending()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .songMetadataUpdated)) { _ in
            library.scheduleMetadataRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            Task { await ArtworkImageCache.shared.removeAll() }
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
                AlbumArtworkBackground(artworkPath: player.currentSong?.artworkPath)
                LibraryHome(
                    library: library,
                    openFilesApp: openFilesApp,
                    scanMusicFolder: { Task { await library.scanMusicFolder() } }
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingReport = true } label: { Image(systemName: "line.3.horizontal") }
                        .accessibilityLabel("听歌报告")
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
            .navigationDestination(isPresented: $showingReport) {
                ListeningReportView(library: library) { song in
                    player.play(song, queue: library.songs)
                    showingReport = false
                    selectedTab = 1
                }
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

private struct BottomNavigationBar: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            item(index: 0, icon: "rectangle.stack.fill", title: "媒体库")
            item(index: 1, icon: "play.circle.fill", title: "正在播放")
            item(index: 2, icon: "slider.horizontal.3", title: "音效中心")
        }
        .frame(height: 58)
        .background(PlayerPalette.background.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PlayerPalette.line)
                .frame(height: 0.5)
        }
        .background(PlayerPalette.background.ignoresSafeArea(edges: .bottom))
    }

    private func item(index: Int, icon: String, title: String) -> some View {
        Button {
            selection = index
        } label: {
            ZStack {
                Color.clear
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(selection == index ? PlayerPalette.green : PlayerPalette.secondary)
                    .scaleEffect(selection == index ? 1.06 : 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selection == index ? .isSelected : [])
    }
}

private struct LibraryHome: View {
    @EnvironmentObject private var player: PlayerViewModel
    @ObservedObject var library: LibraryViewModel
    @State private var sortByTitle = true
    @State private var songPendingDeletion: Song?
    let openFilesApp: () -> Void
    let scanMusicFolder: () -> Void

    var body: some View {
        let sections = library.alphabeticSections
        let orderedSongs = sortByTitle && !sections.isEmpty ? sections.flatMap(\.songs) : library.songs

        ScrollViewReader { proxy in
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

                if orderedSongs.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "waveform").font(.system(size: 38)).foregroundStyle(PlayerPalette.green)
                        Text("还没有音乐").font(.headline).foregroundStyle(PlayerPalette.primary)
                        Button("打开“文件”App", action: openFilesApp).buttonStyle(.borderedProminent).tint(PlayerPalette.green)
                    }.frame(maxWidth: .infinity).padding(.top, 100)
                    } else {
                        LazyVStack(spacing: 0) {
                            if sortByTitle {
                                ForEach(sections) { section in
                                    Text(section.key)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(PlayerPalette.green)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 20)
                                        .padding(.top, 16)
                                        .padding(.bottom, 6)
                                        .id("library-section-\(section.key)")
                                    ForEach(section.songs, id: \.objectID) { song in
                                        songRow(song, queue: orderedSongs)
                                        Divider().overlay(PlayerPalette.line).padding(.leading, 82)
                                    }
                                }
                            } else {
                                ForEach(orderedSongs, id: \.objectID) { song in
                                    songRow(song, queue: orderedSongs)
                                    Divider().overlay(PlayerPalette.line).padding(.leading, 82)
                                }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .overlay(alignment: .trailing) {
                if sortByTitle, !sections.isEmpty {
                    AlphabetIndexView(keys: sections.map(\.key)) { key in
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo("library-section-\(key)", anchor: .top)
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .alert("删除歌曲？", isPresented: Binding(
            get: { songPendingDeletion != nil },
            set: { if !$0 { songPendingDeletion = nil } }
        ), presenting: songPendingDeletion) { song in
            Button("删除", role: .destructive) {
                let objectID = song.objectID
                if library.deleteSourceFileAndLibraryRecord(song) {
                    player.removeFromPlaybackQueue(objectID)
                }
                songPendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                songPendingDeletion = nil
            }
        } message: { song in
            Text("将从“文件”App中的音乐文件夹删除“\(song.fileName)”。此操作无法撤销。")
        }
    }

    @ViewBuilder
    private func songRow(_ song: Song, queue: [Song]) -> some View {
        SongRow(song: song, current: player.currentSong == song, isAvailable: library.isAvailable(song)) {
            player.play(song, queue: queue)
        } onPlayNext: {
            player.playNext(song, fallbackQueue: queue)
        } onDelete: {
            songPendingDeletion = song
        }
    }
}

private struct AlphabetIndexView: View {
    let keys: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 1) {
            ForEach(keys, id: \.self) { key in
                Button(key) { onSelect(key) }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PlayerPalette.green)
                    .frame(width: 18, height: 15)
                    .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.trailing, 4)
    }
}

private struct SongRow: View {
    let song: Song
    let current: Bool
    let isAvailable: Bool
    let action: () -> Void
    let onPlayNext: () -> Void
    let onDelete: () -> Void

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
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: onPlayNext) {
                Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button(role: .destructive, action: onDelete) {
                Label("删除歌曲", systemImage: "trash")
            }
        }
    }
}

private struct SearchView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @ObservedObject var library: LibraryViewModel
    @ObservedObject private var listeningHistory = ListeningHistoryStore.shared
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
        let listeningTotals = listeningHistory.listenedSecondsByArtist()
        return Dictionary(grouping: library.songs) { song in
            song.artist.nilIfEmpty ?? "未知艺术家"
        }
        .map { name, songs in
            ArtistGroup(
                name: name,
                songs: songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending },
                listenedSeconds: listeningTotals[normalizedArtist(name)] ?? 0
            )
        }
        .sorted {
            if $0.listenedSeconds != $1.listenedSeconds {
                return $0.listenedSeconds > $1.listenedSeconds
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        ZStack {
            AlbumArtworkBackground(artworkPath: player.currentSong?.artworkPath)
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
                ForEach(artists.indices, id: \.self) { index in
                        let artist = artists[index]
                        NavigationLink {
                            ArtistSongsView(artist: artist)
                                .environmentObject(player)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(index < 3 ? PlayerPalette.green : PlayerPalette.secondary)
                                    .frame(width: 20)
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
                                    Text(artistSubtitle(artist))
                                        .font(.caption)
                                        .foregroundStyle(PlayerPalette.secondary)
                                }
                            }
                            .frame(height: 58)
                        }
                        .listRowBackground(PlayerPalette.background)
                        .listRowSeparatorTint(PlayerPalette.line)
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

    private func artistSubtitle(_ artist: ArtistGroup) -> String {
        guard artist.listenedSeconds >= 1 else { return "\(artist.songs.count) 首歌曲" }
        let minutes = max(1, Int(artist.listenedSeconds / 60))
        return "\(artist.songs.count) 首歌曲 · 已听 \(minutes) 分钟"
    }

    private func normalizedArtist(_ artist: String) -> String {
        artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct ArtistGroup: Identifiable {
    let name: String
    let songs: [Song]
    let listenedSeconds: Double
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
        .background(AlbumArtworkBackground(artworkPath: player.currentSong?.artworkPath))
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
