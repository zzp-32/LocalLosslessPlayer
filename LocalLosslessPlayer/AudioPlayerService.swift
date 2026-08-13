import AVFoundation
import Combine
import MediaPlayer

enum AudioPlayerError: Error {
    case noAudioLoaded
}

@MainActor
final class AudioPlayerService: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    var onPlaybackFinished: (() -> Void)?
    var onNextRequested: (() -> Void)?
    var onPreviousRequested: (() -> Void)?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var startFrame: AVAudioFramePosition = 0
    private var scheduleGeneration = 0
    private var progressTimer: Timer?

    init() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        configureAudioSession()
        configureRemoteCommands()
    }

    func load(url: URL, title: String, artist: String?) throws {
        invalidateSchedule()
        playerNode.stop()
        let file = try AVAudioFile(forReading: url)
        audioFile = file
        duration = Double(file.length) / file.fileFormat.sampleRate
        currentTime = 0
        startFrame = 0
        schedule(from: 0)
        updateNowPlaying(title: title, artist: artist)
    }

    func play() throws {
        guard audioFile != nil else { throw AudioPlayerError.noAudioLoaded }
        if !engine.isRunning { try engine.start() }
        playerNode.play()
        isPlaying = true
        startProgressUpdates()
        updatePlaybackState()
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        stopProgressUpdates()
        updatePlaybackState()
    }

    func seek(to seconds: Double) throws {
        guard let file = audioFile else { throw AudioPlayerError.noAudioLoaded }
        let shouldResume = isPlaying
        let clamped = min(max(seconds, 0), duration)
        let totalFrames = AVAudioFramePosition(file.length)
        let frame = min(AVAudioFramePosition(clamped * file.fileFormat.sampleRate), totalFrames)
        invalidateSchedule()
        playerNode.stop()
        startFrame = frame
        currentTime = clamped
        schedule(from: frame)
        if shouldResume { playerNode.play() }
        updatePlaybackState()
    }

    func stop() {
        invalidateSchedule()
        playerNode.stop()
        isPlaying = false
        currentTime = 0
        startFrame = 0
        stopProgressUpdates()
        updatePlaybackState()
    }

    private func schedule(from frame: AVAudioFramePosition) {
        guard let file = audioFile else { return }
        let totalFrames = AVAudioFramePosition(file.length)
        guard frame < totalFrames else { return }
        scheduleGeneration += 1
        let generation = scheduleGeneration
        let remaining = AVAudioFrameCount(totalFrames - frame)
        playerNode.scheduleSegment(file, startingFrame: frame, frameCount: remaining, at: nil) { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.scheduleGeneration else { return }
                self.isPlaying = false
                self.currentTime = self.duration
                self.stopProgressUpdates()
                self.updatePlaybackState()
                self.onPlaybackFinished?()
            }
        }
    }

    private func invalidateSchedule() { scheduleGeneration += 1 }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? session.setActive(true)
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in try? self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in try? self?.seek(to: event.positionTime) }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onNextRequested?() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPreviousRequested?() }
            return .success
        }
    }

    private func updateNowPlaying(title: String, artist: String?) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1 : 0
        ]
    }

    private func updatePlaybackState() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1 : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func startProgressUpdates() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateProgress() }
        }
    }

    private func stopProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let file = audioFile,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        let renderedFrame = startFrame + playerTime.sampleTime
        currentTime = min(duration, Double(renderedFrame) / file.fileFormat.sampleRate)
    }
}
