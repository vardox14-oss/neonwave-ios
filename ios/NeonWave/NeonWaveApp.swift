import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
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
    var body: some Scene {
        WindowGroup {
            Group {
                if session.authenticated { MainView() }
                else { WelcomeView() }
            }
            .environmentObject(session).environmentObject(library).environmentObject(player).environmentObject(downloads)
            .preferredColorScheme(.dark).tint(NW.blue)
            .task(id: session.storageID) {
                player.stop(); library.activate(session.storageID); player.connect(library); downloads.connect(library)
            }
            .alert("NeonWave", isPresented: Binding(get: { library.message != nil || player.error != nil || downloads.error != nil }, set: { if !$0 { library.message = nil; player.error = nil; downloads.error = nil } })) {
                Button("D’accord", role: .cancel) { library.message = nil; player.error = nil; downloads.error = nil }
            } message: { Text(library.message ?? player.error ?? downloads.error ?? "") }
        }
    }
}
