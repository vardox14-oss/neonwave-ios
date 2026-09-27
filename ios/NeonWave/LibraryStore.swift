import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@MainActor final class LibraryStore: ObservableObject {
    @Published private(set) var snapshot = LibrarySnapshot()
    @Published var importing = false
    @Published var syncing = false
    @Published var uploading: Set<String> = []
    @Published var message: String?
    private(set) var userID = "guest"
    private var directory: URL!
    var tracks: [Track] { snapshot.tracks }
    var playlists: [Playlist] { snapshot.playlists }
    var liked: [Track] { tracks.filter { snapshot.likedIDs.contains($0.id) } }
    var downloaded: [Track] { tracks.filter { localURL($0) != nil } }
    var recent: [Track] { tracks.filter { $0.lastPlayedAt != nil }.sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) } }
    var storageBytes: Int64 {
        downloaded.reduce(0) { total, track in
            let urls = [localURL(track), artworkURL(track), canvasURL(track)].compactMap { $0 }
            return total + urls.reduce(0) { subtotal, url in
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                return subtotal + ((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
            }
        }
    }

    init() { activate("guest") }
    func activate(_ userID: String) {
        self.userID = userID
        // User IDs are converted to a safe directory name, never used as paths from a response.
        let safe = Data(userID.utf8).base64URLEncoded
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = root.appendingPathComponent("NeonWave/\(safe)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: url.path) { snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: url)) }
            else { snapshot = LibrarySnapshot() }
        } catch { snapshot = LibrarySnapshot(); message = "La bibliothèque n’a pas pu être ouverte. Les fichiers existants sont conservés." }
    }
    func fileURL(_ fileName: String) -> URL? {
        guard fileName == (fileName as NSString).lastPathComponent, !fileName.isEmpty, fileName != ".", fileName != ".." else { return nil }
        return directory.appendingPathComponent(fileName)
    }
    func localURL(_ track: Track) -> URL? {
        guard let fileName = track.fileName, let url = fileURL(fileName), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
    func artworkURL(_ track: Track) -> URL? { track.artworkFile.flatMap(fileURL) }
    func canvasURL(_ track: Track) -> URL? {
        guard let name = track.canvasFile, let url = fileURL(name), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
    func playlistTracks(_ playlist: Playlist) -> [Track] { playlist.trackIDs.compactMap { id in tracks.first { $0.id == id } } }
    private func persist() {
        do { try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent("library.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { message = "La sauvegarde a échoué. Vérifiez l’espace disponible sur cet iPhone." }
    }
    func toggleLike(_ track: Track) {
        if snapshot.likedIDs.contains(track.id) { snapshot.likedIDs.remove(track.id) } else { snapshot.likedIDs.insert(track.id) }
        haptic(); persist()
    }
    func createPlaylist(_ name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        snapshot.playlists.insert(Playlist(name: String(cleaned.prefix(80))), at: 0); persist(); haptic()
    }
    func addTrackIfMissing(_ track: Track) {
        if !snapshot.tracks.contains(where: { $0.id == track.id }) {
            snapshot.tracks.insert(track, at: 0)
            persist()
        }
    }
    func renamePlaylist(_ playlist: Playlist, name: String) {
        guard let index = snapshot.playlists.firstIndex(where: { $0.id == playlist.id }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        snapshot.playlists[index].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)); persist()
    }
    func add(_ track: Track, to playlist: Playlist) {
        guard let index = snapshot.playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        if !snapshot.playlists[index].trackIDs.contains(track.id) { snapshot.playlists[index].trackIDs.append(track.id); persist() }
    }
    func remove(_ track: Track, from playlist: Playlist) {
        guard let index = snapshot.playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        snapshot.playlists[index].trackIDs.removeAll { $0 == track.id }; persist()
    }
    func deletePlaylist(_ playlist: Playlist) { snapshot.playlists.removeAll { $0.id == playlist.id }; persist() }
    func recordPlay(_ track: Track) {
        guard let index = snapshot.tracks.firstIndex(where: { $0.id == track.id }) else { return }
        snapshot.tracks[index].playCount += 1; snapshot.tracks[index].lastPlayedAt = Date(); persist()
    }
    func setWifiOnly(_ value: Bool) { snapshot.wifiOnly = value; persist() }
    func setHaptics(_ value: Bool) { snapshot.haptics = value; persist() }
    func haptic() { if snapshot.haptics { UISelectionFeedbackGenerator().selectionChanged() } }

    func importSpotifyPlaylist(_ data: MusicCatalogService.SpotifyPlaylistImport) async {
        guard !data.tracks.isEmpty else { return }
        // 1. Créer la playlist
        let cleanName = data.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlistName = cleanName.isEmpty ? "Playlist Spotify" : String(cleanName.prefix(80))
        let playlist = Playlist(name: playlistName)
        snapshot.playlists.insert(playlist, at: 0)
        // 2. Ajouter les titres à la bibliothèque et à la playlist
        var addedIDs: [String] = []
        for track in data.tracks {
            if !snapshot.tracks.contains(where: { $0.id == track.id }) {
                snapshot.tracks.append(track)
            }
            addedIDs.append(track.id)
        }
        // 3. Remplir la playlist
        guard let index = snapshot.playlists.firstIndex(where: { $0.id == playlist.id }) else { persist(); return }
        snapshot.playlists[index].trackIDs = addedIDs
        persist()
        haptic()
    }

    func importFiles(_ urls: [URL]) async {
        guard !importing else { return }
        importing = true
        let owner = userID
        defer { importing = false }
        var imported = 0; var failures = 0
        for url in urls {
            guard owner == userID else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let id = UUID().uuidString
            let ext = url.pathExtension.lowercased()
            guard ["mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac"].contains(ext) else { failures += 1; continue }
            let fileName = "\(id).\(ext)"
            guard let destination = fileURL(fileName) else { continue }
            do {
                let asset = AVURLAsset(url: url)
                guard try await asset.load(.isPlayable) else { throw MessageError("Format non lisible.") }
                let duration = try await asset.load(.duration).seconds
                let metadata = (try? await asset.load(.commonMetadata)) ?? []
                var title = url.deletingPathExtension().lastPathComponent
                var artist = "Fichiers personnels"
                var artwork: Data?
                for item in metadata {
                    switch item.commonKey {
                    case .commonKeyTitle: if let text = try? await item.load(.stringValue), !text.isEmpty { title = text }
                    case .commonKeyArtist: if let text = try? await item.load(.stringValue), !text.isEmpty { artist = text }
                    case .commonKeyArtwork: artwork = try? await item.load(.dataValue)
                    default: break
                    }
                }
                guard owner == userID else { return }
                // Copy the actual file; file-provider URLs do not remain usable after the picker closes.
                try FileManager.default.copyItem(at: url, to: destination)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
                var artworkFile: String?
                if let artwork, let image = UIImage(data: artwork), let jpeg = image.jpegData(compressionQuality: 0.85), let imageURL = fileURL("\(id).jpg") {
                    try jpeg.write(to: imageURL, options: .atomic); artworkFile = "\(id).jpg"
                }
                snapshot.tracks.insert(Track(id: id, title: title, artist: artist, duration: duration.isFinite ? duration : 0, fileName: fileName, artworkFile: artworkFile), at: 0)
                persist(); imported += 1
            } catch { try? FileManager.default.removeItem(at: destination); failures += 1 }
        }
        message = "\(imported) titre\(imported > 1 ? "s" : "") importé\(imported > 1 ? "s" : "")\(failures > 0 ? ". \(failures) fichier(s) non lisible(s)." : ". Prêt pour le mode avion.")"
    }
    func sync() async {
        guard !syncing, AppConfiguration.apiURL != nil else { return }
        syncing = true; let owner = userID
        defer { syncing = false }
        do {
            let remote: RemoteLibrary = try await APIClient().call("api/ios/library")
            guard owner == userID else { return }
            for item in remote.tracks {
                if let index = snapshot.tracks.firstIndex(where: { $0.remoteID == item.id }) {
                    snapshot.tracks[index].title = item.title; snapshot.tracks[index].artist = item.artist
                } else {
                    snapshot.tracks.append(Track(title: item.title, artist: item.artist, duration: item.durationMs / 1000, remoteID: item.id))
                }
            }
            persist()
        } catch { message = error.localizedDescription }
    }
    func upload(_ track: Track) async {
        guard let url = localURL(track), track.remoteID == nil, !uploading.contains(track.id) else { return }
        guard AppConfiguration.apiURL != nil else { message = "La sauvegarde en ligne sera disponible après configuration du serveur distant."; return }
        let mimeTypes = ["mp3": "audio/mpeg", "m4a": "audio/mp4", "wav": "audio/wav", "flac": "audio/flac"]
        guard let mime = mimeTypes[url.pathExtension.lowercased()] else { message = "La sauvegarde serveur prend en charge les fichiers MP3, M4A, WAV et FLAC. Ce titre reste disponible sur cet iPhone."; return }
        let owner = userID
        uploading.insert(track.id)
        defer { uploading.remove(track.id) }
        do {
            let encoded = try await Task.detached(priority: .utility) {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 50 * 1024 * 1024 else { throw MessageError("Ce fichier dépasse la limite de sauvegarde de 50 Mo. Il reste disponible sur cet iPhone.") }
                return try Data(contentsOf: url).base64EncodedString()
            }.value
            guard userID == owner else { return }
            let remote: RemoteTrack = try await APIClient().call("api/user/local-tracks", method: "POST", body: ["filename": url.lastPathComponent, "title": track.title, "artist": track.artist, "durationMs": track.duration * 1000, "mimeType": mime, "data": encoded])
            guard userID == owner, let index = snapshot.tracks.firstIndex(where: { $0.id == track.id }) else { return }
            snapshot.tracks[index].remoteID = remote.id; persist()
            message = "« \(track.title) » est sauvegardé sur votre compte."
        } catch { message = error.localizedDescription }
    }
    func downloadDestination(_ track: Track, fileExtension: String? = nil) -> URL {
        let ext = fileExtension ?? ((track.videoId != nil || track.spotifyId != nil || track.streamURL?.contains(".m4a") == true || track.streamURL?.contains(".aac") == true) ? "m4a" : "mp3")
        return directory.appendingPathComponent("\(track.id).\(ext)")
    }
    func setResolvedVideoID(trackID: String, videoID: String) {
        guard let index = snapshot.tracks.firstIndex(where: { $0.id == trackID }), snapshot.tracks[index].videoId != videoID else { return }
        snapshot.tracks[index].videoId = videoID; persist()
    }
    func finishDownload(trackID: String, fileName: String) {
        guard let index = snapshot.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        snapshot.tracks[index].fileName = fileName; persist()
    }
    func cacheOfflineMedia(trackID: String) async {
        guard let original = snapshot.tracks.first(where: { $0.id == trackID }), localURL(original) != nil else { return }
        let owner = userID

        if artworkURL(original) == nil, let source = original.artworkURL.flatMap(URL.init(string:)) {
            do {
                let (data, response) = try await URLSession.shared.data(from: source)
                guard owner == userID,
                      let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      data.count < 12 * 1024 * 1024,
                      let image = UIImage(data: data),
                      let jpeg = image.jpegData(compressionQuality: 0.86) else { throw URLError(.cannotDecodeContentData) }
                let name = "\(trackID)-cover.jpg"
                guard let destination = fileURL(name) else { return }
                try jpeg.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                if let index = snapshot.tracks.firstIndex(where: { $0.id == trackID }) { snapshot.tracks[index].artworkFile = name; persist() }
            } catch { }
        }

#if !APPSTORE
        guard owner == userID,
              let current = snapshot.tracks.first(where: { $0.id == trackID }),
              canvasURL(current) == nil else { return }
        let canvasState = await SpotifyCanvasService.load(for: current)
        guard case .ready(let source) = canvasState, !source.isFileURL else { return }
        do {
            let (temporary, response) = try await URLSession.shared.download(from: source)
            guard owner == userID,
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else { return }
            let attributes = try FileManager.default.attributesOfItem(atPath: temporary.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 16_384, size < 80 * 1024 * 1024 else { return }
            let name = "\(trackID)-canvas.mp4"
            guard let destination = fileURL(name) else { return }
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: temporary, to: destination)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
            var url = destination; var values = URLResourceValues(); values.isExcludedFromBackup = true; try? url.setResourceValues(values)
            if let index = snapshot.tracks.firstIndex(where: { $0.id == trackID }) { snapshot.tracks[index].canvasFile = name; persist() }
        } catch { }
#endif
    }
    func removeDownload(_ track: Track) {
        guard track.isDownloadedSource else { return }
        do {
            if let url = localURL(track) { try FileManager.default.removeItem(at: url) }
            if let url = canvasURL(track) { try? FileManager.default.removeItem(at: url) }
            if let index = snapshot.tracks.firstIndex(where: { $0.id == track.id }) {
                snapshot.tracks[index].fileName = nil
                snapshot.tracks[index].canvasFile = nil
                persist()
            }
        } catch { message = "Impossible de supprimer ce téléchargement." }
    }
    func deleteTrack(_ track: Track) {
        do {
            if let url = localURL(track) { try FileManager.default.removeItem(at: url) }
            if let url = artworkURL(track) { try? FileManager.default.removeItem(at: url) }
            if let url = canvasURL(track) { try? FileManager.default.removeItem(at: url) }
            snapshot.tracks.removeAll { $0.id == track.id }; snapshot.likedIDs.remove(track.id)
            for index in snapshot.playlists.indices { snapshot.playlists[index].trackIDs.removeAll { $0 == track.id } }
            persist()
        } catch { message = "Impossible de supprimer ce fichier." }
    }
    func eraseAccountFiles() throws {
        // Directory is derived locally from the account ID; it cannot point outside Application Support.
        try FileManager.default.removeItem(at: directory)
        snapshot = LibrarySnapshot()
    }
}
