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

    struct YouTubeCandidate: Equatable {
        let videoId: String
        let title: String
        let channel: String
        let duration: Double?
    }

    static func resolveYouTubeId(title: String, artist: String, duration: Double = 0, spotifyId: String? = nil) async -> String? {
        let key = "\(artist.lowercased())|\(title.lowercased())"
        if let cached = ytCache[key] { return cached }

        if AppConfiguration.apiURL != nil {
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
        }

        let cleanTitle = title
            .replacingOccurrences(of: "(feat.", with: "")
            .replacingOccurrences(of: "(ft.", with: "")
            .replacingOccurrences(of: "feat.", with: "")
            .replacingOccurrences(of: "ft.", with: "")
        let query = "\(artist) \(cleanTitle) official audio".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
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

            let candidates = parseYouTubeCandidates(html)
            if let best = bestYouTubeCandidate(candidates, title: title, artist: artist, duration: duration) {
                ytCache[key] = best.videoId
                return best.videoId
            }

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

    static func bestYouTubeCandidate(_ candidates: [YouTubeCandidate], title: String, artist: String, duration: Double) -> YouTubeCandidate? {
        candidates.max { youtubeScore($0, title: title, artist: artist, duration: duration) < youtubeScore($1, title: title, artist: artist, duration: duration) }
    }

    private static func youtubeScore(_ candidate: YouTubeCandidate, title: String, artist: String, duration: Double) -> Double {
        let wantedTitle = normalized(title)
        let wantedArtist = normalized(artist)
        let candidateTitle = normalized(candidate.title)
        let candidateChannel = normalized(candidate.channel)
        let combined = candidateTitle + " " + candidateChannel
        let wantedTokens = Set(wantedTitle.split(separator: " ").map(String.init).filter { $0.count > 1 })
        let candidateTokens = Set(candidateTitle.split(separator: " ").map(String.init))
        var score = 0.0
        if candidateTitle.contains(wantedTitle) { score += 80 }
        if !wantedTokens.isEmpty { score += 60 * Double(wantedTokens.intersection(candidateTokens).count) / Double(wantedTokens.count) }
        if combined.contains(wantedArtist) { score += 55 }
        if combined.contains("official audio") || combined.contains("audio officiel") { score += 35 }
        if candidateChannel.contains("topic") { score += 24 }
        if combined.contains("official") || combined.contains("officiel") { score += 12 }
        let requestedSpecialTerms = ["live", "remix", "sped up", "slowed", "nightcore", "karaoke", "cover"]
        for term in requestedSpecialTerms where candidateTitle.contains(term) && !wantedTitle.contains(term) { score -= 65 }
        if duration > 0, let candidateDuration = candidate.duration {
            let delta = abs(duration - candidateDuration)
            if delta <= 2 { score += 65 }
            else if delta <= 5 { score += 48 }
            else if delta <= 12 { score += 24 }
            else if delta > 30 { score -= min(90, delta) }
        }
        return score
    }

    static func parseYouTubeCandidates(_ html: String) -> [YouTubeCandidate] {
        let ns = html as NSString
        let pattern = #"\"videoId\":\"([A-Za-z0-9_-]{11})\""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var candidates: [YouTubeCandidate] = []
        var seen = Set<String>()
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).prefix(80) {
            let id = ns.substring(with: match.range(at: 1))
            guard seen.insert(id).inserted else { continue }
            let start = match.range.location
            let length = min(5000, ns.length - start)
            let window = ns.substring(with: NSRange(location: start, length: length))
            let title = firstJSONText(in: window, keys: ["title"]) ?? ""
            guard !title.isEmpty else { continue }
            let channel = firstJSONText(in: window, keys: ["ownerText", "longBylineText", "shortBylineText"]) ?? ""
            let durationText = firstSimpleText(in: window, key: "lengthText")
            candidates.append(YouTubeCandidate(videoId: id, title: title, channel: channel, duration: durationText.flatMap(parseClock)))
        }
        return candidates
    }

    private static func firstJSONText(in value: String, keys: [String]) -> String? {
        for key in keys {
            let escapedKey = NSRegularExpression.escapedPattern(for: key)
            let patterns = [
                "\\\"\(escapedKey)\\\":\\{\\\"runs\\\":\\[\\{\\\"text\\\":\\\"((?:\\\\.|[^\\\"])*)\\\"",
                "\\\"\(escapedKey)\\\":\\{\\\"simpleText\\\":\\\"((?:\\\\.|[^\\\"])*)\\\""
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                      let range = Range(match.range(at: 1), in: value) else { continue }
                return decodeJSONString(String(value[range]))
            }
        }
        return nil
    }

    private static func firstSimpleText(in value: String, key: String) -> String? {
        firstJSONText(in: value, keys: [key])
    }

    private static func decodeJSONString(_ escaped: String) -> String {
        let wrapped = "\"\(escaped)\""
        return (try? JSONDecoder().decode(String.self, from: Data(wrapped.utf8))) ?? escaped
    }

    private static func parseClock(_ value: String) -> Double? {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reversed().enumerated().reduce(0) { $0 + $1.element * pow(60, Double($1.offset)) }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
