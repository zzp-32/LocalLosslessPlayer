import AVFoundation
import CoreData
import CryptoKit
import Foundation

private let supportedAudioExtensions: Set<String> = [
    "flac", "alac", "wav", "wave", "aif", "aiff", "m4a", "mp3", "aac", "caf"
]

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
    private let context: NSManagedObjectContext
    private let fileManager = FileManager.default
    private var songsByRelativePath: [String: Song] = [:]
    private var songsByChecksum: [String: Song] = [:]
    private var legacySongsByFileName: [String: [Song]] = [:]

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
                                  supportedAudioExtensions.contains(url.pathExtension.lowercased()) else { continue }
                            files.append(url)
                        } catch {
                            if supportedAudioExtensions.contains(url.pathExtension.lowercased()) {
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

        rebuildExistingSongIndex()
        print("[Import] Received \(urls.count) selected file URLs")
        for (index, source) in urls.enumerated() {
            if index == 0 || index == urls.count - 1 || index % 10 == 0 {
                progress(source.lastPathComponent, index + 1, urls.count)
            }
            do {
                switch try indexFile(source, rootFolder: rootFolder, rootBookmark: rootBookmark) {
                case .imported: importedCount += 1
                case .updated, .unchanged: duplicateCount += 1
                }
                if importedCount > 0, importedCount % 25 == 0, context.hasChanges { try context.save() }
            } catch {
                print("[Import] Failed \(source.lastPathComponent): \(error.localizedDescription)")
                failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
            if index % 8 == 0 { await Task.yield() }
        }

        if context.hasChanges {
            do { try context.save() }
            catch { failures.append("Library save failed: \(error.localizedDescription)") }
        }
        print("[Import] Finished: imported=\(importedCount), existing=\(duplicateCount), failed=\(failures.count)")
        return ImportResult(importedCount: importedCount, duplicateCount: duplicateCount, failures: failures)
    }

    private enum Outcome { case imported, updated, unchanged }

    private func indexFile(_ source: URL, rootFolder: URL?, rootBookmark: Data?) throws -> Outcome {
        if rootBookmark == nil, rootFolder?.standardizedFileURL == StorageConfiguration.mediaRootURL.standardizedFileURL {
            return try indexCoordinatedFile(
                source,
                readURL: source,
                rootFolder: rootFolder,
                rootBookmark: rootBookmark
            )
        }
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
            let changed = existing.checksum != checksum
            updateReference(existing, source: source, fileBookmark: fileBookmark, rootBookmark: rootBookmark, relativePath: relativePath, checksum: checksum)
            if changed {
                MetadataMatcher.shared.schedule(song: existing, forceLocalRefresh: true)
                return .updated
            }
            return .unchanged
        }

        let song = Song(context: context)
        song.id = UUID()
        song.title = source.deletingPathExtension().lastPathComponent
        song.artist = nil
        song.album = nil
        song.fileName = source.lastPathComponent
        song.filePath = relativePath ?? source.lastPathComponent
        song.sourceBookmark = fileBookmark
        song.sourceRootBookmark = rootBookmark
        song.sourceRelativePath = relativePath
        song.checksum = checksum
        song.duration = 0
        song.createdAt = Date()

        remember(song)
        MetadataMatcher.shared.schedule(song: song)
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
        if let relativePath, let song = songsByRelativePath[relativePath] { return song }
        if let song = songsByChecksum[checksum] { return song }
        for song in legacySongsByFileName[source.lastPathComponent] ?? [] {
            if SourceReference.resolveURL(for: song)?.standardizedFileURL == source.standardizedFileURL { return song }
        }
        return nil
    }

    private func rebuildExistingSongIndex() {
        let request = Song.fetchRequest()
        request.fetchBatchSize = 200
        let existing = (try? context.fetch(request)) ?? []
        songsByRelativePath = Dictionary(
            existing.compactMap { song in song.sourceRelativePath.map { ($0, song) } },
            uniquingKeysWith: { first, _ in first }
        )
        songsByChecksum = Dictionary(
            existing.map { ($0.checksum, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        legacySongsByFileName = Dictionary(grouping: existing.filter { $0.sourceRelativePath == nil }, by: \.fileName)
    }

    private func remember(_ song: Song) {
        if let relativePath = song.sourceRelativePath { songsByRelativePath[relativePath] = song }
        songsByChecksum[song.checksum] = song
        if song.sourceRelativePath == nil { legacySongsByFileName[song.fileName, default: []].append(song) }
    }

    private func fastIdentifier(source: URL, relativePath: String?, fileSize: Int?, modifiedAt: Date?) -> String {
        let location = relativePath ?? source.standardizedFileURL.path
        let seed = "\(location.lowercased())|\(fileSize ?? -1)|\(modifiedAt?.timeIntervalSince1970 ?? 0)"
        return SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
