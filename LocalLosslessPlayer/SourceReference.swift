import Foundation

enum SourceReference {
    enum ReferenceError: LocalizedError {
        case unavailable
        case deletionFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "文件不可用，请重新定位文件夹。"
            case .deletionFailed(let message):
                return "无法删除原始文件：\(message)"
            }
        }
    }

    static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolveBookmark(_ data: Data) -> (url: URL, stale: Bool)? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        return (url, stale)
    }

    static func resolveURL(for song: Song) -> URL? {
        if let rootBookmark = song.sourceRootBookmark,
           let relativePath = song.sourceRelativePath,
           let root = resolveBookmark(rootBookmark)?.url {
            return root.appendingPathComponent(relativePath)
        }

        if song.sourceRootBookmark == nil,
           let relativePath = song.sourceRelativePath {
            return StorageConfiguration.mediaRootURL.appendingPathComponent(relativePath)
        }

        if let bookmark = song.sourceBookmark,
           let resolved = resolveBookmark(bookmark) {
            return resolved.url
        }

        // Migration fallback for songs imported by older app versions.
        let legacy = URL(fileURLWithPath: song.filePath)
        return FileManager.default.fileExists(atPath: legacy.path) ? legacy : nil
    }

    static func isAvailable(_ song: Song) -> Bool {
        guard let url = resolveURL(for: song) else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return (try? url.checkResourceIsReachable()) == true
    }

    static func deleteSourceFile(for song: Song) throws {
        guard let targetURL = resolveURL(for: song) else { throw ReferenceError.unavailable }

        let accessURL: URL
        if let rootBookmark = song.sourceRootBookmark,
           let rootURL = resolveBookmark(rootBookmark)?.url {
            accessURL = rootURL
        } else {
            accessURL = targetURL
        }

        let scoped = accessURL.startAccessingSecurityScopedResource()
        defer { if scoped { accessURL.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            throw ReferenceError.unavailable
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var deletionError: Error?
        coordinator.coordinate(writingItemAt: targetURL, options: .forDeleting, error: &coordinationError) { coordinatedURL in
            do {
                try FileManager.default.removeItem(at: coordinatedURL)
            } catch {
                deletionError = error
            }
        }

        if let coordinationError {
            throw ReferenceError.deletionFailed(coordinationError.localizedDescription)
        }
        if let deletionError {
            throw ReferenceError.deletionFailed(deletionError.localizedDescription)
        }
    }

    static func relativePath(of file: URL, in root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return String(filePath.dropFirst(prefix.count))
    }

    static func sidecarURL(for song: Song, extension ext: String) -> URL? {
        guard let source = resolveURL(for: song) else { return nil }
        return source.deletingPathExtension().appendingPathExtension(ext)
    }
}
