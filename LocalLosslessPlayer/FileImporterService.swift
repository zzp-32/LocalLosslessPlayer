import AVFoundation
import CoreData
import CryptoKit
import Foundation

struct ImportResult {
    let importedCount: Int
    let duplicateCount: Int
    let failures: [String]

    var message: String {
        var parts = ["Imported \(importedCount) songs"]
        if duplicateCount > 0 { parts.append("Skipped \(duplicateCount) duplicates") }
        if !failures.isEmpty { parts.append("Failed: \(failures.joined(separator: ", "))") }
        return parts.joined(separator: "\n")
    }
}

@MainActor
final class FileImporterService {
    private let context: NSManagedObjectContext
    private let fileManager = FileManager.default

    init(context: NSManagedObjectContext) { self.context = context }

    static func audioFiles(in folder: URL) async -> [URL] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let extensions = Set(["flac", "alac", "wav", "wave", "aif", "aiff", "m4a", "mp3", "aac", "caf"])
                let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
                let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
                var files: [URL] = []
                if let enumerator = FileManager.default.enumerator(
                    at: folder,
                    includingPropertiesForKeys: keys,
                    options: options
                ) {
                    for case let url as URL in enumerator {
                        guard let values = try? url.resourceValues(forKeys: Set(keys)),
                              values.isRegularFile == true,
                              extensions.contains(url.pathExtension.lowercased()) else { continue }
                        files.append(url)
                    }
                }
                continuation.resume(returning: files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending })
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

        for (index, source) in urls.enumerated() {
            progress(source.lastPathComponent, index + 1, urls.count)
            do {
                switch try await indexFile(source, rootFolder: rootFolder, rootBookmark: rootBookmark) {
                case .imported: importedCount += 1
                case .duplicate: duplicateCount += 1
                }
                if importedCount > 0, importedCount % 25 == 0, context.hasChanges { try context.save() }
            } catch {
                failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if context.hasChanges {
            do { try context.save() }
            catch { failures.append("Library save failed: \(error.localizedDescription)") }
        }
        return ImportResult(importedCount: importedCount, duplicateCount: duplicateCount, failures: failures)
    }

    private enum Outcome { case imported, duplicate }

    private func indexFile(_ source: URL, rootFolder: URL?, rootBookmark: Data?) async throws -> Outcome {
        let hasSecurityScope = source.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { source.stopAccessingSecurityScopedResource() } }
        guard fileManager.fileExists(atPath: source.path) else { throw SourceReference.ReferenceError.unavailable }

        let checksum = try await hash(source)
        let fileBookmark = try SourceReference.bookmark(for: source)
        let relativePath = rootFolder.flatMap { SourceReference.relativePath(of: source, in: $0) }

        if let existing = try existingSong(with: checksum) {
            updateReference(existing, source: source, fileBookmark: fileBookmark, rootBookmark: rootBookmark, relativePath: relativePath)
            return .duplicate
        }

        let asset = AVURLAsset(url: source)
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds).flatMap { $0.isFinite ? max(0, $0) : nil } ?? 0
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
        song.duration = duration
        song.createdAt = Date()

        _ = LocalMetadataService.apply(to: song)
        Task { await MetadataMatcher.shared.match(song: song) }
        return .imported
    }

    private func updateReference(_ song: Song, source: URL, fileBookmark: Data, rootBookmark: Data?, relativePath: String?) {
        song.fileName = source.lastPathComponent
        song.filePath = relativePath ?? source.lastPathComponent
        song.sourceBookmark = fileBookmark
        song.sourceRootBookmark = rootBookmark
        song.sourceRelativePath = relativePath
    }

    private func existingSong(with checksum: String) throws -> Song? {
        let request = Song.fetchRequest()
        request.predicate = NSPredicate(format: "checksum == %@", checksum)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func hash(_ source: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handle = try FileHandle(forReadingFrom: source)
                    defer { try? handle.close() }
                    var hasher = SHA256()
                    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) }
                    let checksum = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                    continuation.resume(returning: checksum)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

private func metadataValue(_ items: [AVMetadataItem], key: AVMetadataKey) -> String? {
    guard let value = items.first(where: { $0.commonKey == key })?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
}
