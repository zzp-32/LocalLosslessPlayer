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

    init(context: NSManagedObjectContext) {
        self.context = context
        refresh()
        Task { await rescanSavedFolder() }
    }

    func refresh() {
        let request = Song.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        songs = (try? context.fetch(request)) ?? []
    }

    func importFiles(_ urls: [URL], rootFolder: URL? = nil, rootBookmark: Data? = nil, reportStatus: Bool = true) async {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        let result = await FileImporterService(context: context).importFiles(urls, rootFolder: rootFolder, rootBookmark: rootBookmark) { [weak self] name, current, total in
            self?.importProgress = "\(current)/\(total)  \(name)"
        }
        refresh()
        isImporting = false
        importProgress = ""
        guard reportStatus else { return }
        if result.importedCount == 0, !result.failures.isEmpty {
            errorMessage = result.message
        } else {
            statusMessage = result.message
        }
    }

    func importFolder(_ folder: URL) async {
        guard !isImporting else { return }
        let hasAccess = folder.startAccessingSecurityScopedResource()
        let bookmark = saveFolderBookmark(folder)
        isImporting = true
        importProgress = "Scanning folder..."
        let files = await FileImporterService.audioFiles(in: folder)
        isImporting = false
        guard !files.isEmpty else {
            if hasAccess { folder.stopAccessingSecurityScopedResource() }
            errorMessage = "No supported audio files found in this folder."
            importProgress = ""
            return
        }
        await importFiles(files, rootFolder: folder, rootBookmark: bookmark)
        if hasAccess { folder.stopAccessingSecurityScopedResource() }
    }

    func rescanSavedFolder() async {
        guard let data = UserDefaults.standard.data(forKey: "library.folder.bookmark") else { return }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        if stale, let renewed = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(renewed, forKey: "library.folder.bookmark")
        }
        let hasAccess = folder.startAccessingSecurityScopedResource()
        let files = await FileImporterService.audioFiles(in: folder)
        guard !files.isEmpty else {
            if hasAccess { folder.stopAccessingSecurityScopedResource() }
            return
        }
        await importFiles(files, rootFolder: folder, rootBookmark: data, reportStatus: false)
        if hasAccess { folder.stopAccessingSecurityScopedResource() }
    }

    private func saveFolderBookmark(_ folder: URL) -> Data? {
        guard let data = try? SourceReference.bookmark(for: folder) else {
            errorMessage = "Unable to save folder permission. Please select it again."
            return nil
        }
        UserDefaults.standard.set(data, forKey: "library.folder.bookmark")
        UserDefaults.standard.set(folder.lastPathComponent, forKey: "library.folder.name")
        return data
    }

    func delete(_ song: Song) {
        context.delete(song)
        do { try context.save(); refresh() }
        catch { errorMessage = "Delete failed: \(error.localizedDescription)" }
    }
}
