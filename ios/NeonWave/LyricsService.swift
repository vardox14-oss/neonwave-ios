import Foundation

struct LyricsResult {
    let lines: [LyricLine]
    let plain: String?
    let sourceDuration: Double?
}

enum LyricsService {
    struct LRCLIBResponse: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private struct ServerLyricsResponse: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let duration: Double?
    }

    static func fetchLyrics(title: String, artist: String, duration: Double? = nil) async -> LyricsResult {
        if AppConfiguration.apiURL != nil {
            var query = [
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "artist", value: artist)
            ]
            if let duration, duration > 0 {
                query.append(URLQueryItem(name: "duration", value: String(Int(duration))))
            }
            if let response: ServerLyricsResponse = try? await APIClient().call("api/music/lyrics", authenticated: false, queryItems: query) {
                if let synced = response.syncedLyrics, !synced.isEmpty {
                    let parsed = parseLRC(synced, insertInterludes: true)
                    if !parsed.isEmpty {
                        return LyricsResult(lines: parsed, plain: response.plainLyrics, sourceDuration: response.duration)
                    }
                }
                if let plain = response.plainLyrics, !plain.isEmpty {
                    return LyricsResult(lines: [], plain: plain, sourceDuration: response.duration)
                }
            }
        }

        let primaryResult = await queryLRCLIB(title: title, artist: artist, duration: duration)
        if !primaryResult.lines.isEmpty {
            return primaryResult
        }

        let cleanedT = cleanTitle(title)
        let cleanedA = cleanArtist(artist)
        if cleanedT != title || cleanedA != artist {
            let fallbackResult = await queryLRCLIB(title: cleanedT, artist: cleanedA, duration: duration)
            if !fallbackResult.lines.isEmpty {
                return fallbackResult
            }
            if primaryResult.plain != nil {
                return primaryResult
            }
            return fallbackResult
        }

        return primaryResult
    }

    private static func queryLRCLIB(title: String, artist: String, duration: Double? = nil) async -> LyricsResult {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        guard let url = components.url else { return LyricsResult(lines: [], plain: nil, sourceDuration: nil) }

        var request = URLRequest(url: url)
        request.setValue("NeonWave/1.1 (iOS; lyrics sync)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let candidates = try? JSONDecoder().decode([LRCLIBResponse].self, from: data),
                  let chosen = bestCandidate(candidates, title: title, artist: artist, duration: duration) else {
                return LyricsResult(lines: [], plain: nil, sourceDuration: nil)
            }
            if let synced = chosen.syncedLyrics, !synced.isEmpty {
                let parsed = parseLRC(synced, insertInterludes: true)
                if !parsed.isEmpty {
                    return LyricsResult(lines: parsed, plain: chosen.plainLyrics, sourceDuration: chosen.duration)
                }
            }
            return LyricsResult(lines: [], plain: chosen.plainLyrics, sourceDuration: chosen.duration)
        } catch {
            return LyricsResult(lines: [], plain: nil, sourceDuration: nil)
        }
    }

    static func cleanTitle(_ title: String) -> String {
        var cleaned = title
        let patterns = [
            #"\s*[\(\[](?:clip|officiel|official|audio|video|lyrics?|paroles|version|remix|hd|4k|feat\.?|ft\.).*?[\)\]]"#,
            #"\s*-\s*(?:clip|officiel|official|audio|video|lyrics?|paroles).*$"#
        ]
        for pattern in patterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanArtist(_ artist: String) -> String {
        let parts = artist.components(separatedBy: CharacterSet(charactersIn: ",&/"))
        let first = parts.first ?? artist
        let featCleaned = first.replacingOccurrences(of: #"(?i)\s+(?:feat\.?|ft\.?).*$"#, with: "", options: .regularExpression)
        return featCleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func bestCandidate(_ candidates: [LRCLIBResponse], title: String, artist: String, duration: Double?) -> LRCLIBResponse? {
        let wantedTitle = normalized(title)
        let wantedArtist = normalized(artist)
        let valid = candidates.filter { !($0.syncedLyrics ?? "").isEmpty || !($0.plainLyrics ?? "").isEmpty }
        guard !valid.isEmpty else { return nil }

        // ALWAYS prioritize candidates with synced lyrics: karaoke/synchronized experience is primary!
        let synced = valid.filter { !($0.syncedLyrics ?? "").isEmpty }
        if !synced.isEmpty {
            return synced.max {
                score($0, title: wantedTitle, artist: wantedArtist, duration: duration) <
                score($1, title: wantedTitle, artist: wantedArtist, duration: duration)
            }
        }

        return valid.max {
            score($0, title: wantedTitle, artist: wantedArtist, duration: duration) <
            score($1, title: wantedTitle, artist: wantedArtist, duration: duration)
        }
    }

    private static func score(_ candidate: LRCLIBResponse, title: String, artist: String, duration: Double?) -> Double {
        let candidateTitle = normalized(candidate.trackName ?? "")
        let candidateArtist = normalized(candidate.artistName ?? "")
        var value = 0.0
        if candidateTitle == title { value += 100 }
        else if candidateTitle.contains(title) || title.contains(candidateTitle) { value += 55 }
        let titleTokens = Set(title.split(separator: " ").map(String.init).filter { $0.count > 1 })
        let candidateTokens = Set(candidateTitle.split(separator: " ").map(String.init))
        if !titleTokens.isEmpty { value += 45 * Double(titleTokens.intersection(candidateTokens).count) / Double(titleTokens.count) }

        if candidateArtist == artist { value += 65 }
        else if candidateArtist.contains(artist) || artist.contains(candidateArtist) { value += 50 }
        else {
            let artistTokens = Set(artist.split(separator: " ").map(String.init).filter { $0.count > 1 })
            let candArtistTokens = Set(candidateArtist.split(separator: " ").map(String.init))
            if !artistTokens.isEmpty && !artistTokens.intersection(candArtistTokens).isEmpty {
                value += 40
            }
        }

        if let duration, duration > 0, let candidateDuration = candidate.duration, candidateDuration > 0 {
            let delta = abs(duration - candidateDuration)
            if delta <= 1.5 { value += 70 }
            else if delta <= 4 { value += 52 }
            else if delta <= 9 { value += 28 }
            else if delta > 20 { value -= min(80, delta) }
        }
        if !((candidate.syncedLyrics ?? "").isEmpty) { value += 150 }
        return value
    }

    static func parseLRC(_ lrc: String, insertInterludes: Bool = false) -> [LyricLine] {
        let timePattern = #"\[(\d{1,3}):(\d{2}(?:\.\d{1,3})?)\]"#
        guard let regex = try? NSRegularExpression(pattern: timePattern) else { return [] }
        let offsetPattern = #"\[offset:([+-]?\d+)\]"#
        var offset = 0.0
        if let offsetRegex = try? NSRegularExpression(pattern: offsetPattern, options: [.caseInsensitive]),
           let match = offsetRegex.firstMatch(in: lrc, range: NSRange(lrc.startIndex..., in: lrc)),
           let range = Range(match.range(at: 1), in: lrc), let milliseconds = Double(lrc[range]) {
            offset = milliseconds / 1000
        }

        var result: [LyricLine] = []
        for rawLine in lrc.components(separatedBy: .newlines) {
            let matches = regex.matches(in: rawLine, range: NSRange(rawLine.startIndex..., in: rawLine))
            guard !matches.isEmpty else { continue }
            let lastRange = matches.map(\.range).max { ($0.location + $0.length) < ($1.location + $1.length) }
            guard let lastRange, let textRange = Range(NSRange(location: lastRange.location + lastRange.length, length: max(0, rawLine.utf16.count - lastRange.location - lastRange.length)), in: rawLine) else { continue }
            let content = String(rawLine[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let enhanced = parseWordTimings(content, offset: offset)
            let text = enhanced.text
            guard !text.isEmpty else { continue }
            for match in matches {
                guard let minuteRange = Range(match.range(at: 1), in: rawLine),
                      let secondRange = Range(match.range(at: 2), in: rawLine),
                      let minutes = Double(rawLine[minuteRange]),
                      let seconds = Double(rawLine[secondRange]) else { continue }
                let lineTime = max(0, minutes * 60 + seconds + offset)
                // Repeated line tags replay the same relative word timing.
                let first = matches[0]
                let firstMinutes = Range(first.range(at: 1), in: rawLine).flatMap { Double(rawLine[$0]) } ?? minutes
                let firstSeconds = Range(first.range(at: 2), in: rawLine).flatMap { Double(rawLine[$0]) } ?? seconds
                let shift = lineTime - max(0, firstMinutes * 60 + firstSeconds + offset)
                let words = enhanced.words.map {
                    LyricWord(text: $0.text, start: $0.start + shift, end: $0.end.map { $0 + shift })
                }
                result.append(LyricLine(time: lineTime, text: text, words: words))
            }
        }
        let sorted = result.sorted { $0.time < $1.time }
        guard !sorted.isEmpty else { return [] }
        guard insertInterludes else { return sorted }

        // LRC timestamps mark line starts, not vocal ends. A long gap can be a
        // sustained phrase, so never invent an interlude inside that interval:
        // doing so shortens the phrase and accelerates its word animation.
        // Only the intro has a known end (the first lyric timestamp).
        var enriched: [LyricLine] = []
        if let first = sorted.first, first.time >= 2.0 {
            enriched.append(LyricLine(time: 0.0, text: "•••"))
        }
        enriched.append(contentsOf: sorted)

        return enriched
    }

    // Enhanced LRC: <mm:ss.xx>word <mm:ss.xx>word <end timestamp>.
    // A final empty marker supplies the held word's real end, including before a silence.
    private static func parseWordTimings(_ content: String, offset: Double) -> (text: String, words: [LyricWord]) {
        guard let regex = try? NSRegularExpression(pattern: #"<(\d{1,3}):(\d{2}(?:\.\d{1,3})?)>"#) else {
            return (content, [])
        }
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)
        let plain = regex.stringByReplacingMatches(in: content, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard matches.first?.range.location == 0 else { return (plain, []) }
        let times: [Double] = matches.compactMap { match in
            guard let minutes = Range(match.range(at: 1), in: content),
                  let seconds = Range(match.range(at: 2), in: content),
                  let m = Double(content[minutes]), let s = Double(content[seconds]), s < 60 else { return nil }
            return max(0, m * 60 + s + offset)
        }
        guard times.count == matches.count,
              zip(times, times.dropFirst()).allSatisfy({ $0.0 < $0.1 }) else { return (plain, []) }
        var words: [LyricWord] = []
        for index in matches.indices {
            let start = NSMaxRange(matches[index].range)
            let end = index + 1 < matches.count ? matches[index + 1].range.location : content.utf16.count
            guard let textRange = Range(NSRange(location: start, length: end - start), in: content) else { continue }
            let text = String(content[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                words.append(LyricWord(text: text, start: times[index],
                                       end: index + 1 < times.count ? times[index + 1] : nil))
            }
        }
        return (plain, words)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
