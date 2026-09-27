import Foundation
import MusicKit

/// App Store catalogue and playback source.
/// MusicKit keeps catalogue access, authorization, playback and lock-screen
/// controls inside Apple's supported APIs. The app never receives a downloadable
/// Apple Music audio URL.
enum AppleMusicService {
    static func requestAuthorization() async -> Bool {
        if MusicAuthorization.currentStatus == .authorized { return true }
        return await MusicAuthorization.request() == .authorized
    }

    static func searchTracks(_ term: String, limit: Int = 30) async -> [Track] {
        guard await requestAuthorization() else { return [] }
        do {
            var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
            request.limit = limit
            let response = try await request.response()
            return response.songs.map(mapSong)
        } catch {
            return []
        }
    }

    static func searchAlbums(_ term: String, limit: Int = 20) async -> [Album] {
        guard await requestAuthorization() else { return [] }
        do {
            var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Album.self])
            request.limit = limit
            let response = try await request.response()
            return response.albums.map { album in
                Album(
                    id: "am-\(album.id.rawValue)",
                    title: album.title,
                    artist: album.artistName,
                    coverURL: album.artwork?.url(width: 1000, height: 1000)?.absoluteString,
                    trackCount: nil,
                    releaseDate: nil,
                    appleMusicID: album.id.rawValue
                )
            }
        } catch {
            return []
        }
    }

    static func albumTracks(albumID: String, title: String, artist: String) async -> [Track] {
        let results = await searchTracks("\(artist) \(title)", limit: 50)
        return results.filter {
            $0.album?.localizedCaseInsensitiveCompare(title) == .orderedSame ||
            $0.artist.localizedCaseInsensitiveCompare(artist) == .orderedSame
        }
    }

    static func searchArtists(_ term: String, limit: Int = 12) async -> [ArtistChoice] {
        guard await requestAuthorization() else { return [] }
        do {
            var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Artist.self])
            request.limit = limit
            let response = try await request.response()
            return response.artists.map { artist in
                ArtistChoice(
                    spotifyId: artist.id.rawValue,
                    name: artist.name,
                    imageUrl: artist.artwork?.url(width: 600, height: 600)?.absoluteString ?? "",
                    spotifyUrl: artist.url?.absoluteString ?? "",
                    source: "appleMusic"
                )
            }
        } catch {
            return []
        }
    }

    static func songs(ids: [String]) async throws -> [Song] {
        guard await requestAuthorization() else {
            throw MessageError("Autorisez Apple Music pour écouter ce titre.")
        }
        var result: [Song] = []
        for rawID in ids {
            var request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(rawID))
            request.limit = 1
            if let song = try await request.response().items.first { result.append(song) }
        }
        return result
    }

    private static func mapSong(_ song: Song) -> Track {
        Track(
            id: "am-\(song.id.rawValue)",
            title: song.title,
            artist: song.artistName,
            duration: song.duration ?? 0,
            album: song.albumTitle,
            artworkURL: song.artwork?.url(width: 1000, height: 1000)?.absoluteString,
            appleMusicID: song.id.rawValue
        )
    }
}
