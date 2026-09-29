import SwiftUI
import AVFoundation

enum SpotifyCanvasState: Equatable {
    case loading
    case ready(URL)
    case unavailable(String)
}

enum SpotifyCanvasService {
    private struct CanvasResponse: Decodable {
        let canvasUrl: String?
        let spotifyId: String?
        let connected: Bool
    }

    static func load(for track: Track) async -> SpotifyCanvasState {
        guard AppConfiguration.apiURL != nil else {
            return .unavailable("Le service NeonWave doit être connecté pour charger les vidéos d'ambiance.")
        }
        let targetId: String
        var queryItems: [URLQueryItem] = []
        if let spId = track.spotifyId, spId.count == 22 {
            targetId = spId
        } else {
            targetId = "resolve"
            queryItems.append(URLQueryItem(name: "title", value: track.title))
            queryItems.append(URLQueryItem(name: "artist", value: track.artist))
        }
        do {
            let response: CanvasResponse = try await APIClient().call(
                "api/ambient/\(targetId)",
                authenticated: false,
                queryItems: queryItems
            )
            guard response.connected else {
                return .unavailable("Le service vidéo d'ambiance n'est pas actif sur votre serveur NeonWave.")
            }
            guard let value = response.canvasUrl, let url = URL(string: value) else {
                return .unavailable("Aucune vidéo d'ambiance disponible pour ce morceau.")
            }
            return .ready(url)
        } catch {
            return .unavailable("La vidéo d'ambiance est momentanément inaccessible.")
        }
    }
}

final class LoopingCanvasUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct LoopingCanvasVideo: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var loadedURL: URL?

        func load(_ url: URL, in view: LoopingCanvasUIView) {
            guard loadedURL != url else { return }
            player?.pause()
            let queue = AVQueuePlayer()
            queue.isMuted = true
            queue.actionAtItemEnd = .advance
            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: queue, templateItem: item)
            player = queue
            loadedURL = url
            view.playerLayer.player = queue
            view.playerLayer.videoGravity = .resizeAspectFill
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> LoopingCanvasUIView {
        let view = LoopingCanvasUIView()
        view.backgroundColor = .clear
        context.coordinator.load(url, in: view)
        if isPlaying { context.coordinator.player?.play() }
        return view
    }

    func updateUIView(_ uiView: LoopingCanvasUIView, context: Context) {
        context.coordinator.load(url, in: uiView)
        if isPlaying { context.coordinator.player?.play() }
        else { context.coordinator.player?.pause() }
    }

    static func dismantleUIView(_ uiView: LoopingCanvasUIView, coordinator: Coordinator) {
        coordinator.player?.pause()
        uiView.playerLayer.player = nil
    }
}

struct SpotifyCanvasView: View {
    let track: Track
    let isPlaying: Bool
    @State private var state: SpotifyCanvasState = .loading
    @State private var reloadID = UUID()

    var body: some View {
        ZStack {
            switch state {
            case .loading:
                RoundedRectangle(cornerRadius: 28).fill(Color.white.opacity(0.04))
                VStack(spacing: 14) {
                    ProgressView().tint(.white)
                    Text("CHARGEMENT DU FOND VIDÉO").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(NW.muted)
                }
            case .ready(let url):
                LoopingCanvasVideo(url: url, isPlaying: isPlaying)
                    .overlay(alignment: .bottomLeading) {
                        Label("VIDÉO D'AMBIANCE", systemImage: "sparkles.tv.fill")
                            .font(.system(size: 9, weight: .bold)).tracking(1.3)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule()).padding(14)
                    }
            case .unavailable(let message):
                ZStack {
                    AsyncImage(url: track.artworkURL.flatMap(URL.init(string:))) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        LinearGradient(colors: [NW.colors[track.colorIndex][0], NW.background], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    Rectangle().fill(.black.opacity(0.52))
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles.tv.fill").font(.system(size: 38, weight: .light)).foregroundStyle(NW.blue)
                        Text("Vidéo d'ambiance").font(.title3.bold())
                        Text(message).font(.caption).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).padding(.horizontal, 30)
                        Button { reloadID = UUID() } label: { Label("Réessayer", systemImage: "arrow.clockwise").font(.caption.bold()).padding(.horizontal, 16).padding(.vertical, 10).background(.white.opacity(0.12), in: Capsule()) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.08)))
        .task(id: "\(track.id)-\(reloadID.uuidString)") {
            state = .loading
            state = await SpotifyCanvasService.load(for: track)
        }
    }
}
