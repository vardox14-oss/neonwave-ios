import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var taste: MusicTasteStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLogout = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var error: String?
    @State private var showPrivacy = false
    @State private var showTaste = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Text(String((session.account?.username ?? "N").prefix(1)).uppercased()).font(.title.bold()).frame(width: 64, height: 64).background(NW.blue.gradient, in: RoundedRectangle(cornerRadius: 20))
                        VStack(alignment: .leading, spacing: 6) { Text(session.account?.username ?? "Votre espace local").font(.headline); Text(session.account?.email ?? "La musique reste sur cet iPhone").font(.caption).foregroundStyle(NW.muted) }
                    }.padding(.vertical, 10)
                }.listRowBackground(NW.surface)
                Section("Votre musique en chiffres") {
                    stat("Titres dans la bibliothèque", value: String(library.tracks.count), symbol: "music.note")
                    stat("Coups de cœur", value: String(library.liked.count), symbol: "heart")
                    stat("Écoutes lancées", value: String(library.tracks.reduce(0) { $0 + $1.playCount }), symbol: "waveform")
                    stat("Stockage audio", value: ByteCountFormatter.string(fromByteCount: library.storageBytes, countStyle: .file), symbol: "internaldrive")
                }.listRowBackground(NW.surface)
                Section("À votre façon") {
                    Button { showTaste = true } label: { Label("Mes goûts musicaux", systemImage: "sparkles") }
                    Toggle("Retours haptiques", isOn: Binding(get: { library.snapshot.haptics }, set: library.setHaptics))
                    Toggle("Téléchargements en Wi-Fi", isOn: Binding(get: { library.snapshot.wifiOnly }, set: library.setWifiOnly))
                }.listRowBackground(NW.surface)
                Section("À propos") {
                    Button { showPrivacy = true } label: { Label("Confidentialité", systemImage: "hand.raised") }
                    if let url = AppConfiguration.publicURL("NeonWaveSupportURL") { Link(destination: url) { Label("Besoin d’aide ?", systemImage: "questionmark.circle") } }
                    HStack { Text("NeonWave pour iPhone"); Spacer(); Text("1.0.0").foregroundStyle(NW.muted) }
                }.listRowBackground(NW.surface)
                Section {
                    Button(session.isGuest ? "Revenir à la connexion" : "Se déconnecter") { confirmLogout = true }
                    if session.account != nil {
                        Button(role: .destructive) { confirmDelete = true } label: { HStack { Text("Supprimer mon compte"); if deleting { ProgressView() } } }.disabled(deleting)
                    }
                } footer: { Text("Les playlists et les favoris de cette version sont enregistrés sur cet iPhone. Les fichiers du compte peuvent être récupérés depuis le serveur via Actualiser.") }.listRowBackground(NW.surface)
                if let error { Section { Text(error).foregroundStyle(.orange) }.listRowBackground(NW.surface) }
            }.scrollContentBackground(.hidden).background(NW.background).navigationTitle("Votre espace").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Terminé") { dismiss() } } }
        }
        .sheet(isPresented: $showPrivacy) { PrivacyView() }
        .fullScreenCover(isPresented: $showTaste) { TasteOnboardingView(editing: true).environmentObject(taste) }
        .confirmationDialog("Quitter cet espace ?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button(session.isGuest ? "Revenir à la connexion" : "Se déconnecter") {
                Task { player.stop(); await downloads.cancelAll(); dismiss(); session.signOut() }
            }
        } message: { Text("Les fichiers restent sur cet iPhone. Vous retrouverez cette bibliothèque en revenant dans le même espace.") }
        .confirmationDialog("Supprimer définitivement votre compte ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer mon compte et ses fichiers", role: .destructive) {
                Task {
                    deleting = true
                    defer { deleting = false }
                    do {
                        try await session.deleteAccount()
                        player.stop(); await downloads.cancelAll()
                        do { try library.eraseAccountFiles() }
                        catch { library.message = "Le compte a été supprimé. Certains fichiers locaux n’ont pas pu être effacés ; supprimez les données de l’application dans les réglages iOS." }
                        dismiss(); session.signOut()
                    } catch { self.error = error.localizedDescription }
                }
            }
        } message: { Text("Votre compte, les fichiers personnels du serveur et la bibliothèque de ce compte sur cet iPhone seront supprimés. Cette action est irréversible.") }
    }
    private func stat(_ title: String, value: String, symbol: String) -> some View {
        HStack { Label(title, systemImage: symbol); Spacer(); Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(NW.muted) }.font(.subheadline)
    }
}
