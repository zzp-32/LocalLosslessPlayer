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
}
