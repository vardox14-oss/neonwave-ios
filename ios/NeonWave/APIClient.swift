import Foundation
import Security

enum Keychain {
    private static let service = "app.neonwave.ios"
    private static let defaults = UserDefaults.standard
    private static let prefix = "nw_sec_"

    static func read(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            return data
        }
        return defaults.data(forKey: prefix + key)
    }

    static func save(_ data: Data, key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        if status != errSecSuccess {
            // In iOS Simulator or sandboxes like Appetize without keychain entitlements (-34018),
            // safely persist in user defaults so account creation/login never fails.
            defaults.set(data, forKey: prefix + key)
        }
    }

    static func delete(_ key: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ] as CFDictionary)
        defaults.removeObject(forKey: prefix + key)
    }
}

struct APIClient {
    var token: String? { Keychain.read("token").flatMap { String(data: $0, encoding: .utf8) } }
    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, authenticated: Bool = true) throws -> URLRequest {
        guard let base = AppConfiguration.apiURL else { throw MessageError("La connexion aux comptes sera disponible après configuration du service NeonWave. Votre bibliothèque locale reste accessible.") }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method; request.timeoutInterval = 30; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return request
    }
    func call<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil, authenticated: Bool = true) async throws -> T {
        let request = try request(path, method: method, body: body, authenticated: authenticated)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            throw MessageError(payload?["error"] ?? "Le service est indisponible (\(response.statusCode)). Réessayez.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
