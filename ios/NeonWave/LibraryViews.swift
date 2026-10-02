import SwiftUI
import PhotosUI

struct TrackRow: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var artistRouter: ArtistRouter
    let track: Track
    var context: [Track] = []
    var playlist: Playlist? = nil
    @State private var confirmDelete = false
    @State private var showEditTrack = false

    private var isCurrent: Bool {
        player.current?.id == track.id
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    if isCurrent {
                        if player.isPlaying { player.pause() } else { player.resume() }
                    } else {
                        player.play(track, in: context.isEmpty ? [track] : context)
                    }
                } label: {
                    HStack(spacing: 12) {
                        CoverArt(track: track, imageURL: library.artworkURL(track), remoteURL: track.artworkURL, radius: 8)
                            .frame(width: 48, height: 48)
                            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(isCurrent ? NW.accent : .white)
                                .lineLimit(1)

                            HStack(spacing: 4) {
                                if library.localURL(track) != nil {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundStyle(Color(white: 0.65))
                                        .font(.system(size: 10))
                                }
                                Text(track.artist)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(Color(white: 0.60))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Écouter \(track.title), \(track.artist)")

                if let progress = downloads.progress[track.id] {
                    Button { downloads.cancel(track.id) } label: {
                        ProgressView(value: progress).progressViewStyle(.circular).frame(width: 28)
                    }
                    .accessibilityLabel("Annuler le téléchargement")
                } else if library.localURL(track) == nil && track.canDownload {
                    Button {
                        Haptic.medium()
                        downloads.download(track)
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(white: 0.55))
                            .frame(width: 36, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Télécharger \(track.title)")
                }

                Menu {
                    Button("Voir l’artiste « \(track.artist) »", systemImage: "person.crop.circle") {
                        artistRouter.open(name: track.artist, spotifyId: track.spotifyId)
                    }
                    Button(library.snapshot.likedIDs.contains(track.id) ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: "heart") {
                        library.toggleLike(track)
                    }
                    Button("Ajouter à la file", systemImage: "text.line.first.and.arrowtriangle.forward") {
                        player.enqueue(track)
                    }
                    if session.account != nil && track.remoteID == nil {
                        Button(library.uploading.contains(track.id) ? "Sauvegarde en cours…" : "Sauvegarder sur mon compte", systemImage: "icloud.and.arrow.up") {
                            Task { await library.upload(track) }
                        }
                        .disabled(library.uploading.contains(track.id))
                    }
                    Menu("Ajouter à une playlist", systemImage: "text.badge.plus") {
                        if library.playlists.isEmpty { Text("Créez une playlist dans Bibliothèque") }
                        ForEach(library.playlists) { item in Button(item.name) { library.add(track, to: item) } }
                    }
                    if let playlist {
                        Button("Retirer de cette playlist", systemImage: "minus.circle") { library.remove(track, from: playlist) }
                    }
                    if track.isDownloadedSource && library.localURL(track) != nil {
                        Button("Retirer le téléchargement", systemImage: "arrow.down.circle", role: .destructive) {
                            if player.current?.id == track.id { player.stop() }
                            library.removeDownload(track)
                        }
                    }
                    Button("Modifier le titre et la pochette", systemImage: "pencil") {
                        showEditTrack = true
                    }
                    Button("Supprimer de cet iPhone", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(white: 0.50))
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Options de \(track.title)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isCurrent ? Color.white.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Divider()
                .overlay(Color.white.opacity(0.06))
                .padding(.leading, 68)
        }
        .confirmationDialog("Supprimer « \(track.title) » ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer le fichier et ses références", role: .destructive) {
                downloads.cancel(track.id)
                if player.current?.id == track.id { player.stop() }
                library.deleteTrack(track)
            }
        } message: { Text("Le fichier sera retiré de cet iPhone et de vos playlists locales. Conservez une copie de votre fichier original.") }
        .sheet(isPresented: $showEditTrack) {
            TrackEditSheet(track: track)
        }
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
                CoverArt(index: symbol == "heart.fill" ? 2 : 0, symbol: symbol, radius: 18)
                    .frame(width: 180)
                    .shadow(color: .black.opacity(0.35), radius: 25, y: 10)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist?.name ?? title)
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(.white)
                    Text("\(tracks.count) titres · \(Int(tracks.reduce(0) { $0 + $1.duration }) / 60) min")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white: 0.55))
                }

                HStack(spacing: 12) {
                    Button {
                        if let first = tracks.first(where: { player.isPlayable($0) }) ?? tracks.first {
                            player.shuffle = false
                            player.play(first, in: tracks)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                            Text("Lecture").font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.black)
                    }
                    .buttonStyle(PressStyle())
                    .disabled(tracks.isEmpty)

                    Button {
                        let available = tracks.filter { player.isPlayable($0) }
                        if let first = (available.isEmpty ? tracks : available).randomElement() {
                            player.shuffle = true
                            player.play(first, in: available.isEmpty ? tracks : available)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "shuffle").font(.system(size: 14, weight: .bold))
                            Text("Aléatoire").font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(PressStyle())
                    .disabled(tracks.isEmpty)
                }

                let undownloaded = tracks.filter { $0.canDownload && library.localURL($0) == nil }
                if !tracks.isEmpty {
                    Button {
                        if undownloaded.isEmpty {
                            downloads.showSuccessToast("Tous les titres de cette playlist sont déjà téléchargés.")
                        } else {
                            undownloaded.forEach(downloads.download)
                            downloads.showSuccessToast("Téléchargement lancé (\(undownloaded.count) titres)")
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: undownloaded.isEmpty ? "checkmark.circle.fill" : "arrow.down.circle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(undownloaded.isEmpty ? Color.green : Color.white.opacity(0.85))
                            Text(undownloaded.isEmpty ? "Téléchargé" : "Télécharger la sélection (\(undownloaded.count))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            if !undownloaded.isEmpty && undownloaded.contains(where: { downloads.progress[$0.id] != nil }) {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
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
                            Button("Télécharger la playlist", systemImage: "arrow.down.circle") {
                                let pending = tracks.filter { $0.canDownload && library.localURL($0) == nil }
                                if pending.isEmpty {
                                    downloads.showSuccessToast("Playlist déjà téléchargée.")
                                } else {
                                    pending.forEach(downloads.download)
                                    downloads.showSuccessToast("Téléchargement de la playlist lancé (\(pending.count) titre\(pending.count > 1 ? "s" : ""))")
                                }
                            }
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
    @EnvironmentObject private var downloads: DownloadManager
    let importFiles: () -> Void
    @State private var newPlaylist = false
    @State private var playlistName = ""
    @State private var showSpotifyImport = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("COLLECTION")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(Color(white: 0.55))
                        Text("Bibliothèque")
                            .font(.system(size: 32, weight: .bold))
                            .tracking(-0.8)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            showSpotifyImport = true
                        } label: {
                            Image(systemName: "arrow.down.to.line.compact")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(white: 0.85))
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .accessibilityLabel("Importer une playlist Spotify")

                        Button {
                            newPlaylist = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(white: 0.85))
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .accessibilityLabel("Créer une playlist")
                    }
                }
                .padding(.top, 12)

                // Apple Music Library categories
                VStack(spacing: 0) {
                    NavigationLink {
                        TrackCollectionView(title: "Tous les titres", kind: .all)
                    } label: {
                        categoryRow("Tous les titres", count: library.tracks.count, symbol: "music.note", tint: NW.accent)
                    }

                    categoryDivider

                    NavigationLink {
                        TrackCollectionView(title: "Titres aimés", kind: .liked)
                    } label: {
                        categoryRow("Titres aimés", count: library.liked.count, symbol: "heart.fill", tint: .pink)
                    }

                    categoryDivider

                    NavigationLink {
                        TrackCollectionView(title: "Sur cet iPhone", kind: .downloaded)
                    } label: {
                        categoryRow("Sur cet iPhone", count: library.downloaded.count, symbol: "arrow.down.circle.fill", tint: NW.accent)
                    }
                }
                .padding(.horizontal, 14)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 0.5))

                HStack(spacing: 10) {
                    Button(action: importFiles) {
                        HStack(spacing: 7) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Importer des fichiers")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.07), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                        .foregroundStyle(.white)
                    }

                    if session.account != nil {
                        Button {
                            Task { await library.sync() }
                        } label: {
                            HStack(spacing: 6) {
                                if library.syncing {
                                    ProgressView().tint(.white).scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                Text("Synchroniser")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.07), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                            .foregroundStyle(.white)
                        }
                        .disabled(library.syncing)
                    }
                }

                SectionHeading(title: "Vos playlists", eyebrow: "COLLECTION")

                if library.playlists.isEmpty {
                    EmptyLibrary(
                        symbol: "square.stack",
                        title: "À chaque moment, sa playlist.",
                        description: "Créez une playlist pour vos trajets, séances ou soirées.",
                        actionTitle: "Créer une playlist"
                    ) {
                        newPlaylist = true
                    }
                } else {
                    LazyVGrid(columns: [.init(.flexible(), spacing: 16), .init(.flexible(), spacing: 16)], spacing: 18) {
                        ForEach(Array(library.playlists.enumerated()), id: \.element.id) { index, playlist in
                            NavigationLink {
                                TrackCollectionView(title: playlist.name, kind: .playlist(playlist.id))
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    CoverArt(index: index % 6, symbol: playlist.symbol, radius: 14)
                                        .aspectRatio(1, contentMode: .fit)
                                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text("\(playlist.trackIDs.count) titres")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundStyle(Color(white: 0.55))
                                    }
                                }
                            }
                            .buttonStyle(PressStyle())
                            .contextMenu {
                                Button {
                                    let pTracks = library.playlistTracks(playlist)
                                    let pending = pTracks.filter { $0.canDownload && library.localURL($0) == nil }
                                    if pending.isEmpty {
                                        downloads.showSuccessToast("Playlist déjà téléchargée.")
                                    } else {
                                        pending.forEach(downloads.download)
                                        downloads.showSuccessToast("Téléchargement de « \(playlist.name) » lancé (\(pending.count) titres)")
                                    }
                                } label: {
                                    Label("Télécharger la playlist", systemImage: "arrow.down.circle")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.visible)
        .scrollBounceBehavior(.always, axes: .vertical)
        .alert("Nouvelle playlist", isPresented: $newPlaylist) {
            TextField("Nom de la playlist", text: $playlistName)
            Button("Annuler", role: .cancel) { playlistName = "" }
            Button("Créer") { library.createPlaylist(playlistName); playlistName = "" }
        } message: { Text("Vous pourrez y ajouter des titres de votre bibliothèque.") }
        .sheet(isPresented: $showSpotifyImport) {
            SpotifyPlaylistImportSheet()
        }
    }

    private func categoryRow(_ title: String, count: Int, symbol: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)

            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            Text("\(count)")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(white: 0.50))

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.35))
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var categoryDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.07))
            .padding(.leading, 42)
    }
}

// ─── Spotify Playlist Import Sheet ───────────────────────────────────────────
struct SpotifyPlaylistImportSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var loading = false
    @State private var errorMsg: String?
    @State private var preview: MusicCatalogService.SpotifyPlaylistImport?
    @State private var imported = false

    var body: some View {
        NavigationStack {
            ZStack {
                NW.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // ── Header ──
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(NW.cyan)
                                Text("Importer depuis Spotify")
                                    .font(.title2.bold())
                            }
                            Text("Collez le lien d'une playlist publique Spotify pour l'importer directement dans NeonWave.")
                                .font(.subheadline)
                                .foregroundStyle(NW.muted)
                        }
                        .padding(.top, 8)

                        // ── URL Input ──
                        VStack(alignment: .leading, spacing: 10) {
                            Text("LIEN SPOTIFY")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.4)
                                .foregroundStyle(NW.muted)

                            HStack(spacing: 12) {
                                Image(systemName: "link")
                                    .foregroundStyle(NW.muted)
                                TextField("https://open.spotify.com/playlist/…", text: $url)
                                    .autocorrectionDisabled()
                                    .autocapitalization(.none)
                                    .keyboardType(.URL)
                                    .onChange(of: url) { _, _ in
                                        preview = nil
                                        errorMsg = nil
                                        imported = false
                                    }
                                if !url.isEmpty {
                                    Button { url = "" } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(NW.muted)
                                    }
                                }
                            }
                            .padding(14)
                            .background(NW.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10)))
                        }

                        // ── Error ──
                        if let err = errorMsg {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                Text(err).font(.subheadline).foregroundStyle(.orange)
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        }

                        // ── Preview ──
                        if let p = preview {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 14) {
                                    if !p.imageUrl.isEmpty, let imgURL = URL(string: p.imageUrl) {
                                        AsyncImage(url: imgURL) { phase in
                                            if case .success(let img) = phase { img.resizable().scaledToFill() }
                                            else { Color.white.opacity(0.06) }
                                        }
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(p.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                                        if !p.ownerName.isEmpty {
                                            Text("Par \(p.ownerName)").font(.caption).foregroundStyle(NW.muted)
                                        }
                                        Text("\(p.totalTracks) titres trouvés")
                                            .font(.caption.bold())
                                            .foregroundStyle(NW.cyan)
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(NW.surface, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NW.cyan.opacity(0.25)))

                                if !p.description.isEmpty {
                                    Text(p.description)
                                        .font(.caption)
                                        .foregroundStyle(NW.muted)
                                        .lineLimit(3)
                                }

                                // Track preview (first 5)
                                VStack(spacing: 4) {
                                    ForEach(p.tracks.prefix(5)) { track in
                                        HStack(spacing: 12) {
                                            CoverArt(track: track, remoteURL: track.artworkURL, radius: 8)
                                                .frame(width: 40, height: 40)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(track.title).font(.caption.bold()).foregroundStyle(.white).lineLimit(1)
                                                Text(track.artist).font(.caption2).foregroundStyle(NW.muted).lineLimit(1)
                                            }
                                            Spacer()
                                            Text(track.duration.clockTime).font(.caption2.monospacedDigit()).foregroundStyle(NW.muted)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    if p.totalTracks > 5 {
                                        Text("+ \(p.totalTracks - 5) autre\(p.totalTracks - 5 > 1 ? "s" : "") titre\(p.totalTracks - 5 > 1 ? "s" : "")")
                                            .font(.caption)
                                            .foregroundStyle(NW.muted)
                                            .padding(.top, 4)
                                    }
                                }
                            }
                        }

                        // ── Success ──
                        if imported {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Playlist importée !").font(.subheadline.bold()).foregroundStyle(.white)
                                    Text("Retrouvez-la dans vos playlists.").font(.caption).foregroundStyle(NW.muted)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.3)))
                        }

                        Spacer()
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Importer une playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if loading {
                        ProgressView().tint(NW.blue)
                    } else if preview == nil || imported {
                        Button("Charger") {
                            Task { await loadPreview() }
                        }
                        .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading)
                        .font(.subheadline.bold())
                    } else {
                        Button("Importer") {
                            Task { await doImport() }
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(NW.cyan)
                    }
                }
            }
        }
    }

    private func loadPreview() async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        loading = true
        errorMsg = nil
        preview = nil
        do {
            let result = try await MusicCatalogService.importSpotifyPlaylist(trimmed)
            preview = result
        } catch {
            errorMsg = error.localizedDescription
        }
        loading = false
    }

    private func doImport() async {
        guard let p = preview else { return }
        loading = true
        await library.importSpotifyPlaylist(p)
        imported = true
        loading = false
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
    @EnvironmentObject private var network: NetworkMonitor
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
                VStack(alignment: .leading, spacing: 3) {
                    Text("EXPLORER")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Color(white: 0.55))
                    Text("Recherche")
                        .font(.system(size: 32, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                }
                .padding(.top, 12)

                if network.isActuallyOffline {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        Text("Mode hors connexion : recherche dans vos musiques enregistrées.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(white: 0.60))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(Color.orange.opacity(0.25)))
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(white: 0.50))
                    TextField("Artistes, titres, paroles…", text: $query)
                        .font(.system(size: 16))
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
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(white: 0.50))
                        }
                        .accessibilityLabel("Effacer la recherche")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                Picker("Filtrer les titres", selection: $filter) {
                    Text("En ligne").tag(0)
                    Text("Favoris").tag(1)
                    Text("Sur l’iPhone").tag(2)
                }
                .pickerStyle(.segmented)

                if filter == 0 {
                    if network.isActuallyOffline {
                        VStack(spacing: 14) {
                            HStack(spacing: 6) {
                                Image(systemName: "wifi.slash").foregroundStyle(.orange)
                                Text("Catalogue en ligne indisponible hors connexion.")
                                    .font(.subheadline)
                                    .foregroundStyle(NW.muted)
                            }
                            .padding(.top, 10)

                            if localResults.isEmpty {
                                EmptyLibrary(
                                    symbol: "magnifyingglass",
                                    title: "Aucun résultat sur cet iPhone",
                                    description: "Aucun morceau téléchargé ou favori ne correspond à votre recherche."
                                )
                            } else {
                                Text("\(localResults.count) TITRE\(localResults.count > 1 ? "S" : "") ENREGISTRÉ\(localResults.count > 1 ? "S" : "")").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(NW.muted)
                                LazyVStack(spacing: 2) {
                                    ForEach(localResults) { TrackRow(track: $0, context: localResults) }
                                }
                            }
                        }
                    } else if searching {
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
        .onAppear {
            if network.isActuallyOffline && filter == 0 {
                filter = 2
            }
        }
    }

    private var discoveryLanding: some View {
        VStack(alignment: .leading, spacing: 24) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.10, blue: 0.20),
                        Color(red: 0.05, green: 0.05, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(NW.accent.opacity(0.18))
                    .frame(width: 220)
                    .blur(radius: 60)
                    .offset(x: 140, y: -40)

                VStack(alignment: .leading, spacing: 10) {
                    Label("CATALOGUE", systemImage: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(NW.accent)

                    Text("Explorez des millions\nde morceaux.")
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(.white)

                    Text("Streaming immédiat, paroles synchronisées et téléchargements.")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.65))
                }
                .padding(22)
            }
            .frame(minHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.30), radius: 18, y: 8)

            SectionHeading(title: "Recherches tendance", eyebrow: "SUGGESTIONS")

            LazyVGrid(columns: [.init(.flexible(), spacing: 10), .init(.flexible(), spacing: 10), .init(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(suggestions, id: \.self) { name in
                    Button {
                        query = name
                        triggerSearch(name)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.50))
                            Text(name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(PressStyle())
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
        if network.isActuallyOffline {
            searching = false
            return
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
                VStack(spacing: 20) {
                    CoverArt(index: 2, remoteURL: album.coverURL, radius: 20)
                        .frame(width: 200, height: 200)
                        .shadow(color: .black.opacity(0.35), radius: 25, y: 12)
                        .padding(.top, 14)

                    VStack(spacing: 4) {
                        Text(album.title)
                            .font(.system(size: 24, weight: .bold))
                            .tracking(-0.5)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text(album.artist)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(white: 0.60))
                        if let count = album.trackCount {
                            Text("\(count) morceaux")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(white: 0.45))
                        }
                    }

                    if !tracks.isEmpty {
                        HStack(spacing: 12) {
                            Button {
                                if let first = tracks.first {
                                    player.shuffle = false
                                    player.play(first, in: tracks)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                                    Text("Lecture").font(.system(size: 15, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(.black)
                            }
                            .buttonStyle(PressStyle())

                            Button {
                                if let randomTrack = tracks.randomElement() {
                                    player.shuffle = true
                                    player.play(randomTrack, in: tracks)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "shuffle").font(.system(size: 14, weight: .bold))
                                    Text("Aléatoire").font(.system(size: 15, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(PressStyle())
                        }
                        .padding(.horizontal, 22)
                    }

                    if loading {
                        ProgressView().tint(.white).frame(height: 100)
                    } else if tracks.isEmpty {
                        Text("Aucune piste trouvée pour cet album.")
                            .font(.subheadline)
                            .foregroundStyle(Color(white: 0.55))
                            .padding()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                Button {
                                    player.play(track, in: tracks)
                                } label: {
                                    HStack(spacing: 14) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(player.current?.id == track.id ? NW.accent : Color(white: 0.40))
                                            .frame(width: 24, alignment: .trailing)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(track.title)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundStyle(player.current?.id == track.id ? NW.accent : .white)
                                                .lineLimit(1)
                                            Text(track.duration.clockTime)
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(Color(white: 0.50))
                                        }

                                        Spacer()

                                        if player.current?.id == track.id && player.isPlaying {
                                            Image(systemName: "waveform")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(NW.accent)
                                        }
                                    }
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Divider()
                                    .overlay(Color.white.opacity(0.06))
                                    .padding(.leading, 60)
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
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var downloads: DownloadManager
    let importFiles: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("STOCKAGE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Color(white: 0.55))
                    Text("Téléchargements")
                        .font(.system(size: 32, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                }
                .padding(.top, 12)

                HStack(spacing: 16) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(NW.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(library.downloaded.count) morceaux sur cet iPhone")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("\(ByteCountFormatter.string(fromByteCount: library.storageBytes, countStyle: .file)) d'espace utilisé")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .premiumPanel(radius: 18)

                Toggle(isOn: Binding(get: { library.snapshot.wifiOnly }, set: library.setWifiOnly)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Télécharger en Wi-Fi uniquement")
                            .font(.system(size: 15, weight: .medium))
                        Text("Économise les données cellulaires.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                .tint(NW.accent)

                if !downloads.progress.isEmpty {
                    SectionHeading(title: "En cours")
                    ForEach(library.tracks.filter { downloads.progress[$0.id] != nil }) { track in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(track.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                Spacer()
                                Button("Annuler") { downloads.cancel(track.id) }
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(white: 0.60))
                            }
                            ProgressView(value: downloads.progress[track.id] ?? 0).tint(NW.accent)
                        }
                        .padding(.vertical, 4)
                    }
                }

                let pending = library.tracks.filter { $0.canDownload && library.localURL($0) == nil }
                if !pending.isEmpty {
                    HStack {
                        SectionHeading(title: "À emporter")
                        Spacer()
                        Button("Tout télécharger") { pending.forEach(downloads.download) }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NW.accent)
                    }
                    ForEach(pending) { TrackRow(track: $0) }
                }

                if library.downloaded.isEmpty {
                    EmptyLibrary(
                        symbol: "arrow.down.circle",
                        title: "La musique, même sans réseau.",
                        description: "Téléchargez des titres depuis Recherche ou importez vos fichiers audio.",
                        actionTitle: "Importer des fichiers",
                        action: importFiles
                    )
                } else {
                    HStack(spacing: 12) {
                        Button {
                            if let first = library.downloaded.first {
                                player.shuffle = false
                                player.play(first, in: library.downloaded)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                                Text("Lecture").font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.black)
                        }
                        .buttonStyle(PressStyle())

                        Button {
                            if let randomTrack = library.downloaded.randomElement() {
                                player.shuffle = true
                                player.play(randomTrack, in: library.downloaded)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "shuffle").font(.system(size: 14, weight: .bold))
                                Text("Aléatoire").font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(PressStyle())
                    }

                    SectionHeading(title: "Morceaux téléchargés", eyebrow: "DISPONIBLE HORS LIGNE")
                    LazyVStack(spacing: 0) {
                        ForEach(library.downloaded) { TrackRow(track: $0, context: library.downloaded) }
                    }
                }
            }.padding(22).padding(.bottom, 120)
        }.scrollIndicators(.visible).scrollBounceBehavior(.always, axes: .vertical)
    }
}

enum ArtistDiscographyTab: String, CaseIterable {
    case popular = "Populaires"
    case albums = "Albums"
    case singles = "Singles & EP"
}

struct ArtistDetailView: View {
    let artist: ArtistIdentifier
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var taste: MusicTasteStore
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss

    @State private var profile: MusicCatalogService.ArtistProfileData.Item?
    @State private var loading = true
    @State private var discographyTab: ArtistDiscographyTab = .popular
    @State private var selectedAlbum: Album?
    @State private var subArtist: ArtistIdentifier?

    private var artistName: String { profile?.artist?.name ?? artist.name }
    private var heroImageURL: String? { profile?.artist?.imageUrl ?? artist.imageUrl }
    private var isFollowed: Bool { taste.isFollowed(artistName) }

    private var topTracks: [Track] {
        guard let list = profile?.topTracks else { return [] }
        return list.map { item in
            let dur = item.duration ?? ((item.durationMs ?? 0) / 1000)
            let stableID = item.spotifyId.map { "sp-\($0)" } ?? item.id ?? UUID().uuidString
            return Track(
                id: stableID,
                title: item.title,
                artist: item.artist ?? artistName,
                duration: dur,
                album: item.album,
                artworkURL: item.thumbnail ?? heroImageURL,
                videoId: item.videoId,
                spotifyId: item.spotifyId
            )
        }
    }

    private var currentDiscography: [MusicCatalogService.ArtistProfileData.DiscographyItem] {
        guard let disco = profile?.discography else { return [] }
        switch discographyTab {
        case .popular: return disco.popular ?? disco.albums ?? []
        case .albums: return disco.albums ?? []
        case .singles: return disco.singles ?? []
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    heroHeader
                    actionRow

                    if loading {
                        ProgressView().tint(NW.blue).frame(height: 120)
                    } else {
                        if !topTracks.isEmpty {
                            topTracksSection
                        }

                        if !(profile?.discography?.albums ?? []).isEmpty || !(profile?.discography?.singles ?? []).isEmpty || !(profile?.discography?.popular ?? []).isEmpty {
                            discographySection
                        }

                        if let related = profile?.relatedArtists, !related.isEmpty {
                            relatedArtistsSection(related)
                        }

                        aboutSection
                    }
                }
                .padding(.bottom, 130)
            }
            .scrollIndicators(.visible)
            .background(NW.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(artistName)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        taste.toggleFollow(name: artistName, spotifyId: profile?.artist?.spotifyId ?? artist.spotifyId, imageUrl: heroImageURL)
                    } label: {
                        Image(systemName: isFollowed ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isFollowed ? .pink : .white)
                            .padding(8)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                }
            }
            .task {
                loading = true
                profile = await MusicCatalogService.fetchArtistProfile(name: artist.name, spotifyId: artist.spotifyId)
                loading = false
            }
            .sheet(item: $selectedAlbum) { album in
                AlbumDetailView(album: album)
            }
            .sheet(item: $subArtist) { sub in
                ArtistDetailView(artist: sub)
            }
        }
    }

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            if let heroImageURL, let url = URL(string: heroImageURL) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: 310)
                            .clipped()
                            .overlay(
                                LinearGradient(
                                    colors: [.clear, NW.background.opacity(0.4), NW.background],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        heroFallback
                    }
                }
            } else {
                heroFallback
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(NW.blue)
                        .font(.system(size: 14))
                    Text("ARTISTE VÉRIFIÉ")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(NW.blue)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())

                Text(artistName)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.6), radius: 8, y: 3)

                if let followers = profile?.artist?.followers, followers > 0 {
                    Text("\(formatFollowers(followers)) auditeurs")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
        .frame(height: 310)
    }

    private var heroFallback: some View {
        LinearGradient(colors: [NW.blue.opacity(0.7), NW.violet.opacity(0.5), NW.background], startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(maxWidth: .infinity, maxHeight: 310)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                if let first = topTracks.first {
                    player.shuffle = false
                    player.play(first, in: topTracks)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Écouter")
                        .font(.subheadline.bold())
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(LinearGradient(colors: [NW.blue, NW.violet], startPoint: .leading, endPoint: .trailing), in: Capsule())
                .foregroundStyle(.white)
                .shadow(color: NW.blue.opacity(0.35), radius: 10, y: 4)
            }
            .disabled(topTracks.isEmpty)

            Button {
                if let random = topTracks.randomElement() {
                    player.shuffle = true
                    player.play(random, in: topTracks)
                }
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(13)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .disabled(topTracks.isEmpty)

            Button {
                taste.toggleFollow(name: artistName, spotifyId: profile?.artist?.spotifyId ?? artist.spotifyId, imageUrl: heroImageURL)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isFollowed ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text(isFollowed ? "Abonné" : "S’abonner")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(isFollowed ? Color.white.opacity(0.14) : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                .foregroundStyle(.white)
            }

            Spacer()
        }
        .padding(.horizontal, 22)
    }

    private var topTracksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Titres populaires", eyebrow: "CLASSEMENT")
                .padding(.horizontal, 22)

            LazyVStack(spacing: 2) {
                ForEach(Array(topTracks.prefix(10).enumerated()), id: \.element.id) { index, track in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(index < 3 ? NW.blue : NW.muted)
                            .frame(width: 22, alignment: .trailing)

                        CoverArt(track: track, remoteURL: track.artworkURL, radius: 10)
                            .frame(width: 46, height: 46)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(player.current?.id == track.id ? NW.blue : .white)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.caption)
                                .foregroundStyle(NW.muted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(track.duration.clockTime)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(NW.muted)

                        Button {
                            if player.current?.id == track.id {
                                if player.isPlaying { player.pause() } else { player.resume() }
                            } else {
                                player.play(track, in: topTracks)
                            }
                        } label: {
                            Image(systemName: player.current?.id == track.id && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title3)
                                .foregroundStyle(player.current?.id == track.id ? NW.blue : .white.opacity(0.7))
                        }
                        .padding(.leading, 4)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        player.play(track, in: topTracks)
                    }
                }
            }
        }
    }

    private var discographySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Discographie", eyebrow: "SORTIES")
                .padding(.horizontal, 22)

            Picker("Discographie", selection: $discographyTab) {
                ForEach(ArtistDiscographyTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 22)

            if currentDiscography.isEmpty {
                Text("Aucune sortie dans cette catégorie.")
                    .font(.caption)
                    .foregroundStyle(NW.muted)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(currentDiscography) { item in
                            Button {
                                selectedAlbum = Album(
                                    id: item.deezerId ?? item.spotifyId ?? UUID().uuidString,
                                    title: item.name,
                                    artist: artistName,
                                    coverURL: item.imageUrl,
                                    releaseDate: item.releaseDate
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    CoverArt(remoteURL: item.imageUrl, radius: 14)
                                        .frame(width: 135, height: 135)
                                    Text(item.name)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        if let year = item.releaseDate?.prefix(4) {
                                            Text(String(year))
                                                .font(.caption2)
                                                .foregroundStyle(NW.muted)
                                        }
                                        Text("•")
                                            .font(.caption2)
                                            .foregroundStyle(NW.muted)
                                        Text(item.type == "single" ? "Single" : "Album")
                                            .font(.caption2.bold())
                                            .foregroundStyle(NW.blue)
                                    }
                                }
                                .frame(width: 135, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func relatedArtistsSection(_ list: [MusicCatalogService.ArtistProfileData.RelatedArtist]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Les fans aiment aussi", eyebrow: "SIMILAIRES")
                .padding(.horizontal, 22)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(list) { rel in
                        Button {
                            subArtist = ArtistIdentifier(name: rel.name, spotifyId: rel.spotifyId, imageUrl: rel.imageUrl)
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle().fill(LinearGradient(colors: [NW.blue, NW.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    if let img = rel.imageUrl, let url = URL(string: img) {
                                        AsyncImage(url: url) { phase in
                                            if case .success(let image) = phase {
                                                image.resizable().scaledToFill()
                                            } else {
                                                Text(String(rel.name.prefix(1))).font(.title3.bold())
                                            }
                                        }
                                        .clipShape(Circle())
                                    } else {
                                        Text(String(rel.name.prefix(1))).font(.title3.bold())
                                    }
                                    Circle().stroke(.white.opacity(0.2), lineWidth: 1)
                                }
                                .frame(width: 80, height: 80)
                                .shadow(color: NW.blue.opacity(0.2), radius: 8, y: 4)

                                Text(rel.name)
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .frame(width: 84)

                                if let f = rel.followers, f > 0 {
                                    Text("\(formatFollowers(f))")
                                        .font(.system(size: 9))
                                        .foregroundStyle(NW.muted)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 4)
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "À propos", eyebrow: "DÉTAILS")
                .padding(.horizontal, 22)

            HStack(spacing: 12) {
                if let followers = profile?.artist?.followers, followers > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AUDITEURS")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(NW.muted)
                        Text(formatFollowers(followers))
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .premiumPanel(radius: 16)
                }

                if let genres = profile?.artist?.genres, !genres.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GENRES")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(NW.muted)
                        Text(genres.prefix(2).joined(separator: ", "))
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .premiumPanel(radius: 16)
                }
            }
            .padding(.horizontal, 22)
        }
    }

    private func formatFollowers(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1f M", Double(n) / 1_000_000).replacingOccurrences(of: ".0", with: "")
        } else if n >= 1_000 {
            return String(format: "%.0f k", Double(n) / 1_000)
        }
        return "\(n)"
    }
}

// ─── Custom Track Import Sheet ───────────────────────────────────────────────

struct CustomImportSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let draft: LibraryStore.DraftAudioImport

    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var coverImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var searchingCover = false
    @State private var selectedPlaylistID: String? = nil
    @State private var searchError: String? = nil

    init(draft: LibraryStore.DraftAudioImport) {
        self.draft = draft
        _title = State(initialValue: draft.title)
        _artist = State(initialValue: draft.artist)
        _album = State(initialValue: draft.album)
        _coverImage = State(initialValue: draft.coverImage)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NW.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        // File badge
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(NW.cyan)
                            Text(draft.url.lastPathComponent)
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if draft.duration > 0 {
                                Text("· \(draft.duration.clockTime)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(NW.muted)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(NW.surface, in: Capsule())
                        .overlay(Capsule().stroke(NW.cyan.opacity(0.3), lineWidth: 1))

                        // Cover Artwork Preview
                        VStack(spacing: 14) {
                            ZStack {
                                if let cover = coverImage {
                                    Image(uiImage: cover)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 170, height: 170)
                                        .clipped()
                                } else {
                                    ZStack {
                                        LinearGradient(
                                            colors: [NW.cyan.opacity(0.7), NW.blue.opacity(0.5), NW.violet.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        VStack(spacing: 8) {
                                            Image(systemName: "music.note")
                                                .font(.system(size: 44, weight: .bold))
                                                .foregroundStyle(.white.opacity(0.85))
                                            Text("AUCUNE POCHETTE")
                                                .font(.system(size: 9, weight: .bold))
                                                .tracking(1.4)
                                                .foregroundStyle(.white.opacity(0.6))
                                        }
                                    }
                                    .frame(width: 170, height: 170)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)

                            // Buttons for Cover
                            HStack(spacing: 12) {
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .font(.caption.bold())
                                        Text("Photos")
                                            .font(.caption.bold())
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(NW.surface, in: Capsule())
                                    .foregroundStyle(.white)
                                    .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                                }

                                Button {
                                    Task { await autoSearchCover() }
                                } label: {
                                    HStack(spacing: 6) {
                                        if searchingCover {
                                            ProgressView().tint(NW.cyan)
                                        } else {
                                            Image(systemName: "sparkle.magnifyingglass")
                                                .font(.caption.bold())
                                        }
                                        Text("Pochette web")
                                            .font(.caption.bold())
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(NW.cyan.opacity(0.15), in: Capsule())
                                    .foregroundStyle(NW.cyan)
                                    .overlay(Capsule().stroke(NW.cyan.opacity(0.35)))
                                }
                                .disabled(searchingCover || (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

                                if coverImage != nil {
                                    Button {
                                        coverImage = nil
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption.bold())
                                            .foregroundStyle(Color.red.opacity(0.8))
                                            .padding(9)
                                            .background(Color.red.opacity(0.12), in: Circle())
                                    }
                                }
                            }

                            if let err = searchError {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(Color.orange)
                            }
                        }

                        // Metadata Inputs
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("TITRE DU MORCEAU")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(NW.cyan)
                                    .tracking(1.3)
                                TextField("Titre", text: $title)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .padding(14)
                                    .background(NW.surface, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("ARTISTE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(NW.cyan)
                                    .tracking(1.3)
                                TextField("Nom de l'artiste", text: $artist)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .padding(14)
                                    .background(NW.surface, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("ALBUM (OPTIONNEL)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(NW.muted)
                                    .tracking(1.3)
                                TextField("Nom de l'album", text: $album)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .padding(14)
                                    .background(NW.surface, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
                            }

                            if !library.playlists.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("AJOUTER À UNE PLAYLIST (OPTIONNEL)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(NW.muted)
                                        .tracking(1.3)
                                    Menu {
                                        Button("Aucune (Bibliothèque uniquement)") {
                                            selectedPlaylistID = nil
                                        }
                                        ForEach(library.playlists) { p in
                                            Button(p.name) {
                                                selectedPlaylistID = p.id
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            let currentName = library.playlists.first(where: { $0.id == selectedPlaylistID })?.name ?? "Aucune (Bibliothèque uniquement)"
                                            Text(currentName)
                                                .font(.subheadline)
                                                .foregroundStyle(.white)
                                            Spacer()
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.caption)
                                                .foregroundStyle(NW.muted)
                                        }
                                        .padding(14)
                                        .background(NW.surface, in: RoundedRectangle(cornerRadius: 14))
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Save Button
                        Button {
                            doSave()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.down.fill")
                                Text("Ajouter à la bibliothèque")
                            }
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(colors: [NW.cyan, NW.blue], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                            .shadow(color: NW.blue.opacity(0.3), radius: 12, y: 6)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 40)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Personnaliser le morceau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Importer") { doSave() }
                        .font(.headline)
                        .foregroundStyle(NW.cyan)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            coverImage = image
                        }
                    }
                }
            }
        }
    }

    private func autoSearchCover() async {
        searchingCover = true
        searchError = nil
        if let found = await MusicCatalogService.findCoverImage(title: title, artist: artist) {
            coverImage = found
        } else {
            searchError = "Aucune pochette trouvée sur le web."
        }
        searchingCover = false
    }

    private func doSave() {
        var updatedDraft = draft
        updatedDraft.title = title
        updatedDraft.artist = artist
        updatedDraft.album = album
        updatedDraft.coverImage = coverImage

        let targetPlaylist = library.playlists.first(where: { $0.id == selectedPlaylistID })
        library.importCustomTrack(draft: updatedDraft, to: targetPlaylist)
        dismiss()
    }
}

// ─── Track Edit Sheet (Modifier les informations d'un morceau) ───────────────

struct TrackEditSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    let track: Track

    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var coverImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var searchingCover = false
    @State private var searchError: String? = nil

    init(track: Track) {
        self.track = track
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist)
        _album = State(initialValue: track.album ?? "")
        _coverImage = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NW.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        // Cover Artwork Preview
                        VStack(spacing: 14) {
                            ZStack {
                                if let cover = coverImage {
                                    Image(uiImage: cover)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 170, height: 170)
                                        .clipped()
                                } else if let local = library.artworkURL(track), let img = UIImage(contentsOfFile: local.path) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 170, height: 170)
                                        .clipped()
                                } else if let remote = track.artworkURL, let url = URL(string: remote) {
                                    AsyncImage(url: url) { phase in
                                        if case .success(let img) = phase {
                                            img.resizable().scaledToFill()
                                        } else {
                                            placeholderCover
                                        }
                                    }
                                    .frame(width: 170, height: 170)
                                    .clipped()
                                } else {
                                    placeholderCover
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)

                            // Buttons for Cover
                            HStack(spacing: 12) {
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .font(.caption.bold())
                                        Text("Photos")
                                            .font(.caption.bold())
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(NW.surface, in: Capsule())
                                    .foregroundStyle(.white)
                                    .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                                }

                                Button {
                                    Task { await autoSearchCover() }
                                } label: {
                                    HStack(spacing: 6) {
                                        if searchingCover {
                                            ProgressView().tint(NW.cyan)
                                        } else {
                                            Image(systemName: "sparkle.magnifyingglass")
                                                .font(.caption.bold())
                                        }
                                        Text("Pochette web")
                                            .font(.caption.bold())
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(NW.cyan.opacity(0.15), in: Capsule())
                                    .foregroundStyle(NW.cyan)
                                    .overlay(Capsule().stroke(NW.cyan.opacity(0.35)))
                                }
                                .disabled(searchingCover || (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

                                if coverImage != nil {
                                    Button {
                                        coverImage = nil
                                    } label: {
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.caption.bold())
                                            .foregroundStyle(NW.muted)
                                            .padding(9)
                                            .background(NW.surface, in: Circle())
                                    }
                                }
                            }

                            if let err = searchError {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(Color.orange)
                            }
                        }

                        // Metadata Inputs
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("TITRE DU MORCEAU")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(NW.cyan)
                                    .tracking(1.3)
                                TextField("Titre", text: $title)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .padding(14)
                                    .background(NW.surface, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("ARTISTE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(NW.cyan)
                                    .tracking(1.3)
                                TextField("Nom de l'artiste", text: $artist)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .padding(14)
                                    .background(NW.surface, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("ALBUM")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(NW.muted)
                                    .tracking(1.3)
                                TextField("Nom de l'album", text: $album)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .padding(14)
                                    .background(NW.surface, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
                            }
                        }
                        .padding(.horizontal, 20)

                        // Save Button
                        Button {
                            doSave()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                Text("Enregistrer les modifications")
                            }
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(colors: [NW.cyan, NW.blue], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                            .shadow(color: NW.blue.opacity(0.3), radius: 12, y: 6)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 40)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Modifier le morceau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { doSave() }
                        .font(.headline)
                        .foregroundStyle(NW.cyan)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            coverImage = image
                        }
                    }
                }
            }
        }
    }

    private var placeholderCover: some View {
        ZStack {
            LinearGradient(
                colors: [NW.cyan.opacity(0.7), NW.blue.opacity(0.5), NW.violet.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 170, height: 170)
    }

    private func autoSearchCover() async {
        searchingCover = true
        searchError = nil
        if let found = await MusicCatalogService.findCoverImage(title: title, artist: artist) {
            coverImage = found
        } else {
            searchError = "Aucune pochette trouvée sur le web."
        }
        searchingCover = false
    }

    private func doSave() {
        if let updated = library.updateTrackMetadata(
            trackID: track.id,
            title: title,
            artist: artist,
            album: album,
            coverImage: coverImage
        ) {
            player.refreshCurrentTrack(from: updated)
        }
        dismiss()
    }
}
