import CoreData
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published private(set) var alphabeticSections: [SongAlphabetSection] = []
    @Published private(set) var unavailableSongIDs: Set<UUID> = []
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var isImporting = false
    @Published var importProgress = ""
    private let context: NSManagedObjectContext
    private var isScanning = false
    private var sectionTask: Task<Void, Never>?
    private var availabilityTask: Task<Void, Never>?
    private var metadataRefreshTask: Task<Void, Never>?
    private var lastAutomaticScan: Date?

    init(context: NSManagedObjectContext) {
        self.context = context
        _ = StorageConfiguration.mediaRootURL
        refresh()
        Task { await scanMusicFolder(reportStatus: false) }
    }

    func refresh() {
        let request = Song.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchBatchSize = 100
        songs = (try? context.fetch(request)) ?? []
        rebuildAlphabeticSections()
        refreshAvailability()
    }

    func scanMusicFolder(reportStatus: Bool = true) async {
        guard !isScanning else { return }
        if !reportStatus,
           let lastAutomaticScan,
           Date().timeIntervalSince(lastAutomaticScan) < 300 {
            return
        }
        isScanning = true
        if !reportStatus { lastAutomaticScan = Date() }
        defer { isScanning = false }

        let folder = StorageConfiguration.mediaRootURL
        print("[MusicFolder] Scan started = \(folder.path)")
        if reportStatus {
            isImporting = true
            importProgress = "正在扫描 Music 文件夹…"
        }
        let scan = await FileImporterService.audioFiles(in: folder)
        if reportStatus {
            isImporting = false
            importProgress = ""
        }
        print("[MusicFolder] Music files found = \(scan.files.count)")
        refresh()

        guard !scan.files.isEmpty else {
            if reportStatus {
                statusMessage = "Music 文件夹中暂时没有找到支持的歌曲。"
            }
            return
        }

        await importFiles(
            scan.files,
            rootFolder: folder,
            reportStatus: reportStatus
        )
    }

    func isAvailable(_ song: Song) -> Bool {
        !unavailableSongIDs.contains(song.id)
    }

    func scheduleMetadataRefresh() {
        metadataRefreshTask?.cancel()
        metadataRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func importFiles(
        _ urls: [URL],
        rootFolder: URL,
        reportStatus: Bool
    ) async {
        guard !urls.isEmpty else { return }
        if reportStatus {
            isImporting = true
        }
        let result = await FileImporterService(context: context).importFiles(
            urls,
            rootFolder: rootFolder,
            rootBookmark: nil
        ) { [weak self] name, current, total in
            if reportStatus {
                self?.importProgress = "\(current)/\(total)  \(name)"
            }
        }
        refresh()
        if reportStatus {
            isImporting = false
            importProgress = ""
        }
        guard reportStatus else { return }
        if result.importedCount == 0, !result.failures.isEmpty {
            errorMessage = result.message
        } else {
            statusMessage = result.message
        }
    }

    func deleteSourceFileAndLibraryRecord(_ song: Song) -> Bool {
        let artworkPath = song.artworkPath
        let lyricsPath = song.lyricsPath

        do {
            try SourceReference.deleteSourceFile(for: song)
            context.delete(song)
            try context.save()
            deleteCacheFile(at: artworkPath, containedIn: StorageConfiguration.artworkRootURL)
            deleteCacheFile(at: lyricsPath, containedIn: StorageConfiguration.lyricsRootURL)
            refresh()
            return true
        } catch {
            errorMessage = "删除歌曲失败：\(error.localizedDescription)"
            return false
        }
    }

    private func deleteCacheFile(at path: String?, containedIn root: URL) {
        guard let path else { return }
        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard fileURL.path.hasPrefix(rootPath + "/") || fileURL.path == rootPath else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func rebuildAlphabeticSections() {
        sectionTask?.cancel()
        let snapshot = songs.map { SongSortSnapshot(id: $0.id, title: $0.title) }
        sectionTask = Task { [weak self] in
            let groupedIDs = await Task.detached(priority: .utility) {
                SongTitleSorting.group(snapshot)
            }.value
            guard !Task.isCancelled, let self else { return }
            let songsByID = Dictionary(uniqueKeysWithValues: self.songs.map { ($0.id, $0) })
            self.alphabeticSections = groupedIDs.compactMap { section in
                let values = section.songIDs.compactMap { songsByID[$0] }
                return values.isEmpty ? nil : SongAlphabetSection(key: section.key, songs: values)
            }
        }
    }

    private func refreshAvailability() {
        availabilityTask?.cancel()
        let snapshots = songs.map { song in
            SongAvailabilitySnapshot(
                id: song.id,
                url: SourceReference.resolveURL(for: song),
                accessURL: SourceReference.securityScopeURL(for: song)
            )
        }
        availabilityTask = Task { [weak self] in
            let unavailable = await Task.detached(priority: .utility) {
                Set(snapshots.compactMap { snapshot in
                    guard !Task.isCancelled else { return snapshot.id }
                    guard let url = snapshot.url else { return snapshot.id }
                    let scoped = snapshot.accessURL?.startAccessingSecurityScopedResource() == true
                    defer { if scoped { snapshot.accessURL?.stopAccessingSecurityScopedResource() } }
                    return ((try? url.checkResourceIsReachable()) == true) ? nil : snapshot.id
                })
            }.value
            guard !Task.isCancelled else { return }
            self?.unavailableSongIDs = unavailable
        }
    }
}

struct SongAlphabetSection: Identifiable {
    let key: String
    let songs: [Song]
    var id: String { key }
}

private struct SongSortSnapshot: Sendable {
    let id: UUID
    let title: String
}

private struct SongSortSection: Sendable {
    let key: String
    let songIDs: [UUID]
}

private struct SongAvailabilitySnapshot: Sendable {
    let id: UUID
    let url: URL?
    let accessURL: URL?
}

private enum SongTitleSorting {
    static func group(_ songs: [SongSortSnapshot]) -> [SongSortSection] {
        var grouped: [String: [(id: UUID, sortKey: String)]] = [:]
        for song in songs {
            let sortKey = latinTitle(song.title)
            grouped[initial(forLatinTitle: sortKey), default: []].append((song.id, sortKey))
        }
        return grouped.keys.sorted(by: sectionOrder).compactMap { key in
            guard let values = grouped[key] else { return nil }
            return SongSortSection(
                key: key,
                songIDs: values.sorted {
                    $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending
                }.map(\.id)
            )
        }
    }

    static func latinTitle(_ title: String) -> String {
        let mutable = NSMutableString(string: title)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return (mutable as String).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func initial(forLatinTitle title: String) -> String {
        guard let scalar = title.uppercased().unicodeScalars.first else { return "#" }
        return scalar.value >= 65 && scalar.value <= 90 ? String(scalar) : "#"
    }

    static func sectionOrder(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == "#" { return false }
        if rhs == "#" { return true }
        return lhs < rhs
    }
}
