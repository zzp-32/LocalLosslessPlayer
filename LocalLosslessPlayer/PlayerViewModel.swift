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
    @Published private(set) var currentTime = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var isShuffled = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var sleepTimerEnd: Date?
    @Published var errorMessage: String?

    private var sourceQueue: [Song] = []
    private var queue: [Song] = []
    private var queueIndex = 0
    private let service = AudioPlayerService()
    private var sleepTimer: Timer?
    private var playbackPersistenceTimer: Timer?
    private var activeSourceURL: URL?
    private var activeSourceIsScoped = false
    private var hasAttemptedSessionRestore = false
    private var isRestoringSession = false

    private enum PlaybackMemoryKey {
        static let songChecksum = "playback.lastSongChecksum"
        static let position = "playback.lastPosition"
    }

    init() {
        service.$isPlaying.assign(to: &$isPlaying)
        service.$currentTime.assign(to: &$currentTime)
        service.$duration.assign(to: &$duration)
        service.onPlaybackFinished = { [weak self] in self?.advanceAfterFinish() }
        service.onNextRequested = { [weak self] in self?.next() }
        service.onPreviousRequested = { [weak self] in self?.previous() }
        playbackPersistenceTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard self?.isPlaying == true else { return }
                self?.persistPlaybackSession()
            }
        }
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
        let defaults = UserDefaults.standard
        defaults.set(currentSong.checksum, forKey: PlaybackMemoryKey.songChecksum)
        defaults.set(max(0, min(currentTime, duration)), forKey: PlaybackMemoryKey.position)
    }

    func toggle() {
        guard currentSong != nil else { return }
        if isPlaying {
            service.pause()
            persistPlaybackSession()
        } else {
            do { try service.play() }
            catch { errorMessage = "无法继续播放：\(error.localizedDescription)" }
        }
    }

    func seek(to value: Double) {
        do {
            try service.seek(to: value)
            persistPlaybackSession()
        }
        catch { errorMessage = "无法跳转到指定位置" }
    }

    func next() { advance(by: 1) }

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
        service.pause()
        persistPlaybackSession()
        sleepTimerEnd = nil
        sleepTimer = nil
    }

    private func advanceAfterFinish() {
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

    private func releaseActiveSourceAccess() {
        if activeSourceIsScoped {
            activeSourceURL?.stopAccessingSecurityScopedResource()
        }
        activeSourceURL = nil
        activeSourceIsScoped = false
    }
}
