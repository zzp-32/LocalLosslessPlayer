import AVFoundation
import CoreData
import Foundation

private struct LocalMetadataSnapshot: @unchecked Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double
    let lyrics: String?
    let artworkData: Data?
    let artworkMIMEType: String?
}

@MainActor
enum LocalMetadataService {
    static func apply(to song: Song) async -> Bool {
        guard let url = SourceReference.resolveURL(for: song) else {
            print("[Metadata] Source URL unavailable for \(song.fileName)")
            return false
        }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let isFLAC = song.fileName.lowercased().hasSuffix(".flac")
        guard let snapshot = await extract(from: url, isFLAC: isFLAC) else { return false }
        guard !Task.isCancelled else { return false }

        song.title = snapshot.title.nilIfEmpty ?? song.title
        song.artist = snapshot.artist.nilIfEmpty ?? song.artist
        song.album = snapshot.album.nilIfEmpty ?? song.album
        if snapshot.duration.isFinite, snapshot.duration > 0 { song.duration = snapshot.duration }

        do {
            if let lyrics = snapshot.lyrics.nilIfEmpty {
                let destination = StorageConfiguration.lyricsRootURL
                    .appendingPathComponent(song.checksum)
                    .appendingPathExtension("lrc")
                try lyrics.write(to: destination, atomically: true, encoding: .utf8)
                song.lyricsPath = destination.path
            }
            if let artwork = snapshot.artworkData, !artwork.isEmpty {
                let ext = snapshot.artworkMIMEType == "image/png" ? "png" : "jpg"
                let destination = StorageConfiguration.artworkRootURL
                    .appendingPathComponent(song.checksum)
                    .appendingPathExtension(ext)
                try artwork.write(to: destination, options: .atomic)
                song.artworkPath = destination.path
            }
            try song.managedObjectContext?.save()
        } catch {
            print("[Metadata] Cache/apply failed: \(error.localizedDescription)")
        }

        let lyricLines = snapshot.lyrics.map(LyricParser.parse) ?? []
        print("[Metadata] Title = \(snapshot.title ?? "NOT FOUND")")
        print("[Metadata] Artist = \(snapshot.artist ?? "NOT FOUND")")
        print(String(format: "[Metadata] Duration = %.3f", snapshot.duration))
        print("[Metadata] Lyrics = \(snapshot.lyrics == nil ? "NOT FOUND" : "FOUND")")
        print("[Metadata] Lyrics lines = \(lyricLines.count)")
        print("[Metadata] Artwork = \(snapshot.artworkData == nil ? "NOT FOUND" : "FOUND")")
        NotificationCenter.default.post(name: .songMetadataUpdated, object: song.objectID)
        return true
    }

    private static func extract(from url: URL, isFLAC: Bool) async -> LocalMetadataSnapshot? {
        await Task.detached(priority: .utility) {
            do {
                let sidecarURL = url.deletingPathExtension().appendingPathExtension("lrc")
                let sidecarLyrics = try? String(contentsOf: sidecarURL, encoding: .utf8)
                if isFLAC {
                    let metadata = try FLACMetadataReader.read(from: url)
                    return LocalMetadataSnapshot(
                        title: metadata.title,
                        artist: metadata.artist,
                        album: metadata.album,
                        duration: metadata.duration,
                        lyrics: sidecarLyrics.nilIfEmpty ?? metadata.lyrics,
                        artworkData: metadata.artworkData,
                        artworkMIMEType: metadata.artworkMIMEType
                    )
                }

                let asset = AVURLAsset(url: url)
                let metadata = asset.commonMetadata
                let seconds = CMTimeGetSeconds(asset.duration)
                return LocalMetadataSnapshot(
                    title: metadataValue(metadata, key: .commonKeyTitle),
                    artist: metadataValue(metadata, key: .commonKeyArtist),
                    album: metadataValue(metadata, key: .commonKeyAlbumName),
                    duration: seconds.isFinite ? max(0, seconds) : 0,
                    lyrics: sidecarLyrics,
                    artworkData: metadata.first(where: { $0.commonKey == .commonKeyArtwork })?.dataValue,
                    artworkMIMEType: nil
                )
            } catch {
                print("[Metadata] Local parser failed for \(url.lastPathComponent): \(error.localizedDescription)")
                return nil
            }
        }.value
    }
}

private func metadataValue(_ items: [AVMetadataItem], key: AVMetadataKey) -> String? {
    guard let value = items.first(where: { $0.commonKey == key })?.stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
}
