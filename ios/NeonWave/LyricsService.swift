import Foundation

enum LyricsService {
    private struct LRCLIBResponse: Decodable {
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    static func fetchLyrics(title: String, artist: String, duration: Double? = nil) async -> (lines: [LyricLine], plain: String?) {
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return ([], nil)
        }

        var urlString = "https://lrclib.net/api/get?track_name=\(encodedTitle)&artist_name=\(encodedArtist)"
        if let duration, duration > 0 {
            urlString += "&duration=\(Int(duration))"
        }

        guard let url = URL(string: urlString) else { return ([], nil) }

        var request = URLRequest(url: url)
        request.setValue("NeonWave/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(LRCLIBResponse.self, from: data) else {
                return ([], nil)
            }

            if let synced = decoded.syncedLyrics, !synced.isEmpty {
                let parsed = parseLRC(synced)
                if !parsed.isEmpty {
                    return (parsed, decoded.plainLyrics)
                }
            }

            if let plain = decoded.plainLyrics, !plain.isEmpty {
                return ([], plain)
            }
        } catch { }

        return ([], nil)
    }

    private static func parseLRC(_ lrc: String) -> [LyricLine] {
        var result: [LyricLine] = []
        let lines = lrc.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["), let closingBracket = trimmed.firstIndex(of: "]") else { continue }
            let timeString = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closingBracket])
            let text = String(trimmed[trimmed.index(after: closingBracket)...]).trimmingCharacters(in: .whitespaces)
            let parts = timeString.components(separatedBy: ":")
            guard parts.count >= 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else { continue }
            let totalSeconds = (minutes * 60.0) + seconds
            if !text.isEmpty {
                result.append(LyricLine(time: totalSeconds, text: text))
            }
        }
        return result.sorted { $0.time < $1.time }
    }
}
