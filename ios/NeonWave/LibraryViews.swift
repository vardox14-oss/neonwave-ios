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
            Button { player.play(track, in: context.isEmpty ? [track] : context) } label: {
                HStack(spacing: 13) {
                    CoverArt(track: track, imageURL: library.artworkURL(track), radius: 12).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title).font(.subheadline.weight(.semibold)).foregroundStyle(player.current?.id == track.id ? NW.blue : .white).lineLimit(1)
                        HStack(spacing: 4) {
                            if library.localURL(track) != nil { Image(systemName: "arrow.down.circle.fill").foregroundStyle(NW.blue).font(.system(size: 10)) }
                            Text(track.artist).font(.caption).foregroundStyle(NW.muted).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(PressStyle()).accessibilityLabel("Écouter \(track.title), \(track.artist)")
            if let progress = downloads.progress[track.id] {
                Button { downloads.cancel(track.id) } label: { ProgressView(value: progress).progressViewStyle(.circular).frame(width: 30) }.accessibilityLabel("Annuler le téléchargement")
            } else if library.localURL(track) == nil && track.remoteID != nil {
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
                if track.remoteID != nil && library.localURL(track) != nil {
                    Button("Retirer le téléchargement", systemImage: "arrow.down.circle", role: .destructive) {
                        if player.current?.id == track.id { player.stop() }; library.removeDownload(track)
                    }
                }
                Button("Supprimer de cet iPhone", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis").font(.body.bold()).foregroundStyle(NW.muted).frame(width: 36, height: 48) }.accessibilityLabel("Options de \(track.title)")
        }.padding(.vertical, 7)
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
                    if tracks.contains(where: { $0.remoteID != nil && library.localURL($0) == nil }) {
                        IconButton(symbol: "arrow.down.circle", label: "Télécharger cette playlist") { tracks.forEach(downloads.download) }
                    }
                }
                if playlist != nil { Button { showAdd = true } label: { Label("Ajouter des titres", systemImage: "plus.circle").font(.subheadline.bold()) } }
                if tracks.isEmpty { EmptyLibrary(symbol: symbol, title: "Une place pour vos titres", description: "Ajoutez vos morceaux préférés pour commencer votre collection.") }
                LazyVStack(spacing: 2) { ForEach(tracks) { TrackRow(track: $0, context: tracks, playlist: playlist) } }
            }.padding(22)
        }.background(NW.background).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { if player.current != nil { MiniPlayer { showPlayer = true }.padding(12).background(.ultraThinMaterial) } }
            .fullScreenCover(isPresented: $showPlayer) { PlayerView() }
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
                    SectionHeading(title: "Votre bibliothèque", eyebrow: "Les titres qui restent")
                    IconButton(symbol: "plus", label: "Créer une playlist") { newPlaylist = true }.background(NW.surface, in: Circle())
                }.padding(.top, 16)
                HStack(spacing: 12) {
                    Button(action: importFiles) { Label("Importer", systemImage: "square.and.arrow.down").font(.subheadline.bold()).padding(14).frame(maxWidth: .infinity).background(NW.blue.opacity(0.15), in: Capsule()) }
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
            }.padding(22).padding(.bottom, 15)
        }.scrollIndicators(.hidden).alert("Une nouvelle ambiance", isPresented: $newPlaylist) {
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
        }
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
    @State private var query = ""
    @State private var filter = 0
    private var results: [Track] {
        library.tracks.filter { track in
            (query.isEmpty || track.title.localizedCaseInsensitiveContains(query) || track.artist.localizedCaseInsensitiveContains(query)) && (filter != 1 || library.snapshot.likedIDs.contains(track.id)) && (filter != 2 || library.localURL(track) != nil)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeading(title: "Retrouvez votre son.", eyebrow: "Recherche").padding(.top, 16)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(NW.muted)
                    TextField("Un titre, un artiste…", text: $query).autocorrectionDisabled().submitLabel(.search)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Effacer la recherche") }
                }.padding(17).background(NW.surface, in: RoundedRectangle(cornerRadius: 17))
                Picker("Filtrer les titres", selection: $filter) { Text("Tous").tag(0); Text("Favoris").tag(1); Text("Sur l’iPhone").tag(2) }.pickerStyle(.segmented)
                if results.isEmpty {
                    EmptyLibrary(symbol: "magnifyingglass", title: query.isEmpty ? "Votre prochaine découverte" : "Aucun titre trouvé", description: query.isEmpty ? "Retrouvez ici tous vos fichiers personnels. Importez votre musique depuis Bibliothèque." : "Essayez un autre titre ou le nom de l’artiste.")
                } else {
                    Text("\(results.count) TITRES DANS VOTRE BIBLIOTHÈQUE").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(NW.muted)
                    LazyVStack(spacing: 2) { ForEach(results) { TrackRow(track: $0, context: results) } }
                }
            }.padding(22)
        }.scrollDismissesKeyboard(.interactively).scrollIndicators(.hidden)
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
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(NW.surface, in: RoundedRectangle(cornerRadius: 24))
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
                let pending = library.tracks.filter { $0.remoteID != nil && library.localURL($0) == nil }
                if !pending.isEmpty {
                    HStack { SectionHeading(title: "À emporter"); Button("Tout télécharger") { pending.forEach(downloads.download) }.font(.caption.bold()) }
                    ForEach(pending) { TrackRow(track: $0) }
                }
                if library.downloaded.isEmpty {
                    EmptyLibrary(symbol: "arrow.down.circle", title: "La musique, même sans réseau.", description: "Importez vos fichiers ou téléchargez vos titres personnels depuis votre compte.", actionTitle: "Importer des fichiers", action: importFiles)
                } else {
                    SectionHeading(title: "Disponibles hors connexion")
                    LazyVStack(spacing: 2) { ForEach(library.downloaded) { TrackRow(track: $0, context: library.downloaded) } }
                }
            }.padding(22)
        }.scrollIndicators(.hidden)
    }
}
