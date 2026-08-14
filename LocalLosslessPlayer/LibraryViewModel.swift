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
        defer { if hasAccess { folder.stopAccessingSecurityScopedResource() } }
        print("[Import] Root folder security scope = \(hasAccess), path = \(folder.path)")

        guard let bookmark = saveFolderBookmark(folder) else { return }
        isImporting = true
        importProgress = "Scanning folder..."
        let scan = await FileImporterService.audioFiles(in: folder)
        isImporting = false
        guard !scan.files.isEmpty else {
            errorMessage = scan.diagnosticMessage
            importProgress = ""
            return
        }
        await importFiles(scan.files, rootFolder: folder, rootBookmark: bookmark)
        if scan.inaccessibleCount > 0 || scan.coordinatorError != nil || !scan.enumerationErrors.isEmpty {
            statusMessage = (statusMessage ?? "Import finished") + "\n" + scan.diagnosticMessage
        }
    }

    func rescanSavedFolder() async {
        guard let data = UserDefaults.standard.data(forKey: "library.folder.bookmark") else { return }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            print("[Import] Saved folder bookmark could not be resolved")
            return
        }
        var activeBookmark = data
        if stale, let renewed = try? SourceReference.bookmark(for: folder) {
            UserDefaults.standard.set(renewed, forKey: "library.folder.bookmark")
            activeBookmark = renewed
        }
        let hasAccess = folder.startAccessingSecurityScopedResource()
        defer { if hasAccess { folder.stopAccessingSecurityScopedResource() } }
        print("[Import] Restored folder bookmark, stale = \(stale), scope = \(hasAccess)")
        let scan = await FileImporterService.audioFiles(in: folder)
        guard !scan.files.isEmpty else {
            print("[Import] Restored folder scan returned no files: \(scan.diagnosticMessage)")
            return
        }
        await importFiles(scan.files, rootFolder: folder, rootBookmark: activeBookmark, reportStatus: false)
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
