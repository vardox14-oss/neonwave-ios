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
        let title: String?
        let artist: String?
        let spotifyId: String?
        let thumbnail: String?
    }

    struct ResolvedMedia {
        let videoId: String
        let duration: Double?
        let title: String?
        let artist: String?
        let spotifyId: String?
        let thumbnail: String?
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
                authenticated: false,
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

    static func nativeStreamURL(videoId: String) async -> URL? {
        // Resolve and consume the signed media URL on the same device/network.
        // This avoids the VPS IP being used for YouTube media extraction.
        if let directURL = await deviceAudioURL(videoId: videoId) { return directURL }
        guard !Task.isCancelled else { return nil }
        guard let baseURL = AppConfiguration.apiURL,
              let response: StreamTicketResponse = try? await APIClient().call(
                "api/music/streams/\(videoId)/ticket",
                method: "POST"
              ) else { return nil }
        return URL(string: response.path, relativeTo: baseURL)?.absoluteURL
    }

    static func selectDeviceAudioURL(_ data: Data, videoId: String) -> URL? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = root["playabilityStatus"] as? [String: Any], status["status"] as? String == "OK",
              let details = root["videoDetails"] as? [String: Any], details["videoId"] as? String == videoId,
              let streaming = root["streamingData"] as? [String: Any],
              let formats = streaming["adaptiveFormats"] as? [[String: Any]] else { return nil }
        let audio = formats.filter {
            ($0["mimeType"] as? String)?.hasPrefix("audio/mp4") == true && $0["drmFamilies"] == nil
        }.sorted {
            if ($0["itag"] as? Int == 140) != ($1["itag"] as? Int == 140) { return $0["itag"] as? Int == 140 }
            return ($0["bitrate"] as? Int ?? 0) > ($1["bitrate"] as? Int ?? 0)
        }
        for format in audio {
            guard let raw = format["url"] as? String, let url = URL(string: raw),
                  url.scheme == "https", let host = url.host,
                  host.hasSuffix(".googlevideo.com") else { continue }
            return url
        }
        return nil
    }

    private static func deviceAudioURL(videoId: String) async -> URL? {
        guard videoId.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        do {
            var watch = URLRequest(url: URL(string: "https://www.youtube.com/watch?v=\(videoId)")!)
            watch.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            watch.setValue("en-us,en;q=0.5", forHTTPHeaderField: "Accept-Language")
            watch.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
            let (watchData, watchResponse) = try await session.data(for: watch)
            guard !Task.isCancelled, (watchResponse as? HTTPURLResponse)?.statusCode == 200,
                  let html = String(data: watchData, encoding: .utf8) else { return nil }
            var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!)
            request.httpMethod = "POST"
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("101", forHTTPHeaderField: "X-Youtube-Client-Name")
            request.setValue("1.02", forHTTPHeaderField: "X-Youtube-Client-Version")
            request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
            let visitorPattern = try NSRegularExpression(pattern: #""VISITOR_DATA"\s*:\s*"([^"]+)""#)
            if let match = visitorPattern.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                request.setValue(String(html[range]), forHTTPHeaderField: "X-Goog-Visitor-Id")
            }
            let client: [String: Any] = [
                "clientName": "VISIONOS", "clientVersion": "1.02",
                "deviceMake": "Apple", "deviceModel": "RealityDevice17,1",
                "userAgent": userAgent, "osName": "visionOS", "osVersion": "26.5.23O471",
                "hl": "en", "timeZone": "UTC", "utcOffsetMinutes": 0
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "context": ["client": client], "videoId": videoId,
                "contentCheckOk": true, "racyCheckOk": true
            ])
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200,
                  let url = selectDeviceAudioURL(data, videoId: videoId) else { return nil }
            // Check the actual audio before handing the URL to AVPlayer/downloads.
            // Use a fresh request without the YouTube guest session, like AVPlayer.
            var probe = URLRequest(url: url)
            probe.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
            let (bytes, probeResponse) = try await URLSession.shared.data(for: probe)
            guard !Task.isCancelled, let http = probeResponse as? HTTPURLResponse,
                  http.statusCode == 206, bytes.count == 1024,
                  http.mimeType?.hasPrefix("audio/") == true else { return nil }
            return url
        } catch { return nil }
    }

    static func resolveTrackMedia(title: String, artist: String, duration: Double = 0, spotifyId: String? = nil) async -> ResolvedMedia? {
        let key = "\(artist.lowercased())|\(title.lowercased())"

        if AppConfiguration.apiURL != nil {
            let path = (spotifyId != nil && spotifyId!.count == 22) ? "api/music/resolve/\(spotifyId!)" : "api/music/resolve-by-metadata"
            let query = [
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "artist", value: artist),
                URLQueryItem(name: "durationMs", value: String(Int(duration * 1000)))
            ]
            if let resolved: ResolveResponse = try? await APIClient().call(path, authenticated: false, queryItems: query), !resolved.videoId.isEmpty {
                ytCache[key] = resolved.videoId
                return ResolvedMedia(
                    videoId: resolved.videoId,
                    duration: resolved.duration,
                    title: resolved.title,
                    artist: resolved.artist,
                    spotifyId: resolved.spotifyId ?? spotifyId,
                    thumbnail: resolved.thumbnail
                )
            }
        }

        if let vid = await resolveYouTubeId(title: title, artist: artist, duration: duration, spotifyId: spotifyId) {
            return ResolvedMedia(videoId: vid, duration: duration > 0 ? duration : nil, title: title, artist: artist, spotifyId: spotifyId, thumbnail: nil)
        }
        return nil
    }

    static func resolveYouTubeId(title: String, artist: String, duration: Double = 0, spotifyId: String? = nil) async -> String? {
        let key = "\(artist.lowercased())|\(title.lowercased())"
        if let cached = ytCache[key] { return cached }

        // 1. Prioritize backend resolution when server is configured
        if AppConfiguration.apiURL != nil {
            let path = (spotifyId != nil && spotifyId!.count == 22) ? "api/music/resolve/\(spotifyId!)" : "api/music/resolve-by-metadata"
            let query = [
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "artist", value: artist),
                URLQueryItem(name: "durationMs", value: String(Int(duration * 1000)))
            ]
            if let resolved: ResolveResponse = try? await APIClient().call(path, authenticated: false, queryItems: query), !resolved.videoId.isEmpty {
                ytCache[key] = resolved.videoId
                return resolved.videoId
            }
        }

        // 2. Autonomous client fallback (ensures full playback in simulator, Appetize, and standalone)
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

    static func bestYouTubeCandidate(_ candidates: [YouTubeCandidate], title: String, artist: String, duration: Double, excludeVideoId: String? = nil) -> YouTubeCandidate? {
        let list = candidates.filter { $0.videoId != excludeVideoId }
        return list.max { youtubeScore($0, title: title, artist: artist, duration: duration) < youtubeScore($1, title: title, artist: artist, duration: duration) }
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
        if combined.contains("official audio") || combined.contains("audio officiel") { score += 40 }
        if candidateChannel.contains("topic") { score += 15 }
        if combined.contains("official") || combined.contains("officiel") { score += 12 }
        let requestedSpecialTerms = ["live", "remix", "sped up", "slowed", "nightcore", "karaoke", "cover"]
        for term in requestedSpecialTerms where candidateTitle.contains(term) && !wantedTitle.contains(term) { score -= 85 }

        if duration > 0, let candidateDuration = candidate.duration {
            let delta = abs(duration - candidateDuration)
            if delta <= 3 { score += 95 }
            else if delta <= 8 { score += 60 }
            else if delta <= 14 { score += 25 }
            else if delta > 40 { score -= 450 } // Reject 5m music video clip for 3m track
            else if delta > 25 { score -= 180 }
            else if delta > 15 { score -= 50 }
        }

        let clipTerms = ["clip", "court metrage", "official video", "music video", "film"]
        if let candidateDuration = candidate.duration, duration > 0, abs(duration - candidateDuration) > 15 {
            for term in clipTerms where combined.contains(term) {
                score -= 160
            }
        }
        return score
    }

    static func resolveAlternativeYouTubeId(title: String, artist: String, excludeVideoId: String) async -> String? {
        let cleanTitle = title
            .replacingOccurrences(of: "(feat.", with: "")
            .replacingOccurrences(of: "(ft.", with: "")
            .replacingOccurrences(of: "feat.", with: "")
            .replacingOccurrences(of: "ft.", with: "")
        let query = "\(artist) \(cleanTitle) lyrics paroles".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://www.youtube.com/results?search_query=\(query)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("SOCS=CAESEwgDEgk0ODE3Nzk3MjQaAmVuIAEaBgiA_LyaBg; CONSENT=YES+", forHTTPHeaderField: "Cookie")
        request.setValue("fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 6

        if let (data, _) = try? await URLSession.shared.data(for: request),
           let html = String(data: data, encoding: .utf8) {
            let candidates = parseYouTubeCandidates(html).filter { $0.videoId != excludeVideoId && !$0.channel.lowercased().contains("topic") }
            if let best = candidates.first {
                return best.videoId
            }
        }
        return nil
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

    struct ArtistProfileResponse: Decodable {
        let item: ArtistProfileData.Item?
        let spotifyEnabled: Bool?
    }

    enum ArtistProfileData {
        struct ArtistItem: Decodable {
            let spotifyId: String?
            let name: String
            let imageUrl: String?
            let spotifyUrl: String?
            let genres: [String]?
            let popularity: Int?
            let followers: Int?
            let source: String?
        }

        struct DiscographyItem: Identifiable, Decodable {
            var id: String { "\(name)-\(releaseDate ?? "")-\(spotifyId ?? deezerId ?? "")" }
            let name: String
            let imageUrl: String?
            let releaseDate: String?
            let type: String?
            let group: String?
            let spotifyId: String?
            let deezerId: String?
        }

        struct Discography: Decodable {
            let popular: [DiscographyItem]?
            let albums: [DiscographyItem]?
            let singles: [DiscographyItem]?
        }

        struct RelatedArtist: Identifiable, Decodable {
            var id: String { spotifyId.map { "sp-\($0)" } ?? name }
            let spotifyId: String?
            let name: String
            let imageUrl: String?
            let followers: Int?
        }

        struct TrackItem: Decodable {
            let id: String?
            let title: String
            let artist: String?
            let album: String?
            let thumbnail: String?
            let duration: Double?
            let durationMs: Double?
            let spotifyId: String?
            let videoId: String?
        }

        struct Item: Decodable {
            let artist: ArtistItem?
            let topTracks: [TrackItem]?
            let discography: Discography?
            let relatedArtists: [RelatedArtist]?
        }
    }

    static func fetchArtistProfile(name: String, spotifyId: String? = nil) async -> ArtistProfileData.Item? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }

        if AppConfiguration.apiURL != nil {
            var query = [URLQueryItem(name: "name", value: cleanName)]
            if let spId = spotifyId, spId.count == 22 {
                query.append(URLQueryItem(name: "spotifyId", value: spId))
            }
            if let response: ArtistProfileResponse = try? await APIClient().call(
                "api/spotify/artist-profile",
                authenticated: false,
                queryItems: query
            ), let item = response.item {
                return item
            }
        }

        return await fetchDeezerArtistFallback(name: cleanName)
    }

    private static func fetchDeezerArtistFallback(name: String) async -> ArtistProfileData.Item? {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchUrl = URL(string: "https://api.deezer.com/search/artist?q=\(encoded)&limit=1") else { return nil }

        struct SearchResult: Decodable {
            struct Artist: Decodable {
                let id: Int
                let name: String
                let picture_xl: String?
                let nb_fan: Int?
            }
            let data: [Artist]?
        }

        guard let (data, _) = try? await URLSession.shared.data(from: searchUrl),
              let search = try? JSONDecoder().decode(SearchResult.self, from: data),
              let found = search.data?.first else { return nil }

        let artistId = found.id
        async let topTask = fetchDeezerArtistTopTracks(artistId: artistId, artistName: found.name)
        async let albumsTask = fetchDeezerArtistAlbums(artistId: artistId)
        async let relatedTask = fetchDeezerRelatedArtists(artistId: artistId)

        let (top, discography, related) = await (topTask, albumsTask, relatedTask)

        let artistItem = ArtistProfileData.ArtistItem(
            spotifyId: nil,
            name: found.name,
            imageUrl: found.picture_xl,
            spotifyUrl: nil,
            genres: nil,
            popularity: nil,
            followers: found.nb_fan,
            source: "deezer"
        )

        return ArtistProfileData.Item(
            artist: artistItem,
            topTracks: top,
            discography: discography,
            relatedArtists: related
        )
    }

    private static func fetchDeezerArtistTopTracks(artistId: Int, artistName: String) async -> [ArtistProfileData.TrackItem] {
        guard let url = URL(string: "https://api.deezer.com/artist/\(artistId)/top?limit=10") else { return [] }
        struct TopResponse: Decodable {
            struct Item: Decodable {
                let id: Int
                let title: String
                let duration: Double
                struct Album: Decodable {
                    let title: String?
                    let cover_xl: String?
                    let cover_big: String?
                }
                let album: Album?
            }
            let data: [Item]?
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let res = try? JSONDecoder().decode(TopResponse.self, from: data),
              let items = res.data else { return [] }

        return items.map {
            ArtistProfileData.TrackItem(
                id: "dz-\($0.id)",
                title: $0.title,
                artist: artistName,
                album: $0.album?.title,
                thumbnail: $0.album?.cover_xl ?? $0.album?.cover_big,
                duration: $0.duration,
                durationMs: $0.duration * 1000,
                spotifyId: nil,
                videoId: nil
            )
        }
    }

    private static func fetchDeezerArtistAlbums(artistId: Int) async -> ArtistProfileData.Discography {
        guard let url = URL(string: "https://api.deezer.com/artist/\(artistId)/albums?limit=25") else {
            return ArtistProfileData.Discography(popular: [], albums: [], singles: [])
        }
        struct AlbumsResponse: Decodable {
            struct Item: Decodable {
                let id: Int
                let title: String
                let cover_xl: String?
                let release_date: String?
                let record_type: String?
            }
            let data: [Item]?
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let res = try? JSONDecoder().decode(AlbumsResponse.self, from: data),
              let items = res.data else {
            return ArtistProfileData.Discography(popular: [], albums: [], singles: [])
        }

        let all = items.map {
            ArtistProfileData.DiscographyItem(
                name: $0.title,
                imageUrl: $0.cover_xl,
                releaseDate: $0.release_date,
                type: $0.record_type == "single" ? "single" : "album",
                group: $0.record_type,
                spotifyId: nil,
                deezerId: "\($0.id)"
            )
        }
        let albums = all.filter { $0.type == "album" }
        let singles = all.filter { $0.type == "single" }
        return ArtistProfileData.Discography(popular: all, albums: albums, singles: singles)
    }

    private static func fetchDeezerRelatedArtists(artistId: Int) async -> [ArtistProfileData.RelatedArtist] {
        guard let url = URL(string: "https://api.deezer.com/artist/\(artistId)/related?limit=8") else { return [] }
        struct RelatedResponse: Decodable {
            struct Item: Decodable {
                let id: Int
                let name: String
                let picture_xl: String?
                let nb_fan: Int?
            }
            let data: [Item]?
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let res = try? JSONDecoder().decode(RelatedResponse.self, from: data),
              let items = res.data else { return [] }

        return items.map {
            ArtistProfileData.RelatedArtist(
                spotifyId: nil,
                name: $0.name,
                imageUrl: $0.picture_xl,
                followers: $0.nb_fan
            )
        }
    }

    // ─── Spotify Playlist Import ─────────────────────────────────────────────

    struct SpotifyPlaylistImport {
        let name: String
        let description: String
        let imageUrl: String
        let ownerName: String
        let totalTracks: Int
        let tracks: [Track]
    }

    private struct SpotifyImportResponse: Decodable {
        struct ImportedTrack: Decodable {
            let id: String
            let spotifyId: String?
            let title: String
            let artist: String
            let album: String?
            let duration: Double
            let thumbnail: String?
        }
        let name: String
        let description: String?
        let imageUrl: String?
        let ownerName: String?
        let totalTracks: Int?
        let tracks: [ImportedTrack]
    }

    static func importSpotifyPlaylist(_ urlString: String) async throws -> SpotifyPlaylistImport {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MessageError("URL Spotify invalide.") }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let response: SpotifyImportResponse = try? await APIClient().call(
                "api/spotify/import-playlist",
                authenticated: false,
                queryItems: [URLQueryItem(name: "url", value: encoded)]
              ) else {
            throw MessageError("Impossible de charger la playlist. Vérifiez l'URL et votre connexion.")
        }

        let tracks = response.tracks.map { item in
            Track(
                id: item.id,
                title: item.title,
                artist: item.artist,
                duration: item.duration,
                album: item.album,
                artworkURL: item.thumbnail,
                streamURL: nil,
                videoId: nil,
                spotifyId: item.spotifyId
            )
        }

        return SpotifyPlaylistImport(
            name: response.name,
            description: response.description ?? "",
            imageUrl: response.imageUrl ?? "",
            ownerName: response.ownerName ?? "",
            totalTracks: response.totalTracks ?? tracks.count,
            tracks: tracks
        )
    }

}
