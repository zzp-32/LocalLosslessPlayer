import AVFoundation
import CoreData
import CryptoKit
import Foundation

struct ImportResult {
    let importedCount: Int
    let duplicateCount: Int
    let failures: [String]

    var message: String {
        var parts = ["成功导入 \(importedCount) 首"]
        if duplicateCount > 0 { parts.append("跳过 \(duplicateCount) 个重复文件") }
        if !failures.isEmpty { parts.append("失败：\(failures.joined(separator: "；"))") }
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
                let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .contentTypeKey]
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
        progress: (String, Int, Int) -> Void
    ) async -> ImportResult {
        var importedCount = 0
        var duplicateCount = 0
        var failures: [String] = []

        for (index, source) in urls.enumerated() {
            progress(source.lastPathComponent, index + 1, urls.count)
            do {
                let outcome = try await importFile(source)
                switch outcome {
                case .imported: importedCount += 1
                case .duplicate: duplicateCount += 1
                }
                if importedCount > 0, importedCount % 25 == 0, context.hasChanges {
                    try context.save()
                }
            } catch {
                failures.append("\(source.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        if context.hasChanges {
            do { try context.save() }
            catch { failures.append("音乐库保存失败：\(error.localizedDescription)") }
        }

        return ImportResult(
            importedCount: importedCount,
            duplicateCount: duplicateCount,
            failures: failures
        )
    }

    private enum Outcome { case imported, duplicate }

    private func importFile(_ source: URL) async throws -> Outcome {
        let hasSecurityScope = source.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { source.stopAccessingSecurityScopedResource() } }

        let destination = uniqueDestination(for: source, in: StorageConfiguration.mediaRootURL)
        let checksum = try await copyAndHash(from: source, to: destination)
        if try existingSong(with: checksum) != nil {
            try? fileManager.removeItem(at: destination)
            return .duplicate
        }

        do {
            let duration = (try? await duration(of: destination)) ?? 0

            let song = Song(context: context)
            song.id = UUID()
            let metadata = AVURLAsset(url: destination).commonMetadata
            song.title = metadataValue(metadata, key: .commonKeyTitle) ?? source.deletingPathExtension().lastPathComponent
            song.artist = metadataValue(metadata, key: .commonKeyArtist)
            song.album = metadataValue(metadata, key: .commonKeyAlbumName)
            song.fileName = destination.lastPathComponent
            song.filePath = destination.path
            song.checksum = checksum
            song.duration = duration
            song.createdAt = Date()
            Task { await MetadataMatcher.shared.match(song: song) }
            return .imported
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    private func uniqueDestination(for source: URL, in root: URL) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var candidate = root.appendingPathComponent(source.lastPathComponent)
        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = root.appendingPathComponent(name)
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

    private func copyAndHash(from source: URL, to destination: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try FileManager.default.copyItem(at: source, to: destination)
                    let handle = try FileHandle(forReadingFrom: destination)
                    defer { try? handle.close() }
                    var hasher = SHA256()
                    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                        hasher.update(data: data)
                    }
                    let checksum = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                    continuation.resume(returning: checksum)
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func duration(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let time = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite ? max(0, seconds) : 0
    }
}

private func metadataValue(_ items: [AVMetadataItem], key: AVMetadataKey) -> String? {
    guard let value = items.first(where: { $0.commonKey == key })?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
}
