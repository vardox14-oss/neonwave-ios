import Foundation
import AVFoundation
import Combine
import UIKit
import SwiftUI
import Network

final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()
    static let sessionIdentifier = "app.neonwave.ios.audio-downloads"
    @Published private(set) var progress: [String: Double] = [:]
    @Published var error: String?
    @Published var toastMessage: String?
    var backgroundCompletion: (() -> Void)?
    private weak var library: LibraryStore?
    private var preparationTasks: [String: Task<Void, Never>] = [:]
    private var toastDismissTask: Task<Void, Never>?

    @MainActor func showSuccessToast(_ message: String) {
        toastDismissTask?.cancel()
        toastMessage = message
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                if self.toastMessage == message {
                    self.toastMessage = nil
                }
            }
        }
    }
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    struct DownloadInfo: Codable {
        let trackID: String
        let userID: String
        let destination: URL
    }
    @MainActor func connect(_ library: LibraryStore) {
        self.library = library
        session.getAllTasks { tasks in
            Task { @MainActor in
                for task in tasks {
                    guard let info = Self.info(task), info.userID == library.userID else { task.cancel(); continue }
                    self.progress[info.trackID] = task.countOfBytesExpectedToReceive > 0 ? Double(task.countOfBytesReceived) / Double(task.countOfBytesExpectedToReceive) : 0
                    if FileManager.default.fileExists(atPath: info.destination.path) { library.finishDownload(trackID: info.trackID, fileName: info.destination.lastPathComponent) }
                }
            }
        }
        // Recover a completed background download whose delegate event preceded UI initialization.
        for track in library.tracks where track.canDownload && library.localURL(track) == nil {
            for ext in ["m4a", "mp3"] {
                let destination = library.downloadDestination(track, fileExtension: ext)
                if FileManager.default.fileExists(atPath: destination.path) {
                    library.finishDownload(trackID: track.id, fileName: destination.lastPathComponent)
                    break
                }
            }
        }
    }
    @MainActor func download(_ track: Track) {
        guard let library, library.localURL(track) == nil, progress[track.id] == nil else { return }
        library.addTrackIfMissing(track)
        progress[track.id] = 0
        error = nil
        let owner = library.userID
        preparationTasks[track.id]?.cancel()
        preparationTasks[track.id] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let prepared = try await self.prepareRequest(for: track, library: library)
                guard !Task.isCancelled, self.library?.userID == owner else {
                    self.progress[track.id] = nil
                    return
                }
                if let videoID = prepared.videoID { library.setResolvedVideoID(trackID: track.id, videoID: videoID) }
                let destination = library.downloadDestination(track, fileExtension: prepared.fileExtension)
                let info = DownloadInfo(trackID: track.id, userID: owner, destination: destination)
                let task = self.session.downloadTask(with: prepared.request)
                task.taskDescription = String(data: try JSONEncoder().encode(info), encoding: .utf8)
                self.preparationTasks[track.id] = nil
                task.resume()
            } catch is CancellationError {
                self.preparationTasks[track.id] = nil
                self.progress[track.id] = nil
            } catch {
                self.preparationTasks[track.id] = nil
                self.progress[track.id] = nil
                self.error = error.localizedDescription
            }
        }
    }
    @MainActor private func prepareRequest(for track: Track, library: LibraryStore) async throws -> (request: URLRequest, fileExtension: String, videoID: String?) {
        if let remoteID = track.remoteID {
            var request = try APIClient().request("api/user/local-tracks/\(remoteID)/stream")
            request.allowsCellularAccess = !library.snapshot.wifiOnly
            return (request, sourceExtension(track.streamURL) ?? "mp3", nil)
        }

        let videoID = await MusicCatalogService.resolveYouTubeId(
                title: track.title,
                artist: track.artist,
                duration: track.duration,
                spotifyId: track.spotifyId
            ) ?? track.videoId
        if let videoID, let url = await MusicCatalogService.nativeStreamURL(videoId: videoID) {
            var request = URLRequest(url: url)
            if url.host?.hasSuffix(".googlevideo.com") == true,
               let rawLength = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "clen" })?.value,
               let length = Int64(rawLength), length > 0 {
                request.setValue("bytes=0-\(length - 1)", forHTTPHeaderField: "Range")
            }
            request.timeoutInterval = 60
            request.allowsCellularAccess = !library.snapshot.wifiOnly
            return (request, "m4a", videoID)
        }

        if let stream = track.streamURL, let request = try directRequest(stream, allowsCellular: !library.snapshot.wifiOnly) {
            return (request, sourceExtension(stream) ?? "mp3", videoID)
        }
        throw MessageError("Ce titre n’est pas encore disponible au téléchargement. Réessayez dans quelques secondes.")
    }
    private func directRequest(_ source: String, allowsCellular: Bool) throws -> URLRequest? {
        let request: URLRequest
        if let url = URL(string: source), let scheme = url.scheme, scheme == "https" || scheme == "http" {
            request = URLRequest(url: url)
        } else if !source.isEmpty {
            guard let base = AppConfiguration.apiURL,
                  let url = URL(string: source.trimmingCharacters(in: CharacterSet(charactersIn: "/")), relativeTo: base.appendingPathComponent(""))?.absoluteURL else {
                throw URLError(.badURL)
            }
            var authenticated = URLRequest(url: url)
            if let token = APIClient().token { authenticated.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            request = authenticated
        } else {
            return nil
        }
        var result = request
        result.allowsCellularAccess = allowsCellular
        result.timeoutInterval = 60
        return result
    }
    private func sourceExtension(_ source: String?) -> String? {
        guard let source, let url = URL(string: source) else { return nil }
        switch url.pathExtension.lowercased() {
        case "m4a", "aac", "mp4": return "m4a"
        case "mp3": return "mp3"
        default: return nil
        }
    }
    @MainActor func cancel(_ trackID: String) {
        preparationTasks[trackID]?.cancel()
        preparationTasks[trackID] = nil
        progress[trackID] = nil
        session.getAllTasks { tasks in tasks.filter { Self.info($0)?.trackID == trackID }.forEach { $0.cancel() } }
    }
    func cancelAll() async {
        let tasks: [URLSessionTask] = await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
        tasks.forEach { $0.cancel() }
        await MainActor.run {
            preparationTasks.values.forEach { $0.cancel() }
            preparationTasks = [:]
            progress = [:]
        }
    }
    private static func info(_ task: URLSessionTask) -> DownloadInfo? {
        guard let data = task.taskDescription?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DownloadInfo.self, from: data)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let info = Self.info(downloadTask) else { return }
        Task { @MainActor in
            guard self.library?.userID == info.userID else { return }
            self.progress[info.trackID] = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let info = Self.info(downloadTask) else { return }
        guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            Task { @MainActor in self.progress[info.trackID] = nil; self.error = "Téléchargement impossible. Réessayez." }; return
        }
        do {
            let mime = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard !mime.contains("application/json"), !mime.hasPrefix("text/"), size > 16_384 else {
                throw MessageError("Le serveur n’a pas renvoyé un fichier audio valide.")
            }
            // URLSession deletes the temporary file when this callback returns.
            if FileManager.default.fileExists(atPath: info.destination.path) { try? FileManager.default.removeItem(at: info.destination) }
            try FileManager.default.moveItem(at: location, to: info.destination)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: info.destination.path)
            var url = info.destination; var values = URLResourceValues(); values.isExcludedFromBackup = true; try? url.setResourceValues(values)
            Task { @MainActor in
                guard self.library?.userID == info.userID else { return }
                self.library?.finishDownload(trackID: info.trackID, fileName: info.destination.lastPathComponent)
                self.progress[info.trackID] = nil
                let trackTitle = self.library?.tracks.first(where: { $0.id == info.trackID })?.title
                let titlePrefix = trackTitle.map { "« \($0) »" } ?? "Musique"
                self.showSuccessToast("\(titlePrefix) téléchargée avec succès")
                if let library = self.library { Task { await library.cacheOfflineMedia(trackID: info.trackID) } }
            }
        } catch {
            Task { @MainActor in
                self.progress[info.trackID] = nil
                self.error = "Erreur lors de l'enregistrement du fichier."
            }
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let info = Self.info(task), let error else { return }
        Task { @MainActor in
            self.progress[info.trackID] = nil
            if (error as NSError).code != NSURLErrorCancelled { self.error = "Le téléchargement a été interrompu. Touchez la flèche pour réessayer." }
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Allow CDN redirections (Deezer, iTunes, etc.), stripping private auth header if host changes.
        if let url = request.url, url.scheme == "https" || url.scheme == "http" {
            var sanitized = request
            if request.url?.host != task.originalRequest?.url?.host {
                sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
            }
            completionHandler(sanitized)
        } else {
            completionHandler(nil)
        }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { self.backgroundCompletion?(); self.backgroundCompletion = nil }
    }
}

@MainActor
final class NetworkMonitor: NSObject, ObservableObject {
    static let shared = NetworkMonitor()
    @Published private(set) var isConnected: Bool = true
    @Published var isOfflineModeForced: Bool = false {
        didSet {
            UserDefaults.standard.set(isOfflineModeForced, forKey: "forceOfflineMode")
        }
    }

    var isActuallyOffline: Bool {
        isOfflineModeForced || !isConnected
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.neonwave.networkmonitor")

    private override init() {
        super.init()
        self.isOfflineModeForced = UserDefaults.standard.bool(forKey: "forceOfflineMode")
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }
}
