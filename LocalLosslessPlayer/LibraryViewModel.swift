import CoreData
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var errorMessage: String?
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) { self.context = context; refresh() }

    func refresh() {
        let request = Song.fetchRequest(); request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        songs = (try? context.fetch(request)) ?? []
    }

    func importFiles(_ urls: [URL]) {
        do { _ = try FileImporterService(context: context).importFiles(urls); refresh() }
        catch { errorMessage = error.localizedDescription }
    }
}
