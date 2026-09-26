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
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var playbackObserver: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    private var sleepTask: Task<Void, Never>?
    private var index = 0
    private weak var library: LibraryStore?
    private var resumeAfterInterruption = false
    private var shuffleHistory: [Int] = []

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.4, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = time.seconds.isFinite ? time.seconds : 0
                let length = self.player.currentItem?.duration.seconds ?? 0
                if length.isFinite && length > 0 { self.duration = length }
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
    func play(_ track: Track, in tracks: [Track]? = nil) {
        guard let library, library.localURL(track) != nil else {
            error = "Téléchargez d’abord ce titre pour l’écouter sur cet iPhone."; return
        }
        queue = (tracks ?? [track]).filter { library.localURL($0) != nil }
        index = queue.firstIndex(where: { $0.id == track.id }) ?? 0
        shuffleHistory = []; loadCurrent()
    }
    private func loadCurrent() {
        guard queue.indices.contains(index), let library, let url = library.localURL(queue[index]) else { stop(); return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { self.error = "La sortie audio n’est pas disponible."; return }
        current = queue[index]; elapsed = 0; duration = current?.duration ?? 0
        let item = AVPlayerItem(url: url)
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed { Task { @MainActor in self?.error = "Ce fichier audio ne peut pas être lu."; self?.pause() } }
        }
        player.replaceCurrentItem(with: item)
        player.play(); library.recordPlay(queue[index]); updateNowPlaying(includeArtwork: true)
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
        guard library?.localURL(track) != nil else { error = "Téléchargez ce titre avant de l’ajouter à la file."; return }
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
            if let url = library?.artworkURL(current), let image = UIImage(contentsOfFile: url.path) {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
