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

    init(context: NSManagedObjectContext) { self.context = context; refresh() }

    func refresh() {
        let request = Song.fetchRequest(); request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        songs = (try? context.fetch(request)) ?? []
    }

    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        let result = await FileImporterService(context: context).importFiles(urls) { [weak self] name, current, total in
            self?.importProgress = "\(current)/\(total)  \(name)"
        }
        refresh()
        isImporting = false
        importProgress = ""
        if result.importedCount == 0, !result.failures.isEmpty {
            errorMessage = result.message
        } else {
            statusMessage = result.message
        }
    }

    func importFolder(_ folder: URL) async {
        guard !isImporting else { return }
        isImporting = true
        importProgress = "正在扫描文件夹…"
        let files = await FileImporterService.audioFiles(in: folder)
        isImporting = false
        guard !files.isEmpty else {
            errorMessage = "文件夹中没有找到支持的音频文件（FLAC、ALAC、WAV、AIFF、M4A、MP3）。"
            importProgress = ""
            return
        }
        await importFiles(files)
    }

    func delete(_ song: Song) {
        try? FileManager.default.removeItem(atPath: song.filePath)
        context.delete(song)
        do { try context.save(); refresh() }
        catch { errorMessage = "删除失败：\(error.localizedDescription)" }
    }
}
