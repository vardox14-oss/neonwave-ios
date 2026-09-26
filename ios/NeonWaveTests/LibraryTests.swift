import XCTest
@testable import NeonWave

final class LibraryTests: XCTestCase {
    @MainActor func testPlaylistsKeepTheirOrderAndAvoidDuplicates() throws {
        let store = LibraryStore()
        store.activate("test-\(UUID().uuidString)")
        defer { try? store.eraseAccountFiles() }
        store.createPlaylist("  Dans le train  ")
        let playlist = try XCTUnwrap(store.playlists.first)
        XCTAssertEqual(playlist.name, "Dans le train")
        let first = Track(title: "A"), second = Track(title: "B")
        store.add(first, to: playlist); store.add(second, to: playlist); store.add(first, to: playlist)
        XCTAssertEqual(store.playlists.first?.trackIDs, [first.id, second.id])
        store.remove(first, from: playlist)
        XCTAssertEqual(store.playlists.first?.trackIDs, [second.id])
    }

    @MainActor func testAccountsHaveSeparatePersistentLibraries() throws {
        let firstID = "test-\(UUID().uuidString)", secondID = "test-\(UUID().uuidString)"
        let store = LibraryStore()
        defer {
            store.activate(firstID); try? store.eraseAccountFiles()
            store.activate(secondID); try? store.eraseAccountFiles()
        }
        store.activate(firstID); store.createPlaylist("Privée")
        store.activate(secondID); XCTAssertTrue(store.playlists.isEmpty)
        store.activate(firstID); XCTAssertEqual(store.playlists.first?.name, "Privée")
    }

    @MainActor func testOfflineAvailabilityRequiresAnActualFile() throws {
        let store = LibraryStore(); store.activate("test-\(UUID().uuidString)")
        defer { try? store.eraseAccountFiles() }
        let track = Track(title: "Hors connexion", fileName: "audio.m4a")
        XCTAssertNil(store.localURL(track))
        let url = try XCTUnwrap(store.fileURL("audio.m4a"))
        try Data([0, 1, 2]).write(to: url)
        XCTAssertEqual(store.localURL(track), url)
        XCTAssertNil(store.fileURL("../outside.m4a"))
        XCTAssertNil(store.fileURL("/tmp/outside.m4a"))
    }

    func testTrackAndPreferencesSurviveOfflineSerialization() throws {
        var snapshot = LibrarySnapshot()
        let track = Track(title: "L’été", artist: "Artiste", duration: 185, fileName: "local.m4a", spotifyId: "4uLU6hMCjMI75M1A2tKUQC")
        snapshot.tracks = [track]; snapshot.likedIDs = [track.id]; snapshot.wifiOnly = false
        let restored = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.tracks, [track]); XCTAssertTrue(restored.likedIDs.contains(track.id)); XCTAssertFalse(restored.wifiOnly)
        XCTAssertEqual(185.0.clockTime, "3:05"); XCTAssertEqual(Double.nan.clockTime, "0:00")
        XCTAssertEqual(restored.tracks.first?.spotifyId, "4uLU6hMCjMI75M1A2tKUQC")
    }

    func testLRCParserHandlesOffsetsAndRepeatedTimestamps() {
        let lrc = """
        [offset:+500]
        [00:01.00][00:04.25]Première ligne
        [00:08.5]Deuxième ligne
        """
        let lines = LyricsService.parseLRC(lrc)
        XCTAssertEqual(lines.map(\.text), ["Première ligne", "Première ligne", "Deuxième ligne"])
        XCTAssertEqual(lines.map(\.time), [1.5, 4.75, 9.0])
    }

    func testLyricsCandidateUsesTheActualPlaybackDuration() throws {
        let short = LyricsService.LRCLIBResponse(trackName: "Ainsi va la rue", artistName: "Rim'K", duration: 132, plainLyrics: nil, syncedLyrics: "[00:01.00]Court")
        let full = LyricsService.LRCLIBResponse(trackName: "Ainsi va la rue", artistName: "Rim'K", duration: 158, plainLyrics: nil, syncedLyrics: "[00:01.00]Complet")
        let choice = try XCTUnwrap(LyricsService.bestCandidate([short, full], title: "Ainsi va la rue", artist: "Rim'K", duration: 158))
        XCTAssertEqual(choice.duration, 158)
    }

    func testLyricsCandidatePrefersSyncedOverPlain() throws {
        let plain = LyricsService.LRCLIBResponse(trackName: "Le bonheur est triste", artistName: "Saïf", duration: 155, plainLyrics: "Texte brut", syncedLyrics: nil)
        let synced = LyricsService.LRCLIBResponse(trackName: "Le bonheur est triste", artistName: "Saif, Pato", duration: 155, plainLyrics: "Texte brut", syncedLyrics: "[00:18.98]Texte synchronisé")
        let choice = try XCTUnwrap(LyricsService.bestCandidate([plain, synced], title: "Le bonheur est triste", artist: "Saïf", duration: 155))
        XCTAssertEqual(choice.artistName, "Saif, Pato")
        XCTAssertNotNil(choice.syncedLyrics)
    }

    func testYouTubeResolverPrefersMatchingStudioAudio() throws {
        let live = MusicCatalogService.YouTubeCandidate(videoId: "AAAAAAAAAAA", title: "Ainsi va la rue (Live)", channel: "Concert TV", duration: 158)
        let studio = MusicCatalogService.YouTubeCandidate(videoId: "BBBBBBBBBBB", title: "Rim'K - Ainsi va la rue (Official Audio)", channel: "Rim'K - Topic", duration: 158)
        let choice = try XCTUnwrap(MusicCatalogService.bestYouTubeCandidate([live, studio], title: "Ainsi va la rue", artist: "Rim'K", duration: 158))
        XCTAssertEqual(choice.videoId, "BBBBBBBBBBB")
    }

    func testYouTubeSearchHTMLKeepsMetadataTogether() throws {
        let html = #"{"videoRenderer":{"videoId":"BBBBBBBBBBB","title":{"runs":[{"text":"Rim'K - Ainsi va la rue"}]},"longBylineText":{"runs":[{"text":"Rim'K - Topic"}]},"lengthText":{"simpleText":"2:38"}}}"#
        let item = try XCTUnwrap(MusicCatalogService.parseYouTubeCandidates(html).first)
        XCTAssertEqual(item.title, "Rim'K - Ainsi va la rue")
        XCTAssertEqual(item.channel, "Rim'K - Topic")
        XCTAssertEqual(item.duration, 158)
    }
}
