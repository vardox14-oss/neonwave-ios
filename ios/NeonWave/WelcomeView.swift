import SwiftUI
import AuthenticationServices

struct WelcomeView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showEmail = false
    @State private var showPrivacy = false

    var body: some View {
        ZStack {
            PremiumBackdrop(accent: NW.violet)
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 28)

                        VStack(spacing: 14) {
                            WaveMark(size: 68)
                            Text("neonwave")
                                .font(.system(size: 24, weight: .bold))
                                .tracking(-0.6)
                        }

                        Spacer(minLength: 34)

                        VStack(spacing: 12) {
                            Text("Votre musique.\nSimplement.")
                                .font(.system(size: 36, weight: .bold))
                                .tracking(-1.0)
                                .multilineTextAlignment(.center)
                            Text("Connectez-vous pour retrouver votre univers NeonWave.")
                                .font(.subheadline)
                                .foregroundStyle(Color(white: 0.60))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }

                        Spacer(minLength: 34)

                        VStack(spacing: 11) {
                            SignInWithAppleButton(.continue, onRequest: session.configureApple) { result in
                                Task { await session.completeApple(result) }
                            }
                            .signInWithAppleButtonStyle(.white)
                            .frame(height: 55)
                            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .disabled(!session.appleReady || session.busy)
                            .opacity(session.appleReady ? 1 : 0.45)

                            Button(action: session.signInGoogle) {
                                HStack(spacing: 12) {
                                    Text("G").font(.title3.bold()).foregroundStyle(.blue)
                                    Text("Continuer avec Google").font(.body.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity).frame(height: 55)
                                .background(.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            }
                            .foregroundStyle(.black)
                            .disabled(!session.providers.google || session.busy)
                            .opacity(session.providers.google ? 1 : 0.45)

                            Button { showEmail = true } label: {
                                Label("Continuer avec mon e-mail", systemImage: "envelope.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity).frame(height: 53)
                                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.10)))
                            }.foregroundStyle(.white)

                            if session.busy { ProgressView().tint(.white).padding(.top, 3) }
                            if let error = session.error {
                                Text(error).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                            }

                            Button { session.enterGuest() } label: {
                                Text("Continuer sans compte").font(.subheadline.weight(.semibold)).padding(.vertical, 10)
                            }.foregroundStyle(NW.muted)
                        }
                        .padding(18)
                        .premiumPanel(radius: 25)

                        Spacer(minLength: 22)

                        Button("Confidentialité") { showPrivacy = true }
                            .font(.caption)
                            .foregroundStyle(NW.muted)
                            .padding(.bottom, 16)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 500)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }.scrollIndicators(.hidden)
            }
        }
        .task { await session.loadProviders(); await session.prepareApple() }
        .sheet(isPresented: $showEmail) { EmailAuthView() }
        .sheet(isPresented: $showPrivacy) { PrivacyView() }
    }
}

struct EmailAuthView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var registering = false
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var revealPassword = false
    private var valid: Bool { email.contains("@") && password.count >= (registering ? 8 : 1) && (!registering || username.trimmingCharacters(in: .whitespaces).count >= 2) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    WaveMark(size: 42).padding(20).background(NW.blue.gradient, in: RoundedRectangle(cornerRadius: 24))
                    SectionHeading(title: registering ? "Votre prochain coup de cœur\ncommence ici." : "Heureux de vous retrouver.", eyebrow: "NeonWave")
                    Text(registering ? "Créez votre espace musical personnel." : "Connectez-vous pour retrouver vos fichiers sur votre serveur NeonWave.").foregroundStyle(NW.muted).font(.subheadline)
                    if session.providers.registration { Picker("Mode", selection: $registering) { Text("Connexion").tag(false); Text("Créer un compte").tag(true) }.pickerStyle(.segmented) }
                    if registering {
                        field("Votre nom") { TextField("Comment vous appeler ?", text: $username).textContentType(.username).autocorrectionDisabled() }
                    }
                    field("Adresse e-mail") { TextField("vous@exemple.fr", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.emailAddress) }
                    field("Mot de passe") {
                        HStack {
                            Group {
                                if revealPassword { TextField("Votre mot de passe", text: $password) }
                                else { SecureField(registering ? "8 caractères minimum" : "Votre mot de passe", text: $password) }
                            }.textContentType(registering ? .newPassword : .password).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button { revealPassword.toggle() } label: { Image(systemName: revealPassword ? "eye.slash" : "eye") }.accessibilityLabel(revealPassword ? "Masquer le mot de passe" : "Afficher le mot de passe")
                        }
                    }
                    if let error = session.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                    PrimaryButton(title: registering ? "Créer mon compte" : "Me connecter", symbol: "arrow.right", loading: session.busy) {
                        Task { await session.emailLogin(email: email, password: password, username: registering ? username : nil); if session.account != nil { dismiss() } }
                    }.disabled(!valid).opacity(valid ? 1 : 0.5)
                    Text("Vos fichiers importés restent dans la bibliothèque de ce compte sur cet iPhone.").font(.caption).foregroundStyle(NW.muted)
                }.padding(26)
            }.background(PremiumBackdrop(accent: NW.violet)).navigationTitle(registering ? "Créer un compte" : "Connexion").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }.presentationDragIndicator(.visible)
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(NW.muted)
            content().padding(16).premiumPanel(radius: 16)
        }
    }
}

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SectionHeading(title: "Votre espace,\nvotre musique.", eyebrow: "Confidentialité")
                    Label("Aucun suivi publicitaire", systemImage: "hand.raised.fill").font(.headline)
                    Text("La bibliothèque locale, les playlists et l’historique d’écoute sont stockés sur cet iPhone. Les fichiers personnels ne sont pas envoyés automatiquement au serveur.")
                    Label("Vous gardez le contrôle", systemImage: "lock.shield.fill").font(.headline)
                    Text("Avec un compte, votre nom, votre e-mail et vos informations de connexion sont traités par le service NeonWave. Apple et Google interviennent uniquement si vous choisissez leur connexion. Vos téléchargements personnels nécessitent une connexion au serveur.")
                    Text("Vous pouvez supprimer vos fichiers dans la bibliothèque et votre compte dans les réglages. Les fichiers importés localement peuvent être inclus dans la sauvegarde de votre iPhone ; les téléchargements récupérables du serveur en sont exclus.")
                    if let url = AppConfiguration.publicURL("NeonWavePrivacyURL") { Link("Consulter la politique de confidentialité complète", destination: url) }
                    if let url = AppConfiguration.publicURL("NeonWaveSupportURL") { Link("Contacter l’assistance", destination: url) }
                }.font(.subheadline).foregroundStyle(NW.muted).lineSpacing(5).padding(26)
            }.background(PremiumBackdrop()).navigationTitle("Confidentialité").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
    }
}
