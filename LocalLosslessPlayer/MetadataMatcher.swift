import Foundation

@MainActor
final class MetadataMatcher {
    static let shared = MetadataMatcher()
    func match(song: Song) async {
        let parts = Self.splitTitle(song.title)
        let artist = song.artist.nilIfEmpty ?? parts.artist
        let title = parts.title
        guard !title.isEmpty else { return }

        if song.artworkPath == nil, let artworkData = await fetchArtwork(title: title, artist: artist) {
            let target = StorageConfiguration.artworkRootURL.appendingPathComponent(song.checksum).appendingPathExtension("jpg")
            try? artworkData.write(to: target, options: .atomic)
            if FileManager.default.fileExists(atPath: target.path) { song.artworkPath = target.path }
        }
        if song.lyricsPath == nil, let lyrics = await fetchLyrics(title: title, artist: artist, album: song.album) {
            let target = StorageConfiguration.lyricsRootURL.appendingPathComponent(song.checksum).appendingPathExtension("lrc")
            try? lyrics.write(to: target, atomically: true, encoding: .utf8)
            song.lyricsPath = target.path
        }
        try? song.managedObjectContext?.save()
    }

    private func fetchArtwork(title: String, artist: String?) async -> Data? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: [artist, title].compactMap { $0 }.joined(separator: " ")),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = (json["results"] as? [[String: Any]])?.first,
              let artwork = result["artworkUrl100"] as? String,
              let artworkURL = URL(string: artwork.replacingOccurrences(of: "100x100", with: "600x600")),
              let (imageData, _) = try? await URLSession.shared.data(from: artworkURL) else { return nil }
        return imageData
    }

    private func fetchLyrics(title: String, artist: String?, album: String?) async -> String? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album)
        ].filter { $0.value?.isEmpty == false }
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["syncedLyrics"] as? String).nilIfEmpty ?? (json["plainLyrics"] as? String).nilIfEmpty
    }

    private static func splitTitle(_ raw: String) -> (artist: String?, title: String) {
        let parts = raw.components(separatedBy: " - ")
        guard parts.count > 1 else { return (nil, raw.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let title = parts.dropLast().joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = parts.last!.trimmingCharacters(in: .whitespacesAndNewlines)
        return (artist, title)
    }
}
