import Foundation

@MainActor
enum SourceReference {
    enum ReferenceError: LocalizedError {
        case unavailable

        var errorDescription: String? { "文件不可用，请重新定位文件夹。" }
    }

    static func bookmark(for url: URL) throws -> Data {
        // iOS security-scoped picker URLs use normal bookmark options. The
        // macOS-only withSecurityScope option is unavailable on iOS.
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
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
        if let bookmark = song.sourceBookmark,
           let resolved = resolveBookmark(bookmark) {
            if resolved.stale, let renewed = try? self.bookmark(for: resolved.url) {
                song.sourceBookmark = renewed
            }
            return resolved.url
        }

        if let rootBookmark = song.sourceRootBookmark,
           let relativePath = song.sourceRelativePath,
           let root = resolveBookmark(rootBookmark)?.url {
            return root.appendingPathComponent(relativePath)
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
