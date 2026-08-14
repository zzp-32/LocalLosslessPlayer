import AVFoundation
import CoreData
import CryptoKit
import Foundation

struct FolderScanResult {
    let files: [URL]
    let visitedCount: Int
    let inaccessibleCount: Int
    let coordinatorError: String?
    let enumerationErrors: [String]

    var diagnosticMessage: String {
        var lines = ["Found \(files.count) supported audio files (scanned \(visitedCount) items)."]
        if inaccessibleCount > 0 { lines.append("\(inaccessibleCount) items could not be read.") }
        if let coordinatorError { lines.append("File coordination failed: \(coordinatorError)") }
        if !enumerationErrors.isEmpty { lines.append("Folder errors: \(enumerationErrors.prefix(3).joined(separator: "; "))") }
        return lines.joined(separator: "\n")
    }
}

struct ImportResult {
    let importedCount: Int
    let duplicateCount: Int
    let failures: [String]

    var message: String {
        var parts = ["Imported \(importedCount) songs"]
        if duplicateCount > 0 { parts.append("Updated/skipped \(duplicateCount) existing songs") }
        if !failures.isEmpty { parts.append("Failed: \(failures.prefix(8).joined(separator: ", "))") }
        return parts.joined(separator: "\n")
    }
}

enum ImportAccessError: LocalizedError {
    case coordination(String)
    case inaccessible(String)
    case noCoordinatedURL

    var errorDescription: String? {
        switch self {
        case .coordination(let message): return "File coordination failed: \(message)"
        case .inaccessible(let name): return "No permission to read \(name)"
        case .noCoordinatedURL: return "The file provider did not return a readable file URL"
        }
    }
}

@MainActor
final class FileImporterService {
    private static let supportedExtensions = Set([
        "flac", "alac", "wav", "wave", "aif", "aiff", "m4a", "mp3", "aac", "caf"
    ])

    private let context: NSManagedObjectContext
    private let fileManager = FileManager.default

    init(context: NSManagedObjectContext) { self.context = context }

    static func audioFiles(in folder: URL) async -> FolderScanResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinationError: NSError?
                var files: [URL] = []
                var visitedCount = 0
                var inaccessibleCount = 0
                var enumerationErrors: [String] = []

                coordinator.coordinate(readingItemAt: folder, options: [], error: &coordinationError) { coordinatedFolder in
                    print("[Import] Coordinated folder = \(coordinatedFolder.path)")
                    let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
                    let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
                    let enumerator = FileManager.default.enumerator(
                        at: coordinatedFolder,
                        includingPropertiesForKeys: keys,
                        options: options
                    ) { url, error in
                        enumerationErrors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                        print("[Import] Enumeration error at \(url.path): \(error.localizedDescription)")
                        return true
                    }

                    guard let enumerator else {
                        enumerationErrors.append("The file provider could not enumerate this folder")
                        return
                    }

                    for case let url as URL in enumerator {
                        visitedCount += 1
                        let childAccess = url.startAccessingSecurityScopedResource()
                        defer { if childAccess { url.stopAccessingSecurityScopedResource() } }

                        do {
                            let values = try url.resourceValues(forKeys: Set(keys))
                            guard values.isRegularFile == true,
                                  supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
                            files.append(url)
                        } catch {
                            if supportedExtensions.contains(url.pathExtension.lowercased()) {
                                inaccessibleCount += 1
                                enumerationErrors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                            }
                            print("[Import] Child access = \(childAccess), read failed at \(url.path): \(error.localizedDescription)")
                        }
                    }
                }

                let sorted = files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                print("[Import] Folder scan finished: files=\(sorted.count), visited=\(visitedCount), inaccessible=\(inaccessibleCount), coordinatorError=\(coordinationError?.localizedDescription ?? "none")")
                continuation.resume(returning: FolderScanResult(
                    files: sorted,
                    visitedCount: visitedCount,
                    inaccessibleCount: inaccessibleCount,
                    coordinatorError: coordinationError?.localizedDescription,
                    enumerationErrors: enumerationErrors
                ))
            }
        }
    }

    func importFiles(
        _ urls: [URL],
        rootFolder: URL? = nil,
        rootBookmark: Data? = nil,
        progress: (String, Int, Int) -> Void
    ) async -> ImportResult {
        var importedCount = 0
        var duplicateCount = 0
        var failures: [String] = []

        print("[Import] Received \(urls.count) selected file URLs")
        for (index, source) in urls.enumerated() {
            progress(source.lastPathComponent, index + 1, urls.count)
            do {
                switch try indexFile(source, rootFolder: rootFolder, rootBookmark: rootBookmark) {
                case .imported: importedCount += 1
                case .duplicate: duplicateCount += 1
                }
                if importedCount > 0, importedCount % 25 == 0, context.hasChanges { try context.save() }
            } catch {
                print("[Import] Failed \(source.lastPathComponent): \(error.localizedDescription)")
                failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if context.hasChanges {
            do { try context.save() }
            catch { failures.append("Library save failed: \(error.localizedDescription)") }
        }
        print("[Import] Finished: imported=\(importedCount), existing=\(duplicateCount), failed=\(failures.count)")
        return ImportResult(importedCount: importedCount, duplicateCount: duplicateCount, failures: failures)
    }

    private enum Outcome { case imported, duplicate }

    private func indexFile(_ source: URL, rootFolder: URL?, rootBookmark: Data?) throws -> Outcome {
        let hasSecurityScope = source.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { source.stopAccessingSecurityScopedResource() } }
        print("[Import] File access \(hasSecurityScope ? "started" : "not required/failed"): \(source.path)")

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Outcome, Error>?
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinatedURL in
            result = Result {
                try self.indexCoordinatedFile(
                    source,
                    readURL: coordinatedURL,
                    rootFolder: rootFolder,
                    rootBookmark: rootBookmark
                )
            }
        }

        if let coordinationError { throw ImportAccessError.coordination(coordinationError.localizedDescription) }
        guard let result else { throw ImportAccessError.noCoordinatedURL }
        return try result.get()
    }

    private func indexCoordinatedFile(
        _ source: URL,
        readURL: URL,
        rootFolder: URL?,
        rootBookmark: Data?
    ) throws -> Outcome {
        guard (try? readURL.checkResourceIsReachable()) == true || fileManager.fileExists(atPath: readURL.path) else {
            throw ImportAccessError.inaccessible(source.lastPathComponent)
        }

        let relativePath = rootFolder.flatMap { SourceReference.relativePath(of: source, in: $0) }
        let fileBookmark: Data?
        if rootBookmark == nil, relativePath != nil {
            fileBookmark = nil
        } else {
            do {
                fileBookmark = try SourceReference.bookmark(for: source)
            } catch {
                guard rootBookmark != nil, relativePath != nil else { throw error }
                fileBookmark = nil
                print("[Import] Child bookmark unavailable; using root bookmark + relative path for \(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        let values = try readURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let checksum = fastIdentifier(
            source: source,
            relativePath: relativePath,
            fileSize: values.fileSize,
            modifiedAt: values.contentModificationDate
        )

        if let existing = try existingSong(for: source, relativePath: relativePath, checksum: checksum) {
            updateReference(existing, source: source, fileBookmark: fileBookmark, rootBookmark: rootBookmark, relativePath: relativePath, checksum: checksum)
            return .duplicate
        }

        let asset = AVURLAsset(url: readURL)
        let seconds = CMTimeGetSeconds(asset.duration)
        let metadata = asset.commonMetadata
        let song = Song(context: context)
        song.id = UUID()
        song.title = metadataValue(metadata, key: .commonKeyTitle) ?? source.deletingPathExtension().lastPathComponent
        song.artist = metadataValue(metadata, key: .commonKeyArtist)
        song.album = metadataValue(metadata, key: .commonKeyAlbumName)
        song.fileName = source.lastPathComponent
        song.filePath = relativePath ?? source.lastPathComponent
        song.sourceBookmark = fileBookmark
        song.sourceRootBookmark = rootBookmark
        song.sourceRelativePath = relativePath
        song.checksum = checksum
        song.duration = seconds.isFinite ? max(0, seconds) : 0
        song.createdAt = Date()

        _ = LocalMetadataService.apply(to: song)
        Task { await MetadataMatcher.shared.match(song: song) }
        print("[Import] Indexed \(song.fileName), relativePath=\(relativePath ?? "none")")
        return .imported
    }

    private func updateReference(
        _ song: Song,
        source: URL,
        fileBookmark: Data?,
        rootBookmark: Data?,
        relativePath: String?,
        checksum: String
    ) {
        song.fileName = source.lastPathComponent
        song.filePath = relativePath ?? source.lastPathComponent
        song.sourceBookmark = fileBookmark
        song.sourceRootBookmark = rootBookmark
        song.sourceRelativePath = relativePath
        song.checksum = checksum
    }

    private func existingSong(for source: URL, relativePath: String?, checksum: String) throws -> Song? {
        if let relativePath {
            let request = Song.fetchRequest()
            request.predicate = NSPredicate(format: "sourceRelativePath == %@", relativePath)
            request.fetchLimit = 1
            if let song = try context.fetch(request).first { return song }
        }

        let checksumRequest = Song.fetchRequest()
        checksumRequest.predicate = NSPredicate(format: "checksum == %@", checksum)
        checksumRequest.fetchLimit = 1
        if let song = try context.fetch(checksumRequest).first { return song }

        let nameRequest = Song.fetchRequest()
        nameRequest.predicate = NSPredicate(format: "fileName == %@ AND sourceRelativePath == nil", source.lastPathComponent)
        for song in try context.fetch(nameRequest) {
            if SourceReference.resolveURL(for: song)?.standardizedFileURL == source.standardizedFileURL { return song }
        }
        return nil
    }

    private func fastIdentifier(source: URL, relativePath: String?, fileSize: Int?, modifiedAt: Date?) -> String {
        let location = relativePath ?? source.standardizedFileURL.path
        let seed = "\(location.lowercased())|\(fileSize ?? -1)|\(modifiedAt?.timeIntervalSince1970 ?? 0)"
        return SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private func metadataValue(_ items: [AVMetadataItem], key: AVMetadataKey) -> String? {
    guard let value = items.first(where: { $0.commonKey == key })?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
}
