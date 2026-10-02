import SwiftUI
import AVKit
import MediaPlayer

enum PlayerMode: String, CaseIterable {
    case cover = "Pochette"
    case lyrics = "Paroles"
    var symbol: String { switch self { case .cover: return "square.stack.fill"; case .lyrics: return "quote.bubble.fill" } }
}

struct MiniPlayer: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    let open: () -> Void
    var body: some View {
        if let track = player.current {
            Button(action: open) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        CoverArt(track: track, imageURL: library.artworkURL(track), remoteURL: track.artworkURL, radius: 8)
                            .frame(width: 42, height: 42)
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                                .foregroundStyle(.white)
                            Text(player.isBuffering ? "Connexion…" : track.artist)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(player.isBuffering ? NW.accent : Color(white: 0.60))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 6) {
                            if player.isBuffering {
                                ProgressView().tint(.white).frame(width: 36, height: 36)
                            } else {
                                Button {
                                    Haptic.light()
                                    player.toggle()
                                } label: {
                                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 38, height: 38)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                Haptic.light()
                                player.next()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    // Integrated progress bar
                    GeometryReader { geo in
                        let progress = player.duration > 0 ? min(1.0, max(0.0, player.elapsed / player.duration)) : 0.0
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.10))
                                .frame(width: geo.size.width, height: 1.5)
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: geo.size.width * CGFloat(progress), height: 1.5)
                        }
                    }
                    .frame(height: 1.5)
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            }
            .buttonStyle(.plain)
        }
    }
}

struct PlayerView: View {
    var onClose: (() -> Void)? = nil
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLyricsExpanded = false
    @State private var showQueue = false
    @State private var showTimer = false
    @State private var dragging = false
    @State private var scrub = 0.0
    @State private var canvasURL: URL? = nil
    @State private var selectedArtist: ArtistIdentifier? = nil
    @State private var showArtworkOverlay = false
    @State private var localArtImage: UIImage? = nil

    var body: some View {
        GeometryReader { geo in
            let topInset = max(54, geo.safeAreaInsets.top + 4)
            ZStack {
                immersiveBackground(size: geo.size)
                if let track = player.current {
                    if isLyricsExpanded {
                        fullScreenLyricsView(track, size: geo.size, topInset: topInset, bottomInset: geo.safeAreaInsets.bottom)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.combined(with: .scale(scale: 0.96))
                            ))
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                // 1. Vue lecteur principale
                                VStack(spacing: 0) {
                                    header(track)
                                        .padding(.top, topInset)

                                    Spacer(minLength: 8)

                                    content(track, size: geo.size)

                                    Spacer(minLength: 16)

                                    trackInfo(track)

                                    Spacer(minLength: 14)

                                    timeline

                                    Spacer(minLength: 16)

                                    controls

                                    Spacer(minLength: 20)

                                    footer(track)
                                }
                                .padding(.horizontal, 28)
                                .padding(.bottom, 20)
                                .frame(minHeight: max(600, geo.size.height - 80))

                                // 2. Carte d'aperçu des paroles style Spotify
                                lyricsPreviewCard(track)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, max(36, geo.safeAreaInsets.bottom + 24))
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity.combined(with: .scale(scale: 0.96))
                        ))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.spring(response: 0.40, dampingFraction: 0.82), value: isLyricsExpanded)
        }
        .overlay(alignment: .top) {
            if let toast = downloads.toastMessage {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .font(.system(size: 16, weight: .bold))
                    Text(toast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.green.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
                .padding(.top, 54)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: downloads.toastMessage)
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showQueue) { QueueView() }
        .sheet(item: $selectedArtist) { artist in ArtistDetailView(artist: artist) }
        .confirmationDialog("Minuterie de sommeil", isPresented: $showTimer, titleVisibility: .visible) {
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button("Dans \(minutes) minutes") {
                    player.setSleep(minutes: minutes)
                    Haptic.success()
                }
            }
            Button("À la fin de ce morceau") {
                player.setSleepAtEndOfTrack()
                Haptic.success()
            }
            if player.sleepUntil != nil || player.sleepAtEndOfTrack {
                Button("Désactiver la minuterie", role: .destructive) {
                    player.setSleep(minutes: nil)
                    Haptic.medium()
                }
            }
        }
        .onChange(of: player.current?.id) { _, value in if value == nil { dismiss() } }
        .task(id: "\(player.current?.id ?? "")-\(player.current?.spotifyId ?? "")") {
            guard let track = player.current else {
                canvasURL = nil
                showArtworkOverlay = false
                localArtImage = nil
                return
            }
            if let local = library.artworkURL(track) {
                localArtImage = UIImage(contentsOfFile: local.path)
            } else {
                localArtImage = nil
            }
            if let localCanvas = library.canvasURL(track) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
                    canvasURL = localCanvas
                }
                return
            }
            canvasURL = nil
            showArtworkOverlay = false
            let state = await SpotifyCanvasService.load(for: track)
            if case .ready(let url) = state {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
                    canvasURL = url
                }
            }
        }
    }

    @ViewBuilder private func immersiveBackground(size: CGSize) -> some View {
        if let track = player.current {
            ZStack {
                NW.background

                // 1. Fond vibrant basé sur la pochette
                Group {
                    if let image = localArtImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .scaleEffect(1.40)
                            .blur(radius: 60)
                            .opacity(0.65)
                            .clipped()
                    } else {
                        AsyncImage(url: track.artworkURL.flatMap(URL.init(string:))) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: size.width, height: size.height)
                                    .scaleEffect(1.40)
                                    .blur(radius: 60)
                                    .opacity(0.65)
                                    .clipped()
                            default:
                                Color.clear
                            }
                        }
                        .frame(width: size.width, height: size.height)
                        .clipped()
                    }
                }

                // 2. Mesh gradient liquide animé fluide
                FluidMeshBackground(colors: NW.colors[track.colorIndex], isPlaying: player.isPlaying, reduceMotion: reduceMotion)
                    .opacity(0.85)

                // 3. Vidéo Canvas si présente
                if let canvasURL = canvasURL {
                    LoopingCanvasVideo(url: canvasURL, isPlaying: player.isPlaying && !isLyricsExpanded)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .transition(.opacity.animation(.easeInOut(duration: 0.6)))

                    LinearGradient(
                        colors: [
                            .black.opacity(0.30),
                            .black.opacity(0.05),
                            .black.opacity(0.35),
                            .black.opacity(0.75),
                            NW.background.opacity(0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .ignoresSafeArea()
        }
    }

    private func header(_ track: Track) -> some View {
        HStack {
            Button {
                Haptic.light()
                onClose?()
                dismiss()
            } label: {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(track.album ?? "NeonWave")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            if let until = player.sleepUntil {
                Button {
                    Haptic.light()
                    showTimer = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(until, style: .timer)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 0.5))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else if player.sleepAtEndOfTrack {
                Button {
                    Haptic.light()
                    showTimer = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("FIN DU TITRE")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 0.5))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Haptic.light()
                    showTimer = true
                } label: {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }

    @ViewBuilder private func content(_ track: Track, size: CGSize) -> some View {
        let maxW = size.width - 56
        let dimension = min(maxW, min(330, max(220, size.height * 0.40)))
        Group {
            if canvasURL != nil && !showArtworkOverlay {
                VStack {
                    Spacer()
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                            showArtworkOverlay = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles.tv.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("VIDÉO D'AMBIANCE")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.4)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundStyle(.white.opacity(0.9))
                        .overlay(Capsule().stroke(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: dimension, height: dimension)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                        showArtworkOverlay = true
                    }
                }
            } else {
                CoverArt(track: track, imageURL: library.artworkURL(track), remoteURL: track.artworkURL, radius: 24)
                    .frame(width: dimension, height: dimension)
                    .shadow(color: NW.colors[track.colorIndex][0].opacity(player.isPlaying ? 0.45 : 0.15), radius: player.isPlaying ? 35 : 15, y: player.isPlaying ? 18 : 8)
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 0.5))
                    .scaleEffect(player.isPlaying || reduceMotion ? 1.0 : 0.85)
                    .animation(reduceMotion ? nil : .spring(response: 0.50, dampingFraction: 0.75), value: player.isPlaying)
                    .overlay(alignment: .topTrailing) {
                        if canvasURL != nil {
                            Button {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                                    showArtworkOverlay = false
                                }
                            } label: {
                                Image(systemName: "sparkles.tv.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .overlay(Circle().stroke(.white.opacity(0.15)))
                                    .padding(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height

                    // Swipe horizontal: morceau suivant / précédent
                    if abs(horizontal) > 55 && abs(vertical) < 65 {
                        if horizontal < 0 {
                            player.next()
                            library.haptic()
                        } else {
                            player.previous()
                            library.haptic()
                        }
                    }
                    // Glisser vers le bas: fermer le lecteur
                    else if vertical > 75 && abs(horizontal) < 100 {
                        onClose?()
                        dismiss()
                    }
                }
        )
    }

    private func trackInfo(_ track: Track) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Button {
                    Haptic.light()
                    selectedArtist = ArtistIdentifier(name: track.artist, spotifyId: track.spotifyId)
                } label: {
                    HStack(spacing: 4) {
                        Text(track.artist)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .buttonStyle(.plain)

                // Badge de qualité audio Pro
                HStack(spacing: 6) {
                    Text(library.localURL(track) != nil ? "HORS-LIGNE" : "LOSSLESS")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .foregroundStyle(.white.opacity(0.85))

                    Text("AAC 256 KBPS • 48 KHZ")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.40))
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let progress = downloads.progress[track.id] {
                Button { downloads.cancel(track.id) } label: {
                    ProgressView(value: progress).progressViewStyle(.circular).frame(width: 32)
                }
            } else if library.localURL(track) != nil {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.white.opacity(0.85))
            } else if track.canDownload {
                Button {
                    Haptic.medium()
                    downloads.download(track)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.70))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }

            Button {
                Haptic.medium()
                library.toggleLike(track)
            } label: {
                let isLiked = library.snapshot.likedIDs.contains(track.id)
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isLiked ? Color.pink : .white.opacity(0.70))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private var timeline: some View {
        VStack(spacing: 8) {
            GeometryReader { geom in
                let w = geom.size.width
                let progress = player.duration > 0 ? (dragging ? scrub : player.elapsed) / player.duration : 0.0
                let clamped = min(1.0, max(0.0, progress))
                let barHeight: CGFloat = dragging ? 8 : 4

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: w, height: barHeight)

                    Capsule()
                        .fill(Color.white)
                        .frame(width: w * CGFloat(clamped), height: barHeight)
                }
                .frame(height: 18)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !dragging {
                                dragging = true
                                scrub = player.elapsed
                                Haptic.medium()
                            }
                            let newPercent = gesture.location.x / w
                            let targetSec = min(max(0.0, Double(newPercent) * player.duration), player.duration)
                            if abs(targetSec - scrub) > 2.0 {
                                Haptic.selection()
                            }
                            scrub = targetSec
                        }
                        .onEnded { _ in
                            player.seek(scrub)
                            dragging = false
                            Haptic.light()
                        }
                )
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dragging)
            }
            .frame(height: 18)

            HStack {
                Text((dragging ? scrub : player.elapsed).clockTime)
                Spacer()
                Text("-\(max(0, player.duration - (dragging ? scrub : player.elapsed)).clockTime)")
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.50))
        }
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Button {
                player.shuffle.toggle()
                library.haptic()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(player.shuffle ? NW.accent : .white.opacity(0.45))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(PressStyle())
            .frame(maxWidth: .infinity)

            Button {
                if !player.isBuffering {
                    Haptic.medium()
                    player.toggle()
                }
            } label: {
                ZStack {
                    if player.isBuffering {
                        ProgressView().tint(.white).scaleEffect(1.3)
                            .frame(width: 72, height: 72)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: player.isPlaying ? 0 : 3)
                            .frame(width: 72, height: 72)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .frame(maxWidth: .infinity)

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(PressStyle())
            .frame(maxWidth: .infinity)

            Button {
                player.cycleRepeat()
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(player.repeatMode == .off ? .white.opacity(0.45) : NW.accent)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
    }

    private func footer(_ track: Track) -> some View {
        HStack {
            // 1. Lyrics Toggle
            Button {
                Haptic.light()
                withAnimation(reduceMotion ? nil : .spring(response: 0.40, dampingFraction: 0.82)) {
                    isLyricsExpanded.toggle()
                }
            } label: {
                Image(systemName: isLyricsExpanded ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isLyricsExpanded ? .white : .white.opacity(0.55))
                    .frame(width: 44, height: 44)
                    .background(isLyricsExpanded ? .white.opacity(0.18) : .clear, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            // 2. AirPlay Route Picker
            RoutePicker()
                .frame(width: 44, height: 44)

            Spacer()

            // 3. Queue / Playlist
            Button {
                Haptic.light()
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .frame(height: 48)
    }

    // MARK: - Spotify-Style Lyrics Preview Card
    private func lyricsPreviewCard(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Title + Action Buttons (matching Spotify screenshot)
            HStack {
                Text("Lyrics")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                HStack(spacing: 8) {
                    // Partager
                    ShareLink(item: "\(track.title) - \(track.artist)") {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)

                    // Bouton Agrandir (flèches en diagonale vers l'extérieur)
                    Button {
                        Haptic.medium()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.40, dampingFraction: 0.82)) {
                            isLyricsExpanded = true
                        }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)

                    // Bouton Chevron haut
                    Button {
                        Haptic.medium()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.40, dampingFraction: 0.82)) {
                            isLyricsExpanded = true
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Aperçu dynamique synchronisé des paroles
            if player.loadingLyrics {
                HStack(spacing: 10) {
                    ProgressView().tint(.white).scaleEffect(0.9)
                    Text("Chargement des paroles…")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.70))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 22)
            } else if !player.lyrics.isEmpty {
                let activeIdx = player.activeLyricIndex ?? 0
                let startIdx = max(0, activeIdx)
                let endIdx = min(player.lyrics.count, startIdx + 4)
                let previewSlice = Array(player.lyrics[startIdx..<endIdx])

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(previewSlice.enumerated()), id: \.element.id) { offset, line in
                        let isCurrent = (startIdx + offset == activeIdx)
                        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            Text(text)
                                .font(.system(size: isCurrent ? 23 : 20, weight: isCurrent ? .heavy : .semibold, design: .rounded))
                                .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.48))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .shadow(color: isCurrent ? Color.white.opacity(0.35) : Color.clear, radius: 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
                .padding(.bottom, 6)
                .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75), value: activeIdx)
            } else if let plain = player.plainLyrics, !plain.isEmpty {
                let lines = plain.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(lines.prefix(3).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "music.mic")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.45))
                    Text("Paroles indisponibles pour ce titre")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.vertical, 18)
            }
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                NW.colors[track.colorIndex][0].opacity(0.38),
                                Color.black.opacity(0.60)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.light()
            withAnimation(reduceMotion ? nil : .spring(response: 0.40, dampingFraction: 0.82)) {
                isLyricsExpanded = true
            }
        }
    }

    // MARK: - Full Screen Lyrics View (Karaoke Mode)
    private func fullScreenLyricsView(_ track: Track, size: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Header avec bouton Réduire
            HStack {
                Button {
                    Haptic.light()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.40, dampingFraction: 0.82)) {
                        isLyricsExpanded = false
                    }
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                Button {
                    Haptic.light()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.40, dampingFraction: 0.82)) {
                        isLyricsExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white.opacity(0.70))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, topInset)
            .padding(.bottom, 6)

            // Vue des paroles interactive défilante
            LyricsView(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Mini-lecteur flottant au bas des paroles
            HStack(spacing: 12) {
                CoverArt(track: track, imageURL: library.artworkURL(track), remoteURL: track.artworkURL, radius: 8)
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    GeometryReader { barGeo in
                        let prog = player.duration > 0 ? min(1.0, max(0.0, player.elapsed / player.duration)) : 0.0
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.20)).frame(height: 3)
                            Capsule().fill(Color.white).frame(width: barGeo.size.width * CGFloat(prog), height: 3)
                        }
                    }
                    .frame(height: 3)

                    HStack {
                        Text(player.elapsed.clockTime)
                        Spacer()
                        Text(player.duration.clockTime)
                    }
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.50))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button {
                        Haptic.light()
                        player.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptic.medium()
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptic.light()
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            .padding(.horizontal, 18)
            .padding(.bottom, max(12, bottomInset + 4))
        }
        .frame(width: size.width, height: size.height)
    }
}

struct LyricsView: View {
    @ObservedObject var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if player.loadingLyrics {
                            VStack(spacing: 16) {
                                ProgressView().tint(.white)
                                Text("On cale les paroles\nsur cette version…")
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.68))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 280, alignment: .center)
                        } else if !player.lyrics.isEmpty {
                            Color.clear.frame(height: 110)
                            ForEach(Array(player.lyrics.enumerated()), id: \.element.id) { index, line in
                                let state = lineState(for: index, line: line, currentPos: max(0, player.elapsed - player.lyricsOffset), activeLeadIndex: player.activeLyricIndex ?? -1)
                                let isDot = (line.text == "•••" || line.text == "..." || line.text == "♪")

                                if !isDot || state.isActive {
                                    Button {
                                        player.seek(to: line)
                                        library.haptic()
                                    } label: {
                                        SpicyLyricLine(
                                            line: line,
                                            distance: state.distance,
                                            isActive: state.isActive,
                                            isSung: state.isSung,
                                            progress: state.progress,
                                            duration: state.duration,
                                            isWaveEffect: player.isWaveEffect,
                                            isPlaying: player.isPlaying && !player.isBuffering
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .id(index)
                                }
                            }
                            Color.clear.frame(height: 180)
                        } else if let plain = player.plainLyrics, !plain.isEmpty {
                            Text(plain)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineSpacing(10)
                                .padding(.vertical, 40)
                                .padding(.horizontal, 16)
                        } else {
                            VStack(spacing: 14) {
                                Image(systemName: "music.mic").font(.system(size: 38, weight: .light))
                                Text("Paroles indisponibles").font(.system(size: 17, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(maxWidth: .infinity, minHeight: 280)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.12),
                            .init(color: .black, location: 0.88),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // ─── BARRE D'OUTILS SPICY LYRICS (Calage fin du timing Offset) ─────────
                if !player.lyrics.isEmpty {
                    HStack {
                        Spacer()

                        // Calage fin du timing (Offset)
                        HStack(spacing: 5) {
                            Button { player.adjustLyricsOffset(by: -0.25); library.haptic() } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(width: 22, height: 22)
                            }
                            Button { player.resetLyricsOffset(); library.haptic() } label: {
                                Text(String(format: "%+.2fs", player.lyricsOffset))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .frame(minWidth: 46)
                            }
                            Button { player.adjustLyricsOffset(by: 0.25); library.haptic() } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                        .shadow(color: .black.opacity(0.30), radius: 8, y: 3)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
            }
            .onAppear {
                if let value = player.activeLyricIndex {
                    proxy.scrollTo(value, anchor: .center)
                }
            }
            .onChange(of: player.activeLyricIndex) { _, value in
                if let value {
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.80)) {
                        proxy.scrollTo(value, anchor: .center)
                    }
                }
            }
        }
    }

    private func lineState(for index: Int, line: LyricLine, currentPos: Double, activeLeadIndex: Int) -> LyricLineState {
        let lineStartTime = line.time
        let lineEndTime: Double
        if let existing = line.endTime {
            lineEndTime = max(lineStartTime + 0.5, existing)
        } else if index + 1 < player.lyrics.count {
            let nextTime = player.lyrics[(index + 1)...].first(where: { !$0.isBackground })?.time ?? (lineStartTime + 4.5)
            lineEndTime = max(lineStartTime + 0.5, nextTime)
        } else {
            lineEndTime = lineStartTime + 4.5
        }
        let lineDuration = max(0.5, lineEndTime - lineStartTime)

        let isActive: Bool
        let isSung: Bool
        if line.isBackground {
            isActive = (currentPos >= lineStartTime && currentPos < lineEndTime)
            isSung = (currentPos >= lineEndTime)
        } else {
            if index == activeLeadIndex {
                isActive = (currentPos >= lineStartTime && currentPos < lineEndTime)
                isSung = (currentPos >= lineEndTime)
            } else if index < activeLeadIndex {
                isActive = false
                isSung = true
            } else {
                isActive = (currentPos >= lineStartTime && currentPos < lineEndTime)
                isSung = false
            }
        }

        let distance = isActive ? 0 : abs(index - activeLeadIndex)
        let elapsedInLine = max(0, currentPos - lineStartTime)
        let progress = max(0, min(1.0, elapsedInLine / lineDuration))

        return LyricLineState(
            isActive: isActive,
            isSung: isSung,
            progress: progress,
            duration: lineDuration,
            distance: distance
        )
    }
}

private struct LyricLineState {
    let isActive: Bool
    let isSung: Bool
    let progress: Double
    let duration: Double
    let distance: Int
}

// Lightweight static word for lines that are not currently active.
// Avoids spinning up 60fps TimelineView + Spring physics for inactive lines across the song.
private struct StaticLyricWord: View {
    let text: String
    let isBackground: Bool

    var body: some View {
        let fontSize: CGFloat = isBackground ? 19.5 : 26
        let fontWeight: Font.Weight = isBackground ? .semibold : .bold
        Text(text)
            .font(.system(size: fontSize, weight: fontWeight, design: .rounded))
            .tracking(-0.35)
            .foregroundStyle(Color.white)
    }
}

// ─── LIGNE DE PAROLE EXACT SPICY LYRICS 6.1.1 ──────────────────────────────
private struct SpicyLyricLine: View {
    let line: LyricLine
    let distance: Int
    let isActive: Bool
    let isSung: Bool
    let progress: Double
    let duration: Double
    let isWaveEffect: Bool
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isInstrumental: Bool {
        let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "•••" || trimmed == "..." || trimmed == "♪" || trimmed.isEmpty
    }

    private var textOpacity: Double {
        if isActive { return 1.0 }
        if isSung { return 0.497 } // Spicy Lyrics --Vocal-Sung-opacity: 0.497
        return 0.51               // Spicy Lyrics --Vocal-NotSung-opacity: 0.51
    }

    private var textScale: CGFloat {
        if isActive { return 1.05 } // Spicy Lyrics Active line scale: 1.05
        return 0.95                // Spicy Lyrics NotSung/Sung line scale: 0.95
    }

    private var distanceBlur: CGFloat {
        if isActive { return 0.0 }
        return CGFloat(min(Double(distance) * (isWaveEffect ? 1.25 : 2.2), 7.0)) // Clamped to 7.0 max to save GPU shader samples
    }

    var body: some View {
        blurredContent
            .padding(.horizontal, 12)
            .padding(.vertical, isInstrumental ? 4 : (line.isBackground ? 2 : 8))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive && !isInstrumental && !isWaveEffect ? Color.white.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isActive && !isInstrumental && !isWaveEffect ? Color.white.opacity(0.12) : Color.clear, lineWidth: 1)
                    )
            )
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.64), value: isActive)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var blurredContent: some View {
        let content = Group {
            if isInstrumental {
                SpicyInstrumentalDots(progress: progress, isActive: isActive)
            } else if isWaveEffect {
                syllableWaveView
            } else {
                lineSweepView
            }
        }
        .scaleEffect(isInstrumental ? 1.0 : (line.isBackground ? (isActive ? 1.01 : 0.98) : textScale), anchor: .leading)

        if !isInstrumental && distanceBlur > 0.1 {
            content.blur(radius: distanceBlur)
        } else {
            content
        }
    }

    // Spicy Lyrics word curves, with estimated timing when only line timestamps exist.
    // Keep the same layout before/during/after singing to avoid changing line wraps.
    private var syllableWaveView: some View {
        let words = line.animationWords(duration: duration)
        return FlowLayout(spacing: line.isBackground ? 5 : 7, lineSpacing: line.isBackground ? 4 : 7) {
            ForEach(words.indices, id: \.self) { index in
                let word = words[index]
                if isActive {
                    let wordDuration = max(0.001, (word.end ?? (line.time + duration)) - word.start)
                    let wordProgress = (line.time + progress * duration - word.start) / wordDuration
                    SpicyWaveWord(text: word.text, progress: wordProgress,
                                  duration: wordDuration,
                                  isActive: true, isPlaying: isPlaying,
                                  isBackground: word.isBackground || line.isBackground)
                } else {
                    StaticLyricWord(text: word.text,
                                    isBackground: word.isBackground || line.isBackground)
                }
            }
        }
        .opacity(textOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.text)
    }

    // ─── MODE 2 : BALAYAGE PROGRESSIF CONTINU SANS BOÎTE (Line Mode) ─────────
    private var lineSweepView: some View {
        SmoothLineSweep(
            text: line.text,
            progress: progress,
            duration: duration,
            isActive: isActive,
            isPlaying: isPlaying,
            isBackground: line.isBackground,
            textOpacity: textOpacity
        )
    }
}

private struct SmoothLineSweep: View {
    let text: String
    let progress: Double
    let duration: Double
    let isActive: Bool
    let isPlaying: Bool
    let isBackground: Bool
    let textOpacity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var anchorProgress: Double = 0
    @State private var anchorDate: Date = Date()
    @State private var displayedProgress: Double = 0

    var body: some View {
        let fontSize: CGFloat = isBackground ? 19.5 : 26
        let fontWeight: Font.Weight = isBackground ? .semibold : .bold

        if !isActive {
            Text(text)
                .font(.system(size: fontSize, weight: fontWeight, design: .rounded))
                .tracking(-0.35)
                .lineSpacing(6)
                .multilineTextAlignment(.leading)
                .foregroundStyle(Color.white.opacity(isBackground ? textOpacity * 0.75 : textOpacity))
        } else {
            TimelineView(.animation(paused: !isPlaying || reduceMotion)) { timeline in
                let targetPos = -0.20 + 1.20 * displayedProgress
                let glowIntensity = sin(displayedProgress * .pi)

                Text(text)
                    .font(.system(size: fontSize, weight: fontWeight, design: .rounded))
                    .tracking(-0.35)
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.clear)
                    .overlay(
                        GeometryReader { geo in
                            LinearGradient(
                                stops: [
                                    .init(color: .white, location: 0),
                                    .init(color: .white, location: max(0, targetPos)),
                                    .init(color: .white.opacity(0.38), location: min(1.0, targetPos + 0.20)),
                                    .init(color: .white.opacity(0.38), location: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .mask(
                                Text(text)
                                    .font(.system(size: fontSize, weight: fontWeight, design: .rounded))
                                    .tracking(-0.35)
                                    .lineSpacing(6)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: geo.size.width, alignment: .leading)
                            )
                        }
                    )
                    .shadow(color: Color.white.opacity((isBackground ? 0.35 : 0.55) * glowIntensity), radius: 10, x: 0, y: 0)
                    .shadow(color: Color.white.opacity((isBackground ? 0.18 : 0.28) * glowIntensity), radius: 24, x: 0, y: 0)
                    .onChange(of: timeline.date) { _, date in
                        advance(to: date)
                    }
            }
            .onAppear {
                anchorProgress = progress
                anchorDate = Date()
                displayedProgress = progress
            }
            .onChange(of: progress) { old, new in
                let jump = abs(new - old) * duration
                if jump > 0.4 || new < old {
                    anchorProgress = new
                    anchorDate = Date()
                    displayedProgress = new
                } else {
                    anchorProgress = new
                    anchorDate = Date()
                }
            }
            .onChange(of: isPlaying) { _, _ in
                anchorProgress = progress
                anchorDate = Date()
            }
        }
    }

    private func advance(to date: Date) {
        guard isPlaying, duration > 0 else { return }
        let extra = max(0, date.timeIntervalSince(anchorDate))
        let currentElapsed = anchorProgress * duration + extra
        let p = max(0, min(1.0, currentElapsed / duration))
        displayedProgress = p
    }
}

// Native port of Spicy Lyrics 6.1.1 LyricsAnimator.ts and Fraktality Spring.ts.
// Audio updates anchor the clock; only the active line renders at display cadence.
private struct SpicyWaveWord: View {
    let text: String
    let progress: Double
    let duration: Double
    let isActive: Bool
    let isPlaying: Bool
    var isBackground: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchorProgress = 0.0
    @State private var anchorDate = Date()
    @State private var previousFrame: Date?
    @State private var word = SpicyWaveMotion()
    @State private var letters: [SpicyWaveMotion] = []
    @State private var displayedProgress = 0.0

    private var characters: [String] { text.map(String.init) }
    private var usesLetters: Bool {
        // IsLetterCapable.ts: sustained words >= 1000ms. Keep cursive scripts joined.
        SpicyWaveTiming.usesLetterWave(text: text, duration: duration)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isActive || !isPlaying || reduceMotion)) { timeline in
            Group {
                if usesLetters {
                    HStack(spacing: 0) {
                        ForEach(characters.indices, id: \.self) { index in
                            let motion = letters.indices.contains(index) ? letters[index] : SpicyWaveMotion()
                            let letterProgress = max(0, min(1, displayedProgress * Double(characters.count) - Double(index)))
                            glyph(characters[index], motion: motion,
                                  gradient: -0.20 + 1.20 * sin(letterProgress * .pi / 2),
                                  sung: letterProgress >= 1, emphasis: true)
                        }
                    }
                } else {
                    glyph(text, motion: word, gradient: -0.20 + 1.20 * displayedProgress,
                          sung: displayedProgress >= 1, emphasis: false)
                }
            }
            .scaleEffect(reduceMotion || !usesLetters ? 1 : word.scale.position)
            .offset(y: reduceMotion || !usesLetters ? 0 : (isBackground ? 19.5 : 26) * word.lift.position)
            .onChange(of: timeline.date) { _, date in advance(to: date) }
        }
        .onAppear { synchronize(reset: true) }
        .onChange(of: progress) { old, new in
            let jump = (new - old) * duration
            synchronize(reset: jump < -0.08 || abs(jump) > 0.5)
        }
        .onChange(of: isActive) { _, _ in synchronize(reset: true) }
        .onChange(of: isPlaying) { _, _ in synchronize(reset: false) }
        .onChange(of: reduceMotion) { _, _ in synchronize(reset: true) }
        .transaction { $0.animation = nil }
    }

    private func glyph(_ value: String, motion: SpicyWaveMotion, gradient: Double,
                       sung: Bool, emphasis: Bool) -> some View {
        let glow = isActive && !reduceMotion ? max(0, motion.glow.position) : 0
        let fontSize: CGFloat = isBackground ? 19.5 : 26
        let fontWeight: Font.Weight = isBackground ? .semibold : .bold
        let baseAlpha: Double = isActive ? (isBackground ? 0.35 : 0.4) : (isBackground ? 0.75 : 1)
        return Text(value)
            .font(.system(size: fontSize, weight: fontWeight, design: .rounded))
            .tracking(-0.35)
            .foregroundStyle(Color.white.opacity(baseAlpha))
            .overlay {
                Text(value)
                    .font(.system(size: fontSize, weight: fontWeight, design: .rounded))
                    .tracking(-0.35)
                    .foregroundStyle(.white)
                    .mask {
                        if sung { Color.white }
                        else {
                            LinearGradient(colors: [.white, .clear],
                                           startPoint: UnitPoint(x: gradient, y: 0.5),
                                           endPoint: UnitPoint(x: gradient + 0.20, y: 0.5))
                        }
                    }
                    .opacity(isActive ? (isBackground ? 0.85 : 1) : 0)
            }
            .shadow(color: .white.opacity(min(1, glow * (isBackground ? 0.25 : (emphasis ? 1.85 : 0.35)))),
                    radius: 4 + (emphasis ? 12 : 2) * glow)
            .scaleEffect(reduceMotion ? 1 : motion.scale.position)
            .offset(y: reduceMotion ? 0 : fontSize * (emphasis ? 2 : 1) * motion.lift.position)
    }

    private func synchronize(reset: Bool) {
        anchorProgress = progress
        anchorDate = Date()
        if reset || letters.count != characters.count {
            word = SpicyWaveMotion()
            letters = characters.map { _ in SpicyWaveMotion() }
            previousFrame = nil
        }
        advance(to: anchorDate, reset: reset)
    }

    private func advance(to date: Date, reset: Bool = false) {
        let dt = min(0.05, max(0, previousFrame.map { date.timeIntervalSince($0) } ?? 0))
        previousFrame = date
        // Never extrapolate through a stall or buffering; re-anchor on every audio sample.
        let extra = isActive && isPlaying ? min(0.3, max(0, date.timeIntervalSince(anchorDate))) : 0
        let elapsed = anchorProgress * duration + extra
        // Emphasize.ts releases the last letter 250ms before the word ends.
        let animationDuration = max(0.05, duration - (usesLetters ? 0.25 : 0))
        let p = max(0, min(1, elapsed / animationDuration))
        displayedProgress = p
        let snap = reset || !isActive || reduceMotion
        word.update(scale: SpicyWaveCurve.scale.value(at: p),
                    lift: SpicyWaveCurve.lift.value(at: p),
                    glow: SpicyWaveCurve.glow.value(at: p), dt: dt, snap: snap)
        guard usesLetters, !letters.isEmpty else { return }
        let front = p * Double(letters.count)
        let active = Int(front)
        let local = front - Double(active)
        for index in letters.indices {
            var scale = 0.95
            var lift = 0.01
            var glow = 0.0
            if p >= 1 { scale = 1; lift = 0 }
            else if index <= active && elapsed >= 0 {
                let distance = Double(abs(index - active))
                let falloff = 1 / (1 + pow(distance, 2.8))
                let glowFalloff = 1 / (1 + distance * 0.9)
                scale += (SpicyWaveCurve.letterScale.value(at: local) - 0.95) * falloff
                lift += (SpicyWaveCurve.letterLift.value(at: local) - 0.01) * falloff
                glow = SpicyWaveCurve.glow.value(at: local) * glowFalloff
            }
            letters[index].update(scale: scale, lift: lift, glow: glow, dt: dt, snap: snap)
        }
    }
}

enum SpicyWaveTiming {
    static func usesLetterWave(text: String, duration: Double) -> Bool {
        // IsLetterCapable.ts normal mode: duration >= 1000 ms, irrespective
        // of character count or position in the phrase. Preserve joined scripts.
        duration >= 1 && !text.unicodeScalars.contains {
            (0x0590...0x08FF).contains(Int($0.value))
        }
    }
}

struct SpicyWaveMotion {
    var scale = SpicyWaveSpring(position: 0.95, frequency: 0.88, damping: 0.64)
    var lift = SpicyWaveSpring(position: 0.01, frequency: 1.45, damping: 0.40)
    var glow = SpicyWaveSpring(position: 0, frequency: 1.18, damping: 0.56)

    mutating func update(scale: Double, lift: Double, glow: Double, dt: Double, snap: Bool) {
        self.scale.step(goal: scale, dt: dt, snap: snap)
        self.lift.step(goal: lift, dt: dt, snap: snap)
        self.glow.step(goal: glow, dt: dt, snap: snap)
    }
}

// Fraktality spr, MIT License, original copyright Fraktality.
// Exact underdamped branch used by all three Spicy Lyrics vocal springs.
struct SpicyWaveSpring {
    var position: Double
    let frequency: Double
    let damping: Double
    var velocity = 0.0

    mutating func step(goal: Double, dt: Double, snap: Bool = false) {
        if snap { position = goal; velocity = 0; return }
        let f = frequency * 2 * Double.pi
        let c = sqrt(1 - damping * damping)
        let decay = exp(-damping * f * dt)
        let cosine = cos(dt * f * c)
        let sine = sin(dt * f * c)
        let z = sine / c
        let y = sine / (f * c)
        let offset = position - goal
        position = (offset * (cosine + z * damping) + velocity * y) * decay + goal
        velocity = (velocity * (cosine - z * damping) - offset * z * f) * decay
    }
}

struct SpicyWaveCurve {
    let times: [Double]
    let values: [Double]
    let secondDerivatives: [Double]

    static let scale = SpicyWaveCurve(times: [0, 0.7, 1], values: [0.95, 1.0505, 1])
    static let letterScale = SpicyWaveCurve(times: [0, 0.7, 1], values: [0.95, 1.175, 1])
    static let letterLift = SpicyWaveCurve(times: [0, 0.9, 1], values: [0.01, -1.0 / 56, 0])
    static let lift = SpicyWaveCurve(times: [0, 0.9, 1], values: [0.01, -1.0 / 60, 0])
    static let glow = SpicyWaveCurve(times: [0, 0.15, 0.6, 1], values: [0, 1, 1, 0])

    // Natural cubic spline, matching the cubic-spline package used by Spicy Lyrics.
    init(times: [Double], values: [Double]) {
        self.times = times
        self.values = values
        let count = times.count
        var diagonal = Array(repeating: 0.0, count: count)
        var right = Array(repeating: 0.0, count: count)
        var derivatives = Array(repeating: 0.0, count: count)
        diagonal[0] = 1
        diagonal[count - 1] = 1
        for i in 1..<(count - 1) {
            let leftWidth = times[i] - times[i - 1]
            let rightWidth = times[i + 1] - times[i]
            let factor = leftWidth / diagonal[i - 1]
            let previousUpper = i == 1 ? 0 : leftWidth
            diagonal[i] = 2 * (leftWidth + rightWidth) - factor * previousUpper
            let slopeChange = (values[i + 1] - values[i]) / rightWidth
                - (values[i] - values[i - 1]) / leftWidth
            right[i] = 6 * slopeChange - factor * right[i - 1]
        }
        for i in stride(from: count - 2, through: 1, by: -1) {
            let width = times[i + 1] - times[i]
            derivatives[i] = (right[i] - width * derivatives[i + 1]) / diagonal[i]
        }
        secondDerivatives = derivatives
    }

    func value(at progress: Double) -> Double {
        let p = max(times[0], min(times[times.count - 1], progress))
        let upper = times.indices.dropFirst().first(where: { times[$0] >= p }) ?? (times.count - 1)
        let lower = upper - 1
        let width = times[upper] - times[lower]
        let a = (times[upper] - p) / width
        let b = (p - times[lower]) / width
        return a * values[lower] + b * values[upper]
            + ((a * a * a - a) * secondDerivatives[lower]
               + (b * b * b - b) * secondDerivatives[upper]) * width * width / 6
    }
}

// ─── INTERMÈDE MUSICAL À 3 POINTS (Exact Spicy Lyrics DotLine) ──────────────
private struct SpicyInstrumentalDots: View {
    let progress: Double
    let isActive: Bool

    var body: some View {
        if !isActive {
            EmptyView()
        } else {
            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { dotIdx in
                    let dotStart = Double(dotIdx) / 3.0
                    let dotEnd = Double(dotIdx + 1) / 3.0
                    let isDotActive = progress >= dotStart && progress < dotEnd
                    let isDotSung = progress >= dotEnd
                    let dotProgress = isDotActive ? max(0, min(1.0, (progress - dotStart) / (dotEnd - dotStart))) : 0.0

                    // Fraktality Dot Spring physics from Spicy Lyrics 6.1.1:
                    // DotScaleSpline: 0.75 -> 1.05 -> 1.0
                    // DotYOffsetSpline: 0 -> -8.0pt -> 0
                    // DotGlowSpline: 0 -> 1.0 -> 1.0
                    // DotOpacitySpline: 0.35 -> 1.0 -> 1.0
                    let bounce = isDotActive ? sin(dotProgress * .pi) : 0.0
                    let scale: CGFloat = isDotActive ? CGFloat(0.75 + 0.30 * bounce) : (isDotSung ? 1.0 : 0.75)
                    let yOffset: CGFloat = isDotActive ? CGFloat(-8.0 * bounce) : 0.0
                    let opacity: Double = isDotSung ? 1.0 : (isDotActive ? (0.35 + 0.65 * bounce) : 0.35)
                    let glow: Double = isDotActive ? bounce : (isDotSung ? 0.20 : 0.0)

                    Circle()
                        .fill(Color.white.opacity(opacity))
                        .frame(width: 14, height: 14)
                        .scaleEffect(scale)
                        .offset(y: yOffset)
                        .shadow(color: Color.white.opacity(glow * 0.95), radius: CGFloat(4.0 + 8.0 * glow))
                }
            }
            // Pre-hidden vanishing collapse à 88% de la pause (Spicy Lyrics pre-hidden)
            .scaleEffect(progress > 0.88 ? max(0, (1.0 - progress) / 0.12) : 1.0)
            .opacity(progress > 0.88 ? max(0, (1.0 - progress) / 0.12) : 1.0)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(response: 0.35, dampingFraction: 0.65), value: progress)
        }
    }
}

// ─── FLOWLAYOUT SWIFTUI POUR LE RETOUR À LA LIGNE DES MOTS ─────────────────
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct QueueView: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.offset) { index, track in
                    Button { player.selectQueue(index) } label: {
                        HStack(spacing: 14) {
                            CoverArt(track: track, imageURL: library.artworkURL(track), remoteURL: track.artworkURL, radius: 10).frame(width: 46)
                            VStack(alignment: .leading, spacing: 5) { Text(track.title).font(.subheadline.bold()).foregroundStyle(.white); Text(track.artist).font(.caption).foregroundStyle(NW.muted) }
                            Spacer(); if player.current?.id == track.id { Image(systemName: "waveform").foregroundStyle(NW.blue) }
                        }
                    }.listRowBackground(NW.surface)
                }
            }.scrollContentBackground(.hidden).background(NW.background).navigationTitle("Votre file d’attente").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Terminé") { dismiss() } } }
        }.presentationDragIndicator(.visible)
    }
}

struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.tintColor = .white; view.activeTintColor = .systemBlue; return view }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}
struct VolumeControl: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView { let view = MPVolumeView(); view.showsRouteButton = false; view.tintColor = .white; return view }
    func updateUIView(_ uiView: MPVolumeView, context: Context) { }
}
