import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: LibraryTab = .home
    @State private var showImport = false
    @State private var showPlayer = false
    @State private var showSettings = false
    var body: some View {
        ZStack {
            PremiumBackdrop()
            YouTubePlayerWebView()
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            NavigationStack {
                Group {
                    switch tab {
                    case .home: HomeView(importFiles: { showImport = true })
                    case .search: SearchView()
                    case .library: LibraryView(importFiles: { showImport = true })
                    case .downloads: DownloadsView(importFiles: { showImport = true })
                    }
                }
                .background(Color.clear).toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 8) {
                            WaveMark(size: 25)
                            Text("neonwave").font(.system(size: 18, weight: .bold, design: .rounded)).tracking(-0.7)
                        }.foregroundStyle(.white)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: {
                            ZStack {
                                Circle().fill(LinearGradient(colors: [NW.blue, NW.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                                Text(String((session.account?.username ?? "N").prefix(1)).uppercased()).font(.caption.bold())
                            }.frame(width: 35, height: 35).overlay(Circle().stroke(.white.opacity(0.22)))
                        }.accessibilityLabel("Mon profil et réglages")
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 8) {
                        if player.current != nil { MiniPlayer { showPlayer = true }.padding(.horizontal, 12) }
                        HStack(spacing: 0) {
                            ForEach(LibraryTab.allCases, id: \.self) { item in
                                Button {
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { tab = item }; library.haptic()
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: item.symbol).font(.system(size: 20, weight: .medium))
                                        Text(item.rawValue).font(.system(size: 9, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                    }.foregroundStyle(tab == item ? .white : NW.muted).frame(maxWidth: .infinity).frame(minHeight: 54)
                                        .background(tab == item ? NW.blue.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 16))
                                }.accessibilityAddTraits(tab == item ? .isSelected : [])
                            }
                        }.padding(5).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.09)))
                            .padding(.horizontal, 12)
                    }.padding(.bottom, 7)
                }
            }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                switch result { case .success(let urls): Task { await library.importFiles(urls) }; case .failure(let error): library.message = error.localizedDescription }
            }
            .overlay(alignment: .top) {
                if library.importing { Label("Import de vos titres…", systemImage: "waveform").font(.caption.bold()).padding(14).background(.ultraThinMaterial, in: Capsule()).padding(.top, 55) }
            }
            .fullScreenCover(isPresented: $showPlayer) { PlayerView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var taste: MusicTasteStore
    let importFiles: () -> Void
    private var greeting: String { Calendar.current.component(.hour, from: Date()) < 18 ? "Bonjour" : "Bonsoir" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(greeting)\(session.account.map { ", \($0.username)" } ?? "")").font(.subheadline.weight(.medium)).foregroundStyle(NW.muted)
                    Text("Votre musique.\nVotre moment.").font(.system(size: 40, weight: .bold, design: .rounded)).tracking(-1.5)
                }.padding(.top, 12)
                ZStack(alignment: .leading) {
                    LinearGradient(colors: [NW.blue.opacity(0.92), NW.violet.opacity(0.78), Color(red: 0.04, green: 0.07, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    GeometryReader { geo in
                        Circle().stroke(.white.opacity(0.09), lineWidth: 38).frame(width: 230).offset(x: geo.size.width - 158, y: 9)
                        Circle().stroke(.white.opacity(0.20), lineWidth: 1).frame(width: 166).offset(x: geo.size.width - 128, y: 41)
                        WaveMark(size: 78).opacity(0.32).rotationEffect(.degrees(-10)).offset(x: geo.size.width - 116, y: 82)
                    }.clipped().accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 17) {
                        Label("MIX PERSONNALISÉ", systemImage: "sparkles").font(.system(size: 9, weight: .bold)).tracking(1.7)
                        Text("Entrez dans\nvotre bulle.").font(.system(size: 31, weight: .bold, design: .rounded)).tracking(-0.9)
                        Text(library.downloaded.isEmpty ? "Commencez votre collection NeonWave." : "Votre sélection évolue avec vos écoutes.").font(.caption).foregroundStyle(.white.opacity(0.72))
                        Button {
                            if let first = library.downloaded.randomElement() { player.shuffle = true; player.play(first, in: library.downloaded) }
                            else { importFiles() }
                        } label: {
                            Label(library.downloaded.isEmpty ? "Importer ma musique" : "Lancer mon mix", systemImage: library.downloaded.isEmpty ? "plus" : "play.fill")
                                .font(.caption.bold()).padding(.horizontal, 18).padding(.vertical, 13).background(.white, in: Capsule()).foregroundStyle(Color.black)
                        }.buttonStyle(PressStyle())
                    }.padding(24)
                }.clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.13)))
                    .shadow(color: NW.blue.opacity(0.18), radius: 26, y: 14)
                HStack(spacing: 12) {
                    NavigationLink { TrackCollectionView(title: "Titres aimés", kind: .liked) } label: { shortcut("Vos favoris", subtitle: "\(library.liked.count) titres", symbol: "heart.fill", color: .purple) }
                    NavigationLink { TrackCollectionView(title: "Sur cet iPhone", kind: .downloaded) } label: { shortcut("Hors connexion", subtitle: "\(library.downloaded.count) titres", symbol: "arrow.down", color: NW.blue) }
                }.buttonStyle(PressStyle())
                if !taste.preferences.artists.isEmpty {
                    SectionHeading(title: "Pensé pour vous", eyebrow: taste.preferences.genres.joined(separator: "  ·  "))
                    ScrollView(.horizontal) {
                        HStack(spacing: 15) {
                            ForEach(taste.preferences.artists) { artist in
                                VStack(spacing: 9) {
                                    ZStack {
                                        Circle().fill(LinearGradient(colors: NW.colors[artist.colorIndex], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        if let url = URL(string: artist.imageUrl), !artist.imageUrl.isEmpty {
                                            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Text(String(artist.name.prefix(1))).font(.title.bold()) }.clipShape(Circle())
                                        } else { Text(String(artist.name.prefix(1))).font(.title.bold()) }
                                    }.frame(width: 82, height: 82)
                                    Text(artist.name).font(.caption.bold()).lineLimit(1).frame(width: 92)
                                }
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                if !taste.recommendations.isEmpty {
                    HStack { SectionHeading(title: "Votre sélection", eyebrow: "Selon vos artistes"); Spacer(); Button { taste.loadRecommendations() } label: { Image(systemName: "arrow.clockwise") } }
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(taste.recommendations) { track in
                                Button { player.play(track, in: taste.recommendations) } label: {
                                    VStack(alignment: .leading, spacing: 9) {
                                        CoverArt(track: track, remoteURL: track.artworkURL, radius: 20).frame(width: 158)
                                        Text(track.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                                        Text(track.artist).font(.caption).foregroundStyle(NW.muted).lineLimit(1)
                                    }.frame(width: 158, alignment: .leading)
                                }.buttonStyle(PressStyle())
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                if !library.recent.isEmpty {
                    SectionHeading(title: "On reprend ?", eyebrow: "Récemment écoutés")
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(Array(library.recent.prefix(8))) { track in
                                Button { player.play(track, in: library.recent) } label: {
                                    VStack(alignment: .leading, spacing: 9) {
                                        CoverArt(track: track, imageURL: library.artworkURL(track)).frame(width: 146)
                                        Text(track.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                                        Text(track.artist).font(.caption).foregroundStyle(NW.muted).lineLimit(1)
                                    }.frame(width: 146, alignment: .leading)
                                }.buttonStyle(PressStyle())
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                if library.tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeading(title: "Tout commence\npar un premier titre.", eyebrow: "Votre collection")
                        Text("Importez vos MP3, M4A ou FLAC depuis Fichiers. Ils restent avec vous, même en mode avion.").font(.subheadline).foregroundStyle(NW.muted).lineSpacing(4)
                        Button(action: importFiles) { Label("Choisir mes fichiers", systemImage: "folder.badge.plus").font(.subheadline.bold()) }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(NW.surface, in: RoundedRectangle(cornerRadius: 24))
                } else {
                    SectionHeading(title: "Derniers ajouts", eyebrow: "Votre collection")
                    VStack(spacing: 2) { ForEach(Array(library.tracks.prefix(5))) { TrackRow(track: $0, context: library.tracks) } }
                }
                HStack(spacing: 12) {
                    Image(systemName: "headphones").font(.title2).foregroundStyle(NW.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("L’écoute vous appartient.").font(.caption.bold())
                        Text("Pas de publicité. Juste votre musique.").font(.caption2).foregroundStyle(NW.muted)
                    }
                }.padding(.vertical, 6)
            }.padding(.horizontal, 22).padding(.bottom, 120)
        }.scrollIndicators(.visible).scrollBounceBehavior(.always, axes: .vertical)
    }
    private func shortcut(_ title: String, subtitle: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption.bold()).foregroundStyle(.white); Text(subtitle).font(.caption2).foregroundStyle(NW.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).premiumPanel(radius: 21)
    }
}
