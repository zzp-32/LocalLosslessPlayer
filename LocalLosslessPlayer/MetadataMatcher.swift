import Foundation

@MainActor
final class MetadataMatcher {
    static let shared = MetadataMatcher()
    private let limiter = MetadataWorkLimiter(limit: 3)
    private var activeSongIDs: Set<UUID> = []
    private var scheduledTasks: [UUID: Task<Void, Never>] = [:]

    func schedule(song: Song, forceLocalRefresh: Bool = false) {
        let id = song.id
        guard scheduledTasks[id] == nil else { return }
        scheduledTasks[id] = Task { [weak self, weak song] in
            guard let self, let song else { return }
            await self.match(song: song, forceLocalRefresh: forceLocalRefresh)
            self.scheduledTasks[id] = nil
        }
    }

    func cancelPending() {
        scheduledTasks.values.forEach { $0.cancel() }
        scheduledTasks.removeAll()
    }

    func match(song: Song, forceLocalRefresh: Bool = false) async {
        guard !activeSongIDs.contains(song.id) else { return }
        activeSongIDs.insert(song.id)
        defer { activeSongIDs.remove(song.id) }
        await limiter.acquire()
        defer { Task { await limiter.release() } }
        guard !Task.isCancelled else { return }

        if forceLocalRefresh || song.duration <= 0 || song.artworkPath == nil || song.lyricsPath == nil {
            _ = await LocalMetadataService.apply(to: song)
        }
        guard !Task.isCancelled else { return }
        let parts = Self.splitTitle(song.title)
        let artist = song.artist.nilIfEmpty ?? parts.artist
        let title = parts.title
        guard !title.isEmpty else { return }

        if song.artworkPath == nil, let artworkData = await fetchArtwork(title: title, artist: artist) {
            let target = StorageConfiguration.artworkRootURL.appendingPathComponent(song.checksum).appendingPathExtension("jpg")
            try? artworkData.write(to: target, options: .atomic)
            if FileManager.default.fileExists(atPath: target.path) { song.artworkPath = target.path }
        }
        guard !Task.isCancelled else { return }
        if song.lyricsPath == nil, let lyrics = await fetchLyrics(title: title, artist: artist, album: song.album) {
            let target = StorageConfiguration.lyricsRootURL.appendingPathComponent(song.checksum).appendingPathExtension("lrc")
            try? lyrics.write(to: target, atomically: true, encoding: .utf8)
            song.lyricsPath = target.path
        }
        try? song.managedObjectContext?.save()
        NotificationCenter.default.post(name: .songMetadataUpdated, object: song.objectID)
    }

    func rematchLyrics(song: Song) async {
        _ = await LocalMetadataService.apply(to: song)
        if let path = song.lyricsPath,
           let content = try? String(contentsOfFile: path, encoding: .utf8),
           !LyricParser.parse(content).isEmpty {
            NotificationCenter.default.post(name: .songMetadataUpdated, object: song.objectID)
            return
        }
        let parts = Self.splitTitle(song.title)
        let artist = song.artist.nilIfEmpty ?? parts.artist
        guard !parts.title.isEmpty,
              let lyrics = await fetchLyrics(title: parts.title, artist: artist, album: song.album) else {
            NotificationCenter.default.post(name: .songMetadataUpdated, object: song.objectID)
            return
        }

        let target = StorageConfiguration.lyricsRootURL
            .appendingPathComponent(song.checksum)
            .appendingPathExtension("lrc")
        do {
            try lyrics.write(to: target, atomically: true, encoding: .utf8)
            song.lyricsPath = target.path
            try song.managedObjectContext?.save()
        } catch {
            print("[Metadata] Lyrics rematch save failed: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: .songMetadataUpdated, object: song.objectID)
    }

    private func fetchArtwork(title: String, artist: String?) async -> Data? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: [artist, title].compactMap { $0 }.joined(separator: " ")),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url,
              let data = await requestData(url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = (json["results"] as? [[String: Any]])?.first,
              let artwork = result["artworkUrl100"] as? String,
              let artworkURL = URL(string: artwork.replacingOccurrences(of: "100x100", with: "600x600")),
              let imageData = await requestData(artworkURL) else { return nil }
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
              let data = await requestData(url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["syncedLyrics"] as? String).nilIfEmpty ?? (json["plainLyrics"] as? String).nilIfEmpty
    }

    private func requestData(_ url: URL) async -> Data? {
        guard !Task.isCancelled else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              !Task.isCancelled,
              (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) != false else { return nil }
        return data
    }

    private static func splitTitle(_ raw: String) -> (artist: String?, title: String) {
        let parts = raw.components(separatedBy: " - ")
        guard parts.count > 1 else { return (nil, raw.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let title = parts.dropLast().joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = parts.last!.trimmingCharacters(in: .whitespacesAndNewlines)
        return (artist, title)
    }
}

private actor MetadataWorkLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = max(1, limit) }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            running = max(0, running - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

extension Notification.Name {
    static let songMetadataUpdated = Notification.Name("LocalLosslessPlayer.songMetadataUpdated")
}
