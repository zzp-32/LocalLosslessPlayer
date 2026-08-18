import CoreData
import SwiftUI

enum RepeatMode: CaseIterable {
    case off, all, one

    var icon: String { self == .one ? "repeat.1" : "repeat" }
    var title: String {
        switch self {
        case .off: return "关闭循环"
        case .all: return "列表循环"
        case .one: return "单曲循环"
        }
    }
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published private(set) var isShuffled = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var sleepTimerEnd: Date?
    @Published var errorMessage: String?

    private var sourceQueue: [Song] = []
    private var queue: [Song] = []
    private var queueIndex = 0
    private let service = AudioPlayerService()
    private let listeningHistory = ListeningHistoryStore.shared
    private var sleepTimer: Timer?
    private var playbackPersistenceTimer: Timer?
    private var listeningTimer: Timer?
    private var activeSourceURL: URL?
    private var activeSourceIsScoped = false
    private var hasAttemptedSessionRestore = false
    private var isRestoringSession = false
    private var listeningPlaybackID: UUID?
    private var listeningSongChecksum: String?
    private var listeningSecondsInPlayback = 0.0
    private var listeningPlayCredited = false
    private var lastListeningTick: Date?
    private var isAppInBackground = false

    private enum PlaybackMemoryKey {
        static let songChecksum = "playback.lastSongChecksum"
        static let position = "playback.lastPosition"
    }

    var playbackProgress: AudioPlayerService { service }
    var currentTime: Double { service.currentTime }
    var duration: Double { service.duration }

    init() {
        service.$isPlaying.assign(to: &$isPlaying)
        service.onPlaybackFinished = { [weak self] in self?.advanceAfterFinish() }
        service.onNextRequested = { [weak self] in self?.next() }
        service.onPreviousRequested = { [weak self] in self?.previous() }
        playbackPersistenceTimer = Timer.scheduledTimer(
            timeInterval: 5,
            target: self,
            selector: #selector(playbackPersistenceTimerFired),
            userInfo: nil,
            repeats: true
        )
        listeningTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(listeningTimerFired),
            userInfo: nil,
            repeats: true
        )
    }

    func play(_ song: Song, queue: [Song]) {
        sourceQueue = queue
        self.queue = arrangedQueue(from: queue, keeping: song)
        queueIndex = self.queue.firstIndex(of: song) ?? 0
        loadAndPlay(song)
    }

    func restoreLastSession(from songs: [Song]) {
        guard !hasAttemptedSessionRestore, currentSong == nil, !songs.isEmpty else { return }

        let defaults = UserDefaults.standard
        guard let checksum = defaults.string(forKey: PlaybackMemoryKey.songChecksum),
              let song = songs.first(where: { $0.checksum == checksum }) else {
            hasAttemptedSessionRestore = true
            return
        }

        hasAttemptedSessionRestore = true
        isRestoringSession = true
        defer { isRestoringSession = false }

        sourceQueue = songs
        queue = arrangedQueue(from: songs, keeping: song)
        queueIndex = queue.firstIndex(of: song) ?? 0

        guard let sourceURL = SourceReference.resolveURL(for: song) else {
            currentSong = song
            errorMessage = "文件不可用，请重新定位文件夹。"
            print("[PlaybackMemory] Restore failed: source unavailable for \(song.title)")
            return
        }

        releaseActiveSourceAccess()
        activeSourceURL = sourceURL
        activeSourceIsScoped = sourceURL.startAccessingSecurityScopedResource()
        currentSong = song

        do {
            try service.load(url: sourceURL, title: song.title, artist: song.artist)
            let savedPosition = defaults.double(forKey: PlaybackMemoryKey.position)
            let position = restoredPosition(savedPosition, duration: service.duration)
            if position > 0 {
                try service.seek(to: position)
            }
            print("[PlaybackMemory] Restored \(song.title) at \(position) seconds (paused)")
        } catch {
            releaseActiveSourceAccess()
            errorMessage = "无法恢复“\(song.title)”：\(error.localizedDescription)"
            print("[PlaybackMemory] Restore failed: \(error.localizedDescription)")
        }
    }

    func persistPlaybackSession() {
        guard !isRestoringSession, let currentSong else { return }
        captureListeningTime()
        let defaults = UserDefaults.standard
        defaults.set(currentSong.checksum, forKey: PlaybackMemoryKey.songChecksum)
        defaults.set(max(0, min(currentTime, duration)), forKey: PlaybackMemoryKey.position)
        listeningHistory.flush()
    }

    func toggle() {
        guard currentSong != nil else { return }
        if isPlaying {
            captureListeningTime()
            service.pause()
            lastListeningTick = nil
            persistPlaybackSession()
        } else {
            do {
                try service.play()
                ensureListeningSession(for: currentSong)
            }
            catch { errorMessage = "无法继续播放：\(error.localizedDescription)" }
        }
    }

    func seek(to value: Double) {
        do {
            captureListeningTime()
            try service.seek(to: value)
            lastListeningTick = isPlaying ? Date() : nil
            persistPlaybackSession()
        }
        catch { errorMessage = "无法跳转到指定位置" }
    }

    func next() { advance(by: 1) }

    func playNext(_ song: Song, fallbackQueue: [Song]) {
        guard let currentSong else {
            play(song, queue: fallbackQueue)
            return
        }
        guard currentSong.objectID != song.objectID else { return }

        if sourceQueue.isEmpty { sourceQueue = fallbackQueue }
        if !sourceQueue.contains(where: { $0.objectID == song.objectID }) {
            sourceQueue.append(song)
        }
        if queue.isEmpty {
            queue = [currentSong]
            queueIndex = 0
        }
        if let existingIndex = queue.firstIndex(where: { $0.objectID == song.objectID }) {
            queue.remove(at: existingIndex)
            if existingIndex < queueIndex { queueIndex -= 1 }
        }
        let insertionIndex = min(queueIndex + 1, queue.count)
        queue.insert(song, at: insertionIndex)
        print("[PlaybackQueue] Next = \(song.title)")
    }

    func removeFromPlaybackQueue(_ objectID: NSManagedObjectID) {
        let isCurrentSong = currentSong?.objectID == objectID
        sourceQueue.removeAll { $0.objectID == objectID }

        if isCurrentSong {
            finishListeningSession(captureRemainder: isPlaying)
            service.stop()
            releaseActiveSourceAccess()
            currentSong = nil
            queue = []
            queueIndex = 0
            UserDefaults.standard.removeObject(forKey: PlaybackMemoryKey.songChecksum)
            UserDefaults.standard.removeObject(forKey: PlaybackMemoryKey.position)
            return
        }

        if let queueItemIndex = queue.firstIndex(where: { $0.objectID == objectID }) {
            queue.remove(at: queueItemIndex)
            if queueItemIndex < queueIndex { queueIndex -= 1 }
            if queue.isEmpty { queueIndex = 0 }
            else { queueIndex = min(queueIndex, queue.count - 1) }
        }
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
        } else {
            advance(by: -1)
        }
    }

    func toggleShuffle() {
        isShuffled.toggle()
        guard let currentSong else { return }
        queue = arrangedQueue(from: sourceQueue, keeping: currentSong)
        queueIndex = queue.firstIndex(of: currentSong) ?? 0
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func apply(settings: AppSettings) {
        service.applySettings(
            gains: settings.equalizerGains,
            preamp: settings.preamp,
            balance: settings.balance,
            bassBoost: settings.bassBoost,
            trebleBoost: settings.trebleBoost,
            stereoExpansion: settings.stereoExpansion,
            monoAudio: settings.monoAudio,
            rate: settings.playbackRate,
            loudness: settings.loudness
        )
    }

    func setSleepTimer(minutes: Int?) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        guard let minutes else { sleepTimerEnd = nil; return }
        sleepTimerEnd = Date().addingTimeInterval(Double(minutes * 60))
        sleepTimer = Timer.scheduledTimer(
            timeInterval: Double(minutes * 60),
            target: self,
            selector: #selector(sleepTimerFired),
            userInfo: nil,
            repeats: false
        )
    }

    @objc private func sleepTimerFired() {
        captureListeningTime()
        service.pause()
        lastListeningTick = nil
        persistPlaybackSession()
        sleepTimerEnd = nil
        sleepTimer = nil
    }

    @objc private func playbackPersistenceTimerFired() {
        guard isPlaying else { return }
        persistPlaybackSession()
    }

    @objc private func listeningTimerFired() {
        guard isPlaying, currentSong != nil else {
            lastListeningTick = nil
            return
        }
        ensureListeningSession(for: currentSong)
        captureListeningTime()
    }

    private func advanceAfterFinish() {
        finishListeningSession(captureRemainder: true)
        if repeatMode == .one, let currentSong {
            loadAndPlay(currentSong)
            return
        }
        if repeatMode == .off, queueIndex == queue.count - 1 {
            service.stop()
            return
        }
        advance(by: 1)
    }

    private func advance(by offset: Int) {
        guard !queue.isEmpty else { return }
        queueIndex = (queueIndex + offset + queue.count) % queue.count
        loadAndPlay(queue[queueIndex])
    }

    private func arrangedQueue(from songs: [Song], keeping current: Song) -> [Song] {
        guard isShuffled else { return songs }
        return [current] + songs.filter { $0 != current }.shuffled()
    }

    private func loadAndPlay(_ song: Song) {
        _ = LocalMetadataService.apply(to: song)
        guard let sourceURL = SourceReference.resolveURL(for: song) else {
            errorMessage = "文件不可用，请重新定位文件夹。"
            return
        }
        finishListeningSession(captureRemainder: isPlaying)
        releaseActiveSourceAccess()
        activeSourceURL = sourceURL
        activeSourceIsScoped = sourceURL.startAccessingSecurityScopedResource()
        currentSong = song
        Task { await MetadataMatcher.shared.match(song: song) }
        do {
            try service.load(
                url: sourceURL,
                title: song.title,
                artist: song.artist
            )
            try service.play()
            beginListeningSession(for: song)
            persistPlaybackSession()
            song.lastPlayedAt = Date()
            try song.managedObjectContext?.save()
        } catch {
            releaseActiveSourceAccess()
            errorMessage = "无法播放“\(song.title)”：\(error.localizedDescription)"
        }
    }

    private func restoredPosition(_ savedPosition: Double, duration: Double) -> Double {
        guard savedPosition.isFinite, duration.isFinite, duration > 0 else { return 0 }
        let clamped = max(0, min(savedPosition, duration))
        return clamped >= max(0, duration - 2) ? 0 : clamped
    }

    private func beginListeningSession(for song: Song) {
        listeningPlaybackID = UUID()
        listeningSongChecksum = song.checksum
        listeningSecondsInPlayback = 0
        listeningPlayCredited = false
        lastListeningTick = Date()
    }

    private func ensureListeningSession(for song: Song?) {
        guard let song else { return }
        if listeningPlaybackID == nil || listeningSongChecksum != song.checksum {
            beginListeningSession(for: song)
        } else if lastListeningTick == nil {
            lastListeningTick = Date()
        }
    }

    private func captureListeningTime(force: Bool = false) {
        guard let song = currentSong,
              let playbackID = listeningPlaybackID,
              listeningSongChecksum == song.checksum,
              let previousTick = lastListeningTick,
              isPlaying || force else { return }

        let now = Date()
        let delta = min(5, max(0, now.timeIntervalSince(previousTick)))
        lastListeningTick = now
        guard delta > 0 else { return }

        listeningSecondsInPlayback += delta
        let threshold = duration > 0 ? min(30, max(1, duration * 0.5)) : 30
        let shouldCredit = !listeningPlayCredited && listeningSecondsInPlayback >= threshold
        if shouldCredit { listeningPlayCredited = true }
        listeningHistory.recordListening(
            song: song,
            playbackID: playbackID,
            seconds: delta,
            at: now,
            creditPlay: shouldCredit
        )
    }

    func setPlayerScreenVisible(_ isVisible: Bool) {
        service.setProgressUpdateRate(isAppInBackground ? 1 : (isVisible ? 60 : 1))
    }

    func setAppInBackground(_ background: Bool) {
        isAppInBackground = background
        if background {
            service.setProgressUpdateRate(1)
        }
    }

    private func finishListeningSession(captureRemainder: Bool) {
        if captureRemainder { captureListeningTime(force: true) }
        listeningHistory.flush()
        listeningPlaybackID = nil
        listeningSongChecksum = nil
        listeningSecondsInPlayback = 0
        listeningPlayCredited = false
        lastListeningTick = nil
    }

    private func releaseActiveSourceAccess() {
        if activeSourceIsScoped {
            activeSourceURL?.stopAccessingSecurityScopedResource()
        }
        activeSourceURL = nil
        activeSourceIsScoped = false
    }
}
