import CoreData
import SwiftUI

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime = 0.0
    @Published private(set) var duration = 0.0
    private var queue: [Song] = []
    private var queueIndex = 0
    private let service = AudioPlayerService()
    init() {
        service.$isPlaying.assign(to: &$isPlaying)
        service.$currentTime.assign(to: &$currentTime)
        service.$duration.assign(to: &$duration)
        service.onPlaybackFinished = { [weak self] in self?.next() }
        service.onNextRequested = { [weak self] in self?.next() }
        service.onPreviousRequested = { [weak self] in self?.previous() }
    }

    func play(_ song: Song, queue: [Song]) {
        self.queue = queue; queueIndex = queue.firstIndex(of: song) ?? 0
        currentSong = song
        do { try service.load(url: URL(fileURLWithPath: song.filePath), title: song.title, artist: song.artist); try service.play(); song.lastPlayedAt = Date(); try song.managedObjectContext?.save() }
        catch { print("Playback failed: \(error)") }
    }

    func toggle() { isPlaying ? service.pause() : try? service.play() }
    func seek(to value: Double) { try? service.seek(to: value) }
    func next() { guard !queue.isEmpty else { return }; queueIndex = (queueIndex + 1) % queue.count; play(queue[queueIndex], queue: queue) }
    func previous() { guard !queue.isEmpty else { return }; queueIndex = (queueIndex - 1 + queue.count) % queue.count; play(queue[queueIndex], queue: queue) }
}
