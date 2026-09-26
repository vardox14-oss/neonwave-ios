import Foundation
import AVFoundation
import Combine

final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()
    static let sessionIdentifier = "app.neonwave.ios.audio-downloads"
    @Published private(set) var progress: [String: Double] = [:]
    @Published var error: String?
    var backgroundCompletion: (() -> Void)?
    private weak var library: LibraryStore?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
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
        for track in library.tracks where track.remoteID != nil && library.localURL(track) == nil {
            let destination = library.downloadDestination(track)
            if FileManager.default.fileExists(atPath: destination.path) { library.finishDownload(trackID: track.id, fileName: destination.lastPathComponent) }
        }
    }
    @MainActor func download(_ track: Track) {
        guard let library, library.localURL(track) == nil, progress[track.id] == nil else { return }
        library.addTrackIfMissing(track)
        do {
            let request: URLRequest
            if let stream = track.streamURL, let url = URL(string: stream) {
                var req = URLRequest(url: url)
                req.allowsCellularAccess = !library.snapshot.wifiOnly
                request = req
            } else if let remoteID = track.remoteID {
                var req = try APIClient().request("api/user/local-tracks/\(remoteID)/stream")
                req.allowsCellularAccess = !library.snapshot.wifiOnly
                request = req
            } else {
                return
            }
            let info = DownloadInfo(trackID: track.id, userID: library.userID, destination: library.downloadDestination(track))
            let task = session.downloadTask(with: request)
            task.taskDescription = String(data: try JSONEncoder().encode(info), encoding: .utf8)
            progress[track.id] = 0; task.resume()
        } catch { self.error = error.localizedDescription }
    }
    func cancel(_ trackID: String) {
        session.getAllTasks { tasks in tasks.filter { Self.info($0)?.trackID == trackID }.forEach { $0.cancel() } }
    }
    func cancelAll() async {
        let tasks: [URLSessionTask] = await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
        tasks.forEach { $0.cancel() }
        await MainActor.run { progress = [:] }
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
            // URLSession deletes the temporary file when this callback returns.
            if FileManager.default.fileExists(atPath: info.destination.path) { try? FileManager.default.removeItem(at: info.destination) }
            try FileManager.default.moveItem(at: location, to: info.destination)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: info.destination.path)
            var url = info.destination; var values = URLResourceValues(); values.isExcludedFromBackup = true; try? url.setResourceValues(values)
            Task { @MainActor in
                guard self.library?.userID == info.userID else { return }
                self.library?.finishDownload(trackID: info.trackID, fileName: info.destination.lastPathComponent)
                self.progress[info.trackID] = nil
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
