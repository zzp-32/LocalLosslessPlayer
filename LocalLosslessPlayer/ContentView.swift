import SwiftUI

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var player: PlayerViewModel
    @StateObject private var library: LibraryViewModel
    @State private var showingImporter = false

    init() { _library = StateObject(wrappedValue: LibraryViewModel(context: PersistenceController.shared.container.viewContext)) }

    var body: some View {
        NavigationStack {
            List(library.songs, id: \.objectID) { song in
                Button { player.play(song, queue: library.songs) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note").frame(width: 36, height: 36).background(.green.opacity(0.18)).cornerRadius(6)
                        VStack(alignment: .leading) { Text(song.title).foregroundColor(.primary); Text(song.artist ?? "未知艺术家").font(.caption).foregroundColor(.secondary) }
                        Spacer(); Text(format(song.duration)).font(.caption).foregroundColor(.secondary)
                    }
                }.buttonStyle(.plain)
            }
            .navigationTitle("本地音乐")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { showingImporter = true } label: { Image(systemName: "plus") } } }
            .safeAreaInset(edge: .bottom) { MiniPlayer() }
            .overlay {
                if library.isImporting {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在导入音乐…").font(.subheadline)
                        Text(library.importProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .background(.regularMaterial)
                    .cornerRadius(8)
                }
            }
            .sheet(isPresented: $showingImporter) {
                DocumentPicker { urls in
                    showingImporter = false
                    Task { await library.importFiles(urls) }
                }
                .ignoresSafeArea()
            }
            .alert("导入失败", isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            )) { Button("好") { library.errorMessage = nil } } message: {
                Text(library.errorMessage ?? "未知错误")
            }
            .alert("导入完成", isPresented: Binding(
                get: { library.statusMessage != nil },
                set: { if !$0 { library.statusMessage = nil } }
            )) { Button("好") { library.statusMessage = nil } } message: {
                Text(library.statusMessage ?? "")
            }
        }
    }

    private func format(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}

private struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerViewModel
    var body: some View {
        VStack(spacing: 6) {
            if let song = player.currentSong {
                HStack { VStack(alignment: .leading) { Text(song.title).font(.subheadline).lineLimit(1); Text(song.artist ?? "").font(.caption).foregroundColor(.secondary) }; Spacer(); Button { player.previous() } label: { Image(systemName: "backward.fill") }; Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }.font(.title3); Button { player.next() } label: { Image(systemName: "forward.fill") } }
                Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }), in: 0...max(player.duration, 1))
            } else { Text("导入音乐开始播放").font(.caption).foregroundColor(.secondary) }
        }.padding(.horizontal).padding(.vertical, 8).background(.thinMaterial)
    }
}
