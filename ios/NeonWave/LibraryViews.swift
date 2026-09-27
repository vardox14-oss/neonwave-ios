import SwiftUI

struct TrackRow: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var downloads: DownloadManager
    let track: Track
    var context: [Track] = []
    var playlist: Playlist? = nil
    @State private var confirmDelete = false
    var body: some View {
        HStack(spacing: 12) {
            Button {
                if player.current?.id == track.id {
                    if player.isPlaying { player.pause() } else { player.resume() }
                } else {
                    player.play(track, in: context.isEmpty ? [track] : context)
                }
            } label: {
                HStack(spacing: 13) {
                    CoverArt(track: track, imageURL: library.artworkURL(track), remoteURL: track.artworkURL, radius: 12).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title).font(.subheadline.weight(.semibold)).foregroundStyle(player.current?.id == track.id ? NW.blue : .white).lineLimit(1)
                        HStack(spacing: 4) {
                            if library.localURL(track) != nil { Image(systemName: "arrow.down.circle.fill").foregroundStyle(NW.blue).font(.system(size: 10)) }
                            Text(track.artist).font(.caption).foregroundStyle(NW.muted).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Écouter \(track.title), \(track.artist)")
            if let progress = downloads.progress[track.id] {
                Button { downloads.cancel(track.id) } label: { ProgressView(value: progress).progressViewStyle(.circular).frame(width: 30) }.accessibilityLabel("Annuler le téléchargement")
            } else if library.localURL(track) == nil && track.canDownload {
                IconButton(symbol: "arrow.down.circle", label: "Télécharger \(track.title)") { downloads.download(track) }.foregroundStyle(NW.blue)
            }
            Menu {
                Button(library.snapshot.likedIDs.contains(track.id) ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: "heart") { library.toggleLike(track) }
                Button("Ajouter à la file", systemImage: "text.line.first.and.arrowtriangle.forward") { player.enqueue(track) }
                if session.account != nil && track.remoteID == nil {
                    Button(library.uploading.contains(track.id) ? "Sauvegarde en cours…" : "Sauvegarder sur mon compte", systemImage: "icloud.and.arrow.up") { Task { await library.upload(track) } }.disabled(library.uploading.contains(track.id))
                }
                Menu("Ajouter à une playlist", systemImage: "text.badge.plus") {
                    if library.playlists.isEmpty { Text("Créez une playlist dans Bibliothèque") }
                    ForEach(library.playlists) { item in Button(item.name) { library.add(track, to: item) } }
                }
                if let playlist { Button("Retirer de cette playlist", systemImage: "minus.circle") { library.remove(track, from: playlist) } }
                if track.isDownloadedSource && library.localURL(track) != nil {
                    Button("Retirer le téléchargement", systemImage: "arrow.down.circle", role: .destructive) {
                        if player.current?.id == track.id { player.stop() }; library.removeDownload(track)
                    }
                }
                Button("Supprimer de cet iPhone", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis").font(.body.bold()).foregroundStyle(NW.muted).frame(width: 36, height: 48) }.accessibilityLabel("Options de \(track.title)")
        }.padding(.horizontal, 9).padding(.vertical, 7)
            .background(player.current?.id == track.id ? NW.blue.opacity(0.11) : .white.opacity(0.025), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(player.current?.id == track.id ? NW.blue.opacity(0.22) : .white.opacity(0.035)))
            .confirmationDialog("Supprimer « \(track.title) » ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer le fichier et ses références", role: .destructive) {
                    downloads.cancel(track.id); if player.current?.id == track.id { player.stop() }; library.deleteTrack(track)
                }
            } message: { Text("Le fichier sera retiré de cet iPhone et de vos playlists locales. Conservez une copie de votre fichier original.") }
    }
}

enum CollectionKind { case all, liked, downloaded, playlist(String) }

struct TrackCollectionView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    let title: String
    let kind: CollectionKind
    @State private var showAdd = false
    @State private var showRename = false
    @State private var showDelete = false
    @State private var name = ""
    @State private var showPlayer = false
    private var playlist: Playlist? {
        if case .playlist(let id) = kind { return library.playlists.first { $0.id == id } }; return nil
    }
    private var tracks: [Track] {
        switch kind {
        case .all: return library.tracks
        case .liked: return library.liked
        case .downloaded: return library.downloaded
        case .playlist: return playlist.map(library.playlistTracks) ?? []
        }
    }
    private var symbol: String {
        switch kind { case .liked: return "heart.fill"; case .downloaded: return "arrow.down"; default: return "waveform" }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CoverArt(index: symbol == "heart.fill" ? 2 : 0, symbol: symbol).frame(width: 190).shadow(color: NW.blue.opacity(0.15), radius: 35, y: 12).frame(maxWidth: .infinity).padding(.vertical, 12)
                VStack(alignment: .leading, spacing: 8) {
                    Text(playlist?.name ?? title).font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-1)
                    Text("\(tracks.count) titres · \(Int(tracks.reduce(0) { $0 + $1.duration }) / 60) min").font(.subheadline).foregroundStyle(NW.muted)
                }
                HStack(spacing: 12) {
                    PrimaryButton(title: "Écouter", symbol: "play.fill") {
                        if let first = tracks.first(where: { library.localURL($0) != nil }) { player.play(first, in: tracks) }
                    }.disabled(!tracks.contains { library.localURL($0) != nil })
                    IconButton(symbol: "shuffle", label: "Écouter en aléatoire") {
                        let available = tracks.filter { library.localURL($0) != nil }
                        if let first = available.randomElement() { player.shuffle = true; player.play(first, in: available) }
                    }.background(NW.surface, in: RoundedRectangle(cornerRadius: 16))
                    if tracks.contains(where: { $0.canDownload && library.localURL($0) == nil }) {
                        IconButton(symbol: "arrow.down.circle", label: "Télécharger cette playlist") { tracks.forEach(downloads.download) }
                    }
                }
                if playlist != nil { Button { showAdd = true } label: { Label("Ajouter des titres", systemImage: "plus.circle").font(.subheadline.bold()) } }
                if tracks.isEmpty { EmptyLibrary(symbol: symbol, title: "Une place pour vos titres", description: "Ajoutez vos morceaux préférés pour commencer votre collection.") }
                LazyVStack(spacing: 2) { ForEach(tracks) { TrackRow(track: $0, context: tracks, playlist: playlist) } }
            }.padding(22)
        }.background(PremiumBackdrop()).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { if player.current != nil { MiniPlayer { showPlayer = true }.padding(12).background(.ultraThinMaterial) } }
            .fullScreenCover(isPresented: $showPlayer) { PlayerView(onClose: { showPlayer = false }) }
            .toolbar {
                if let playlist {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Renommer", systemImage: "pencil") { name = playlist.name; showRename = true }
                            Button("Supprimer la playlist", systemImage: "trash", role: .destructive) { showDelete = true }
                        } label: { Image(systemName: "ellipsis") }
                    }
                }
            }
            .sheet(isPresented: $showAdd) { if let playlist { PlaylistPickerView(playlist: playlist) } }
            .alert("Renommer la playlist", isPresented: $showRename) {
                TextField("Nom", text: $name)
                Button("Annuler", role: .cancel) { }
                Button("Enregistrer") { if let playlist { library.renamePlaylist(playlist, name: name) } }
            }
            .confirmationDialog("Supprimer cette playlist ?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Supprimer la playlist", role: .destructive) { if let playlist { library.deletePlaylist(playlist); dismiss() } }
            } message: { Text("Vos fichiers audio seront conservés.") }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var session: SessionStore
    let importFiles: () -> Void
    @State private var newPlaylist = false
    @State private var playlistName = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    SectionHeading(title: "Votre bibliothèque", eyebrow: "VOTRE COLLECTION")
                    IconButton(symbol: "plus", label: "Créer une playlist") { newPlaylist = true }.background(NW.surface, in: Circle())
                }.padding(.top, 16)
                ZStack(alignment: .leading) {
                    LinearGradient(colors: [NW.violet.opacity(0.72), NW.blue.opacity(0.42), NW.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                    HStack(spacing: 22) {
                        libraryMetric(value: library.tracks.count, label: "TITRES", symbol: "music.note")
                        Divider().overlay(.white.opacity(0.12)).frame(height: 50)
                        libraryMetric(value: library.playlists.count, label: "PLAYLISTS", symbol: "square.stack.fill")
                        Divider().overlay(.white.opacity(0.12)).frame(height: 50)
                        libraryMetric(value: library.liked.count, label: "FAVORIS", symbol: "heart.fill")
                    }.frame(maxWidth: .infinity).padding(20)
                }.clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.11)))
                HStack(spacing: 12) {
                    Button(action: importFiles) { Label("Importer", systemImage: "square.and.arrow.down").font(.subheadline.bold()).padding(14).frame(maxWidth: .infinity).background(NW.blue.opacity(0.18), in: Capsule()).overlay(Capsule().stroke(NW.blue.opacity(0.25))) }
                    if session.account != nil {
                        Button { Task { await library.sync() } } label: {
                            HStack { if library.syncing { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath") }; Text("Actualiser") }.font(.subheadline.bold()).padding(14).background(NW.surface, in: Capsule())
                        }.disabled(library.syncing)
                    }
                }
                VStack(spacing: 14) {
                    NavigationLink { TrackCollectionView(title: "Tous les titres", kind: .all) } label: { collectionRow("Tous les titres", subtitle: "\(library.tracks.count) titres", symbol: "music.note", index: 0) }
                    NavigationLink { TrackCollectionView(title: "Titres aimés", kind: .liked) } label: { collectionRow("Titres aimés", subtitle: "\(library.liked.count) coups de cœur", symbol: "heart.fill", index: 2) }
                }.buttonStyle(PressStyle())
                SectionHeading(title: "Vos playlists", eyebrow: "Toutes vos ambiances")
                if library.playlists.isEmpty {
                    EmptyLibrary(symbol: "square.stack", title: "À chaque moment, sa playlist.", description: "Un trajet, une soirée, un nouveau départ. Donnez un nom à votre prochaine sélection.", actionTitle: "Créer ma première playlist") { newPlaylist = true }
                } else {
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], alignment: .leading, spacing: 22) {
                        ForEach(Array(library.playlists.enumerated()), id: \.element.id) { index, playlist in
                            NavigationLink { TrackCollectionView(title: playlist.name, kind: .playlist(playlist.id)) } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    CoverArt(index: index % 6, symbol: playlist.symbol)
                                    Text(playlist.name).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2)
                                    Text("\(playlist.trackIDs.count) titres").font(.caption).foregroundStyle(NW.muted)
                                }
                            }.buttonStyle(PressStyle())
                        }
                    }
                }
            }.padding(22).padding(.bottom, 120)
        }.scrollIndicators(.visible).scrollBounceBehavior(.always, axes: .vertical).alert("Une nouvelle ambiance", isPresented: $newPlaylist) {
            TextField("Nom de votre playlist", text: $playlistName)
            Button("Annuler", role: .cancel) { playlistName = "" }
            Button("Créer") { library.createPlaylist(playlistName); playlistName = "" }
        } message: { Text("Vous pourrez y ajouter des titres de votre bibliothèque.") }
    }
    private func collectionRow(_ title: String, subtitle: String, symbol: String, index: Int) -> some View {
        HStack(spacing: 16) {
            CoverArt(index: index, symbol: symbol, radius: 16).frame(width: 64)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.subheadline.bold()).foregroundStyle(.white); Text(subtitle).font(.caption).foregroundStyle(NW.muted) }
            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(NW.muted)
        }.padding(10).premiumPanel(radius: 20)
    }
    private func libraryMetric(value: Int, label: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(NW.cyan)
            Text("\(value)").font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 7, weight: .bold)).tracking(1).foregroundStyle(NW.muted)
        }.frame(maxWidth: .infinity)
    }
}

struct PlaylistPickerView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var query = ""
    private var current: Playlist { library.playlists.first { $0.id == playlist.id } ?? playlist }
    var body: some View {
        NavigationStack {
            List {
                ForEach(library.tracks.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) }) { track in
                    Button {
                        if current.trackIDs.contains(track.id) { library.remove(track, from: current) } else { library.add(track, to: current) }
                    } label: {
                        HStack {
                            CoverArt(track: track, imageURL: library.artworkURL(track), radius: 8).frame(width: 40)
                            VStack(alignment: .leading) { Text(track.title).foregroundStyle(.white); Text(track.artist).font(.caption).foregroundStyle(NW.muted) }
                            Spacer(); Image(systemName: current.trackIDs.contains(track.id) ? "checkmark.circle.fill" : "plus.circle")
                        }
                    }.listRowBackground(NW.surface)
                }
            }.scrollContentBackground(.hidden).background(NW.background).searchable(text: $query, prompt: "Un titre, un artiste")
                .navigationTitle("Ajouter des titres").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Terminé") { dismiss() } } }
                .overlay { if library.tracks.isEmpty { EmptyLibrary(symbol: "music.note", title: "Votre bibliothèque est vide", description: "Importez d’abord des fichiers depuis l’onglet Bibliothèque.") } }
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var downloads: DownloadManager
    @State private var query = ""
    @State private var filter = 0
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var onlineTracks: [Track] = []
    @State private var onlineAlbums: [Album] = []
    @State private var selectedAlbum: Album?
    private let suggestions = ["Ninho", "Saïf", "Tiakola", "Damso", "Gazo", "SCH"]

    private var localResults: [Track] {
        library.tracks.filter { track in
            (query.isEmpty || track.title.localizedCaseInsensitiveContains(query) || track.artist.localizedCaseInsensitiveContains(query)) && (filter != 1 || library.snapshot.likedIDs.contains(track.id)) && (filter != 2 || library.localURL(track) != nil)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(title: "Retrouvez votre son.", eyebrow: "Recherche").padding(.top, 16)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(NW.muted)
                    TextField("Rechercher un titre, Saïf, un album…", text: $query)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onChange(of: query) { _, newValue in
                            triggerSearch(newValue)
                        }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            onlineTracks = []
                            onlineAlbums = []
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(NW.muted)
                        }
                        .accessibilityLabel("Effacer la recherche")
                    }
                }
                .padding(17).premiumPanel(radius: 18)

                Picker("Filtrer les titres", selection: $filter) {
                    Text("En ligne").tag(0)
                    Text("Favoris").tag(1)
                    Text("Sur l’iPhone").tag(2)
                }
                .pickerStyle(.segmented)

                if filter == 0 {
                    if searching {
                        HStack(spacing: 12) {
                            ProgressView().tint(NW.blue)
                            Text("Recherche dans le catalogue…").font(.subheadline).foregroundStyle(NW.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        discoveryLanding
                    } else if onlineTracks.isEmpty && onlineAlbums.isEmpty {
                        EmptyLibrary(
                            symbol: "magnifyingglass",
                            title: "Aucun résultat pour « \(query) »",
                            description: "Vérifiez l'orthographe ou essayez un autre mot-clé."
                        )
                    } else {
                        if !onlineAlbums.isEmpty {
                            SectionHeading(title: "Albums", eyebrow: "Découverte")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(onlineAlbums) { album in
                                        Button {
                                            selectedAlbum = album
                                        } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                CoverArt(index: 1, remoteURL: album.coverURL, radius: 14)
                                                    .frame(width: 140, height: 140)
                                                Text(album.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                                                Text(album.artist).font(.caption).foregroundStyle(NW.muted).lineLimit(1)
                                                if let count = album.trackCount {
                                                    Text("\(count) pistes").font(.caption2).foregroundStyle(NW.blue)
                                                }
                                            }
                                            .frame(width: 140, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                        }

                        if !onlineTracks.isEmpty {
                            SectionHeading(title: "Titres", eyebrow: "Catalogue")
                            LazyVStack(spacing: 2) {
                                ForEach(onlineTracks) { track in
                                    TrackRow(track: track, context: onlineTracks)
                                }
                            }
                        }
                    }
                } else {
                    if localResults.isEmpty {
                        EmptyLibrary(
                            symbol: filter == 1 ? "heart" : "arrow.down.circle",
                            title: filter == 1 ? "Aucun coup de cœur" : "Aucun titre sur cet iPhone",
                            description: filter == 1 ? "Ajoutez des titres en favoris pour les retrouver ici." : "Téléchargez des titres en ligne ou importez vos MP3 pour les écouter hors connexion."
                        )
                    } else {
                        Text("\(localResults.count) TITRE\(localResults.count > 1 ? "S" : "")").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(NW.muted)
                        LazyVStack(spacing: 2) {
                            ForEach(localResults) { TrackRow(track: $0, context: localResults) }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 140)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.visible)
        .scrollBounceBehavior(.always, axes: .vertical)
        .sheet(item: $selectedAlbum) { album in
            AlbumDetailView(album: album)
        }
    }

    private var discoveryLanding: some View {
        VStack(alignment: .leading, spacing: 22) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [NW.blue.opacity(0.82), NW.violet.opacity(0.60), NW.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().stroke(.white.opacity(0.10), lineWidth: 28).frame(width: 170).offset(x: 210, y: -35)
                VStack(alignment: .leading, spacing: 11) {
                    Label("CATALOGUE NEONWAVE", systemImage: "sparkles").font(.system(size: 9, weight: .bold)).tracking(1.6)
                    Text("Cherchez. Lancez.\nVibrez.").font(.system(size: 29, weight: .bold, design: .rounded)).tracking(-0.9)
                    Text("Titres, albums, artistes et paroles synchronisées.").font(.caption).foregroundStyle(.white.opacity(0.7))
                }.padding(22)
            }.frame(minHeight: 205).clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 27).stroke(.white.opacity(0.12)))

            SectionHeading(title: "À découvrir", eyebrow: "RECHERCHES RAPIDES")
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 10) {
                ForEach(suggestions, id: \.self) { name in
                    Button {
                        query = name; triggerSearch(name)
                    } label: {
                        HStack(spacing: 7) { Image(systemName: "waveform").foregroundStyle(NW.cyan); Text(name).lineLimit(1) }
                            .font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 13).premiumPanel(radius: 16)
                    }.buttonStyle(PressStyle())
                }
            }
        }
    }

    private func triggerSearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        searchTask?.cancel()
        guard !trimmed.isEmpty else {
            onlineTracks = []; onlineAlbums = []; searching = false; return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            async let tracks = MusicCatalogService.searchTracks(trimmed)
            async let albums = MusicCatalogService.searchAlbums(trimmed)
            let (t, a) = await (tracks, albums)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.onlineTracks = t
                self.onlineAlbums = a
                self.searching = false
            }
        }
    }
}

struct AlbumDetailView: View {
    let album: Album
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [Track] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    CoverArt(index: 2, remoteURL: album.coverURL, radius: 24)
                        .frame(width: 220, height: 220)
                        .shadow(color: NW.blue.opacity(0.3), radius: 25, y: 15)
                        .padding(.top, 16)

                    VStack(spacing: 6) {
                        Text(album.title).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
                        Text(album.artist).font(.subheadline).foregroundStyle(NW.muted)
                        if let count = album.trackCount {
                            Text("\(count) morceaux • NeonWave").font(.caption).foregroundStyle(NW.blue)
                        }
                    }

                    if !tracks.isEmpty {
                        PrimaryButton(title: "Écouter l’album", symbol: "play.fill") {
                            if let first = tracks.first {
                                player.play(first, in: tracks)
                            }
                        }
                        .padding(.horizontal, 24)
                    }

                    if loading {
                        ProgressView().tint(NW.blue).frame(height: 100)
                    } else if tracks.isEmpty {
                        Text("Aucune piste trouvée pour cet album.").font(.subheadline).foregroundStyle(NW.muted).padding()
                    } else {
                        VStack(spacing: 2) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                HStack(spacing: 14) {
                                    Text("\(index + 1)")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(NW.muted)
                                        .frame(width: 24, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(player.current?.id == track.id ? NW.blue : .white)
                                            .lineLimit(1)
                                        Text(track.duration.clockTime)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(NW.muted)
                                    }
                                    Spacer()
                                    Button {
                                        player.play(track, in: tracks)
                                    } label: {
                                        Image(systemName: player.current?.id == track.id && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(NW.blue)
                                    }
                                }
                                .padding(.horizontal, 22)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .scrollIndicators(.visible)
            .scrollBounceBehavior(.always, axes: .vertical)
            .background(NW.background)
            .navigationTitle("Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task {
                tracks = await MusicCatalogService.fetchAlbumTracks(
                    albumId: album.id,
                    albumTitle: album.title,
                    artistName: album.artist,
                    coverURL: album.coverURL
                )
                loading = false
            }
        }
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    let importFiles: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                SectionHeading(title: "Prêt à vous suivre.", eyebrow: "Hors connexion").padding(.top, 16)
                HStack(spacing: 20) {
                    Image(systemName: "airplane").font(.system(size: 36, weight: .light)).rotationEffect(.degrees(-15)).foregroundStyle(NW.blue)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(library.downloaded.count) titres avec vous").font(.headline)
                        Text("\(ByteCountFormatter.string(fromByteCount: library.storageBytes, countStyle: .file)) sur cet iPhone").font(.caption).foregroundStyle(NW.muted)
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).premiumPanel(radius: 24)
                Toggle(isOn: Binding(get: { library.snapshot.wifiOnly }, set: library.setWifiOnly)) {
                    VStack(alignment: .leading, spacing: 4) { Text("Télécharger en Wi-Fi uniquement").font(.subheadline.bold()); Text("Appliqué aux prochains téléchargements.").font(.caption).foregroundStyle(NW.muted) }
                }.tint(NW.blue)
                if !downloads.progress.isEmpty {
                    SectionHeading(title: "En cours")
                    ForEach(library.tracks.filter { downloads.progress[$0.id] != nil }) { track in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(track.title).font(.subheadline).lineLimit(1); Spacer(); Button("Annuler") { downloads.cancel(track.id) }.font(.caption) }
                            ProgressView(value: downloads.progress[track.id] ?? 0).tint(NW.blue)
                        }
                    }
                }
                let pending = library.tracks.filter { $0.canDownload && library.localURL($0) == nil }
                if !pending.isEmpty {
                    HStack { SectionHeading(title: "À emporter"); Button("Tout télécharger") { pending.forEach(downloads.download) }.font(.caption.bold()) }
                    ForEach(pending) { TrackRow(track: $0) }
                }
                if library.downloaded.isEmpty {
                    EmptyLibrary(symbol: "arrow.down.circle", title: "La musique, même sans réseau.", description: "Téléchargez un titre depuis Recherche ou importez vos propres fichiers audio.", actionTitle: "Importer des fichiers", action: importFiles)
                } else {
                    SectionHeading(title: "Disponibles hors connexion")
                    LazyVStack(spacing: 2) { ForEach(library.downloaded) { TrackRow(track: $0, context: library.downloaded) } }
                }
            }.padding(22).padding(.bottom, 120)
        }.scrollIndicators(.visible).scrollBounceBehavior(.always, axes: .vertical)
    }
}
