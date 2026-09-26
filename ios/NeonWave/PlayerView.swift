import SwiftUI
import AVKit
import MediaPlayer

enum PlayerMode: String, CaseIterable {
    case cover = "Pochette"
    case lyrics = "Paroles"
    case canvas = "Canvas"
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
                                Text(track.artist).font(.caption2).foregroundStyle(NW.muted).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Ouvrir le lecteur : \(track.title)")
                    IconButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "Pause" : "Lecture") { player.toggle() }
                    IconButton(symbol: "forward.end.fill", label: "Titre suivant") { player.next() }
                }.padding(.horizontal, 10).padding(.vertical, 8)
                GeometryReader { geo in
                    Rectangle().fill(NW.blue).frame(width: geo.size.width * min(1, max(0, player.duration > 0 ? player.elapsed / player.duration : 0)))
                }.frame(height: 2).background(.white.opacity(0.08))
            }.background(Color(red: 0.105, green: 0.125, blue: 0.20), in: RoundedRectangle(cornerRadius: 17)).clipShape(RoundedRectangle(cornerRadius: 17))
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
        ZStack {
            NW.background.ignoresSafeArea()
            if let track = player.current {
                LinearGradient(colors: [NW.colors[track.colorIndex][0].opacity(0.28), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        HStack {
                            IconButton(symbol: "chevron.down", label: "Réduire le lecteur") { dismiss() }
                            Spacer()
                            VStack(spacing: 5) {
                                Text("DANS VOTRE BULLE").font(.system(size: 9, weight: .bold)).tracking(2)
                                Text(track.album ?? "NeonWave Player").font(.caption2).foregroundStyle(NW.muted).lineLimit(1)
                            }
                            Spacer()
                            IconButton(symbol: "moon.zzz", label: "Minuterie de sommeil") { showTimer = true }.foregroundStyle(player.sleepUntil != nil ? NW.blue : .white)
                        }

                        // Mode Selector: Pochette | Paroles | Canvas
                        Picker("Affichage", selection: $mode) {
                            ForEach(PlayerMode.allCases, id: \.self) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 14)

                        // Center content depending on selected mode
                        Group {
                            switch mode {
                            case .cover:
                                CoverArt(track: track, imageURL: library.artworkURL(track), remoteURL: track.artworkURL, radius: 30)
                                    .shadow(color: NW.colors[track.colorIndex][0].opacity(0.25), radius: 35, y: 20)
                                    .scaleEffect(player.isPlaying || reduceMotion ? 1 : 0.94)
                                    .animation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.85), value: player.isPlaying)
                                    .padding(.horizontal, 9).padding(.vertical, 12)
                            case .lyrics:
                                LyricsView(player: player)
                                    .padding(.vertical, 6)
                            case .canvas:
                                CanvasVisualizerView(color: NW.colors[track.colorIndex][0], isPlaying: player.isPlaying)
                                    .padding(.vertical, 6)
                            }
                        }

                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(track.title).font(.system(.title, design: .rounded, weight: .bold)).tracking(-0.8).lineLimit(2)
                                Text(track.artist).font(.subheadline).foregroundStyle(NW.muted).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            IconButton(symbol: library.snapshot.likedIDs.contains(track.id) ? "heart.fill" : "heart", label: library.snapshot.likedIDs.contains(track.id) ? "Retirer des favoris" : "Ajouter aux favoris") { library.toggleLike(track) }
                                .foregroundStyle(library.snapshot.likedIDs.contains(track.id) ? NW.blue : .white)
                        }

                        VStack(spacing: 2) {
                            Slider(value: Binding(get: { dragging ? scrub : min(player.elapsed, max(1, player.duration)) }, set: { scrub = $0 }), in: 0...max(1, player.duration)) { editing in
                                if editing { scrub = player.elapsed; dragging = true }
                                else { player.seek(scrub); dragging = false }
                            }.tint(.white).accessibilityLabel("Position dans le morceau").accessibilityValue(player.elapsed.clockTime)
                            HStack { Text((dragging ? scrub : player.elapsed).clockTime); Spacer(); Text(player.duration.clockTime) }.font(.caption2.monospacedDigit()).foregroundStyle(NW.muted)
                        }

                        HStack(spacing: 0) {
                            IconButton(symbol: "shuffle", label: player.shuffle ? "Désactiver la lecture aléatoire" : "Activer la lecture aléatoire") { player.shuffle.toggle(); library.haptic() }.foregroundStyle(player.shuffle ? NW.blue : NW.muted)
                            Spacer(minLength: 4)
                            IconButton(symbol: "backward.end.fill", label: "Titre précédent") { player.previous() }
                            Spacer(minLength: 4)
                            Button { player.toggle(); library.haptic() } label: {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 27, weight: .semibold)).offset(x: player.isPlaying ? 0 : 2).foregroundStyle(.black)
                                    .frame(width: 76, height: 76).background(.white, in: Circle())
                            }.buttonStyle(PressStyle()).accessibilityLabel(player.isPlaying ? "Pause" : "Lecture")
                            Spacer(minLength: 4)
                            IconButton(symbol: "forward.end.fill", label: "Titre suivant") { player.next() }
                            Spacer(minLength: 4)
                            IconButton(symbol: player.repeatMode == .one ? "repeat.1" : "repeat", label: "Répétition : \(player.repeatMode == .off ? "désactivée" : player.repeatMode == .one ? "un titre" : "tous les titres")") { player.cycleRepeat() }.foregroundStyle(player.repeatMode == .off ? NW.muted : NW.blue)
                        }

                        HStack {
                            RoutePicker().frame(width: 44, height: 44).accessibilityLabel("Choisir une sortie AirPlay")
                            Spacer()
                            Label(library.localURL(track) != nil ? "SUR CET IPHONE" : "STREAMING EN LIGNE", systemImage: library.localURL(track) != nil ? "checkmark.circle.fill" : "waveform.badge.magnifyingglass")
                                .font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(NW.muted)
                            Spacer()
                            IconButton(symbol: "list.bullet", label: "File d’attente") { showQueue = true }
                        }
                        VolumeControl().frame(height: 32).accessibilityLabel("Volume")
                        if let until = player.sleepUntil { Text("La musique s’arrête à \(until.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(NW.muted) }
                    }.padding(.horizontal, 24).padding(.bottom, 22).frame(maxWidth: 530).frame(maxWidth: .infinity)
                }.scrollIndicators(.hidden)
            }
        }
        .sheet(isPresented: $showQueue) { QueueView() }
        .confirmationDialog("Minuterie de sommeil", isPresented: $showTimer, titleVisibility: .visible) {
            ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in Button("Dans \(minutes) minutes") { player.setSleep(minutes: minutes) } }
            if player.sleepUntil != nil { Button("Désactiver la minuterie", role: .destructive) { player.setSleep(minutes: nil) } }
        }
        .onChange(of: player.current?.id) { _, value in if value == nil { dismiss() } }
    }
}

struct LyricsView: View {
    @ObservedObject var player: AudioPlayer

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if player.loadingLyrics {
                        HStack(spacing: 12) {
                            ProgressView().tint(NW.blue)
                            Text("Recherche des paroles…").font(.subheadline).foregroundStyle(NW.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else if !player.lyrics.isEmpty {
                        ForEach(Array(player.lyrics.enumerated()), id: \.element.id) { index, line in
                            let isActive = index == (player.activeLyricIndex ?? -1)
                            Button {
                                player.seek(line.time)
                            } label: {
                                Text(line.text)
                                    .font(.system(size: isActive ? 22 : 17, weight: isActive ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(isActive ? .white : NW.muted.opacity(0.6))
                                    .shadow(color: isActive ? NW.blue.opacity(0.85) : .clear, radius: 10)
                                    .multilineTextAlignment(.leading)
                                    .scaleEffect(isActive ? 1.03 : 1.0, anchor: .leading)
                                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isActive)
                            }
                            .buttonStyle(.plain)
                            .id(index)
                            .padding(.vertical, 3)
                        }
                    } else if let plain = player.plainLyrics, !plain.isEmpty {
                        Text(plain)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineSpacing(8)
                            .padding(.vertical, 10)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "music.mic").font(.system(size: 34)).foregroundStyle(NW.muted)
                            Text("Paroles non disponibles pour ce titre.").font(.subheadline).foregroundStyle(NW.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 260)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 310)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24))
            .onChange(of: player.activeLyricIndex) { _, newIndex in
                if let newIndex {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }
}

struct CanvasVisualizerView: View {
    let color: Color
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { timeline in
            let date = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                RadialGradient(
                    colors: [color.opacity(0.4), NW.blue.opacity(0.15), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 220
                )

                ForEach(0..<4) { i in
                    let offset = Double(i) * 0.7
                    let scale = 1.0 + sin(date * 1.6 + offset) * 0.08
                    let opacity = 0.28 + cos(date * 2.0 + offset) * 0.14

                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [color.opacity(opacity), NW.blue.opacity(opacity * 0.7), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: CGFloat(16 + i * 12)
                        )
                        .scaleEffect(scale)
                        .rotationEffect(.degrees(date * Double(12 + i * 6)))
                        .frame(width: CGFloat(140 + i * 44), height: CGFloat(140 + i * 44))
                }

                HStack(spacing: 7) {
                    ForEach(0..<9) { bar in
                        let heightFactor = max(0.2, sin(date * 4.0 + Double(bar) * 0.75) * 0.5 + 0.5)
                        Capsule()
                            .fill(LinearGradient(colors: [.white, color, NW.blue], startPoint: .top, endPoint: .bottom))
                            .frame(width: 6, height: CGFloat(28 + heightFactor * 105))
                            .shadow(color: color.opacity(0.6), radius: 8)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 310)
            .clipShape(RoundedRectangle(cornerRadius: 24))
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
                            VStack(alignment: .leading, spacing: 5) {
                                Text(track.title).font(.subheadline.bold()).foregroundStyle(.white)
                                Text(track.artist).font(.caption).foregroundStyle(NW.muted)
                            }
                            Spacer()
                            if player.current?.id == track.id { Image(systemName: "waveform").foregroundStyle(NW.blue) }
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
