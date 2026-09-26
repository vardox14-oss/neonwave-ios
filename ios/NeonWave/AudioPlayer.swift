import SwiftUI
import AVFoundation
import MediaPlayer

@MainActor final class AudioPlayer: ObservableObject {
    @Published private(set) var current: Track?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var isPlaying = false
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

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var playbackObserver: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    private var sleepTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var index = 0
    private weak var library: LibraryStore?
    private var resumeAfterInterruption = false
    private var shuffleHistory: [Int] = []

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = time.seconds.isFinite ? time.seconds : 0
                let length = self.player.currentItem?.duration.seconds ?? 0
                if length.isFinite && length > 0 { self.duration = length }
                if !self.lyrics.isEmpty {
                    self.activeLyricIndex = self.lyrics.lastIndex(where: { $0.time <= self.elapsed })
                }
                self.updateNowPlaying()
            }
        }
        playbackObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.isPlaying = self?.player.timeControlStatus == .playing }
        }
        observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                guard let self, let ended = notification.object as? AVPlayerItem, ended === self.player.currentItem else { return }
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

    func connect(_ library: LibraryStore) { self.library = library }

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
        let playable = list.filter { playableURL(for: $0) != nil }
        guard !playable.isEmpty, let target = playable.first(where: { $0.id == track.id }) ?? playable.first else {
            error = "Source audio introuvable pour ce titre."; return
        }
        queue = playable
        index = queue.firstIndex(where: { $0.id == target.id }) ?? 0
        shuffleHistory = []; loadCurrent()
    }

    private func loadCurrent() {
        guard queue.indices.contains(index), let url = playableURL(for: queue[index]) else { stop(); return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        current = queue[index]; elapsed = 0; duration = current?.duration ?? 0
        let item = AVPlayerItem(url: url)
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed { Task { @MainActor in self?.error = "Ce flux audio ne peut pas être lu."; self?.pause() } }
        }
        player.replaceCurrentItem(with: item)
        player.automaticallyWaitsToMinimizeStalling = true
        player.playImmediately(atRate: 1.0)
        if let library, library.localURL(queue[index]) != nil {
            library.recordPlay(queue[index])
        }
        fetchLyricsForCurrent()
        updateNowPlaying(includeArtwork: true)
    }

    private func fetchLyricsForCurrent() {
        lyricsTask?.cancel()
        guard let current else {
            lyrics = []; plainLyrics = nil; activeLyricIndex = nil; loadingLyrics = false; return
        }
        loadingLyrics = true; lyrics = []; plainLyrics = nil; activeLyricIndex = nil
        lyricsTask = Task { [weak self] in
            let result = await LyricsService.fetchLyrics(title: current.title, artist: current.artist, duration: current.duration)
            Task { @MainActor in
                guard let self, self.current?.id == current.id else { return }
                self.lyrics = result.lines
                self.plainLyrics = result.plain
                self.loadingLyrics = false
            }
        }
    }

    func toggle() { isPlaying ? pause() : resume() }
    func pause() { player.pause(); isPlaying = false; updateNowPlaying() }
    func resume() {
        guard current != nil else { return }
        do { try AVAudioSession.sharedInstance().setActive(true); player.play() }
        catch { self.error = "Impossible de reprendre la lecture." }
    }

    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        player.seek(to: CMTime(seconds: min(max(0, seconds), duration), preferredTimescale: 600)); elapsed = seconds
        if !lyrics.isEmpty { activeLyricIndex = lyrics.lastIndex(where: { $0.time <= seconds }) }
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
        guard playableURL(for: track) != nil else { error = "Source audio introuvable."; return }
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
        pause(); player.replaceCurrentItem(with: nil); current = nil; queue = []; elapsed = 0; duration = 0
        lyrics = []; plainLyrics = nil; activeLyricIndex = nil
        setSleep(minutes: nil); MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateNowPlaying(includeArtwork: Bool = false) {
        guard let current else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = current.title; info[MPMediaItemPropertyArtist] = current.artist
        info[MPMediaItemPropertyPlaybackDuration] = duration; info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
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
    }
}
