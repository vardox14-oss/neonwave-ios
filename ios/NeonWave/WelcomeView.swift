import SwiftUI
import AuthenticationServices

struct WelcomeView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showEmail = false
    @State private var showPrivacy = false
    @State private var floating = false
    var body: some View {
        ZStack {
            NW.background.ignoresSafeArea()
            RadialGradient(colors: [NW.blue.opacity(0.26), .clear], center: .init(x: 0.8, y: 0.15), startRadius: 10, endRadius: 380).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 10) {
                        WaveMark(size: 26)
                        Text("neonwave").font(.system(.title3, design: .rounded, weight: .bold)).tracking(-0.7)
                        Spacer()
                        Text("FAITES PLACE AU SON").font(.system(size: 8, weight: .bold)).tracking(1.6).foregroundStyle(NW.muted)
                    }.padding(.top, 18)
                    ZStack {
                        Circle().stroke(NW.blue.opacity(0.18), lineWidth: 1).frame(width: 265, height: 265)
                        Circle().stroke(.white.opacity(0.08), lineWidth: 1).frame(width: 315, height: 315)
                        CoverArt(index: 2).frame(width: 178).rotationEffect(.degrees(-19)).offset(x: -48, y: floating ? -5 : 5)
                        CoverArt(index: 0).frame(width: 196).rotationEffect(.degrees(12)).shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 20).offset(x: 46, y: floating ? 25 : 15)
                        HStack(spacing: 8) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("VOTRE MONDE. VOTRE BANDE-SON.").font(.system(size: 8, weight: .bold)).tracking(1)
                        }.padding(12).background(.ultraThinMaterial, in: Capsule()).offset(y: 132)
                    }.frame(maxWidth: .infinity).frame(height: 310).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("La musique,\nà votre rythme.").font(.system(size: 42, weight: .bold, design: .rounded)).tracking(-1.8).fixedSize(horizontal: false, vertical: true)
                        Text("Vos titres. Vos playlists. Votre bulle.\nEmportez ce qui vous fait vibrer.").font(.subheadline).foregroundStyle(NW.muted).lineSpacing(5)
                    }
                    VStack(spacing: 12) {
                        SignInWithAppleButton(.continue, onRequest: session.configureApple) { result in Task { await session.completeApple(result) } }
                            .signInWithAppleButtonStyle(.white).frame(height: 54).clipShape(RoundedRectangle(cornerRadius: 16))
                            .disabled(!session.appleReady || session.busy).opacity(session.appleReady ? 1 : 0.4)
                            .accessibilityHint(session.appleReady ? "" : "Connexion Apple actuellement indisponible")
                        Button(action: session.signInGoogle) {
                            HStack(spacing: 12) { Text("G").font(.title3.bold()); Text("Continuer avec Google").font(.body.weight(.semibold)) }
                                .frame(maxWidth: .infinity).frame(minHeight: 54).background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
                        }.foregroundStyle(.white).disabled(!session.providers.google || session.busy).opacity(session.providers.google ? 1 : 0.4)
                            .accessibilityHint(session.providers.google ? "" : "Connexion Google actuellement indisponible")
                        Button { showEmail = true } label: {
                            Label("Continuer avec mon e-mail", systemImage: "envelope").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        }.foregroundStyle(NW.muted)
                        if session.busy { ProgressView().tint(NW.blue) }
                        if let error = session.error { Text(error).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center).accessibilityAddTraits(.updatesFrequently) }
                        Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.vertical, 2)
                        Button { session.enterGuest() } label: {
                            HStack { Text("Commencer sur cet iPhone"); Image(systemName: "arrow.right") }.font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.foregroundStyle(.white)
                        Text("Sans compte, avec vos fichiers personnels.").font(.caption).foregroundStyle(NW.muted)
                            .frame(maxWidth: .infinity)
                    }
                    Button("Votre musique reste personnelle. Notre confidentialité.") { showPrivacy = true }
                        .font(.system(size: 11)).foregroundStyle(NW.muted).frame(maxWidth: .infinity).padding(.bottom, 20)
                }.padding(.horizontal, 28).frame(maxWidth: 500).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
        }
        .task { await session.loadProviders(); await session.prepareApple() }
        .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) { floating = true } } }
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
            }.background(NW.background).navigationTitle(registering ? "Créer un compte" : "Connexion").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }.presentationDragIndicator(.visible)
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(NW.muted)
            content().padding(16).background(NW.surface, in: RoundedRectangle(cornerRadius: 14))
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
                    if let url = Configuration.publicURL("NeonWavePrivacyURL") { Link("Consulter la politique de confidentialité complète", destination: url) }
                    if let url = Configuration.publicURL("NeonWaveSupportURL") { Link("Contacter l’assistance", destination: url) }
                }.font(.subheadline).foregroundStyle(NW.muted).lineSpacing(5).padding(26)
            }.background(NW.background).navigationTitle("Confidentialité").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
    }
}
