import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var artistRouter: ArtistRouter
    @EnvironmentObject private var network: NetworkMonitor
    @State private var tab: LibraryTab = .home
    @State private var showImport = false
    @State private var pendingImportDraft: LibraryStore.DraftAudioImport? = nil
    @State private var showPlayer = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            PremiumBackdrop(accent: tab == .downloads ? NW.cyan : NW.violet)

            NavigationStack {
                Group {
                    switch tab {
                    case .home: HomeView(importFiles: { showImport = true })
                    case .search: SearchView()
                    case .library: LibraryView(importFiles: { showImport = true })
                    case .downloads: DownloadsView(importFiles: { showImport = true })
                    }
                }
                .background(Color.clear)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 9) {
                            NeonWaveWordmark()
                            if network.isActuallyOffline {
                                HStack(spacing: 4) {
                                    Image(systemName: "wifi.slash")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("HORS LIGNE")
                                        .font(.system(size: 8, weight: .bold))
                                        .tracking(0.6)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(Color.orange.opacity(0.18), in: Capsule())
                                .overlay(Capsule().stroke(Color.orange.opacity(0.35), lineWidth: 1))
                                .foregroundStyle(Color.orange)
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ProfileButton(name: session.account?.username ?? "N") { showSettings = true }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 9) {
                        if player.current != nil {
                            MiniPlayer { showPlayer = true }
                                .padding(.horizontal, 12)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        PremiumTabBar(selection: $tab)
                            .padding(.horizontal, 12)
                    }.padding(.bottom, 7)
                }
            }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    guard !urls.isEmpty else { return }
                    if urls.count == 1 {
                        let url = urls[0]
                        Task {
                            let draft = await LibraryStore.prepareDraft(from: url)
                            await MainActor.run {
                                pendingImportDraft = draft
                            }
                        }
                    } else {
                        Task { await library.importFiles(urls) }
                    }
                case .failure(let error): library.message = error.localizedDescription
                }
            }
            .sheet(item: $pendingImportDraft) { draft in
                CustomImportSheet(draft: draft)
            }
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
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
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if library.importing {
                        Label("Import de vos titres…", systemImage: "waveform")
                            .font(.caption.bold()).padding(.horizontal, 16).padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, 54)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: downloads.toastMessage)
            }
            .fullScreenCover(isPresented: $showPlayer) { PlayerView(onClose: { showPlayer = false }) }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $artistRouter.selectedArtist) { artist in ArtistDetailView(artist: artist) }

            YouTubePlayerWebView()
                .frame(width: 200, height: 200)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(999)
        }
    }
}

private struct NeonWaveWordmark: View {
    var body: some View {
        HStack(spacing: 9) {
            WaveMark(size: 26)
            Text("neonwave").font(.system(size: 18, weight: .bold, design: .rounded)).tracking(-0.75)
        }.foregroundStyle(.white)
    }
}

private struct ProfileButton: View {
    let name: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(LinearGradient(colors: [NW.blue, NW.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(String(name.prefix(1)).uppercased()).font(.caption.bold()).foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            .overlay(Circle().stroke(.white.opacity(0.25)))
            .shadow(color: NW.blue.opacity(0.28), radius: 10)
        }.accessibilityLabel("Mon profil et réglages")
    }
}

private struct PremiumTabBar: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: LibraryTab

    var body: some View {
        HStack(spacing: 3) {
            ForEach(LibraryTab.allCases, id: \.self) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82)) { selection = item }
                    library.haptic()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.symbol).font(.system(size: 18, weight: selection == item ? .semibold : .regular))
                        Text(item.rawValue).font(.system(size: 9, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(selection == item ? .white : NW.muted)
                    .frame(maxWidth: .infinity).frame(height: 55)
                    .background(selection == item ? NW.blue.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay(alignment: .top) {
                        if selection == item { Capsule().fill(NW.cyan).frame(width: 19, height: 2).offset(y: 3) }
                    }
                }.buttonStyle(PressStyle()).accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.10)))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }
}

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var taste: MusicTasteStore
    @EnvironmentObject private var artistRouter: ArtistRouter
    @EnvironmentObject private var network: NetworkMonitor
    let importFiles: () -> Void

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Bonjour" }
        if hour < 18 { return "Bon après-midi" }
        return "Bonsoir"
    }

    var body: some View {
        if network.isActuallyOffline {
            OfflineModeView(importFiles: importFiles)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    welcomeHeader
                    HomeMixHero(importFiles: importFiles)
                    quickActions

                    if !taste.preferences.artists.isEmpty { artistShelf }
                    if !taste.recommendations.isEmpty { recommendationShelf }
                    if !library.recent.isEmpty { recentShelf }

                    collectionSection
                    listeningPromise
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 145)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always, axes: .vertical)
        }
    }

    private var welcomeHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text("\(greeting)\(session.account.map { ", \($0.username)" } ?? "")")
                    .font(.subheadline.weight(.medium)).foregroundStyle(NW.muted)
                Text("À vous le son.")
                    .font(.system(size: 40, weight: .bold, design: .rounded)).tracking(-1.6)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(library.tracks.count)").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("TITRES").font(.system(size: 8, weight: .bold)).tracking(1.5).foregroundStyle(NW.muted)
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 11) {
            NavigationLink { TrackCollectionView(title: "Titres aimés", kind: .liked) } label: {
                HomeShortcut(title: "Favoris", value: "\(library.liked.count)", symbol: "heart.fill", tint: .pink)
            }
            NavigationLink { TrackCollectionView(title: "Sur cet iPhone", kind: .downloaded) } label: {
                HomeShortcut(title: "Hors ligne", value: "\(library.downloaded.count)", symbol: "arrow.down.circle.fill", tint: NW.cyan)
            }
            Button(action: importFiles) {
                HomeShortcut(title: "Importer", value: "Fichiers", symbol: "folder.badge.plus", tint: NW.blue)
            }
        }.buttonStyle(PressStyle())
    }

    private var artistShelf: some View {
        VStack(alignment: .leading, spacing: 17) {
            SectionHeading(title: "Vos artistes", eyebrow: "VOTRE UNIVERS")
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(taste.preferences.artists) { artist in
                        Button {
                            artistRouter.open(artist: artist)
                        } label: {
                            ArtistAvatar(artist: artist)
                        }
                        .buttonStyle(PressStyle())
                    }
                }.padding(.horizontal, 1).padding(.vertical, 5)
            }.scrollIndicators(.hidden)
        }
    }

    private var recommendationShelf: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .bottom) {
                SectionHeading(title: "Fait pour vous", eyebrow: taste.preferences.genres.prefix(3).joined(separator: "  ·  "))
                Spacer()
                Button { taste.loadRecommendations() } label: {
                    Image(systemName: "arrow.clockwise").font(.subheadline.bold()).frame(width: 36, height: 36).background(.white.opacity(0.07), in: Circle())
                }.foregroundStyle(.white)
            }
            TrackShelf(tracks: taste.recommendations, cardWidth: 164)
        }
    }

    private var recentShelf: some View {
        VStack(alignment: .leading, spacing: 17) {
            SectionHeading(title: "Reprendre l’écoute", eyebrow: "RÉCEMMENT")
            TrackShelf(tracks: Array(library.recent.prefix(10)), cardWidth: 148)
        }
    }

    @ViewBuilder private var collectionSection: some View {
        if library.tracks.isEmpty {
            VStack(alignment: .leading, spacing: 17) {
                Label("VOTRE PREMIER TITRE", systemImage: "sparkles").font(.system(size: 9, weight: .bold)).tracking(1.6).foregroundStyle(NW.cyan)
                Text("Votre collection commence ici.").font(.system(size: 25, weight: .bold, design: .rounded)).tracking(-0.7)
                Text("Importez vos MP3, M4A ou FLAC. Ils restent accessibles sur cet iPhone, même sans connexion.")
                    .font(.subheadline).foregroundStyle(NW.muted).lineSpacing(4)
                Button(action: importFiles) {
                    Label("Choisir mes fichiers", systemImage: "folder.badge.plus").font(.subheadline.bold()).padding(.horizontal, 17).padding(.vertical, 13).background(.white, in: Capsule()).foregroundStyle(.black)
                }.buttonStyle(PressStyle())
            }.padding(22).premiumPanel(radius: 26)
        } else {
            VStack(alignment: .leading, spacing: 15) {
                SectionHeading(title: "Derniers ajouts", eyebrow: "VOTRE COLLECTION")
                LazyVStack(spacing: 7) {
                    ForEach(Array(library.tracks.prefix(6))) { TrackRow(track: $0, context: library.tracks) }
                }
            }
        }
    }

    private var listeningPromise: some View {
        HStack(spacing: 14) {
            Image(systemName: "headphones.circle.fill").font(.system(size: 34)).foregroundStyle(NW.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("Votre écoute reste la vôtre.").font(.subheadline.bold())
                Text("Sans publicité. Avec vos choix.").font(.caption).foregroundStyle(NW.muted)
            }
            Spacer(); WaveMark(size: 28).opacity(0.75)
        }.padding(17).premiumPanel(radius: 21)
    }
}

private struct HomeMixHero: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    let importFiles: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [NW.blue, NW.violet.opacity(0.88), Color(red: 0.035, green: 0.06, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { geo in
                Circle().stroke(.white.opacity(0.10), lineWidth: 40).frame(width: 240, height: 240).offset(x: geo.size.width - 150, y: 12)
                Circle().stroke(.white.opacity(0.20), lineWidth: 1).frame(width: 172, height: 172).offset(x: geo.size.width - 115, y: 46)
                WaveMark(size: 82).opacity(0.28).rotationEffect(.degrees(-11)).offset(x: geo.size.width - 105, y: 90)
            }.clipped().accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 7) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("MIX NEONWAVE").font(.system(size: 9, weight: .bold)).tracking(1.8)
                }
                Text("Entrez dans\nvotre bulle.").font(.system(size: 32, weight: .bold, design: .rounded)).tracking(-1)
                Text(library.downloaded.isEmpty ? "Ajoutez vos titres et créez votre univers." : "Une sélection construite autour de vos écoutes.")
                    .font(.caption).foregroundStyle(.white.opacity(0.72)).frame(maxWidth: 225, alignment: .leading)
                Button {
                    if let first = library.downloaded.randomElement() {
                        player.shuffle = true; player.play(first, in: library.downloaded)
                    } else { importFiles() }
                } label: {
                    Label(library.downloaded.isEmpty ? "Ajouter ma musique" : "Lancer le mix", systemImage: library.downloaded.isEmpty ? "plus" : "play.fill")
                        .font(.caption.bold()).padding(.horizontal, 18).padding(.vertical, 13).background(.white, in: Capsule()).foregroundStyle(.black)
                }.buttonStyle(PressStyle())
            }.padding(24)
        }
        .frame(minHeight: 278)
        .clipShape(RoundedRectangle(cornerRadius: 31, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 31).stroke(.white.opacity(0.15)))
        .shadow(color: NW.blue.opacity(0.24), radius: 30, y: 16)
    }
}

private struct HomeShortcut: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Text(value).font(.system(size: 9, weight: .medium)).foregroundStyle(NW.muted).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).premiumPanel(radius: 19)
    }
}

private struct ArtistAvatar: View {
    let artist: ArtistChoice
    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle().fill(LinearGradient(colors: NW.colors[artist.colorIndex], startPoint: .topLeading, endPoint: .bottomTrailing))
                if let url = URL(string: artist.imageUrl), !artist.imageUrl.isEmpty {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() }
                        else { Text(String(artist.name.prefix(1))).font(.title.bold()) }
                    }.clipShape(Circle())
                } else { Text(String(artist.name.prefix(1))).font(.title.bold()) }
                Circle().stroke(.white.opacity(0.16), lineWidth: 1)
            }.frame(width: 84, height: 84).shadow(color: NW.blue.opacity(0.18), radius: 14, y: 7)
            Text(artist.name).font(.caption.bold()).lineLimit(1).frame(width: 92)
        }
    }
}

private struct TrackShelf: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var artistRouter: ArtistRouter
    let tracks: [Track]
    let cardWidth: CGFloat

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 15) {
                ForEach(tracks) { track in
                    Button { player.play(track, in: tracks) } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            ZStack(alignment: .bottomTrailing) {
                                CoverArt(track: track, remoteURL: track.artworkURL, radius: 20).frame(width: cardWidth, height: cardWidth)
                                Image(systemName: player.current?.id == track.id && player.isPlaying ? "waveform.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 31)).symbolRenderingMode(.palette).foregroundStyle(.black, .white)
                                    .padding(9).shadow(color: .black.opacity(0.25), radius: 8)
                            }
                            Text(track.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                            Button {
                                artistRouter.open(name: track.artist)
                            } label: {
                                Text(track.artist).font(.caption).foregroundStyle(NW.muted).lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }.frame(width: cardWidth, alignment: .leading)
                    }.buttonStyle(PressStyle())
                }
            }.padding(.horizontal, 1).padding(.bottom, 5)
        }.scrollIndicators(.hidden)
    }
}

struct OfflineModeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var network: NetworkMonitor
    let importFiles: () -> Void

    @State private var query = ""
    @State private var filterFavoritesOnly = false

    private var offlineTracks: [Track] {
        library.downloaded
    }

    private var filteredTracks: [Track] {
        offlineTracks.filter { track in
            let matchesQuery = query.isEmpty ||
                track.title.localizedCaseInsensitiveContains(query) ||
                track.artist.localizedCaseInsensitiveContains(query)
            let matchesFav = !filterFavoritesOnly || library.snapshot.likedIDs.contains(track.id)
            return matchesQuery && matchesFav
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                offlineHeader

                if offlineTracks.isEmpty {
                    emptyOfflineState
                } else {
                    playbackControlsCard
                    searchBar

                    HStack {
                        Text("\(filteredTracks.count) MORCEAU\(filteredTracks.count > 1 ? "X" : "") DISPONIBLE\(filteredTracks.count > 1 ? "S" : "")")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(NW.muted)
                        Spacer()
                        if !library.liked.filter({ library.localURL($0) != nil }).isEmpty {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    filterFavoritesOnly.toggle()
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: filterFavoritesOnly ? "heart.fill" : "heart")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Favoris")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(filterFavoritesOnly ? Color.pink.opacity(0.2) : NW.surface, in: Capsule())
                                .overlay(Capsule().stroke(filterFavoritesOnly ? Color.pink.opacity(0.5) : .white.opacity(0.08)))
                                .foregroundStyle(filterFavoritesOnly ? Color.pink : NW.muted)
                            }
                        }
                    }
                    .padding(.top, 4)

                    LazyVStack(spacing: 6) {
                        ForEach(filteredTracks) { track in
                            TrackRow(track: track, context: offlineTracks)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 145)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.always, axes: .vertical)
    }

    private var offlineHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.orange.opacity(0.28), NW.blue.opacity(0.22), NW.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.orange)
                    Text("MODE HORS CONNEXION")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(.orange)
                    Spacer()
                    if network.isOfflineModeForced {
                        Button {
                            network.isOfflineModeForced = false
                        } label: {
                            Text("Quitter le forçage")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.12), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }

                Text("Votre musique,\nmême sans réseau.")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(.white)

                Text("Seuls les morceaux téléchargés ou importés sur cet iPhone sont lisibles sans connexion Internet.")
                    .font(.caption)
                    .foregroundStyle(NW.muted)
                    .lineLimit(2)
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.orange.opacity(0.25), lineWidth: 1))
    }

    private var playbackControlsCard: some View {
        HStack(spacing: 12) {
            Button {
                if let first = filteredTracks.first ?? offlineTracks.first {
                    player.play(first, in: offlineTracks)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Tout écouter")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(PressStyle())

            Button {
                if let randomTrack = (filteredTracks.isEmpty ? offlineTracks : filteredTracks).randomElement() {
                    player.shuffle = true
                    player.play(randomTrack, in: offlineTracks)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 14, weight: .bold))
                    Text("Aléatoire")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(NW.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.10)))
            }
            .buttonStyle(PressStyle())
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(NW.muted)
                .font(.system(size: 14))
            TextField("Filtrer vos morceaux hors ligne…", text: $query)
                .font(.subheadline)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(NW.muted)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(NW.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08)))
    }

    private var emptyOfflineState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 38))
                    .foregroundStyle(.orange)
            }
            .padding(.top, 24)

            VStack(spacing: 8) {
                Text("Aucun titre hors ligne")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Pour écouter de la musique sans connexion, téléchargez vos titres favoris lorsque vous avez du réseau, ou importez des fichiers audio directement.")
                    .font(.subheadline)
                    .foregroundStyle(NW.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button(action: importFiles) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Importer des fichiers audio")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(NW.blue, in: Capsule())
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(NW.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.08)))
    }
}
