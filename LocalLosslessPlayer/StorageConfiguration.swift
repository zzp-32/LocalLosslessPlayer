import Foundation

struct StorageConfiguration {
    static let appFolderName = "LocalLosslessPlayer"
    static let mediaFolderName = "Music"
    static let artworkFolderName = "Artwork"
    static let lyricsFolderName = "Lyrics"

    static var dataRootURL: URL {
        let fm = FileManager.default
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["LOCAL_PLAYER_DATA_ROOT"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        #endif
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = base.appendingPathComponent(appFolderName, isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static var mediaRootURL: URL {
        let root = dataRootURL.appendingPathComponent(mediaFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static var artworkRootURL: URL { directory(named: artworkFolderName) }
    static var lyricsRootURL: URL { directory(named: lyricsFolderName) }

    private static func directory(named name: String) -> URL {
        let url = dataRootURL.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
