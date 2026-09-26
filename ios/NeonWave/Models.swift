import Foundation

struct Track: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var artist: String
    var duration: Double
    var fileName: String?
    var remoteID: String?
    var artworkFile: String?
    var album: String?
    var artworkURL: String?
    var streamURL: String?
    var addedAt: Date
    var playCount: Int
    var lastPlayedAt: Date?

    init(id: String = UUID().uuidString, title: String, artist: String = "Artiste inconnu", duration: Double = 0, fileName: String? = nil, remoteID: String? = nil, artworkFile: String? = nil, album: String? = nil, artworkURL: String? = nil, streamURL: String? = nil) {
        self.id = id; self.title = title; self.artist = artist; self.duration = duration
        self.fileName = fileName; self.remoteID = remoteID; self.artworkFile = artworkFile
        self.album = album; self.artworkURL = artworkURL; self.streamURL = streamURL
        self.addedAt = Date(); self.playCount = 0
    }
    var colorIndex: Int { id.utf8.reduce(0) { ($0 + Int($1)) % 6 } }
}

struct Album: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var artist: String
    var coverURL: String?
    var trackCount: Int?
    var releaseDate: String?
}

struct LyricLine: Identifiable, Hashable {
    let id = UUID()
    let time: Double
    let text: String
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
    var wifiOnly = true
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
        let seconds = Int(self)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
