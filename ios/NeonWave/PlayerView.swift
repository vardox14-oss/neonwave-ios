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
                            CoverArt(track: track, imageURL: library.artworkURL(track), remoteURL: track.artworkURL, radius: 10).frame(width: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).font(.caption.bold()).lineLimit(1)
                                Text(player.isBuffering ? "Connexion au son…" : track.artist).font(.caption2).foregroundStyle(player.isBuffering ? NW.blue : NW.muted).lineLimit(1)
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
                immersiveBackground
                if let track = player.current {
                    VStack(spacing: 0) {
                        header(track)
                        modeSelector.padding(.top, 8)
                        content(track, size: geo.size).frame(maxHeight: .infinity).padding(.top, 14)
                        trackInfo(track).padding(.top, 15)
                        timeline.padding(.top, 13)
                        controls.padding(.top, 8)
                        footer(track).padding(.top, 8)
                    }.padding(.horizontal, 22).padding(.bottom, max(10, geo.safeAreaInsets.bottom))
                }
            }
        }
        .sheet(isPresented: $showQueue) { QueueView() }
        .confirmationDialog("Minuterie de sommeil", isPresented: $showTimer, titleVisibility: .visible) {
            ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in Button("Dans \(minutes) minutes") { player.setSleep(minutes: minutes) } }
            if player.sleepUntil != nil { Button("Désactiver la minuterie", role: .destructive) { player.setSleep(minutes: nil) } }
        }
        .onChange(of: player.current?.id) { _, value in if value == nil { dismiss() } }
    }

    @ViewBuilder private var immersiveBackground: some View {
        if let track = player.current {
            ZStack {
                NW.background
                AsyncImage(url: track.artworkURL.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() } placeholder: { LinearGradient(colors: NW.colors[track.colorIndex], startPoint: .topLeading, endPoint: .bottomTrailing) }
                    .scaleEffect(1.4).blur(radius: 72).opacity(0.38)
                LinearGradient(colors: [.black.opacity(0.12), NW.background.opacity(0.72), NW.background], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [NW.colors[track.colorIndex][0].opacity(0.19), .clear], center: .topTrailing, startRadius: 20, endRadius: 390)
            }.ignoresSafeArea()
        }
    }

    private func header(_ track: Track) -> some View {
        HStack {
            glassIcon("chevron.down", label: "Réduire") { dismiss() }
            Spacer()
            VStack(spacing: 4) {
                Text("À L’ÉCOUTE").font(.system(size: 9, weight: .bold)).tracking(2.2).foregroundStyle(.white.opacity(0.65))
                Text(track.album ?? "NeonWave").font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }.frame(maxWidth: 190)
            Spacer()
            glassIcon("moon.zzz.fill", label: "Minuterie") { showTimer = true }.foregroundStyle(player.sleepUntil == nil ? .white : NW.blue)
        }.frame(height: 48)
    }

    private var modeSelector: some View {
        HStack(spacing: 5) {
            ForEach(PlayerMode.allCases, id: \.self) { item in
                Button { withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) { mode = item } } label: {
                    HStack(spacing: 6) { Image(systemName: item.symbol).font(.system(size: 11)); Text(item.rawValue).font(.caption.bold()) }
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(mode == item ? .white.opacity(0.17) : .clear, in: Capsule())
                        .foregroundStyle(mode == item ? .white : .white.opacity(0.48))
                }.buttonStyle(.plain)
            }
        }.padding(5).background(.black.opacity(0.22), in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.07)))
    }

    @ViewBuilder private func content(_ track: Track, size: CGSize) -> some View {
        let dimension = min(size.width - 52, min(390, size.height * 0.44))
        switch mode {
        case .cover:
            CoverArt(track: track, imageURL: library.artworkURL(track), remoteURL: track.artworkURL, radius: 34)
                .frame(width: dimension, height: dimension).shadow(color: .black.opacity(0.45), radius: 34, y: 22)
                .overlay(RoundedRectangle(cornerRadius: 34).stroke(.white.opacity(0.12)))
                .scaleEffect(player.isPlaying || reduceMotion ? 1 : 0.96)
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.86), value: player.isPlaying)
        case .lyrics:
            LyricsView(player: player).frame(maxWidth: .infinity, maxHeight: min(410, size.height * 0.48))
        case .canvas:
            SpotifyCanvasView(track: track, isPlaying: player.isPlaying).frame(maxHeight: min(410, size.height * 0.48))
        }
    }

    private func trackInfo(_ track: Track) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(track.title).font(.system(size: 25, weight: .bold, design: .rounded)).tracking(-0.8).lineLimit(1)
                Text(track.artist).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            glassIcon(library.snapshot.likedIDs.contains(track.id) ? "heart.fill" : "heart", label: "Favori") { library.toggleLike(track) }
                .foregroundStyle(library.snapshot.likedIDs.contains(track.id) ? Color.pink : .white)
        }
    }

    private var timeline: some View {
        VStack(spacing: 3) {
            Slider(value: Binding(get: { dragging ? scrub : min(player.elapsed, max(1, player.duration)) }, set: { scrub = $0 }), in: 0...max(1, player.duration)) { editing in
                if editing { scrub = player.elapsed; dragging = true } else { player.seek(scrub); dragging = false }
            }.tint(.white)
            HStack { Text((dragging ? scrub : player.elapsed).clockTime); Spacer(); Text(player.duration.clockTime) }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "shuffle", label: "Lecture aléatoire") { player.shuffle.toggle(); library.haptic() }.foregroundStyle(player.shuffle ? NW.blue : .white.opacity(0.5))
            Spacer(); IconButton(symbol: "backward.end.fill", label: "Précédent") { player.previous() }; Spacer()
            Button { if !player.isBuffering { player.toggle(); library.haptic() } } label: {
                ZStack {
                    Circle().fill(.white).frame(width: 72, height: 72).shadow(color: .white.opacity(0.2), radius: 18)
                    if player.isBuffering { ProgressView().tint(.black) }
                    else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(.black).offset(x: player.isPlaying ? 0 : 2) }
                }
            }.buttonStyle(PressStyle())
            Spacer(); IconButton(symbol: "forward.end.fill", label: "Suivant") { player.next() }; Spacer()
            IconButton(symbol: player.repeatMode == .one ? "repeat.1" : "repeat", label: "Répétition") { player.cycleRepeat() }.foregroundStyle(player.repeatMode == .off ? .white.opacity(0.5) : NW.blue)
        }
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
        }.frame(height: 42)
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
                            Color.clear.frame(height: 85)
                            ForEach(Array(player.lyrics.enumerated()), id: \.element.id) { index, line in
                                let active = index == (player.activeLyricIndex ?? -1)
                                Button { player.seek(to: line) } label: {
                                    Text(line.text).font(.system(size: active ? 30 : 24, weight: active ? .bold : .semibold, design: .rounded)).tracking(active ? -0.8 : -0.45)
                                        .foregroundStyle(active ? .white : .white.opacity(0.24)).multilineTextAlignment(.leading)
                                        .scaleEffect(active ? 1 : 0.97, anchor: .leading).animation(.spring(response: 0.38, dampingFraction: 0.83), value: active)
                                }.buttonStyle(.plain).id(index)
                            }
                            Color.clear.frame(height: 130)
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
            }.onChange(of: player.activeLyricIndex) { _, value in if let value { withAnimation(.easeInOut(duration: 0.32)) { proxy.scrollTo(value, anchor: .center) } } }
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
