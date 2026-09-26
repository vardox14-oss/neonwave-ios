import SwiftUI
import AuthenticationServices

struct WelcomeView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showEmail = false
    @State private var showPrivacy = false
    @State private var floating = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            PremiumBackdrop(accent: NW.violet)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 11) {
                        WaveMark(size: 31)
                        Text("neonwave").font(.system(size: 21, weight: .bold, design: .rounded)).tracking(-0.8)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(Color.green).frame(width: 6, height: 6).shadow(color: .green, radius: pulse ? 7 : 2)
                            Text("POUR IPHONE").font(.system(size: 8, weight: .bold)).tracking(1.5)
                        }.foregroundStyle(.white.opacity(0.72)).padding(.horizontal, 11).padding(.vertical, 8).premiumPanel(radius: 20)
                    }.padding(.top, 10)

                    ZStack {
                        Circle().fill(NW.blue.opacity(0.16)).frame(width: 250).blur(radius: 35)
                        Circle().stroke(NW.blue.opacity(0.22), lineWidth: 1).frame(width: 276)
                        Circle().stroke(.white.opacity(0.08), lineWidth: 1).frame(width: 326)
                        CoverArt(index: 2).frame(width: 164).rotationEffect(.degrees(-16)).offset(x: -63, y: floating ? -13 : 1)
                        CoverArt(index: 0).frame(width: 196).rotationEffect(.degrees(10)).shadow(color: .black.opacity(0.52), radius: 34, y: 22).offset(x: 47, y: floating ? 15 : 29)
                        VStack(spacing: 3) {
                            Image(systemName: "waveform").foregroundStyle(NW.cyan)
                            Text("AUDIO NATIF").font(.system(size: 7, weight: .bold)).tracking(1.2)
                        }.padding(.horizontal, 13).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule()).offset(x: -92, y: 113)
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("HORS LIGNE").font(.system(size: 7, weight: .bold)).tracking(1.1)
                        }.padding(.horizontal, 13).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule()).offset(x: 89, y: -104)
                    }.frame(maxWidth: .infinity).frame(height: 294).accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Toute votre musique.\nMême sans réseau.").font(.system(size: 43, weight: .bold, design: .rounded)).tracking(-1.9).fixedSize(horizontal: false, vertical: true)
                        Text("Un lecteur pensé pour l’iPhone, avec vos playlists, vos paroles synchronisées et vos artistes préférés.").font(.subheadline).foregroundStyle(NW.muted).lineSpacing(5)
                    }

                    HStack(spacing: 9) {
                        promise("Paroles", symbol: "quote.bubble.fill")
                        promise("Canvas", symbol: "sparkles.tv.fill")
                        promise("Hors ligne", symbol: "airplane")
                    }

                    VStack(spacing: 11) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ENTREZ DANS VOTRE BULLE").font(.system(size: 9, weight: .bold)).tracking(1.8).foregroundStyle(NW.blue)
                                Text("Votre espace vous attend.").font(.headline)
                            }
                            Spacer(); WaveMark(size: 30)
                        }.padding(.bottom, 4)
                        SignInWithAppleButton(.continue, onRequest: session.configureApple) { result in Task { await session.completeApple(result) } }
                            .signInWithAppleButtonStyle(.white).frame(height: 55).clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .disabled(!session.appleReady || session.busy).opacity(session.appleReady ? 1 : 0.4)
                        Button(action: session.signInGoogle) {
                            HStack(spacing: 12) {
                                Text("G").font(.title3.bold()).foregroundStyle(.blue)
                                Text("Continuer avec Google").font(.body.weight(.semibold))
                            }.frame(maxWidth: .infinity).frame(minHeight: 55).background(.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }.foregroundStyle(.black).disabled(!session.providers.google || session.busy).opacity(session.providers.google ? 1 : 0.4)
                        Button { showEmail = true } label: {
                            Label("Continuer avec mon e-mail", systemImage: "envelope.fill").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(minHeight: 51)
                                .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16))
                        }.foregroundStyle(.white)
                        if session.busy { ProgressView().tint(NW.blue) }
                        if let error = session.error { Text(error).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center) }
                        HStack {
                            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                            Text("OU").font(.system(size: 8, weight: .bold)).tracking(1.5).foregroundStyle(NW.muted)
                            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                        }.padding(.vertical, 2)
                        Button { session.enterGuest() } label: {
                            HStack { Text("Essayer sur cet iPhone"); Spacer(); Image(systemName: "arrow.right") }.font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        }.foregroundStyle(.white)
                        Text("Le mode local ne demande aucun compte.").font(.caption2).foregroundStyle(NW.muted).frame(maxWidth: .infinity)
                    }.padding(18).premiumPanel(radius: 26)

                    Button("Confidentialité et traitement des données") { showPrivacy = true }
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(NW.muted).frame(maxWidth: .infinity).padding(.bottom, 16)
                }.padding(.horizontal, 22).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
        }
        .task { await session.loadProviders(); await session.prepareApple() }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) { floating = true }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulse = true }
        }
        .sheet(isPresented: $showEmail) { EmailAuthView() }
        .sheet(isPresented: $showPrivacy) { PrivacyView() }
    }

    private func promise(_ title: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(NW.cyan)
            Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
        }.frame(maxWidth: .infinity).padding(.vertical, 13).premiumPanel(radius: 17)
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
