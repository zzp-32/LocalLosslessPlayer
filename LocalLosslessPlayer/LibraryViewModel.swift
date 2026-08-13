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

    func importFiles(_ urls: [URL], reportStatus: Bool = true) async {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        let result = await FileImporterService(context: context).importFiles(urls) { [weak self] name, current, total in
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
        saveFolderBookmark(folder)
        isImporting = true
        importProgress = "Scanning folder..."
        let files = await FileImporterService.audioFiles(in: folder)
        if hasAccess { folder.stopAccessingSecurityScopedResource() }
        isImporting = false
        guard !files.isEmpty else {
            errorMessage = "No supported audio files found in this folder."
            importProgress = ""
            return
        }
        await importFiles(files)
    }

    func rescanSavedFolder() async {
        guard let data = UserDefaults.standard.data(forKey: "library.folder.bookmark") else { return }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        if stale, let renewed = try? folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(renewed, forKey: "library.folder.bookmark")
        }
        let hasAccess = folder.startAccessingSecurityScopedResource()
        let files = await FileImporterService.audioFiles(in: folder)
        if hasAccess { folder.stopAccessingSecurityScopedResource() }
        guard !files.isEmpty else { return }
        await importFiles(files, reportStatus: false)
    }

    private func saveFolderBookmark(_ folder: URL) {
        guard let data = try? folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            errorMessage = "Unable to save folder permission. Please select it again."
            return
        }
        UserDefaults.standard.set(data, forKey: "library.folder.bookmark")
        UserDefaults.standard.set(folder.lastPathComponent, forKey: "library.folder.name")
    }

    func delete(_ song: Song) {
        try? FileManager.default.removeItem(atPath: song.filePath)
        context.delete(song)
        do { try context.save(); refresh() }
        catch { errorMessage = "Delete failed: \(error.localizedDescription)" }
    }
}
