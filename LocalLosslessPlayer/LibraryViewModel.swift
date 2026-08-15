import CoreData
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var isImporting = false
    @Published var importProgress = ""
    private let context: NSManagedObjectContext
    private var isScanning = false

    init(context: NSManagedObjectContext) {
        self.context = context
        _ = StorageConfiguration.mediaRootURL
        refresh()
        Task { await scanMusicFolder(reportStatus: false) }
    }

    func refresh() {
        let request = Song.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        songs = (try? context.fetch(request)) ?? []
    }

    func scanMusicFolder(reportStatus: Bool = true) async {
        guard !isScanning else { return }
        isScanning = true
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
}
