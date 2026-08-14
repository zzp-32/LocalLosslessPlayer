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

    init() {
        service.$isPlaying.assign(to: &$isPlaying)
        service.$currentTime.assign(to: &$currentTime)
        service.$duration.assign(to: &$duration)
        service.onPlaybackFinished = { [weak self] in self?.advanceAfterFinish() }
        service.onNextRequested = { [weak self] in self?.next() }
        service.onPreviousRequested = { [weak self] in self?.previous() }
    }

    func play(_ song: Song, queue: [Song]) {
        sourceQueue = queue
        self.queue = arrangedQueue(from: queue, keeping: song)
        queueIndex = self.queue.firstIndex(of: song) ?? 0
        loadAndPlay(song)
    }

    func toggle() {
        guard currentSong != nil else { return }
        if isPlaying {
            service.pause()
        } else {
            do { try service.play() }
            catch { errorMessage = "无法继续播放：\(error.localizedDescription)" }
        }
    }

    func seek(to value: Double) {
        do { try service.seek(to: value) }
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
        currentSong = song
        Task { await MetadataMatcher.shared.match(song: song) }
        do {
            try service.load(
                url: URL(fileURLWithPath: song.filePath),
                title: song.title,
                artist: song.artist
            )
            try service.play()
            song.lastPlayedAt = Date()
            try song.managedObjectContext?.save()
        } catch {
            errorMessage = "无法播放“\(song.title)”：\(error.localizedDescription)"
        }
    }
}
