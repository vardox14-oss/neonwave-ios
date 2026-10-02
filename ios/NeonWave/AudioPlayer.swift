import SwiftUI
import AVFoundation
import MediaPlayer
import MusicKit

private final class SilentAudioKeepAlive {
    static let shared = SilentAudioKeepAlive()
    private var audioPlayer: AVAudioPlayer?

    private init() {
        if let data = Self.createSilentWavData() {
            audioPlayer = try? AVAudioPlayer(data: data)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 0.01
            audioPlayer?.prepareToPlay()
        }
    }

    func start() {
        audioPlayer?.play()
    }

    func pause() {
        audioPlayer?.pause()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
    }

    private static func createSilentWavData() -> Data? {
        let sampleRate: UInt32 = 44100
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let numSamples: UInt32 = 44100
        let subchunk2Size = numSamples * UInt32(channels) * UInt32(bitsPerSample / 8)
        let chunkSize = 36 + subchunk2Size

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        var cSize = chunkSize.littleEndian
        data.append(Data(bytes: &cSize, count: MemoryLayout<UInt32>.size))
        data.append(contentsOf: "WAVEfmt ".utf8)
        var sc1Size = UInt32(16).littleEndian
        data.append(Data(bytes: &sc1Size, count: MemoryLayout<UInt32>.size))
        var formatTag = UInt16(1).littleEndian
        data.append(Data(bytes: &formatTag, count: MemoryLayout<UInt16>.size))
        var ch = channels.littleEndian
        data.append(Data(bytes: &ch, count: MemoryLayout<UInt16>.size))
        var sr = sampleRate.littleEndian
        data.append(Data(bytes: &sr, count: MemoryLayout<UInt32>.size))
        var br = (sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)).littleEndian
        data.append(Data(bytes: &br, count: MemoryLayout<UInt32>.size))
        var ba = (channels * (bitsPerSample / 8)).littleEndian
        data.append(Data(bytes: &ba, count: MemoryLayout<UInt16>.size))
        var bps = bitsPerSample.littleEndian
        data.append(Data(bytes: &bps, count: MemoryLayout<UInt16>.size))
        data.append(contentsOf: "data".utf8)
        var sc2Size = subchunk2Size.littleEndian
        data.append(Data(bytes: &sc2Size, count: MemoryLayout<UInt32>.size))
        data.append(Data(count: Int(subchunk2Size)))
        return data
    }
}

enum CrossfadeMath {
    static let preloadLead: Double = 5
    static let minimumFade: Double = 1

    /// Equal-power curve: out² + in² = 1, so perceived loudness stays constant through the overlap.
    static func gains(progress: Double) -> (out: Float, in: Float) {
        let t = progress.isFinite ? min(1, max(0, progress)) : 1
        return (Float(cos(t * .pi / 2)), Float(sin(t * .pi / 2)))
    }

    static func effectiveFade(setting: Double, outgoingLength: Double, incomingLength: Double) -> Double {
        guard setting > 0, outgoingLength > 0 else { return 0 }
        let shortest = incomingLength > 0 ? min(outgoingLength, incomingLength) : outgoingLength
        return min(setting, shortest * 0.4)
    }

    static func upcomingIndex(current: Int, count: Int, shuffle: Bool, repeatMode: RepeatMode, random: (Range<Int>) -> Int = { Int.random(in: $0) }) -> Int? {
        guard count > 0, repeatMode != .one else { return nil }
        if shuffle && count > 1 {
            let pick = random(0..<(count - 1))
            return pick >= current ? pick + 1 : pick
        }
        if current + 1 < count { return current + 1 }
        return repeatMode == .all ? 0 : nil
    }
}

@MainActor final class AudioPlayer: ObservableObject {
    @Published private(set) var current: Track?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var sleepUntil: Date?
    @Published private(set) var sleepAtEndOfTrack = false
    @Published var error: String?

    // Paroles synchronisées (Karaoké)
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var plainLyrics: String?
    @Published private(set) var activeLyricIndex: Int?
    @Published private(set) var loadingLyrics = false
    @Published private(set) var lyricsOffset: Double = 0
    // Alternance automatique des styles 1 musique sur 2 : Vague -> Ligne -> Vague -> Ligne...
    @Published private(set) var songCounter: Int = 0
    var isWaveEffect: Bool { songCounter % 2 != 0 }

    @Published var crossfadeSeconds: Double = UserDefaults.standard.object(forKey: "nw.crossfadeSeconds") as? Double ?? 6 {
        didSet { UserDefaults.standard.set(crossfadeSeconds, forKey: "nw.crossfadeSeconds") }
    }
    @Published private(set) var isCrossfading = false

    // Two players alternate: `player` is always the audible/current track,
    // `standbyPlayer` preloads the next one, then tails out the previous one during a fade.
    private var player = AVPlayer()
    private var standbyPlayer = AVPlayer()
    private var fadeOutPlayer: AVPlayer?
    private var fadeTimer: Timer?
    private var plannedIndex: Int?
    private var plannedTrackID: String?
    private lazy var appleMusicPlayer = ApplicationMusicPlayer.shared
    private var isAppleMusicActive = false
    private var isYouTubeActive = false
    private var resolveTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var timeObservers: [Any] = []
    private var statusObserver: NSKeyValueObservation?
    private var playbackObservers: [NSKeyValueObservation] = []
    private var observers: [NSObjectProtocol] = []
    private var sleepTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var lyricsFallbackTask: Task<Void, Never>?
    private var lyricsRequestedDuration: Double = 0
    private var spotifyDuration: Double = 0   // durée Spotify originale (référence)
    private var index = 0
    private weak var library: LibraryStore?
    private var resumeAfterInterruption = false
    private var shuffleHistory: [Int] = []
    private var bufferingWatchdogTask: Task<Void, Never>?
    private var musicKitTimer: Timer?
    private var musicKitCompletedTrackID: String?

    init() {
        installObservers(on: player)
        installObservers(on: standbyPlayer)
        observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                guard let self, !self.isYouTubeActive, let ended = notification.object as? AVPlayerItem, ended === self.player.currentItem else { return }
                self.next(automatic: true)
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            Task { @MainActor in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue { self.resumeAfterInterruption = self.isPlaying; self.pause() }
                else if self.resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) { self.resume() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { @MainActor in self?.pause() } }
        })

#if !APPSTORE
        setupYouTubeCallbacks()
#endif

        musicKitTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.isAppleMusicActive else { return }
            Task { @MainActor in self.refreshAppleMusicState() }
        }

        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        commands.pauseCommand.isEnabled = true
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.togglePlayPauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        commands.nextTrackCommand.isEnabled = true
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        commands.previousTrackCommand.isEnabled = true
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }

        // Disable 15s skip/seek commands so iOS Control Center & Lock Screen show Previous / Next Track (|<< and >>|) instead of +15s/-15s video buttons
        commands.skipForwardCommand.isEnabled = false
        commands.skipBackwardCommand.isEnabled = false
        commands.seekForwardCommand.isEnabled = false
        commands.seekBackwardCommand.isEnabled = false

        commands.changePlaybackPositionCommand.isEnabled = true
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(event.positionTime) }; return .success
        }
    }

    private func installObservers(on observed: AVPlayer) {
        let observedID = ObjectIdentifier(observed)
        timeObservers.append(observed.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, ObjectIdentifier(self.player) == observedID, !self.isYouTubeActive else { return }
                self.handleTick(time)
            }
        })
        playbackObservers.append(observed.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, ObjectIdentifier(self.player) == observedID, !self.isYouTubeActive else { return }
                self.isPlaying = self.player.timeControlStatus == .playing
                self.isBuffering = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.updateNowPlaying()
            }
        })
    }

    private func handleTick(_ time: CMTime) {
        elapsed = time.seconds.isFinite ? time.seconds : 0

        // ── Durée affichée ──────────────────────────────────────────
        // On préfère la durée Spotify (spotifyDuration) si elle est connue.
        // La durée du fichier YouTube peut contenir du silence après la chanson.
        let length = player.currentItem?.duration.seconds ?? 0
        if length.isFinite && length > 0 {
            let displayDuration = spotifyDuration > 0 ? spotifyDuration : length
            if duration <= 0 || abs(duration - displayDuration) > 1 {
                duration = displayDuration
                if queue.indices.contains(index) {
                    queue[index].duration = displayDuration
                    current = queue[index]
                }
            }
            if lyricsRequestedDuration == 0 || abs(lyricsRequestedDuration - displayDuration) > 2 {
                fetchLyricsForCurrent(preferredDuration: displayDuration)
            }
        }

        if evaluateCrossfade() { return }

        // ── Auto-avance si la chanson est terminée mais le stream continue ──
        // (ex: vidéo YouTube de 4min pour une chanson de 2min05)
        if spotifyDuration > 0 && isPlaying && elapsed > spotifyDuration + 2.0 {
            next(automatic: true)
            return
        }

        updateActiveLyric()
        updateNowPlaying()
    }

    // MARK: - Crossfade (downloaded files only: MusicKit and the YouTube webview expose no volume control)

    /// Returns true when a fade was just started (the tick must stop: state now describes the new track).
    private func evaluateCrossfade() -> Bool {
        guard crossfadeSeconds > 0, !isCrossfading, !isAppleMusicActive, !isYouTubeActive,
              player.timeControlStatus == .playing,
              let current, library?.localURL(current) != nil,
              let item = player.currentItem else { return false }
        let itemLength = item.duration.seconds
        let now = player.currentTime().seconds
        guard itemLength.isFinite, itemLength > 0, now.isFinite else { return false }
        // Same cut-off as the auto-advance below, so the fade ends exactly where the song would.
        let end = spotifyDuration > 0 ? min(itemLength, spotifyDuration + 2) : itemLength
        let timeLeft = end - now
        guard timeLeft > 0 else { return false }

        let roughFade = CrossfadeMath.effectiveFade(setting: crossfadeSeconds, outgoingLength: end, incomingLength: 0)
        guard roughFade >= CrossfadeMath.minimumFade else { return false }
        if timeLeft <= roughFade + CrossfadeMath.preloadLead { preparePlannedTrack() }

        guard let nextIndex = plannedIndex, queue.indices.contains(nextIndex), queue[nextIndex].id == plannedTrackID,
              let incoming = standbyPlayer.currentItem, incoming.status == .readyToPlay else { return false }
        let incomingLength = incoming.duration.seconds
        let fade = CrossfadeMath.effectiveFade(setting: crossfadeSeconds, outgoingLength: end, incomingLength: incomingLength.isFinite ? incomingLength : 0)
        guard fade >= CrossfadeMath.minimumFade, timeLeft <= fade else { return false }
        beginCrossfade(to: nextIndex, over: timeLeft)
        return true
    }

    private func preparePlannedTrack() {
        if let planned = plannedIndex, queue.indices.contains(planned), queue[planned].id == plannedTrackID {
            let stillValid = shuffle
                ? planned != index
                : planned == CrossfadeMath.upcomingIndex(current: index, count: queue.count, shuffle: false, repeatMode: repeatMode)
            if stillValid { return }
        }
        discardPlannedTrack()
        guard let nextIndex = CrossfadeMath.upcomingIndex(current: index, count: queue.count, shuffle: shuffle, repeatMode: repeatMode) else { return }
        plannedIndex = nextIndex
        plannedTrackID = queue[nextIndex].id
        // Local tracks and preloaded online streams can be buffered in standbyPlayer
        let plannedURL = library?.localURL(queue[nextIndex]) ?? (queue[nextIndex].streamURL.flatMap { URL(string: $0) })
        guard let url = plannedURL else { return }
        standbyPlayer.volume = 0
        standbyPlayer.automaticallyWaitsToMinimizeStalling = false
        standbyPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    private func discardPlannedTrack() {
        plannedIndex = nil
        plannedTrackID = nil
        if !isCrossfading {
            standbyPlayer.pause()
            standbyPlayer.replaceCurrentItem(with: nil)
        }
    }

    private func beginCrossfade(to nextIndex: Int, over fadeDuration: Double) {
        let outgoing = player
        let incoming = standbyPlayer
        plannedIndex = nil
        plannedTrackID = nil
        if shuffle { shuffleHistory.append(index) }
        index = nextIndex
        player = incoming
        standbyPlayer = outgoing
        fadeOutPlayer = outgoing
        isCrossfading = true

        // The UI switches to the new song as soon as it starts fading in, like Apple Music.
        let target = queue[index]
        resetState(for: target)
        isPlaying = true
        isBuffering = false
        if let item = incoming.currentItem { observeLocalItem(item) }
        incoming.volume = 0
        incoming.playImmediately(atRate: 1.0)
        fetchLyricsForCurrent(preferredDuration: target.duration)
        library?.recordPlay(target)

        let start = ProcessInfo.processInfo.systemUptime
        fadeTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.stepCrossfade(startedAt: start, duration: fadeDuration) }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    private func stepCrossfade(startedAt start: TimeInterval, duration fadeDuration: Double) {
        guard isCrossfading, let outgoing = fadeOutPlayer else { return }
        let progress = (ProcessInfo.processInfo.systemUptime - start) / max(fadeDuration, 0.01)
        let gains = CrossfadeMath.gains(progress: progress)
        outgoing.volume = gains.out
        player.volume = gains.in
        if progress >= 1 { finishCrossfade() }
    }

    /// Ends the fade immediately: the previous song stops, the new one goes to full volume.
    private func finishCrossfade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        if let outgoing = fadeOutPlayer {
            outgoing.pause()
            outgoing.replaceCurrentItem(with: nil)
            outgoing.volume = 1
        }
        fadeOutPlayer = nil
        player.volume = 1
        isCrossfading = false
    }

    var fadeSnapshot: (outgoingVolume: Float, incomingVolume: Float, outgoingPlaying: Bool)? {
        guard isCrossfading, let outgoing = fadeOutPlayer else { return nil }
        return (outgoing.volume, player.volume, outgoing.timeControlStatus == .playing)
    }

    private func cancelCrossfade() {
        if isCrossfading { finishCrossfade() }
        discardPlannedTrack()
        player.volume = 1
    }

    private func resetState(for target: Track) {
        spotifyDuration = target.duration > 10 ? target.duration : 0
        songCounter += 1
        current = target; elapsed = 0; duration = target.duration; lyricsOffset = 0; lyricsRequestedDuration = 0
        lyricsTask?.cancel(); lyricsFallbackTask?.cancel(); lyrics = []; plainLyrics = nil; activeLyricIndex = nil; loadingLyrics = true
        updateNowPlaying(includeArtwork: true)
    }

    private func observeLocalItem(_ item: AVPlayerItem) {
        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, item === self.player.currentItem else { return }
                if item.status == .failed {
                    self.error = "Ce fichier audio ne peut pas être lu."
                    self.pause()
                } else if item.status == .readyToPlay {
                    let itemDur = item.duration.seconds
                    if itemDur.isFinite && itemDur > 0 {
                        if self.duration <= 0 || abs(self.duration - itemDur) > 1 {
                            self.duration = itemDur
                            if self.queue.indices.contains(self.index) {
                                self.queue[self.index].duration = itemDur
                                self.current = self.queue[self.index]
                            }
                        }
                        if self.lyricsRequestedDuration == 0 || abs(self.lyricsRequestedDuration - itemDur) > 2 {
                            self.fetchLyricsForCurrent(preferredDuration: itemDur)
                        }
                        self.updateNowPlaying()
                    }
                }
            }
        }
    }

    private func setupYouTubeCallbacks() {
        YouTubePlayer.shared.onTimeUpdate = { [weak self] cur, dur in
            Task { @MainActor in
                guard let self, self.isYouTubeActive else { return }
                self.elapsed = cur
                if dur > 0 {
                    if self.duration <= 0 || abs(self.duration - dur) > 1 {
                        self.duration = dur
                        if self.queue.indices.contains(self.index) {
                            self.queue[self.index].duration = dur
                            self.current = self.queue[self.index]
                        }
                    }
                    if self.lyricsRequestedDuration == 0 || abs(self.lyricsRequestedDuration - dur) > 2 {
                        self.fetchLyricsForCurrent(preferredDuration: dur)
                    }
                }
                self.updateActiveLyric()
                self.updateNowPlaying()
            }
        }

        YouTubePlayer.shared.onStateChange = { [weak self] playing in
            Task { @MainActor in
                guard let self, self.isYouTubeActive else { return }
                self.isPlaying = playing
                if playing {
                    self.isBuffering = false
                    self.bufferingWatchdogTask?.cancel()
                }
                self.updateNowPlaying()
            }
        }

        YouTubePlayer.shared.onEnded = { [weak self] in
            Task { @MainActor in
                guard let self, self.isYouTubeActive else { return }
                self.next(automatic: true)
            }
        }

        YouTubePlayer.shared.onError = { [weak self] code in
            Task { @MainActor in
                guard let self, self.isYouTubeActive, let cur = self.current else { return }
                self.bufferingWatchdogTask?.cancel()
                // If Topic track is blocked by YouTube embed rules (Error 101 or 150), fallback to server stream or alternative non-blocked video
                Task {
                    if let vid = cur.videoId, let streamURL = await MusicCatalogService.nativeStreamURL(videoId: vid) {
                        await MainActor.run {
                            guard self.current?.id == cur.id else { return }
                            self.startAVPlayerPlayback(url: streamURL)
                        }
                    } else if let altVid = await MusicCatalogService.resolveAlternativeYouTubeId(title: cur.title, artist: cur.artist, excludeVideoId: cur.videoId ?? "") {
                        await MainActor.run {
                            guard self.current?.id == cur.id else { return }
                            if self.queue.indices.contains(self.index) {
                                self.queue[self.index].videoId = altVid
                                self.current = self.queue[self.index]
                            }
                            self.startNativeOnlinePlayback(videoId: altVid, trackID: cur.id)
                        }
                    } else if let stream = cur.streamURL, let url = URL(string: stream) {
                        await MainActor.run {
                            self.startAVPlayerPlayback(url: url)
                        }
                    } else {
                        await MainActor.run {
                            self.error = "Erreur lors de la lecture du titre."
                            self.pause()
                        }
                    }
                }
            }
        }
    }

    func connect(_ library: LibraryStore) { self.library = library }

    func refreshCurrentTrack(from updatedTrack: Track) {
        if current?.id == updatedTrack.id {
            current = updatedTrack
            if queue.indices.contains(index), queue[index].id == updatedTrack.id {
                queue[index] = updatedTrack
            }
            updateNowPlaying(includeArtwork: true)
        }
    }

    func isPlayable(_ track: Track) -> Bool {
        if library?.localURL(track) != nil { return true }
        if track.appleMusicID != nil { return true }
        if track.videoId != nil { return true }
        if track.streamURL != nil { return true }
        if !track.title.isEmpty { return true }
        return false
    }

    func playableURL(for track: Track) -> URL? {
        if let local = library?.localURL(track) { return local }
        if let stream = track.streamURL, let url = URL(string: stream) { return url }
        return nil
    }

    func play(_ track: Track, in tracks: [Track]? = nil) {
        preloadTask?.cancel()
        if current?.id == track.id {
            if isPlaying { pause() } else { resume() }
            return
        }
        var list = tracks ?? [track]
        if NetworkMonitor.shared.isActuallyOffline {
            if library?.localURL(track) == nil {
                error = "Ce titre n’a pas été téléchargé pour le mode hors connexion."
                return
            }
            list = list.filter { library?.localURL($0) != nil }
        }
        let playable = list.filter { isPlayable($0) }
        guard !playable.isEmpty, let target = playable.first(where: { $0.id == track.id }) ?? playable.first else {
            error = "Source audio introuvable pour ce titre."; return
        }
        queue = playable
        index = queue.firstIndex(where: { $0.id == target.id }) ?? 0
        shuffleHistory = []; loadCurrent()
    }

    private func loadCurrent() {
        guard queue.indices.contains(index) else { stop(); return }
        let target = queue[index]
        resolveTask?.cancel()
        cancelCrossfade()

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        // Mémoriser la durée Spotify AVANT de charger le stream YouTube
        // (le stream peut être plus long que la chanson réelle)
        resetState(for: target)

        // 1. If downloaded / imported locally, use native AVPlayer
        if let localURL = library?.localURL(target) {
            if isAppleMusicActive { appleMusicPlayer.stop() }
            isAppleMusicActive = false
            isYouTubeActive = false
            SilentAudioKeepAlive.shared.stop()
#if !APPSTORE
            YouTubePlayer.shared.stop()
#endif

            let item = AVPlayerItem(url: localURL)
            observeLocalItem(item)
            player.replaceCurrentItem(with: item)
            player.automaticallyWaitsToMinimizeStalling = true
            player.playImmediately(atRate: 1.0)
            isPlaying = true; isBuffering = false
            fetchLyricsForCurrent(preferredDuration: target.duration)
            library?.recordPlay(target)
            return
        }

        if target.appleMusicID != nil {
            startAppleMusicPlayback(target)
            return
        }

        // 2. Online track: resolve the complete song, then play it natively.
        // Fast-path: if streamURL is already known on this track (e.g. from background queue preloading), start AVPlayer immediately!
        if let stream = target.streamURL, let url = URL(string: stream) {
            isAppleMusicActive = false
            isYouTubeActive = false
            SilentAudioKeepAlive.shared.stop()
            fetchLyricsForCurrent(preferredDuration: target.duration)
            startAVPlayerPlayback(url: url, fallbackVideoId: target.videoId)
            preloadUpcomingTrack()
            return
        }

        // Native AVPlayer keeps playing with the screen locked and exposes the
        // real iOS lock-screen controls.
        isYouTubeActive = false
        isPlaying = false
        isBuffering = true
        player.replaceCurrentItem(with: nil) // Stop AVPlayer preview
        lyricsFallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.current?.id == target.id, self.lyricsRequestedDuration == 0 else { return }
                self.fetchLyricsForCurrent(preferredDuration: target.duration)
            }
        }

        // Re-resolve stored IDs so old incorrect matches do not survive an update.
        do {
            resolveTask = Task { [weak self] in
                guard let self else { return }
                let media = await MusicCatalogService.resolveTrackMedia(title: target.title, artist: target.artist, duration: target.duration, spotifyId: target.spotifyId)
                Task { @MainActor in
                    guard self.current?.id == target.id else { return }
                    if let media {
                        if self.queue.indices.contains(self.index) {
                            self.queue[self.index].videoId = media.videoId
                            if let dur = media.duration, dur > 0 {
                                self.queue[self.index].duration = dur
                                self.duration = dur
                            }
                            if let spId = media.spotifyId, !spId.isEmpty {
                                self.queue[self.index].spotifyId = spId
                            }
                            if let thumb = media.thumbnail, !thumb.isEmpty, (self.queue[self.index].artworkURL == nil || self.queue[self.index].artworkURL?.isEmpty == true) {
                                self.queue[self.index].artworkURL = thumb
                            }
                            self.current = self.queue[self.index]
                        }
                        if self.duration > 0 && (self.lyricsRequestedDuration == 0 || abs(self.lyricsRequestedDuration - self.duration) > 2) {
                            self.fetchLyricsForCurrent(preferredDuration: self.duration)
                        }
                        self.updateNowPlaying(includeArtwork: true)
                        if let streamURL = media.streamURL {
                            self.startAVPlayerPlayback(url: streamURL, fallbackVideoId: media.videoId)
                            self.preloadUpcomingTrack()
                        } else {
                            self.startNativeOnlinePlayback(videoId: media.videoId, trackID: target.id)
                        }
                    } else if let existingVid = target.videoId, !existingVid.isEmpty {
                        self.startNativeOnlinePlayback(videoId: existingVid, trackID: target.id)
                    } else if let stream = target.streamURL, let url = URL(string: stream) {
                        self.startAVPlayerPlayback(url: url)
                        self.preloadUpcomingTrack()
                    } else {
                        self.error = "Impossible de charger ce titre."
                        self.pause()
                    }
                }
            }
        }
    }

    private func startAppleMusicPlayback(_ target: Track) {
        guard let appleMusicID = target.appleMusicID else { return }
        isAppleMusicActive = true
        isYouTubeActive = false
        musicKitCompletedTrackID = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        // Reset du ApplicationMusicPlayer : sans ça, après plusieurs heures
        // la queue précédente reste dans un état stale et play() échoue en silence
        // (le symptôme "le matin ça marche, le soir plus").
        appleMusicPlayer.stop()
        // MusicKit gère sa propre session audio — on désactive la nôtre pour
        // éviter le conflit qui bloque le premier play().
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        SilentAudioKeepAlive.shared.stop()
#if !APPSTORE
        YouTubePlayer.shared.stop()
#endif
        isPlaying = false
        isBuffering = true
        lyricsFallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.fetchLyricsForCurrent(preferredDuration: target.duration) }
        }
        resolveTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let song = try await AppleMusicService.songs(ids: [appleMusicID]).first else {
                    throw MessageError("Ce titre Apple Music est indisponible dans votre région.")
                }
                guard self.current?.id == target.id else { return }
                self.appleMusicPlayer.queue = ApplicationMusicPlayer.Queue(for: [song], startingAt: song)
                // MusicKit: la queue doit être préparée avant play(), sinon le premier
                // appel échoue silencieusement et il faut re-tapoter pour que ça démarre.
                try await self.appleMusicPlayer.prepareToPlay()
                guard self.current?.id == target.id else { return }
                try await self.appleMusicPlayer.play()
                self.isPlaying = true
                self.isBuffering = false
                self.library?.recordPlay(target)
                self.fetchLyricsForCurrent(preferredDuration: song.duration ?? target.duration)
            } catch {
                guard self.current?.id == target.id else { return }
                self.isPlaying = false
                self.isBuffering = false
                self.error = error.localizedDescription
            }
        }
    }

    private func refreshAppleMusicState() {
        guard isAppleMusicActive, current != nil else { return }
        elapsed = appleMusicPlayer.playbackTime.isFinite ? appleMusicPlayer.playbackTime : 0
        isPlaying = appleMusicPlayer.state.playbackStatus == .playing
        isBuffering = appleMusicPlayer.state.playbackStatus == .seekingForward || appleMusicPlayer.state.playbackStatus == .seekingBackward
        updateActiveLyric()
        if duration > 0, elapsed >= duration - 0.35, musicKitCompletedTrackID != current?.id {
            musicKitCompletedTrackID = current?.id
            next(automatic: true)
        }
    }

    private func startNativeOnlinePlayback(videoId: String, trackID: String) {
        resolveTask?.cancel()
        isYouTubeActive = false
        isPlaying = false
        isBuffering = true

        Task { [weak self] in
            guard let self else { return }
            // 1. Try direct high-quality audio stream via native AVPlayer (bypasses YouTube iframe embed restrictions)
            if let streamURL = await MusicCatalogService.nativeStreamURL(videoId: videoId) {
                await MainActor.run {
                    guard self.current?.id == trackID else { return }
                    self.startAVPlayerPlayback(url: streamURL, fallbackVideoId: videoId)
                }
            } else {
                // 2. Fallback to YouTube embed player
                await MainActor.run {
                    guard self.current?.id == trackID else { return }
                    self.startYouTubePlayback(videoId: videoId)
                }
            }
        }
    }

    private func startYouTubePlayback(videoId: String) {
        isYouTubeActive = true
        SilentAudioKeepAlive.shared.start()
        YouTubePlayer.shared.playVideo(videoId)
        isPlaying = false
        isBuffering = true
        updateNowPlaying(includeArtwork: true)

        bufferingWatchdogTask?.cancel()
        bufferingWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isYouTubeActive, self.isBuffering, !self.isPlaying, let cur = self.current else { return }
                Task {
                    // 1. Try native/server stream URL
                    if let streamURL = await MusicCatalogService.nativeStreamURL(videoId: videoId) {
                        await MainActor.run {
                            guard self.current?.id == cur.id, self.isYouTubeActive, !self.isPlaying else { return }
                            self.startAVPlayerPlayback(url: streamURL)
                        }
                    } else if let altVid = await MusicCatalogService.resolveAlternativeYouTubeId(title: cur.title, artist: cur.artist, excludeVideoId: videoId) {
                        await MainActor.run {
                            guard self.current?.id == cur.id, self.isYouTubeActive, !self.isPlaying else { return }
                            if self.queue.indices.contains(self.index) {
                                self.queue[self.index].videoId = altVid
                                self.current = self.queue[self.index]
                            }
                            self.startYouTubePlayback(videoId: altVid)
                        }
                    } else if let stream = cur.streamURL, let url = URL(string: stream) {
                        await MainActor.run {
                            self.startAVPlayerPlayback(url: url)
                        }
                    } else {
                        await MainActor.run {
                            self.error = "Erreur de lecture du titre."
                            self.isBuffering = false
                        }
                    }
                }
            }
        }
    }

    private func startAVPlayerPlayback(url: URL, fallbackVideoId: String? = nil) {
        isYouTubeActive = false
        bufferingWatchdogTask?.cancel()
        SilentAudioKeepAlive.shared.stop()
#if !APPSTORE
        YouTubePlayer.shared.stop()
#endif
        let item = AVPlayerItem(url: url)
        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, item === self.player.currentItem else { return }
                if item.status == .failed {
                    print("⚠️ AVPlayer playback failed for \(url): \(String(describing: item.error))")
                    if let fallbackVideoId {
                        Task {
                            if let sURL = await MusicCatalogService.serverStreamURL(videoId: fallbackVideoId), sURL != url {
                                await MainActor.run {
                                    self.startAVPlayerPlayback(url: sURL, fallbackVideoId: nil)
                                }
                                return
                            }
                            await MainActor.run {
                                self.startYouTubePlayback(videoId: fallbackVideoId)
                            }
                        }
                    } else {
                        self.error = "Ce flux audio ne peut pas être lu."
                        self.pause()
                    }
                } else if item.status == .readyToPlay {
                    self.bufferingWatchdogTask?.cancel()
                    self.isPlaying = true
                    self.isBuffering = false
                    let itemDur = item.duration.seconds
                    if itemDur.isFinite && itemDur > 0 {
                        if self.duration <= 0 || abs(self.duration - itemDur) > 1 {
                            self.duration = itemDur
                            if self.queue.indices.contains(self.index) {
                                self.queue[self.index].duration = itemDur
                                self.current = self.queue[self.index]
                            }
                        }
                        if self.lyricsRequestedDuration == 0 || abs(self.lyricsRequestedDuration - itemDur) > 2 {
                            self.fetchLyricsForCurrent(preferredDuration: itemDur)
                        }
                        self.updateNowPlaying()
                    }
                    self.preloadUpcomingTrack()
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.automaticallyWaitsToMinimizeStalling = true
        player.playImmediately(atRate: 1.0)
        isPlaying = false
        isBuffering = true
        if lyricsRequestedDuration == 0 { fetchLyricsForCurrent(preferredDuration: current?.duration ?? 0) }
        updateNowPlaying(includeArtwork: true)

        bufferingWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, !self.isYouTubeActive, self.isBuffering, !self.isPlaying, self.player.currentItem === item else { return }
                if let fallbackVideoId {
                    print("⚠️ AVPlayer timed out after 25s, falling back to YouTube")
                    self.startYouTubePlayback(videoId: fallbackVideoId)
                } else {
                    self.error = "Délai de chargement dépassé."
                    self.isBuffering = false
                }
            }
        }
    }

    private func fetchLyricsForCurrent(preferredDuration: Double) {
        lyricsTask?.cancel()
        guard let current else {
            lyrics = []; plainLyrics = nil; activeLyricIndex = nil; loadingLyrics = false; return
        }
        lyricsRequestedDuration = preferredDuration
        loadingLyrics = true; lyrics = []; plainLyrics = nil; activeLyricIndex = nil
        lyricsTask = Task { [weak self] in
            let result = await LyricsService.fetchLyrics(title: current.title, artist: current.artist, duration: preferredDuration)
            guard !Task.isCancelled else { return }
            Task { @MainActor in
                guard let self, self.current?.id == current.id else { return }
                self.lyrics = result.lines
                self.plainLyrics = result.plain
                self.loadingLyrics = false
                self.updateActiveLyric()
            }
        }
    }

    private func preloadUpcomingTrack() {
        preloadTask?.cancel()
        guard let nextIndex = CrossfadeMath.upcomingIndex(current: index, count: queue.count, shuffle: shuffle, repeatMode: repeatMode),
              queue.indices.contains(nextIndex) else { return }
        let nextTrack = queue[nextIndex]
        if nextTrack.appleMusicID != nil || library?.localURL(nextTrack) != nil { return }
        if nextTrack.streamURL != nil { return }

        preloadTask = Task.detached(priority: .utility) { [weak self] in
            // Pause 2 seconds so the current song's initial playback is completely smooth
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }

            let media = await MusicCatalogService.resolveTrackMedia(
                title: nextTrack.title,
                artist: nextTrack.artist,
                duration: nextTrack.duration,
                spotifyId: nextTrack.spotifyId
            )
            guard !Task.isCancelled, let media else { return }

            await MainActor.run { [weak self] in
                guard let self, self.queue.indices.contains(nextIndex), self.queue[nextIndex].id == nextTrack.id else { return }
                self.queue[nextIndex].videoId = media.videoId
                if let dur = media.duration, dur > 0 { self.queue[nextIndex].duration = dur }
                if let spId = media.spotifyId, !spId.isEmpty { self.queue[nextIndex].spotifyId = spId }
                if let thumb = media.thumbnail, !thumb.isEmpty, (self.queue[nextIndex].artworkURL == nil || self.queue[nextIndex].artworkURL?.isEmpty == true) {
                    self.queue[nextIndex].artworkURL = thumb
                }
                if let stream = media.streamURL {
                    self.queue[nextIndex].streamURL = stream.absoluteString
                }
            }
        }
    }

    private func updateActiveLyric() {
        guard !lyrics.isEmpty else { activeLyricIndex = nil; return }
        let pos = elapsed - lyricsOffset
        activeLyricIndex = lyrics.lastIndex(where: { !$0.isBackground && $0.time <= pos }) ?? lyrics.lastIndex(where: { $0.time <= pos })
    }

    func adjustLyricsOffset(by delta: Double) {
        lyricsOffset = min(10, max(-10, lyricsOffset + delta))
        updateActiveLyric()
    }

    func resetLyricsOffset() {
        lyricsOffset = 0
        updateActiveLyric()
    }

    func seek(to lyric: LyricLine) { seek(lyric.time + lyricsOffset) }

    func toggle() { isPlaying ? pause() : resume() }

    func pause() {
        bufferingWatchdogTask?.cancel()
        cancelCrossfade()
        if isAppleMusicActive {
            appleMusicPlayer.pause()
        } else if isYouTubeActive {
#if !APPSTORE
            YouTubePlayer.shared.pause()
#endif
            SilentAudioKeepAlive.shared.pause()
        } else {
            player.pause()
        }
        isPlaying = false; isBuffering = false
        updateNowPlaying()
    }

    func resume() {
        guard current != nil else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if isAppleMusicActive {
                isBuffering = true
                Task { [weak self] in
                    do {
                        try await self?.appleMusicPlayer.play()
                        self?.isPlaying = true
                        self?.isBuffering = false
                    } catch {
                        self?.isBuffering = false
                        self?.error = error.localizedDescription
                    }
                }
            } else if isYouTubeActive {
#if !APPSTORE
                isBuffering = true
                SilentAudioKeepAlive.shared.start()
                YouTubePlayer.shared.resume()
#endif
            } else {
                player.play()
                isPlaying = true
                isBuffering = false
            }
            updateNowPlaying()
        } catch {
            self.error = "Impossible de reprendre la lecture."
        }
    }

    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        cancelCrossfade()
        let targetTime = min(max(0, seconds), duration > 0 ? duration : seconds)
        elapsed = targetTime
        if isAppleMusicActive {
            appleMusicPlayer.playbackTime = targetTime
        } else if isYouTubeActive {
#if !APPSTORE
            YouTubePlayer.shared.seek(to: targetTime)
#endif
        } else {
            player.seek(to: CMTime(seconds: targetTime, preferredTimescale: 600))
        }
        updateActiveLyric()
        updateNowPlaying()
    }

    func next(automatic: Bool = false) {
        if automatic && sleepAtEndOfTrack {
            sleepAtEndOfTrack = false
            pause()
            seek(0)
            return
        }
        guard !queue.isEmpty else { return }
        if automatic && repeatMode == .one { seek(0); resume(); return }
        if shuffle && queue.count > 1 {
            shuffleHistory.append(index)
            index = queue.indices.filter { $0 != index }.randomElement() ?? index
        } else if index + 1 < queue.count { index += 1 }
        else if repeatMode == .all || !automatic { index = 0 }
        else { pause(); seek(0); return }
        loadCurrent()
    }

    func previous() {
        if elapsed > 3 { seek(0); return }
        if shuffle, let previous = shuffleHistory.popLast() { index = previous }
        else { index = max(0, index - 1) }
        loadCurrent()
    }

    func enqueue(_ track: Track) {
        guard isPlayable(track) else { error = "Source audio introuvable."; return }
        if current == nil { play(track) } else { queue.append(track) }
    }

    func selectQueue(_ position: Int) { guard queue.indices.contains(position) else { return }; index = position; loadCurrent() }
    func cycleRepeat() { repeatMode = RepeatMode(rawValue: (repeatMode.rawValue + 1) % 3) ?? .off }

    func setSleep(minutes: Int?) {
        sleepTask?.cancel()
        sleepAtEndOfTrack = false
        guard let minutes else { sleepUntil = nil; return }
        sleepUntil = Date().addingTimeInterval(Double(minutes * 60))
        sleepTask = Task { [weak self] in
            do {
                if minutes > 0 {
                    let waitTime = max(0, Double(minutes * 60) - 3.0)
                    try await Task.sleep(for: .seconds(waitTime))
                }
            } catch { return }
            await self?.fadeOutAndPause()
            self?.sleepUntil = nil
        }
    }

    func setSleepAtEndOfTrack() {
        sleepTask?.cancel()
        sleepUntil = nil
        sleepAtEndOfTrack = true
    }

    private func fadeOutAndPause() async {
        let initialVolume = player.volume
        for step in (0...10).reversed() {
            player.volume = initialVolume * Float(step) / 10.0
            try? await Task.sleep(for: .milliseconds(300))
        }
        pause()
        player.volume = initialVolume
    }

    func stop() {
        preloadTask?.cancel()
        resolveTask?.cancel()
        lyricsTask?.cancel()
        lyricsFallbackTask?.cancel()
        cancelCrossfade()
        if isYouTubeActive {
#if !APPSTORE
            YouTubePlayer.shared.stop()
#endif
            SilentAudioKeepAlive.shared.stop()
        }
        if isAppleMusicActive { appleMusicPlayer.stop() }
        player.pause()
        player.replaceCurrentItem(with: nil)
        isYouTubeActive = false
        isAppleMusicActive = false
        isPlaying = false
        isBuffering = false
        current = nil
        queue = []
        elapsed = 0
        duration = 0
        lyrics = []
        plainLyrics = nil
        activeLyricIndex = nil
        lyricsOffset = 0
        lyricsRequestedDuration = 0
        setSleep(minutes: nil)
        bufferingWatchdogTask?.cancel()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private var lastNowPlayingUpdate: Date = .distantPast

    private func updateNowPlaying(includeArtwork: Bool = false) {
        // Throttle to 1Hz max — MPNowPlayingInfoCenter IPC is expensive
        let now = Date()
        guard includeArtwork || now.timeIntervalSince(lastNowPlayingUpdate) >= 1.0 else { return }
        lastNowPlayingUpdate = now
        guard !isAppleMusicActive else { return }
        guard let current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            return
        }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = current.title
        info[MPMediaItemPropertyArtist] = current.artist
        info[MPMediaItemPropertyAlbumTitle] = current.album ?? "NeonWave"
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = max(1, queue.count)
        if includeArtwork {
            info.removeValue(forKey: MPMediaItemPropertyArtwork)
            if let local = library?.artworkURL(current), let image = UIImage(contentsOfFile: local.path) {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            } else if let remote = current.artworkURL, let url = URL(string: remote) {
                Task {
                    if let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) {
                        Task { @MainActor in
                            var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                            currentInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
                        }
                    }
                }
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : (isBuffering ? .interrupted : .paused)
    }
}
