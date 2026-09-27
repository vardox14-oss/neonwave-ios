import Foundation

enum MusicCatalogService {
    private struct ServerSearchResponse: Decodable {
        struct Item: Decodable {
            let id: String?
            let videoId: String?
            let spotifyId: String?
            let title: String
            let artist: String
            let album: String?
            let thumbnail: String?
            let duration: Double?
            let durationMs: Double?
            let streamUrl: String?
        }
        let items: [Item]
    }

    private struct ResolveResponse: Decodable {
        let videoId: String
        let duration: Double?
    }

    private struct StreamTicketResponse: Decodable {
        let path: String
    }

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

        // Same Spotify-first catalogue as the desktop app. Keeping spotifyId is
        // essential: it is also the key used to request the real Spotify Canvas.
        if AppConfiguration.apiURL != nil,
           let response: ServerSearchResponse = try? await APIClient().call(
                "api/music/search",
                queryItems: [URLQueryItem(name: "q", value: trimmed), URLQueryItem(name: "filter", value: "music")]
           ), !response.items.isEmpty {
            return response.items.map { item in
                let duration = item.duration ?? ((item.durationMs ?? 0) / 1000)
                let stableID = item.spotifyId.map { "sp-\($0)" } ?? item.videoId.map { "yt-\($0)" } ?? item.id ?? UUID().uuidString
                return Track(
                    id: stableID,
                    title: item.title,
                    artist: item.artist,
                    duration: duration,
                    album: item.album,
                    artworkURL: item.thumbnail,
                    streamURL: item.streamUrl,
                    videoId: item.videoId,
                    spotifyId: item.spotifyId
                )
            }
        }

        // 1. Try Deezer API
        if let url = URL(string: "https://api.deezer.com/search?q=\(encoded)&limit=30") {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if (response as? HTTPURLResponse)?.statusCode == 200,
                   let decoded = try? JSONDecoder().decode(DeezerSearchResponse.self, from: data),
                   let items = decoded.data, !items.isEmpty {
                    return items.compactMap { item in
                        guard let preview = item.preview, !preview.isEmpty, URL(string: preview) != nil else { return nil }
                        let cover = item.album?.cover_xl ?? item.album?.cover_big ?? item.album?.cover_medium
                        return Track(
                            id: "dz-\(item.id)",
                            title: item.title,
                            artist: item.artist.name,
                            duration: Double(item.duration),
                            album: item.album?.title,
                            artworkURL: cover,
                            streamURL: preview
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
                        guard let id = item.trackId, let title = item.trackName, let artist = item.artistName,
                              let preview = item.previewUrl, !preview.isEmpty, URL(string: preview) != nil else { return nil }
                        let cover = item.artworkUrl100?.replacingOccurrences(of: "100x100", with: "600x600")
                        let dur = Double(item.trackTimeMillis ?? 0) / 1000.0
                        return Track(
                            id: "it-\(id)",
                            title: title,
                            artist: artist,
                            duration: dur,
                            album: item.collectionName,
                            artworkURL: cover,
                            streamURL: preview
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
                return items.compactMap { item in
                    guard let preview = item.preview, !preview.isEmpty, URL(string: preview) != nil else { return nil }
                    return Track(
                        id: "dz-\(item.id)",
                        title: item.title,
                        artist: item.artist.name.isEmpty ? artistName : item.artist.name,
                        duration: Double(item.duration),
                        album: albumTitle,
                        artworkURL: coverURL,
                        streamURL: preview
                    )
                }
            }
        } catch { }
        return []
    }

    private static var ytCache: [String: String] = [:]

    static func nativeStreamURL(videoId: String) async -> URL? {
        guard let baseURL = AppConfiguration.apiURL,
              let response: StreamTicketResponse = try? await APIClient().call(
                "api/music/streams/\(videoId)/ticket",
                method: "POST"
              ) else { return nil }
        return URL(string: response.path, relativeTo: baseURL)?.absoluteURL
    }

    static func resolveYouTubeId(title: String, artist: String, duration: Double = 0, spotifyId: String? = nil) async -> String? {
        let key = "\(artist.lowercased())|\(title.lowercased())"
        if let cached = ytCache[key] { return cached }

        guard AppConfiguration.apiURL != nil else { return nil }

        let path = spotifyId.map { "api/music/resolve/\($0)" } ?? "api/music/resolve-by-metadata"
        let query = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "durationMs", value: String(Int(duration * 1000)))
        ]
        if let resolved: ResolveResponse = try? await APIClient().call(path, queryItems: query), !resolved.videoId.isEmpty {
            ytCache[key] = resolved.videoId
            return resolved.videoId
        }
        return nil
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
