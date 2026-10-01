import SwiftUI
import WebKit

@MainActor
final class YouTubePlayer: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = YouTubePlayer()

    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isReady = false
    @Published var currentVideoId: String?

    var onTimeUpdate: ((Double, Double) -> Void)?
    var onStateChange: ((Bool) -> Void)?
    var onEnded: (() -> Void)?
    var onError: ((Int) -> Void)?

    private var backingWebView: WKWebView?
    var webView: WKWebView {
        if backingWebView == nil { setupWebView() }
        return backingWebView!
    }
    private var pendingVideoId: String?

    override init() {
        super.init()
    }

    private func setupWebView() {
        guard backingWebView == nil else { return }
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.suppressesIncrementalRendering = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let controller = WKUserContentController()
        controller.add(self, name: "neonwaveBridge")
        config.userContentController = controller

        let wv = WKWebView(frame: .init(x: 0, y: 0, width: 200, height: 200), configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.navigationDelegate = self
        self.backingWebView = wv
        loadHTML()
    }

    func loadHTML() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <script src="https://www.youtube.com/iframe_api"></script>
        <style>
        * { margin:0; padding:0; background:transparent; overflow:hidden; }
        html, body, #player { width:100%; height:100%; background:transparent; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script>
        var player = null;
        var pendingId = null;
        var isApiReady = false;
        var progressTimer = null;
        var lastPlayRequestTime = 0;
        var userRequestedPause = false;

        function onYouTubeIframeAPIReady() {
            isApiReady = true;
            window.webkit.messageHandlers.neonwaveBridge.postMessage({ type: 'ready' });
            if (pendingId) {
                var id = pendingId;
                pendingId = null;
                playVideoId(id);
            }
        }

        function startProgressTimer() {
            if (progressTimer) clearInterval(progressTimer);
            progressTimer = setInterval(function() {
                if (player && typeof player.getCurrentTime === 'function' && typeof player.getDuration === 'function') {
                    var cur = player.getCurrentTime() || 0;
                    var dur = player.getDuration() || 0;
                    window.webkit.messageHandlers.neonwaveBridge.postMessage({
                        type: 'time',
                        current: cur,
                        duration: dur
                    });
                }
            }, 250);
        }

        function onPlayerReady(event) {
            window.webkit.messageHandlers.neonwaveBridge.postMessage({ type: 'ready' });
            startProgressTimer();
            try {
                if (player) {
                    if (player.unMute) player.unMute();
                    if (player.setVolume) player.setVolume(100);
                    if (player.playVideo) player.playVideo();
                }
            } catch(e) {}
        }

        function onPlayerStateChange(event) {
            // 1: PLAYING, 2: PAUSED, 0: ENDED, 3: BUFFERING
            window.webkit.messageHandlers.neonwaveBridge.postMessage({
                type: 'state',
                state: event.data
            });
            if (event.data === 1) { // PLAYING
                startProgressTimer();
            }
            if (event.data === 2 && !userRequestedPause && (Date.now() - lastPlayRequestTime) < 3000) {
                setTimeout(function() {
                    try {
                        if (player && !userRequestedPause) {
                            if (player.unMute) player.unMute();
                            if (player.setVolume) player.setVolume(100);
                            if (player.playVideo) player.playVideo();
                        }
                    } catch(e) {}
                }, 120);
            }
        }

        function onPlayerError(event) {
            window.webkit.messageHandlers.neonwaveBridge.postMessage({
                type: 'error',
                code: event.data
            });
        }

        function playVideoId(id) {
            if (!id) return;
            lastPlayRequestTime = Date.now();
            userRequestedPause = false;

            if (!isApiReady || typeof YT === 'undefined' || !YT.Player) {
                pendingId = id;
                return;
            }

            if (!player) {
                player = new YT.Player('player', {
                    width: '100%',
                    height: '100%',
                    videoId: id,
                    playerVars: {
                        'playsinline': 1,
                        'autoplay': 1,
                        'controls': 0,
                        'disablekb': 1,
                        'fs': 0,
                        'modestbranding': 1,
                        'rel': 0,
                        'origin': window.location.origin
                    },
                    events: {
                        'onReady': onPlayerReady,
                        'onStateChange': onPlayerStateChange,
                        'onError': onPlayerError
                    }
                });
            } else {
                try {
                    if (player.unMute) player.unMute();
                    if (player.setVolume) player.setVolume(100);
                    if (typeof player.loadVideoById === 'function') {
                        player.loadVideoById(id, 0);
                    } else if (typeof player.cueVideoById === 'function') {
                        player.cueVideoById(id, 0);
                    }
                    if (player.playVideo) player.playVideo();
                } catch(e) {}
                setTimeout(function() {
                    try {
                        if (player && player.unMute) player.unMute();
                        if (player && player.setVolume) player.setVolume(100);
                        if (player && player.playVideo && !userRequestedPause) player.playVideo();
                    } catch(e) {}
                }, 300);
            }
        }

        function resume() {
            userRequestedPause = false;
            lastPlayRequestTime = Date.now();
            if (player) {
                if (player.unMute) player.unMute();
                if (player.setVolume) player.setVolume(100);
                if (player.playVideo) player.playVideo();
            }
        }

        function pause() {
            userRequestedPause = true;
            if (player && player.pauseVideo) player.pauseVideo();
        }

        function seek(sec) {
            if (player && player.seekTo) player.seekTo(sec, true);
        }
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
            if let pending = pendingVideoId {
                playVideo(pending)
                pendingVideoId = nil
            }
        case "time":
            let cur = (body["current"] as? Double) ?? 0
            let dur = (body["duration"] as? Double) ?? 0
            self.currentTime = cur
            if dur > 0 { self.duration = dur }
            onTimeUpdate?(cur, dur)
        case "state":
            let state = (body["state"] as? Int) ?? -1
            if state == 1 { // PLAYING
                isPlaying = true
                onStateChange?(true)
            } else if state == 2 { // PAUSED
                isPlaying = false
                onStateChange?(false)
            } else if state == 0 { // ENDED
                isPlaying = false
                onStateChange?(false)
                onEnded?()
            }
        case "error":
            let code = (body["code"] as? Int) ?? -1
            onError?(code)
        default:
            break
        }
    }

    func playVideo(_ videoId: String) {
        currentVideoId = videoId
        _ = webView
        let safeId = videoId.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\\", with: "")
        webView.evaluateJavaScript("playVideoId('\(safeId)');") { [weak self] _, error in
            if error != nil {
                self?.pendingVideoId = videoId
            }
        }
    }

    func resume() {
        _ = webView
        webView.evaluateJavaScript("resume();")
    }

    func pause() {
        isPlaying = false
        backingWebView?.evaluateJavaScript("pause();")
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        backingWebView?.evaluateJavaScript("seek(\(seconds));")
    }

    func stop() {
        pause()
        currentVideoId = nil
        currentTime = 0
        duration = 0
    }
}

struct YouTubePlayerWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        return YouTubePlayer.shared.webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
