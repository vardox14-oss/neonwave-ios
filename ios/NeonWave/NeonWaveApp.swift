import SwiftUI
import AVFoundation

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
        UIApplication.shared.beginReceivingRemoteControlEvents()
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == DownloadManager.sessionIdentifier else { completionHandler(); return }
        DownloadManager.shared.backgroundCompletion = completionHandler
    }
}

@main struct NeonWaveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var session = SessionStore()
    @StateObject private var library = LibraryStore()
    @StateObject private var player = AudioPlayer()
    @StateObject private var downloads = DownloadManager.shared
    @StateObject private var taste = MusicTasteStore()
    @StateObject private var artistRouter = ArtistRouter()
    @StateObject private var network = NetworkMonitor.shared
    var body: some Scene {
        WindowGroup {
            Group {
                if !session.authenticated {
                    WelcomeView()
                } else if !taste.isLoaded {
                    ZStack {
                        LinearGradient(colors: [NW.background, Color(red: 0.08, green: 0.04, blue: 0.2)], startPoint: .bottom, endPoint: .top).ignoresSafeArea()
                        VStack(spacing: 18) { WaveMark(size: 48); ProgressView().tint(.white); Text("CRÉATION DE VOTRE UNIVERS").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(NW.muted) }
                    }
                } else if !taste.preferences.completed {
                    TasteOnboardingView()
                } else {
                    MainView()
                }
            }
            .environmentObject(session).environmentObject(library).environmentObject(player).environmentObject(downloads).environmentObject(taste).environmentObject(artistRouter).environmentObject(network)
            .preferredColorScheme(.dark).tint(NW.blue)
            .task(id: session.storageID) {
                player.stop(); library.activate(session.storageID); player.connect(library); downloads.connect(library); await taste.activate(session.storageID)
            }
            .alert("NeonWave", isPresented: Binding(get: { library.message != nil || player.error != nil || downloads.error != nil }, set: { if !$0 { library.message = nil; player.error = nil; downloads.error = nil } })) {
                Button("D’accord", role: .cancel) { library.message = nil; player.error = nil; downloads.error = nil }
            } message: { Text(library.message ?? player.error ?? downloads.error ?? "") }
        }
    }
}
