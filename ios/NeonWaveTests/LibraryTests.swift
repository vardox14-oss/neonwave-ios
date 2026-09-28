import XCTest
@testable import NeonWave

final class LibraryTests: XCTestCase {
    func testDeviceAudioSelectsNativeAACAndRejectsWrongVideo() throws {
        let data = Data(#"{"playabilityStatus":{"status":"OK"},"videoDetails":{"videoId":"9Et9XGVMmUw"},"streamingData":{"adaptiveFormats":[{"itag":251,"mimeType":"audio/webm","url":"https://r1.googlevideo.com/opus"},{"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","url":"https://r1.googlevideo.com/aac"}]}}"#.utf8)
        XCTAssertEqual(MusicCatalogService.selectDeviceAudioURL(data, videoId: "9Et9XGVMmUw")?.path, "/aac")
        XCTAssertNil(MusicCatalogService.selectDeviceAudioURL(data, videoId: "6O8kvPpiQy8"))
    }

    func testDeviceAudioRejectsBlockedAndUntrustedStreams() throws {
        for (status, url) in [("LOGIN_REQUIRED", "https://r1.googlevideo.com/aac"), ("OK", "https://googlevideo.com.attacker.example/aac"), ("OK", "http://r1.googlevideo.com/aac")] {
            let data = try JSONSerialization.data(withJSONObject: [
                "playabilityStatus": ["status": status], "videoDetails": ["videoId": "9Et9XGVMmUw"],
                "streamingData": ["adaptiveFormats": [["itag": 140, "mimeType": "audio/mp4", "url": url]]]
            ])
            XCTAssertNil(MusicCatalogService.selectDeviceAudioURL(data, videoId: "9Et9XGVMmUw"))
        }
    }

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


final class SpicyWaveAnimationTests: XCTestCase {
    func testSourceCurveKnotsAndEndpoints() {
        XCTAssertEqual(SpicyWaveCurve.scale.value(at: 0), 0.95, accuracy: 1e-12)
        XCTAssertEqual(SpicyWaveCurve.scale.value(at: 0.7), 1.0505, accuracy: 1e-12)
        XCTAssertEqual(SpicyWaveCurve.letterScale.value(at: 0.7), 1.175, accuracy: 1e-12)
        XCTAssertEqual(SpicyWaveCurve.lift.value(at: 0.9), -1.0 / 60, accuracy: 1e-12)
        XCTAssertEqual(SpicyWaveCurve.letterLift.value(at: 0.9), -1.0 / 56, accuracy: 1e-12)
        XCTAssertEqual(SpicyWaveCurve.glow.value(at: 0.15), 1, accuracy: 1e-12)
        XCTAssertEqual(SpicyWaveCurve.glow.value(at: 0.6), 1, accuracy: 1e-12)
        XCTAssertEqual(SpicyWaveCurve.scale.value(at: 2), 1, accuracy: 1e-12)
        XCTAssertEqual(SpicyWaveCurve.glow.value(at: -1), 0, accuracy: 1e-12)
    }

    func testSpringIsIndependentOfDisplayRefreshRate() {
        for (frequency, damping) in [(0.88, 0.64), (1.45, 0.40), (1.18, 0.56)] {
            var sixty = SpicyWaveSpring(position: 0.95, frequency: frequency, damping: damping)
            var oneTwenty = sixty
            for _ in 0..<60 { sixty.step(goal: 1.175, dt: 1.0 / 60) }
            for _ in 0..<120 { oneTwenty.step(goal: 1.175, dt: 1.0 / 120) }
            XCTAssertEqual(sixty.position, oneTwenty.position, accuracy: 1e-10)
            XCTAssertEqual(sixty.velocity, oneTwenty.velocity, accuracy: 1e-10)
        }
    }

    func testSeekingClearsSpringMomentum() {
        var spring = SpicyWaveSpring(position: 0.95, frequency: 0.88, damping: 0.64)
        spring.step(goal: 1.175, dt: 0.1)
        XCTAssertNotEqual(spring.velocity, 0)
        spring.step(goal: 0.95, dt: 0, snap: true)
        XCTAssertEqual(spring.position, 0.95)
        XCTAssertEqual(spring.velocity, 0)
        spring.step(goal: 0.95, dt: 1.0 / 60)
        XCTAssertEqual(spring.position, 0.95, accuracy: 1e-12)
    }
}
