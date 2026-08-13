import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var library: LibraryViewModel
    @State private var selectedTab = 0
    @State private var showingImporter = false
    @State private var showingFolderPicker = false
    @State private var showingImportOptions = false
    @State private var showingMenu = false

    init() {
        _library = StateObject(wrappedValue: LibraryViewModel(context: PersistenceController.shared.container.viewContext))
    }

    var body: some View {
        ZStack {
            PlayerPalette.background.ignoresSafeArea()
            TabView(selection: $selectedTab) {
                libraryTab.tag(0)
                livePlayerTab.tag(1)
                searchTab.tag(2)
            }
            .tint(PlayerPalette.green)
        }
        .preferredColorScheme(settings.theme == .light ? .light : .dark)
        .onAppear { player.apply(settings: settings) }
        .sheet(isPresented: $showingImporter) {
            DocumentPicker { urls in
                showingImporter = false
                Task { await library.importFiles(urls) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingFolderPicker) {
            FolderPicker { folder in
                showingFolderPicker = false
                Task { await library.importFolder(folder) }
            }
            .ignoresSafeArea()
        }
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
                LibraryHome(library: library, showImporter: { showingImportOptions = true })
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingMenu = true } label: { Image(systemName: "line.3.horizontal") }
                        .accessibilityLabel("更多功能")
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await library.rescanSavedFolder() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("刷新歌库")
                }
            }
            .toolbarBackground(PlayerPalette.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationTitle("音乐库")
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog("导入音乐", isPresented: $showingImportOptions, titleVisibility: .visible) {
                Button("选择歌曲（可多选）") { showingImporter = true }
                Button("导入整个文件夹") { showingFolderPicker = true }
                Button("取消", role: .cancel) {}
            } message: {
                Text("可一次导入几百首歌曲，支持子文件夹。")
            }
        }
        .tabItem { Label("音乐库", systemImage: "rectangle.stack.fill") }
    }

    private var livePlayerTab: some View {
        NavigationStack {
            LivePlaybackView().environmentObject(player).environmentObject(settings)
        }
        .tabItem { Label("正在播放", systemImage: "play.circle.fill") }
    }

    private var searchTab: some View {
        NavigationStack {
            SearchView(library: library)
                .navigationTitle("搜索")
        }
        .tabItem { Label("搜索", systemImage: "magnifyingglass") }
    }

    private func messageBinding(for message: Binding<String?>) -> Binding<Bool> {
        Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })
    }
}

private struct LibraryHome: View {
    @EnvironmentObject private var player: PlayerViewModel
    @ObservedObject var library: LibraryViewModel
    @State private var searchText = ""
    @State private var sortByTitle = false
    let showImporter: () -> Void

    private var songs: [Song] {
        let source = searchText.isEmpty ? library.songs : library.songs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.artist?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.album?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        return sortByTitle ? source.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } : source
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
                    Button(action: showImporter) {
                        Image(systemName: "plus").font(.system(size: 19, weight: .bold))
                            .foregroundStyle(PlayerPalette.background).frame(width: 42, height: 42)
                            .background(PlayerPalette.green).clipShape(Circle())
                    }
                    .accessibilityLabel("导入音乐")
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(PlayerPalette.secondary)
                    TextField("搜索歌曲、艺术家或专辑", text: $searchText).foregroundStyle(PlayerPalette.primary)
                    if !searchText.isEmpty { Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PlayerPalette.secondary) } }
                }
                .padding(.horizontal, 14).frame(height: 44).background(PlayerPalette.surface).cornerRadius(7).padding(.horizontal, 20)

                HStack {
                    Text(searchText.isEmpty ? "全部歌曲" : "搜索结果").font(.headline).foregroundStyle(PlayerPalette.primary)
                    Spacer()
                    Button { sortByTitle.toggle() } label: { Image(systemName: sortByTitle ? "textformat.abc" : "clock").foregroundStyle(PlayerPalette.green) }
                        .accessibilityLabel(sortByTitle ? "按最近导入排序" : "按标题排序")
                }
                .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 8)

                if songs.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: searchText.isEmpty ? "waveform" : "magnifyingglass").font(.system(size: 38)).foregroundStyle(PlayerPalette.green)
                        Text(searchText.isEmpty ? "还没有音乐" : "没有找到歌曲").font(.headline).foregroundStyle(PlayerPalette.primary)
                        if searchText.isEmpty { Button("导入音乐", action: showImporter).buttonStyle(.borderedProminent).tint(PlayerPalette.green) }
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

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) { ArtworkTile(title: song.title, size: 48, artworkPath: song.artworkPath) }.buttonStyle(.plain)
            Button(action: action) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title).font(.system(size: 16, weight: current ? .semibold : .regular)).foregroundStyle(current ? PlayerPalette.green : PlayerPalette.primary).lineLimit(1)
                    Text(song.artist.nilIfEmpty ?? "未知艺术家").font(.caption).foregroundStyle(PlayerPalette.secondary).lineLimit(1)
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

    private var songs: [Song] { library.songs.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || ($0.artist?.localizedCaseInsensitiveContains(query) ?? false) } }

    var body: some View {
        ZStack {
            PlayerPalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(PlayerPalette.secondary); TextField("搜索本地音乐", text: $query).foregroundStyle(PlayerPalette.primary) }
                    .padding(.horizontal, 14).frame(height: 44).background(PlayerPalette.surface).cornerRadius(7).padding()
                if query.isEmpty { VStack(spacing: 12) { Image(systemName: "waveform").font(.system(size: 34)).foregroundStyle(PlayerPalette.green); Text("输入歌名或艺术家开始搜索").foregroundStyle(PlayerPalette.secondary) }.padding(.top, 90) }
                else { List(songs, id: \.objectID) { song in Button { player.play(song, queue: songs) } label: { HStack { ArtworkTile(title: song.title, size: 44); VStack(alignment: .leading) { Text(song.title).foregroundStyle(PlayerPalette.primary); Text(song.artist.nilIfEmpty ?? "未知艺术家").font(.caption).foregroundStyle(PlayerPalette.secondary) } } }.listRowBackground(PlayerPalette.background) } .scrollContentBackground(.hidden) }
            }
        }
    }
}
