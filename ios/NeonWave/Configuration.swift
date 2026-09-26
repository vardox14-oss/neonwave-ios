import Foundation

enum Configuration {
    static var apiURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "NeonWaveAPIURL") as? String,
              let url = URL(string: value), url.scheme == "https", let host = url.host,
              !host.hasSuffix(".example"), !value.contains("$(") else { return nil }
        return url
    }
    static func publicURL(_ key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: value), url.scheme == "https", let host = url.host,
              !host.hasSuffix(".example"), !value.contains("$(") else { return nil }
        return url
    }
}
