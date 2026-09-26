import SwiftUI
import AVKit
import MediaPlayer

enum PlayerMode: String, CaseIterable {
    case cover = "Pochette"
    case lyrics = "Paroles"
    case canvas = "Canvas"
    var symbol: String { switch self { case .cover: return "square.stack.fill"; case .lyrics: return "quote.bubble.fill"; case .canvas: return "sparkles.tv.fill" } }
}

struct MiniPlayer: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    let open: () -> Void
    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button(action: open) {
                        HStack(spacing: 12) {
                            CoverArt(track: track, imageURL: library.artworkURL(track), remoteURL: track.artworkURL, radius: 10).frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title).font(.system(size: 13, weight: .bold)).lineLimit(1).foregroundStyle(.white)
                                Text(player.isBuffering ? "Connexion au son…" : track.artist).font(.system(size: 11, weight: .medium)).foregroundStyle(player.isBuffering ? NW.blue : NW.muted).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if player.isBuffering { ProgressView().tint(.white).frame(width: 46, height: 46) }
                    else { IconButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "Pause" : "Lecture") { player.toggle() } }
                    IconButton(symbol: "forward.end.fill", label: "Titre suivant") { player.next() }
                }.padding(.horizontal, 10).padding(.vertical, 8)
                GeometryReader { geo in Rectangle().fill(NW.blue.gradient).frame(width: geo.size.width * min(1, max(0, player.duration > 0 ? player.elapsed / player.duration : 0))) }
                    .frame(height: 2).background(.white.opacity(0.08))
            }.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct PlayerView: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: PlayerMode = .cover
    @State private var showQueue = false
    @State private var showTimer = false
    @State private var dragging = false
    @State private var scrub = 0.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                immersiveBackground(size: geo.size)
                if let track = player.current {
                    VStack(spacing: 0) {
                        header(track)
                            .padding(.top, max(10, geo.safeAreaInsets.top))
                        modeSelector
                            .padding(.top, 4)

                        Spacer(minLength: 10)

                        content(track, size: geo.size)

                        Spacer(minLength: 14)

                        trackInfo(track)

                        Spacer(minLength: 10)

                        timeline

                        Spacer(minLength: 12)

                        controls

                        Spacer(minLength: 20)

                        footer(track)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(14, geo.safeAreaInsets.bottom + 6))
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showQueue) { QueueView() }
        .confirmationDialog("Minuterie de sommeil", isPresented: $showTimer, titleVisibility: .visible) {
            ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in Button("Dans \(minutes) minutes") { player.setSleep(minutes: minutes) } }
            if player.sleepUntil != nil { Button("Désactiver la minuterie", role: .destructive) { player.setSleep(minutes: nil) } }
        }
        .onChange(of: player.current?.id) { _, value in if value == nil { dismiss() } }
    }

    @ViewBuilder private func immersiveBackground(size: CGSize) -> some View {
        if let track = player.current {
            ZStack {
                NW.background
                AsyncImage(url: track.artworkURL.flatMap(URL.init(string:))) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } placeholder: {
                    LinearGradient(colors: NW.colors[track.colorIndex], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .frame(width: size.width, height: size.height)
                .scaleEffect(1.4)
                .blur(radius: 72)
                .opacity(0.38)
                .clipped()

                LinearGradient(colors: [.black.opacity(0.12), NW.background.opacity(0.72), NW.background], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [NW.colors[track.colorIndex][0].opacity(0.19), .clear], center: .topTrailing, startRadius: 20, endRadius: 390)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .ignoresSafeArea()
        }
    }

    private func header(_ track: Track) -> some View {
        HStack {
            glassIcon("chevron.down", label: "Réduire") { dismiss() }
            Spacer()
            VStack(spacing: 3) {
                Text("À L’ÉCOUTE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(2.0)
                    .foregroundStyle(.white.opacity(0.65))
                Text(track.album ?? "NeonWave")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            Spacer()
            glassIcon("moon.zzz.fill", label: "Minuterie") { showTimer = true }
                .foregroundStyle(player.sleepUntil == nil ? .white : NW.blue)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
    }

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(PlayerMode.allCases, id: \.self) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
                        mode = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 11, weight: .semibold))
                        Text(item.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 4)
                    .background(mode == item ? .white.opacity(0.17) : .clear, in: Capsule())
                    .foregroundStyle(mode == item ? .white : .white.opacity(0.48))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.22), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.07)))
    }

    @ViewBuilder private func content(_ track: Track, size: CGSize) -> some View {
        let maxW = size.width - 64
        let dimension = min(maxW, min(290, max(180, size.height * 0.34)))
        switch mode {
        case .cover:
            CoverArt(track: track, imageURL: library.artworkURL(track), remoteURL: track.artworkURL, radius: 28)
                .frame(width: dimension, height: dimension)
                .shadow(color: .black.opacity(0.45), radius: 28, y: 18)
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.12)))
                .scaleEffect(player.isPlaying || reduceMotion ? 1 : 0.96)
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.86), value: player.isPlaying)
        case .lyrics:
            LyricsView(player: player)
                .frame(maxWidth: .infinity, maxHeight: min(390, size.height * 0.44))
        case .canvas:
            SpotifyCanvasView(track: track, isPlaying: player.isPlaying)
                .frame(width: dimension, height: dimension)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .shadow(color: .black.opacity(0.45), radius: 28, y: 18)
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.12)))
        }
    }

    private func trackInfo(_ track: Track) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(.system(size: 22, weight: .bold, design: .rounded)).tracking(-0.5).lineLimit(1)
                Text(track.artist).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            glassIcon(library.snapshot.likedIDs.contains(track.id) ? "heart.fill" : "heart", label: "Favori") { library.toggleLike(track) }
                .foregroundStyle(library.snapshot.likedIDs.contains(track.id) ? Color.pink : .white)
        }.frame(maxWidth: .infinity)
    }

    private var timeline: some View {
        VStack(spacing: 3) {
            Slider(value: Binding(get: { dragging ? scrub : min(player.elapsed, max(1, player.duration)) }, set: { scrub = $0 }), in: 0...max(1, player.duration)) { editing in
                if editing { scrub = player.elapsed; dragging = true } else { player.seek(scrub); dragging = false }
            }.tint(.white)
            HStack { Text((dragging ? scrub : player.elapsed).clockTime); Spacer(); Text(player.duration.clockTime) }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
        }.frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "shuffle", label: "Lecture aléatoire") {
                player.shuffle.toggle()
                library.haptic()
            }
            .foregroundStyle(player.shuffle ? NW.blue : .white.opacity(0.5))
            .frame(maxWidth: .infinity)

            IconButton(symbol: "backward.end.fill", label: "Précédent") {
                player.previous()
            }
            .frame(maxWidth: .infinity)

            Button {
                if !player.isBuffering {
                    player.toggle()
                    library.haptic()
                }
            } label: {
                ZStack {
                    Circle().fill(.white).frame(width: 68, height: 68).shadow(color: .white.opacity(0.2), radius: 18)
                    if player.isBuffering {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.black)
                            .offset(x: player.isPlaying ? 0 : 2)
                    }
                }
            }
            .buttonStyle(PressStyle())
            .frame(maxWidth: .infinity)

            IconButton(symbol: "forward.end.fill", label: "Suivant") {
                player.next()
            }
            .frame(maxWidth: .infinity)

            IconButton(symbol: player.repeatMode == .one ? "repeat.1" : "repeat", label: "Répétition") {
                player.cycleRepeat()
            }
            .foregroundStyle(player.repeatMode == .off ? .white.opacity(0.5) : NW.blue)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
    }

    private func footer(_ track: Track) -> some View {
        HStack {
            RoutePicker().frame(width: 42, height: 38)
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(player.isPlaying ? Color.green : player.isBuffering ? Color.orange : .white.opacity(0.35)).frame(width: 6, height: 6)
                Text(library.localURL(track) != nil ? "SUR CET IPHONE" : player.isBuffering ? "CONNEXION…" : "AUDIO EN LIGNE")
            }.font(.system(size: 8, weight: .bold)).tracking(1.4).foregroundStyle(.white.opacity(0.48))
            Spacer(); IconButton(symbol: "list.bullet", label: "File d’attente") { showQueue = true }
        }.frame(maxWidth: .infinity).frame(height: 42)
    }

    private func glassIcon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).frame(width: 42, height: 42).background(.white.opacity(0.07), in: Circle()) }
            .buttonStyle(PressStyle()).accessibilityLabel(label)
    }
}

struct LyricsView: View {
    @ObservedObject var player: AudioPlayer
    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if player.loadingLyrics {
                            VStack(alignment: .leading, spacing: 18) { ProgressView().tint(.white); Text("On cale les paroles\nsur cette version…").font(.title2.bold()).foregroundStyle(.white.opacity(0.68)) }
                                .frame(maxWidth: .infinity, minHeight: 290, alignment: .center)
                        } else if !player.lyrics.isEmpty {
                            Color.clear.frame(height: 110)
                            ForEach(Array(player.lyrics.enumerated()), id: \.element.id) { index, line in
                                let activeIndex = player.activeLyricIndex ?? -1
                                let active = index == activeIndex
                                let nextTime = index + 1 < player.lyrics.count ? player.lyrics[index + 1].time : line.time + 4
                                Button { player.seek(to: line) } label: {
                                    KaraokeLyricLine(
                                        line: line,
                                        nextTime: nextTime,
                                        elapsed: player.elapsed,
                                        offset: player.lyricsOffset,
                                        distance: abs(index - activeIndex),
                                        isActive: active
                                    )
                                }.buttonStyle(.plain).id(index)
                            }
                            Color.clear.frame(height: 160)
                        } else if let plain = player.plainLyrics, !plain.isEmpty {
                            Text(plain).font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.72)).lineSpacing(10).padding(.vertical, 60)
                        } else {
                            VStack(spacing: 14) { Image(systemName: "music.mic").font(.system(size: 38)); Text("Paroles indisponibles").font(.headline) }.foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity, minHeight: 290)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.scrollIndicators(.hidden)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12), .init(color: .black, location: 0.84), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                if !player.lyrics.isEmpty {
                    HStack(spacing: 4) {
                        Button { player.adjustLyricsOffset(by: -0.25) } label: { Image(systemName: "minus") }
                        Button { player.resetLyricsOffset() } label: { Text(String(format: "%+.2fs", player.lyricsOffset)).font(.caption.monospacedDigit()).frame(minWidth: 54) }
                        Button { player.adjustLyricsOffset(by: 0.25) } label: { Image(systemName: "plus") }
                    }.font(.caption.bold()).padding(8).background(.ultraThinMaterial, in: Capsule())
                }
            }.onChange(of: player.activeLyricIndex) { _, value in
                if let value {
                    withAnimation(.spring(response: 0.58, dampingFraction: 0.88)) {
                        proxy.scrollTo(value, anchor: .center)
                    }
                }
            }
        }
    }
}

private struct KaraokeLyricLine: View {
    let line: LyricLine
    let nextTime: Double
    let elapsed: Double
    let offset: Double
    let distance: Int
    let isActive: Bool

    private var progress: Double {
        guard isActive else { return 0 }
        let start = line.time + offset
        let end = max(start + 0.45, nextTime + offset)
        return min(1, max(0, (elapsed + 0.12 - start) / (end - start)))
    }

    private var baseOpacity: Double {
        if isActive { return 0.28 }
        switch distance { case 1: return 0.34; case 2: return 0.22; default: return 0.12 }
    }

    var body: some View {
        let lyric = Text(line.text)
            .font(.system(size: 27, weight: .bold, design: .rounded))
            .tracking(-0.65)
            .multilineTextAlignment(.leading)

        lyric
            .foregroundStyle(.white.opacity(baseOpacity))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    lyric
                        .foregroundStyle(.white)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: max(0, geo.size.width * progress))
                        }
                }
                .opacity(isActive ? 1 : 0)
            }
            .shadow(color: isActive ? NW.blue.opacity(0.42) : .clear, radius: 18)
            .scaleEffect(isActive ? 1.025 : 0.97, anchor: .leading)
            .blur(radius: distance > 3 ? 0.7 : 0)
            .animation(.linear(duration: 0.24), value: progress)
            .animation(.spring(response: 0.5, dampingFraction: 0.84), value: isActive)
            .contentShape(Rectangle())
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
