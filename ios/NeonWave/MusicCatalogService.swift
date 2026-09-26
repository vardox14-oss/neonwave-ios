import Foundation

enum MusicCatalogService {
    private struct DeezerSearchResponse: Decodable {
        struct Item: Decodable {
            let id: Int
            let title: String
            let duration: Int
            let preview: String?
            struct Artist: Decodable { let name: String }
            let artist: Artist
            struct Album: Decodable {
                let id: Int
                let title: String
                let cover_big: String?
                let cover_xl: String?
                let cover_medium: String?
            }
            let album: Album?
        }
        let data: [Item]?
    }

    private struct DeezerAlbumResponse: Decodable {
        struct Item: Decodable {
            let id: Int
            let title: String
            let nb_tracks: Int?
            struct Artist: Decodable { let name: String }
            let artist: Artist
            let cover_big: String?
            let cover_xl: String?
            let cover_medium: String?
        }
        let data: [Item]?
    }

    private struct DeezerAlbumTracksResponse: Decodable {
        struct TrackItem: Decodable {
            let id: Int
            let title: String
            let duration: Int
            let preview: String?
            struct Artist: Decodable { let name: String }
            let artist: Artist
        }
        let data: [TrackItem]?
    }

    private struct ITunesResponse: Decodable {
        struct Item: Decodable {
            let trackId: Int?
            let collectionId: Int?
            let trackName: String?
            let collectionName: String?
            let artistName: String?
            let previewUrl: String?
            let artworkUrl100: String?
            let trackTimeMillis: Int?
        }
        let results: [Item]?
    }

    static func searchTracks(_ query: String) async -> [Track] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }

        // 1. Try Deezer API
        if let url = URL(string: "https://api.deezer.com/search?q=\(encoded)&limit=30") {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if (response as? HTTPURLResponse)?.statusCode == 200,
                   let decoded = try? JSONDecoder().decode(DeezerSearchResponse.self, from: data),
                   let items = decoded.data, !items.isEmpty {
                    return items.map { item in
                        let cover = item.album?.cover_xl ?? item.album?.cover_big ?? item.album?.cover_medium
                        return Track(
                            id: "dz-\(item.id)",
                            title: item.title,
                            artist: item.artist.name,
                            duration: Double(item.duration),
                            album: item.album?.title,
                            artworkURL: cover,
                            streamURL: item.preview
                        )
                    }
                }
            } catch { }
        }

        // 2. Fallback to iTunes API
        if let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=30") {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let decoded = try? JSONDecoder().decode(ITunesResponse.self, from: data),
                   let items = decoded.results {
                    return items.compactMap { item in
                        guard let id = item.trackId, let title = item.trackName, let artist = item.artistName else { return nil }
                        let cover = item.artworkUrl100?.replacingOccurrences(of: "100x100", with: "600x600")
                        let dur = Double(item.trackTimeMillis ?? 0) / 1000.0
                        return Track(
                            id: "it-\(id)",
                            title: title,
                            artist: artist,
                            duration: dur,
                            album: item.collectionName,
                            artworkURL: cover,
                            streamURL: item.previewUrl
                        )
                    }
                }
            } catch { }
        }

        return []
    }

    static func searchAlbums(_ query: String) async -> [Album] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }

        if let url = URL(string: "https://api.deezer.com/search/album?q=\(encoded)&limit=20") {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let decoded = try? JSONDecoder().decode(DeezerAlbumResponse.self, from: data),
                   let items = decoded.data, !items.isEmpty {
                    return items.map { item in
                        let cover = item.cover_xl ?? item.cover_big ?? item.cover_medium
                        return Album(
                            id: "dz-\(item.id)",
                            title: item.title,
                            artist: item.artist.name,
                            coverURL: cover,
                            trackCount: item.nb_tracks
                        )
                    }
                }
            } catch { }
        }

        return []
    }

    static func fetchAlbumTracks(albumId: String, albumTitle: String, artistName: String, coverURL: String?) async -> [Track] {
        let cleanId = albumId.replacingOccurrences(of: "dz-", with: "")
        guard let url = URL(string: "https://api.deezer.com/album/\(cleanId)/tracks?limit=50") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let decoded = try? JSONDecoder().decode(DeezerAlbumTracksResponse.self, from: data),
               let items = decoded.data {
                return items.map { item in
                    Track(
                        id: "dz-\(item.id)",
                        title: item.title,
                        artist: item.artist.name.isEmpty ? artistName : item.artist.name,
                        duration: Double(item.duration),
                        album: albumTitle,
                        artworkURL: coverURL,
                        streamURL: item.preview
                    )
                }
            }
        } catch { }
        return []
    }
}
