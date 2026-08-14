import AVFoundation
import Combine
import MediaPlayer

enum AudioPlayerError: Error {
    case noAudioLoaded
}

@MainActor
final class AudioPlayerService: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    var onPlaybackFinished: (() -> Void)?
    var onNextRequested: (() -> Void)?
    var onPreviousRequested: (() -> Void)?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: AppSettings.equalizerFrequencies.count)
    private let toneEqualizer = AVAudioUnitEQ(numberOfBands: 2)
    private let timePitch = AVAudioUnitTimePitch()
    private let stereoSpace = AVAudioUnitReverb()
    private let balanceMixer = AVAudioMixerNode()
    private var audioFile: AVAudioFile?
    private var startFrame: AVAudioFramePosition = 0
    private var scheduleGeneration = 0
    private var progressTimer: Timer?
    private var playbackRate: Double = 1
    private var isMonoAudio = false

    override init() {
        super.init()
        engine.attach(playerNode)
        engine.attach(equalizer)
        engine.attach(toneEqualizer)
        engine.attach(timePitch)
        engine.attach(stereoSpace)
        engine.attach(balanceMixer)
        for (index, frequency) in AppSettings.equalizerFrequencies.enumerated() {
            equalizer.bands[index].filterType = .parametric
            equalizer.bands[index].frequency = Float(frequency)
            equalizer.bands[index].bandwidth = 1.0 / 3.0
            equalizer.bands[index].bypass = false
        }

        toneEqualizer.bands[0].filterType = .lowShelf
        toneEqualizer.bands[0].frequency = 120
        toneEqualizer.bands[0].bandwidth = 0.7
        toneEqualizer.bands[0].bypass = false
        toneEqualizer.bands[1].filterType = .highShelf
        toneEqualizer.bands[1].frequency = 6_000
        toneEqualizer.bands[1].bandwidth = 0.7
        toneEqualizer.bands[1].bypass = false
        stereoSpace.loadFactoryPreset(.smallRoom)
        stereoSpace.wetDryMix = 0

        engine.connect(playerNode, to: equalizer, format: nil)
        engine.connect(equalizer, to: toneEqualizer, format: nil)
        engine.connect(toneEqualizer, to: timePitch, format: nil)
        engine.connect(timePitch, to: stereoSpace, format: nil)
        engine.connect(stereoSpace, to: balanceMixer, format: nil)
        engine.connect(balanceMixer, to: engine.mainMixerNode, format: nil)
        configureAudioSession()
        configureRemoteCommands()
    }

    func applySettings(
        gains: [Double],
        preamp: Double,
        balance: Double,
        bassBoost: Double,
        trebleBoost: Double,
        stereoExpansion: Double,
        monoAudio: Bool,
        rate: Double,
        loudness: Bool
    ) {
        for index in 0..<min(gains.count, equalizer.bands.count) {
            equalizer.bands[index].gain = Float(max(-12, min(12, gains[index])))
        }
        toneEqualizer.bands[0].gain = Float(max(0, min(12, bassBoost)))
        toneEqualizer.bands[1].gain = Float(max(0, min(12, trebleBoost)))
        balanceMixer.pan = Float(max(-1, min(1, balance / 100)))
        balanceMixer.outputVolume = Float(max(0.05, min(2, pow(10, preamp / 20))))
        playbackRate = max(0.5, min(2, rate))
        timePitch.rate = Float(playbackRate)
        equalizer.globalGain = loudness ? 2 : 0
        stereoSpace.wetDryMix = Float(max(0, min(100, stereoExpansion)) * 0.18)
        applyMonoOutputIfNeeded(monoAudio)
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

    private func applyMonoOutputIfNeeded(_ monoAudio: Bool) {
        guard monoAudio != isMonoAudio else { return }
        isMonoAudio = monoAudio
        let session = AVAudioSession.sharedInstance()
        let preferredChannels = monoAudio ? 1 : min(2, max(1, session.maximumOutputNumberOfChannels))
        try? session.setPreferredOutputNumberOfChannels(preferredChannels)
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
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: playbackRate
        ]
    }

    private func updatePlaybackState() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = playbackRate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func startProgressUpdates() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / 30.0,
            target: self,
            selector: #selector(progressTimerFired),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    @objc private func progressTimerFired() {
        updateProgress()
    }

    private func updateProgress() {
        guard let file = audioFile,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        let renderedFrame = startFrame + playerTime.sampleTime
        currentTime = min(duration, Double(renderedFrame) / file.fileFormat.sampleRate)
    }
}
