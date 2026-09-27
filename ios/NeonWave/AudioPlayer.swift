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
    @Published var error: String?

    // Paroles synchronisées (Karaoké)
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var plainLyrics: String?
    @Published private(set) var activeLyricIndex: Int?
    @Published private(set) var loadingLyrics = false
    @Published private(set) var lyricsOffset: Double = 0

    private let player = AVPlayer()
    private lazy var appleMusicPlayer = ApplicationMusicPlayer.shared
    private var isAppleMusicActive = false
    private var isYouTubeActive = false
    private var resolveTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var playbackObserver: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    private var sleepTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var lyricsFallbackTask: Task<Void, Never>?
    private var lyricsRequestedDuration: Double = 0
    private var index = 0
    private weak var library: LibraryStore?
    private var resumeAfterInterruption = false
    private var shuffleHistory: [Int] = []
    private var bufferingWatchdogTask: Task<Void, Never>?
    private var musicKitTimer: Timer?
    private var musicKitCompletedTrackID: String?

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isYouTubeActive else { return }
                self.elapsed = time.seconds.isFinite ? time.seconds : 0
                let length = self.player.currentItem?.duration.seconds ?? 0
                if length.isFinite && length > 0 {
                    if self.duration <= 0 || abs(self.duration - length) > 1 {
                        self.duration = length
                        if self.queue.indices.contains(self.index) {
                            self.queue[self.index].duration = length
                            self.current = self.queue[self.index]
                        }
                    }
                    if self.lyricsRequestedDuration == 0 || abs(self.lyricsRequestedDuration - length) > 2 {
                        self.fetchLyricsForCurrent(preferredDuration: length)
                    }
                }
                self.updateActiveLyric()
                self.updateNowPlaying()
            }
        }
        playbackObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, !self.isYouTubeActive else { return }
                self.isPlaying = self.player.timeControlStatus == .playing
                self.isBuffering = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.updateNowPlaying()
            }
        }
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

        musicKitTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAppleMusicState() }
        }

        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(event.positionTime) }; return .success
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

        YouTubePlayer.shared.onError = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isYouTubeActive, let cur = self.current else { return }
                self.bufferingWatchdogTask?.cancel()
                if let stream = cur.streamURL, let url = URL(string: stream) {
                    self.startAVPlayerFallback(url: url)
                } else {
                    self.error = "Erreur lors de la lecture du titre."
                    self.pause()
                }
            }
        }
    }

    func connect(_ library: LibraryStore) { self.library = library }

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
        if current?.id == track.id {
            if isPlaying { pause() } else { resume() }
            return
        }
        let list = tracks ?? [track]
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

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        current = target; elapsed = 0; duration = target.duration; lyricsOffset = 0; lyricsRequestedDuration = 0
        lyricsTask?.cancel(); lyricsFallbackTask?.cancel(); lyrics = []; plainLyrics = nil; activeLyricIndex = nil; loadingLyrics = true
        updateNowPlaying(includeArtwork: true)

        // 1. If downloaded / imported locally, use native AVPlayer
        if let localURL = library?.localURL(target) {
            isAppleMusicActive = false
            appleMusicPlayer.stop()
            isYouTubeActive = false
            SilentAudioKeepAlive.shared.stop()
#if !APPSTORE
            YouTubePlayer.shared.stop()
#endif

            let item = AVPlayerItem(url: localURL)
            statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self else { return }
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

        if let existingVid = target.videoId, !existingVid.isEmpty, target.duration > 0, target.spotifyId != nil {
            startNativeOnlinePlayback(videoId: existingVid, trackID: target.id)
        } else {
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
                        self.startNativeOnlinePlayback(videoId: media.videoId, trackID: target.id)
                    } else if let existingVid = target.videoId, !existingVid.isEmpty {
                        self.startNativeOnlinePlayback(videoId: existingVid, trackID: target.id)
                    } else if let stream = target.streamURL, let url = URL(string: stream) {
                        self.startAVPlayerFallback(url: url)
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
        resolveTask = Task { [weak self] in
            let nativeURL = await MusicCatalogService.nativeStreamURL(videoId: videoId)
            guard !Task.isCancelled, let self, self.current?.id == trackID else { return }
            if let nativeURL {
                self.startAVPlayerFallback(url: nativeURL, fallbackVideoId: videoId)
            } else {
                self.startYouTubePlayback(videoId: videoId)
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
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isYouTubeActive, self.isBuffering, !self.isPlaying, let cur = self.current else { return }
                if let stream = cur.streamURL, let url = URL(string: stream) {
                    self.startAVPlayerFallback(url: url)
                }
            }
        }
    }

    private func startAVPlayerFallback(url: URL, fallbackVideoId: String? = nil) {
        isYouTubeActive = false
        bufferingWatchdogTask?.cancel()
        SilentAudioKeepAlive.shared.stop()
        YouTubePlayer.shared.stop()
        let item = AVPlayerItem(url: url)
        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .failed {
                    if let fallbackVideoId {
                        self.startYouTubePlayback(videoId: fallbackVideoId)
                    } else {
                        self.error = "Ce flux audio ne peut pas être lu."
                        self.pause()
                    }
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
        player.replaceCurrentItem(with: item)
        player.automaticallyWaitsToMinimizeStalling = true
        player.playImmediately(atRate: 1.0)
        isPlaying = false; isBuffering = true
        if lyricsRequestedDuration == 0 { fetchLyricsForCurrent(preferredDuration: current?.duration ?? 0) }
        updateNowPlaying(includeArtwork: true)
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

    private func updateActiveLyric() {
        guard !lyrics.isEmpty else { activeLyricIndex = nil; return }
        activeLyricIndex = lyrics.lastIndex(where: { $0.time + lyricsOffset <= elapsed })
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
        guard let minutes else { sleepUntil = nil; return }
        sleepUntil = Date().addingTimeInterval(Double(minutes * 60))
        sleepTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(minutes * 60)) } catch { return }
            self?.pause(); self?.sleepUntil = nil
        }
    }

    func stop() {
        resolveTask?.cancel()
        lyricsTask?.cancel()
        lyricsFallbackTask?.cancel()
        if isYouTubeActive {
#if !APPSTORE
            YouTubePlayer.shared.stop()
#endif
            SilentAudioKeepAlive.shared.stop()
        }
        appleMusicPlayer.stop()
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

    private func updateNowPlaying(includeArtwork: Bool = false) {
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
