import AVFoundation
import CoreData
import CryptoKit
import UniformTypeIdentifiers

final class FileImporterService {
    private let context: NSManagedObjectContext
    private let fileManager = FileManager.default

    init(context: NSManagedObjectContext) { self.context = context }

    @discardableResult
    func importFiles(_ urls: [URL]) throws -> [Song] {
        var imported: [Song] = []
        let root = StorageConfiguration.mediaRootURL
        for source in urls {
            let hasSecurityScope = source.startAccessingSecurityScopedResource()
            defer { if hasSecurityScope { source.stopAccessingSecurityScopedResource() } }
            let checksum = try sha256(of: source)
            if try existingSong(with: checksum) != nil { continue }
            let destination = uniqueDestination(for: source, in: root)
            try fileManager.copyItem(at: source, to: destination)

            let asset = AVURLAsset(url: destination)
            let values = try awaitAssetValues(asset)
            let song = Song(context: context)
            song.id = UUID()
            song.title = source.deletingPathExtension().lastPathComponent
            song.artist = nil
            song.album = nil
            song.fileName = destination.lastPathComponent
            song.filePath = destination.path
            song.checksum = checksum
            song.duration = values
            song.createdAt = Date()
            imported.append(song)
        }
        if context.hasChanges { try context.save() }
        return imported
    }

    private func uniqueDestination(for source: URL, in root: URL) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var candidate = root.appendingPathComponent(source.lastPathComponent)
        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(base)-\(index).\(ext)")
            index += 1
        }
        return candidate
    }

    private func existingSong(with checksum: String) throws -> Song? {
        let request = Song.fetchRequest()
        request.predicate = NSPredicate(format: "checksum == %@", checksum)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func awaitAssetValues(_ asset: AVURLAsset) throws -> Double {
        let semaphore = DispatchSemaphore(value: 0)
        var duration = 0.0
        asset.loadValuesAsynchronously(forKeys: ["duration"]) { semaphore.signal() }
        semaphore.wait()
        var error: NSError?
        guard asset.statusOfValue(forKey: "duration", error: &error) == .loaded else {
            return duration
        }
        duration = CMTimeGetSeconds(asset.duration)
        return duration.isFinite ? duration : 0
    }
}
