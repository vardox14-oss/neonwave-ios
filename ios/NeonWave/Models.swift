import Foundation

struct Track: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var artist: String
    var duration: Double
    var fileName: String?
    var remoteID: String?
    var artworkFile: String?
    var canvasFile: String?
    var album: String?
    var artworkURL: String?
    var streamURL: String?
    var videoId: String?
    var spotifyId: String?
    var appleMusicID: String?
    var addedAt: Date
    var playCount: Int
    var lastPlayedAt: Date?

    init(id: String = UUID().uuidString, title: String, artist: String = "Artiste inconnu", duration: Double = 0, fileName: String? = nil, remoteID: String? = nil, artworkFile: String? = nil, canvasFile: String? = nil, album: String? = nil, artworkURL: String? = nil, streamURL: String? = nil, videoId: String? = nil, spotifyId: String? = nil, appleMusicID: String? = nil) {
        self.id = id; self.title = title; self.artist = artist; self.duration = duration
        self.fileName = fileName; self.remoteID = remoteID; self.artworkFile = artworkFile; self.canvasFile = canvasFile
        self.album = album; self.artworkURL = artworkURL; self.streamURL = streamURL
        self.videoId = videoId
        self.spotifyId = spotifyId
        self.appleMusicID = appleMusicID
        self.addedAt = Date(); self.playCount = 0
    }
    var colorIndex: Int { id.utf8.reduce(0) { ($0 + Int($1)) % 6 } }
    var canDownload: Bool {
        remoteID != nil || streamURL != nil || videoId != nil || spotifyId != nil || !title.isEmpty
    }
    var isDownloadedSource: Bool {
        remoteID != nil || streamURL != nil || videoId != nil || spotifyId != nil || !title.isEmpty
    }
}

struct Album: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var artist: String
    var coverURL: String?
    var trackCount: Int?
    var releaseDate: String?
    var appleMusicID: String? = nil
}

struct LyricWord: Hashable {
    let text: String
    let start: Double
    let end: Double?
    var isBackground: Bool = false
}

struct LyricLine: Identifiable, Hashable {
    let id: UUID
    let time: Double
    var endTime: Double?
    let text: String
    var words: [LyricWord]
    var isBackground: Bool

    init(id: UUID = UUID(), time: Double, endTime: Double? = nil, text: String, words: [LyricWord] = [], isBackground: Bool? = nil) {
        self.id = id
        self.time = time
        self.endTime = endTime
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isParenWrapped = (trimmed.hasPrefix("(") && trimmed.hasSuffix(")")) ||
                             (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
        let determinedBg = isBackground ?? isParenWrapped
        self.isBackground = determinedBg

        // Strip enclosing parentheses/brackets for backing vocals
        if isParenWrapped && trimmed.count >= 2 {
            let startIdx = trimmed.index(after: trimmed.startIndex)
            let endIdx = trimmed.index(before: trimmed.endIndex)
            self.text = String(trimmed[startIdx..<endIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            self.text = trimmed
        }

        if !words.isEmpty {
            self.words = words.map { w in
                var wBg = w.isBackground || determinedBg
                var wText = w.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if (wText.hasPrefix("(") && wText.hasSuffix(")")) || (wText.hasPrefix("[") && wText.hasSuffix("]")) {
                    wBg = true
                    if wText.count >= 2 {
                        let s = wText.index(after: wText.startIndex)
                        let e = wText.index(before: wText.endIndex)
                        wText = String(wText[s..<e]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                if wBg {
                    wText = wText.replacingOccurrences(of: "(", with: "")
                                 .replacingOccurrences(of: ")", with: "")
                                 .replacingOccurrences(of: "[", with: "")
                                 .replacingOccurrences(of: "]", with: "")
                                 .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return LyricWord(text: wText.isEmpty ? w.text : wText, start: w.start, end: w.end, isBackground: wBg)
            }
        } else {
            self.words = []
        }
    }

    func animationWords(duration: Double) -> [LyricWord] {
        if !words.isEmpty {
            return words.map { word in
                let wordBack = word.isBackground || self.isBackground
                var clean = word.text
                if wordBack {
                    clean = clean.replacingOccurrences(of: "(", with: "")
                                 .replacingOccurrences(of: ")", with: "")
                                 .replacingOccurrences(of: "[", with: "")
                                 .replacingOccurrences(of: "]", with: "")
                                 .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return LyricWord(text: clean.isEmpty ? word.text : clean,
                                 start: word.start,
                                 end: word.end ?? max(word.start + 0.05, time + duration),
                                 isBackground: wordBack)
            }
        }
        // Plain LRC supplies no word durations. Preserve the full phrase interval;
        // do not force a final-word emphasis or invent instrumental gaps.
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let total = Double(max(1, tokens.reduce(0) { $0 + $1.count }))
        var cursor = time
        var insideParen = false
        return tokens.map { token in
            let start = cursor
            cursor += duration * Double(token.count) / total
            if token.hasPrefix("(") || token.hasPrefix("[") { insideParen = true }
            let wordBack = self.isBackground || insideParen || token.hasPrefix("(") || token.hasSuffix(")") || token.hasPrefix("[") || token.hasSuffix("]")
            if token.hasSuffix(")") || token.hasSuffix("]") { insideParen = false }
            var clean = token
            if wordBack {
                clean = clean.replacingOccurrences(of: "(", with: "")
                             .replacingOccurrences(of: ")", with: "")
                             .replacingOccurrences(of: "[", with: "")
                             .replacingOccurrences(of: "]", with: "")
                             .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return LyricWord(text: clean.isEmpty ? token : clean, start: start, end: cursor, isBackground: wordBack)
        }
    }
}

struct ArtistChoice: Identifiable, Codable, Hashable {
    var spotifyId: String = ""
    var name: String
    var imageUrl: String = ""
    var spotifyUrl: String = ""
    var genres: [String] = []
    var popularity: Int = 0
    var followers: Int = 0
    var source: String = "local"

    var id: String { spotifyId.isEmpty ? name.lowercased() : spotifyId }
    var colorIndex: Int { name.utf8.reduce(0) { ($0 + Int($1)) % 6 } }
}

struct MusicPreferences: Codable, Equatable {
    var completed = false
    var genres: [String] = []
    var artists: [ArtistChoice] = []
    var followedArtists: [ArtistChoice] = []
    var spotifyEnabled: Bool? = nil
}

struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var name: String
    var symbol = "waveform"
    var trackIDs: [String] = []
    var createdAt = Date()
}

struct LibrarySnapshot: Codable {
    var tracks: [Track] = []
    var playlists: [Playlist] = []
    var likedIDs: Set<String> = []
    var wifiOnly = false
    var haptics = true
}

struct Account: Codable, Identifiable {
    let id: String
    let username: String
    let email: String
    let role: String
}

struct AuthResponse: Decodable { let token: String; let user: Account }
struct AuthProviders: Decodable { var google = false; var apple = false; var registration = true }
struct RemoteTrack: Decodable {
    let id: String
    let title: String
    let artist: String
    let durationMs: Double
}
struct RemoteLibrary: Decodable { let tracks: [RemoteTrack] }
struct MessageError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum LibraryTab: String, CaseIterable {
    case home = "Accueil", search = "Recherche", library = "Bibliothèque", downloads = "Téléchargements"
    var symbol: String {
        switch self { case .home: return "square.grid.2x2.fill"; case .search: return "magnifyingglass"; case .library: return "square.stack.fill"; case .downloads: return "arrow.down.circle.fill" }
    }
}

enum RepeatMode: Int, CaseIterable { case off, all, one }

extension Double {
    var clockTime: String {
        guard isFinite, self > 0 else { return "0:00" }
        let total = Int(self.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
