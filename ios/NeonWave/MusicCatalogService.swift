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

    static func resolveYouTubeId(title: String, artist: String) async -> String? {
        let key = "\(artist.lowercased())|\(title.lowercased())"
        if let cached = ytCache[key] { return cached }

        let cleanTitle = title
            .replacingOccurrences(of: "(feat.", with: "")
            .replacingOccurrences(of: "(ft.", with: "")
            .replacingOccurrences(of: "feat.", with: "")
            .replacingOccurrences(of: "ft.", with: "")
        let query = "\(artist) \(cleanTitle)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://www.youtube.com/results?search_query=\(query)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("SOCS=CAESEwgDEgk0ODE3Nzk3MjQaAmVuIAEaBgiA_LyaBg; CONSENT=YES+", forHTTPHeaderField: "Cookie")
        request.setValue("fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 8

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            let ns = html as NSString
            let fullRange = NSRange(location: 0, length: ns.length)

            let pattern1 = "\"videoId\":\"([A-Za-z0-9_-]{11})\""
            if let regex1 = try? NSRegularExpression(pattern: pattern1),
               let match = regex1.firstMatch(in: html, range: fullRange),
               match.numberOfRanges > 1 {
                let vid = ns.substring(with: match.range(at: 1))
                ytCache[key] = vid
                return vid
            }

            let pattern2 = "watch\\?v=([A-Za-z0-9_-]{11})"
            if let regex2 = try? NSRegularExpression(pattern: pattern2),
               let match = regex2.firstMatch(in: html, range: fullRange),
               match.numberOfRanges > 1 {
                let vid = ns.substring(with: match.range(at: 1))
                ytCache[key] = vid
                return vid
            }
        } catch { }
        return nil
    }
}
