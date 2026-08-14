import CoreData
import Foundation

@MainActor
enum LocalMetadataService {
    static func apply(to song: Song) -> Bool {
        guard song.fileName.lowercased().hasSuffix(".flac") else { return false }
        do {
            let metadata = try FLACMetadataReader.read(from: URL(fileURLWithPath: song.filePath))
            song.title = metadata.title.nilIfEmpty ?? song.title
            song.artist = metadata.artist.nilIfEmpty ?? song.artist
            song.album = metadata.album.nilIfEmpty ?? song.album
            if metadata.duration > 0 { song.duration = metadata.duration }

            if let lyrics = metadata.lyrics.nilIfEmpty {
                let destination = StorageConfiguration.lyricsRootURL.appendingPathComponent(song.checksum).appendingPathExtension("lrc")
                try lyrics.write(to: destination, atomically: true, encoding: .utf8)
                song.lyricsPath = destination.path
            }
            if let artwork = metadata.artworkData {
                let ext = metadata.artworkMIMEType == "image/png" ? "png" : "jpg"
                let destination = StorageConfiguration.artworkRootURL.appendingPathComponent(song.checksum).appendingPathExtension(ext)
                try artwork.write(to: destination, options: .atomic)
                song.artworkPath = destination.path
            }
            try song.managedObjectContext?.save()

            let lyricLines = metadata.lyrics.map(LyricParser.parse) ?? []
            print("[Metadata] Title = \(metadata.title ?? "NOT FOUND")")
            print("[Metadata] Artist = \(metadata.artist ?? "NOT FOUND")")
            print(String(format: "[Metadata] Duration = %.3f", metadata.duration))
            print("[Metadata] Lyrics = \(metadata.lyrics == nil ? "NOT FOUND" : "FOUND")")
            print("[Metadata] Lyrics lines = \(lyricLines.count)")
            print("[Metadata] Artwork = \(metadata.artworkData == nil ? "NOT FOUND" : "FOUND")")
            NotificationCenter.default.post(name: .songMetadataUpdated, object: song.objectID)
            return true
        } catch {
            print("[Metadata] FLAC read failed at parser layer: \(error.localizedDescription)")
            return false
        }
    }
}
