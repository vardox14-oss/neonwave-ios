import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

@MainActor final class SessionStore: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var account: Account?
    @Published var isGuest = false
    @Published var busy = false
    @Published var error: String?
    @Published var providers = AuthProviders()
    private var webSession: ASWebAuthenticationSession?
    @Published private var appleChallenge: AppleChallenge?
    let api = APIClient()
    var authenticated: Bool { account != nil || isGuest }
    var storageID: String { account?.id ?? "guest" }

    override init() {
        super.init()
        if Keychain.read("token") != nil, let data = Keychain.read("account") { account = try? JSONDecoder().decode(Account.self, from: data) }
        isGuest = account == nil && UserDefaults.standard.bool(forKey: "localMode")
    }
    func loadProviders() async {
        guard Configuration.apiURL != nil else { return }
        do { providers = try await api.call("api/ios/auth/providers", authenticated: false) }
        catch { self.error = "Connexion au service indisponible. Vous pouvez utiliser votre bibliothèque locale." }
    }
    func enterGuest() { isGuest = true; UserDefaults.standard.set(true, forKey: "localMode") }
    private func accept(_ response: AuthResponse) throws {
        try Keychain.save(Data(response.token.utf8), key: "token")
        try Keychain.save(JSONEncoder().encode(response.user), key: "account")
        account = response.user; isGuest = false; UserDefaults.standard.set(false, forKey: "localMode")
    }
    func emailLogin(email: String, password: String, username: String?) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            var body: [String: Any] = ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password, "rememberMe": true]
            if let username { body["username"] = username }
            let result: AuthResponse = try await api.call(username == nil ? "api/auth/login" : "api/auth/register", method: "POST", body: body, authenticated: false)
            try accept(result)
        } catch { self.error = error.localizedDescription }
    }
    func signInGoogle() {
        guard !busy, providers.google, let base = Configuration.apiURL else { return }
        busy = true; error = nil
        let verifier = randomToken()
        let state = randomToken()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        var components = URLComponents(url: base.appendingPathComponent("api/ios/auth/google"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "challenge", value: challenge), .init(name: "state", value: state)]
        webSession = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: "neonwave") { [weak self] url, error in
            Task { @MainActor in
                guard let self else { return }
                defer { self.busy = false; self.webSession = nil }
                if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin { return }
                guard let url, url.host == "auth", let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                      query.first(where: { $0.name == "state" })?.value == state else {
                    self.error = "La connexion Google a été interrompue. Réessayez."; return
                }
                if let reason = query.first(where: { $0.name == "error" })?.value { self.error = Self.authMessage(reason); return }
                guard let ticket = query.first(where: { $0.name == "ticket" })?.value else { self.error = "Réponse Google incomplète."; return }
                do {
                    let result: AuthResponse = try await self.api.call("api/ios/auth/exchange", method: "POST", body: ["ticket": ticket, "verifier": verifier], authenticated: false)
                    try self.accept(result)
                } catch { self.error = error.localizedDescription }
            }
        }
        webSession?.presentationContextProvider = self
        webSession?.prefersEphemeralWebBrowserSession = true
        if webSession?.start() != true { busy = false; error = "Impossible d’ouvrir la connexion Google." }
    }
    struct AppleChallenge: Decodable { let id: String; let nonce: String }
    func prepareApple() async {
        guard providers.apple else { return }
        do { appleChallenge = try await api.call("api/ios/auth/apple/challenge", method: "POST", authenticated: false) }
        catch { self.error = error.localizedDescription }
    }
    var appleReady: Bool { appleChallenge != nil }
    func configureApple(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        if let challenge = appleChallenge { request.nonce = SHA256.hash(data: Data(challenge.nonce.utf8)).map { String(format: "%02x", $0) }.joined() }
    }
    func completeApple(_ result: Result<ASAuthorization, Error>) async {
        guard let challenge = appleChallenge else { return }
        busy = true; error = nil
        defer { busy = false; appleChallenge = nil; Task { await prepareApple() } }
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8),
                  let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8) else { throw MessageError("Réponse Apple incomplète.") }
            let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) } ?? ""
            let response: AuthResponse = try await api.call("api/ios/auth/apple", method: "POST", body: ["challengeID": challenge.id, "identityToken": token, "authorizationCode": code, "username": name], authenticated: false)
            try accept(response)
        } catch let authError as ASAuthorizationError where authError.code == .canceled { }
        catch { self.error = error.localizedDescription }
    }
    func signOut() {
        Keychain.delete("token"); Keychain.delete("account")
        account = nil; isGuest = false; UserDefaults.standard.set(false, forKey: "localMode")
    }
    func deleteAccount() async throws {
        struct Result: Decodable { let success: Bool }
        let _: Result = try await api.call("api/ios/account", method: "DELETE")
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    private func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return UUID().uuidString + UUID().uuidString }
        return Data(bytes).base64URLEncoded
    }
    private static func authMessage(_ reason: String) -> String {
        switch reason {
        case "email_exists": return "Un compte utilise déjà cet e-mail. Connectez-vous avec votre mot de passe."
        case "registration_closed": return "Les inscriptions sont actuellement fermées."
        case "cancelled": return "Connexion annulée."
        default: return "La connexion Google n’a pas abouti. Réessayez ou utilisez votre e-mail."
        }
    }
}

extension Data {
    var base64URLEncoded: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
