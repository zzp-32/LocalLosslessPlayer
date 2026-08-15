import Combine
import Foundation

struct ListeningRecord: Codable, Identifiable {
    let id: UUID
    let playbackID: UUID
    let songChecksum: String
    var title: String
    var artist: String?
    var album: String?
    var artworkPath: String?
    let startedAt: Date
    var endedAt: Date
    var listenedSeconds: Double
    var playCountAt: Date?
}

enum ListeningPeriod: String, CaseIterable, Identifiable {
    case day = "日"
    case week = "周"
    case month = "月"
    case year = "年"

    var id: String { rawValue }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
}

struct ListeningChartPoint: Identifiable {
    let date: Date
    let listenedSeconds: Double
    var id: Date { date }
}

struct ListeningSongRanking: Identifiable {
    let checksum: String
    let title: String
    let artist: String?
    let album: String?
    let artworkPath: String?
    let playCount: Int
    let listenedSeconds: Double
    var id: String { checksum }
}

struct ListeningReportSummary {
    let interval: DateInterval
    let totalListenedSeconds: Double
    let playbackSessions: Int
    let uniqueSongs: Int
    let validPlayCount: Int
    let chartPoints: [ListeningChartPoint]
    let songs: [ListeningSongRanking]
}

@MainActor
final class ListeningHistoryStore: ObservableObject {
    static let shared = ListeningHistoryStore()

    @Published private(set) var records: [ListeningRecord] = []

    private let calendar = Calendar.autoupdatingCurrent
    private let fileURL: URL
    private var saveTimer: Timer?

    private init() {
        fileURL = StorageConfiguration.dataRootURL.appendingPathComponent("ListeningHistory.json")
        load()
    }

    func recordListening(
        song: Song,
        playbackID: UUID,
        seconds: Double,
        at timestamp: Date,
        creditPlay: Bool
    ) {
        guard seconds.isFinite, seconds > 0 else { return }
        let delta = min(seconds, 5)

        if let index = records.indices.last,
           records[index].playbackID == playbackID,
           records[index].songChecksum == song.checksum,
           timestamp.timeIntervalSince(records[index].endedAt) < 3 {
            records[index].endedAt = timestamp
            records[index].listenedSeconds += delta
            records[index].title = song.title
            records[index].artist = song.artist
            records[index].album = song.album
            records[index].artworkPath = song.artworkPath
            if creditPlay, records[index].playCountAt == nil {
                records[index].playCountAt = timestamp
            }
        } else {
            records.append(
                ListeningRecord(
                    id: UUID(),
                    playbackID: playbackID,
                    songChecksum: song.checksum,
                    title: song.title,
                    artist: song.artist,
                    album: song.album,
                    artworkPath: song.artworkPath,
                    startedAt: timestamp.addingTimeInterval(-delta),
                    endedAt: timestamp,
                    listenedSeconds: delta,
                    playCountAt: creditPlay ? timestamp : nil
                )
            )
        }
        scheduleSave()
    }

    func flush() {
        saveTimer?.invalidate()
        saveTimer = nil
        save()
    }

    func totalListenedSeconds(forArtist artist: String) -> Double {
        let target = normalizedArtist(artist)
        return records.reduce(0) { result, record in
            normalizedArtist(record.artist ?? "未知艺术家") == target
                ? result + record.listenedSeconds
                : result
        }
    }

    func summary(for period: ListeningPeriod, anchor: Date) -> ListeningReportSummary {
        let interval = dateInterval(for: period, anchor: anchor)
        let buckets = chartBuckets(for: period, interval: interval)
        var bucketSeconds = Array(repeating: 0.0, count: buckets.count)
        var totalSeconds = 0.0
        var playbackIDs = Set<UUID>()
        var validPlayCount = 0
        var songValues: [String: SongAccumulator] = [:]

        for record in records {
            let contribution = listenedSeconds(of: record, in: interval)
            let countedPlay = record.playCountAt.map { interval.contains($0) } ?? false
            guard contribution > 0 || countedPlay else { continue }

            if contribution > 0 {
                totalSeconds += contribution
                playbackIDs.insert(record.playbackID)
            }
            if countedPlay { validPlayCount += 1 }

            var song = songValues[record.songChecksum] ?? SongAccumulator(record: record)
            song.listenedSeconds += contribution
            if countedPlay { song.playCount += 1 }
            songValues[record.songChecksum] = song

            for index in buckets.indices {
                bucketSeconds[index] += listenedSeconds(of: record, in: buckets[index])
            }
        }

        let chartPoints = zip(buckets, bucketSeconds).map {
            ListeningChartPoint(date: $0.0.start, listenedSeconds: $0.1)
        }
        let songs = songValues.values
            .filter { $0.playCount > 0 }
            .map { $0.ranking }
            .sorted {
                if $0.playCount != $1.playCount { return $0.playCount > $1.playCount }
                if $0.listenedSeconds != $1.listenedSeconds { return $0.listenedSeconds > $1.listenedSeconds }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }

        return ListeningReportSummary(
            interval: interval,
            totalListenedSeconds: totalSeconds,
            playbackSessions: playbackIDs.count,
            uniqueSongs: songValues.values.filter { $0.listenedSeconds > 0 }.count,
            validPlayCount: validPlayCount,
            chartPoints: chartPoints,
            songs: songs
        )
    }

    private func dateInterval(for period: ListeningPeriod, anchor: Date) -> DateInterval {
        calendar.dateInterval(of: period.calendarComponent, for: anchor)
            ?? DateInterval(start: anchor, duration: 1)
    }

    private func chartBuckets(for period: ListeningPeriod, interval: DateInterval) -> [DateInterval] {
        let component: Calendar.Component
        switch period {
        case .day: component = .hour
        case .week, .month: component = .day
        case .year: component = .month
        }

        var buckets: [DateInterval] = []
        var cursor = interval.start
        while cursor < interval.end,
              let next = calendar.date(byAdding: component, value: 1, to: cursor) {
            buckets.append(DateInterval(start: cursor, end: min(next, interval.end)))
            cursor = next
        }
        return buckets
    }

    private func listenedSeconds(of record: ListeningRecord, in interval: DateInterval) -> Double {
        let overlapStart = max(record.startedAt, interval.start)
        let overlapEnd = min(record.endedAt, interval.end)
        guard overlapEnd > overlapStart else { return 0 }
        let recordDuration = max(0.001, record.endedAt.timeIntervalSince(record.startedAt))
        let overlap = overlapEnd.timeIntervalSince(overlapStart)
        return record.listenedSeconds * min(1, overlap / recordDuration)
    }

    private func normalizedArtist(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func scheduleSave() {
        guard saveTimer == nil else { return }
        saveTimer = Timer.scheduledTimer(
            timeInterval: 5,
            target: self,
            selector: #selector(saveTimerFired),
            userInfo: nil,
            repeats: false
        )
    }

    @objc private func saveTimerFired() {
        saveTimer = nil
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = try decoder.decode([ListeningRecord].self, from: data)
        } catch {
            print("[ListeningHistory] Load failed: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[ListeningHistory] Save failed: \(error.localizedDescription)")
        }
    }
}

private struct SongAccumulator {
    let checksum: String
    var title: String
    var artist: String?
    var album: String?
    var artworkPath: String?
    var playCount = 0
    var listenedSeconds = 0.0

    init(record: ListeningRecord) {
        checksum = record.songChecksum
        title = record.title
        artist = record.artist
        album = record.album
        artworkPath = record.artworkPath
    }

    var ranking: ListeningSongRanking {
        ListeningSongRanking(
            checksum: checksum,
            title: title,
            artist: artist,
            album: album,
            artworkPath: artworkPath,
            playCount: playCount,
            listenedSeconds: listenedSeconds
        )
    }
}
