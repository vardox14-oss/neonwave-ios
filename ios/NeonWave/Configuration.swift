import Foundation

enum AppConfiguration {
    static var apiURL: URL? {
        if let custom = UserDefaults.standard.string(forKey: "custom_api_url"),
           let url = URL(string: custom), url.scheme == "https" || url.scheme == "http" {
            return url
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: "NeonWaveAPIURL") as? String,
           let url = URL(string: value), url.scheme == "https", let host = url.host,
           !host.hasSuffix(".example"), !value.contains("$(") {
            return url
        }
        #if DEBUG
        return URL(string: "https://fifty-singers-tan.loca.lt")
        #else
        return nil
        #endif
    }
    static func publicURL(_ key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: value), url.scheme == "https", let host = url.host,
              !host.hasSuffix(".example"), !value.contains("$(") else { return nil }
        return url
    }
}
