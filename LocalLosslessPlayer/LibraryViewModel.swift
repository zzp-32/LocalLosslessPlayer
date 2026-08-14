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

    func delete(_ song: Song) {
        context.delete(song)
        do { try context.save(); refresh() }
        catch { errorMessage = "Delete failed: \(error.localizedDescription)" }
    }
}
