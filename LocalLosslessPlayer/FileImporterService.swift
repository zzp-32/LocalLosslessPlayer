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

    func importFiles(_ urls: [URL]) async -> ImportResult {
        var importedCount = 0
        var duplicateCount = 0
        var failures: [String] = []

        for source in urls {
            do {
                let outcome = try await importFile(source)
                switch outcome {
                case .imported: importedCount += 1
                case .duplicate: duplicateCount += 1
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

        let checksum = try sha256(of: source)
        if try existingSong(with: checksum) != nil { return .duplicate }

        let destination = uniqueDestination(for: source, in: StorageConfiguration.mediaRootURL)
        do {
            try fileManager.copyItem(at: source, to: destination)
            let duration = try await duration(of: destination)

            let song = Song(context: context)
            song.id = UUID()
            song.title = source.deletingPathExtension().lastPathComponent
            song.artist = nil
            song.album = nil
            song.fileName = destination.lastPathComponent
            song.filePath = destination.path
            song.checksum = checksum
            song.duration = duration
            song.createdAt = Date()
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

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
            awaitTaskYield()
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func duration(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let time = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite ? max(0, seconds) : 0
    }

    private func awaitTaskYield() {
        RunLoop.current.run(mode: .default, before: Date())
    }
}
