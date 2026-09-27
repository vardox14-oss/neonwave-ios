import SwiftUI

@MainActor final class MusicTasteStore: ObservableObject {
    static let genres = ["Rap", "Drill", "R&B", "Afro", "Pop", "Electro", "House", "Techno", "Trap", "Dancehall", "Amapiano", "Latino"]
    static let featuredNames = ["Ninho", "Tiakola", "SCH", "Damso", "Gazo", "Aya Nakamura", "Burna Boy", "Drake", "The Weeknd", "Travis Scott", "Jul", "Maes"]

    @Published private(set) var preferences = MusicPreferences()
    @Published private(set) var isLoaded = false
    @Published private(set) var saving = false
    @Published private(set) var recommendations: [Track] = []
    @Published var error: String?

    private var storageID = "guest"
    private var recommendationTask: Task<Void, Never>?

    func activate(_ id: String) async {
        storageID = id
        isLoaded = false
        recommendations = []
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(MusicPreferences.self, from: data) {
            preferences = saved
        } else {
            preferences = MusicPreferences()
        }
        if AppConfiguration.apiURL != nil, let remote: MusicPreferences = try? await APIClient().call("api/user/music-preferences") {
            preferences = remote
            persist()
        }
        isLoaded = true
        if preferences.completed { loadRecommendations() }
    }

    func save(genres: [String], artists: [ArtistChoice]) async -> Bool {
        guard genres.count == 3, artists.count >= 3 else {
            error = genres.count != 3 ? "Choisissez exactement 3 styles." : "Choisissez au moins 3 artistes."
            return false
        }
        saving = true
        error = nil
        defer { saving = false }
        var saved = MusicPreferences(completed: true, genres: genres, artists: artists, followedArtists: artists)
        if AppConfiguration.apiURL != nil {
            let body: [String: Any] = [
                "genres": genres,
                "artists": artists.map { artist in
                    ["spotifyId": artist.spotifyId, "name": artist.name, "imageUrl": artist.imageUrl, "spotifyUrl": artist.spotifyUrl, "genres": artist.genres, "popularity": artist.popularity, "followers": artist.followers, "source": artist.source]
                }
            ]
            do {
                let remote: MusicPreferences = try await APIClient().call("api/user/music-preferences", method: "POST", body: body)
                saved = remote
            } catch {
                self.error = "Vos goûts sont enregistrés sur cet iPhone. La synchronisation du compte reprendra dès que le service sera disponible."
            }
        }
        preferences = saved
        persist()
        loadRecommendations()
        return true
    }

    func isFollowed(_ artistName: String) -> Bool {
        preferences.followedArtists.contains { $0.name.caseInsensitiveCompare(artistName) == .orderedSame }
    }

    func toggleFollow(name: String, spotifyId: String? = nil, imageUrl: String? = nil) {
        if isFollowed(name) {
            preferences.followedArtists.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        } else {
            let choice = ArtistChoice(spotifyId: spotifyId ?? "", name: name, imageUrl: imageUrl ?? "")
            preferences.followedArtists.append(choice)
        }
        persist()
        if AppConfiguration.apiURL != nil {
            Task {
                let body: [String: Any] = [
                    "genres": preferences.genres,
                    "artists": preferences.artists.map { [
                        "spotifyId": $0.spotifyId, "name": $0.name, "imageUrl": $0.imageUrl,
                        "spotifyUrl": $0.spotifyUrl, "genres": $0.genres, "popularity": $0.popularity,
                        "followers": $0.followers, "source": $0.source
                    ]},
                    "followedArtists": preferences.followedArtists.map { [
                        "spotifyId": $0.spotifyId, "name": $0.name, "imageUrl": $0.imageUrl,
                        "spotifyUrl": $0.spotifyUrl, "genres": $0.genres, "popularity": $0.popularity,
                        "followers": $0.followers, "source": $0.source
                    ]}
                ]
                _ = try? await APIClient().call("api/user/music-preferences", method: "POST", body: body)
            }
        }
    }

    func loadRecommendations() {
        recommendationTask?.cancel()
        let artists = preferences.artists
        recommendationTask = Task { [weak self] in
            let names = Array(artists.prefix(5)).map(\.name)
            let batches = await withTaskGroup(of: [Track].self, returning: [[Track]].self) { group in
                names.forEach { name in group.addTask { await MusicCatalogService.searchTracks(name) } }
                var values: [[Track]] = []
                for await value in group { values.append(value) }
                return values
            }
            guard !Task.isCancelled else { return }
            var seen = Set<String>()
            let merged = batches.flatMap { $0.prefix(5) }.filter { seen.insert($0.id).inserted }
            await MainActor.run { self?.recommendations = Array(merged.prefix(16)) }
        }
    }

    private var key: String { "nw_music_preferences_\(storageID)" }
    private func persist() {
        if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: key) }
    }
}

enum ArtistDiscoveryService {
    private struct ArtistResponse: Decodable { let items: [ArtistChoice] }
    private struct DeezerResponse: Decodable {
        struct Item: Decodable {
            let id: Int
            let name: String
            let picture_xl: String?
            let picture_big: String?
        }
        let data: [Item]?
    }

    static func featured() async -> [ArtistChoice] {
        guard AppConfiguration.apiURL != nil else {
            return MusicTasteStore.featuredNames.map { ArtistChoice(name: $0) }
        }
        let response: ArtistResponse? = try? await APIClient().call(
            "api/spotify/artists/defaults",
            authenticated: false
        )
        guard let items = response?.items.filter({ !$0.spotifyId.isEmpty && $0.source == "spotify" }), !items.isEmpty else {
            return MusicTasteStore.featuredNames.map { ArtistChoice(name: $0) }
        }
        let byName = Dictionary(items.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        return MusicTasteStore.featuredNames.compactMap { byName[$0.lowercased()] }
    }

    static func search(_ query: String) async -> [ArtistChoice] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else { return [] }
        if AppConfiguration.apiURL != nil {
            let response: ArtistResponse? = try? await APIClient().call(
                "api/spotify/search-artists",
                authenticated: false,
                queryItems: [.init(name: "q", value: value)]
            )
            return response?.items.filter { !$0.spotifyId.isEmpty && $0.source == "spotify" } ?? []
        }
        guard var components = URLComponents(string: "https://api.deezer.com/search/artist") else { return [] }
        components.queryItems = [.init(name: "q", value: value), .init(name: "limit", value: "8")]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(DeezerResponse.self, from: data) else { return [] }
        return (response.data ?? []).map { ArtistChoice(spotifyId: "", name: $0.name, imageUrl: $0.picture_xl ?? $0.picture_big ?? "", source: "deezer") }
    }
}

struct TasteOnboardingView: View {
    @EnvironmentObject private var taste: MusicTasteStore
    @Environment(\.dismiss) private var dismiss
    var editing = false
    @State private var step = 0
    @State private var genres: [String] = []
    @State private var artists: [ArtistChoice] = []
    @State private var suggestions: [ArtistChoice] = []
    @State private var featuredArtists: [ArtistChoice] = []
    @State private var query = ""
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.035, green: 0.02, blue: 0.12), NW.background, Color(red: 0.01, green: 0.12, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            Circle().fill(NW.blue.opacity(0.22)).frame(width: 330).blur(radius: 80).offset(x: 170, y: -310)
            VStack(spacing: 0) {
                HStack {
                    if editing { Button("Fermer") { dismiss() }.foregroundStyle(.white.opacity(0.75)) }
                    Spacer()
                    Text("\(step + 1) / 2").font(.caption.bold()).foregroundStyle(.white.opacity(0.6))
                }.frame(height: 44)
                HStack(spacing: 7) {
                    Capsule().fill(.white).frame(height: 4)
                    Capsule().fill(step == 1 ? .white : .white.opacity(0.18)).frame(height: 4)
                }
                .padding(.bottom, 28)

                if step == 0 { genreStep.transition(.move(edge: .leading).combined(with: .opacity)) }
                else { artistStep.transition(.move(edge: .trailing).combined(with: .opacity)) }
            }.padding(.horizontal, 22).padding(.bottom, 18)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if genres.isEmpty { genres = taste.preferences.genres; artists = taste.preferences.artists }
            if suggestions.isEmpty { suggestions = MusicTasteStore.featuredNames.map { ArtistChoice(name: $0) } }
        }
        .task { await loadFeaturedArtists() }
        .alert("NeonWave", isPresented: Binding(get: { taste.error != nil }, set: { if !$0 { taste.error = nil } })) { Button("D’accord", role: .cancel) { taste.error = nil } } message: { Text(taste.error ?? "") }
    }

    private var genreStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 0)
            Image(systemName: "waveform.path.ecg.rectangle.fill").font(.system(size: 36)).foregroundStyle(NW.blue)
            Text("Quelle énergie\nvous ressemble ?").font(.system(size: 39, weight: .bold, design: .rounded)).tracking(-1.5)
            Text("Choisissez exactement 3 styles. Votre accueil et vos découvertes s’adapteront à vos goûts.").font(.subheadline).foregroundStyle(.white.opacity(0.62)).lineSpacing(4)
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 12) {
                ForEach(MusicTasteStore.genres, id: \.self) { genre in
                    let selected = genres.contains(genre)
                    Button {
                        if selected { genres.removeAll { $0 == genre } }
                        else if genres.count < 3 { genres.append(genre) }
                    } label: {
                        Text(genre).font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(selected ? AnyShapeStyle(NW.blue.gradient) : AnyShapeStyle(.white.opacity(0.07)), in: RoundedRectangle(cornerRadius: 17))
                            .overlay(RoundedRectangle(cornerRadius: 17).stroke(selected ? .white.opacity(0.35) : .white.opacity(0.07)))
                    }.buttonStyle(PressStyle())
                }
            }
            Spacer(minLength: 8)
            PrimaryButton(title: genres.count == 3 ? "Continuer" : "\(genres.count) sur 3", symbol: "arrow.right") {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step = 1 }
            }.disabled(genres.count != 3).opacity(genres.count == 3 ? 1 : 0.45)
        }
    }

    private var artistStep: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Vos artistes,\nvotre NeonWave.").font(.system(size: 36, weight: .bold, design: .rounded)).tracking(-1.3)
            Text("Sélectionnez au moins 3 artistes.").font(.subheadline).foregroundStyle(.white.opacity(0.62))
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                TextField("Rechercher un artiste", text: $query).autocorrectionDisabled()
                if searching { ProgressView().scaleEffect(0.75) }
            }.padding(15).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .onChange(of: query) { _, value in search(value) }
            ScrollView {
                if suggestions.isEmpty && !searching && query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                    VStack(spacing: 10) {
                        Image(systemName: "music.mic").font(.title2).foregroundStyle(NW.blue)
                        Text("Aucun profil d'artiste trouvé").font(.subheadline.bold())
                        Text("Essayez le nom complet de l’artiste.").font(.caption).foregroundStyle(.white.opacity(0.55))
                    }.frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 18) {
                        ForEach(suggestions) { artist in artistCard(artist) }
                    }.padding(.vertical, 6)
                }
            }.scrollIndicators(.hidden)
            HStack {
                Button { withAnimation(.spring()) { step = 0 } } label: { Image(systemName: "chevron.left").frame(width: 54, height: 54).background(.white.opacity(0.08), in: Circle()) }
                PrimaryButton(title: artists.count >= 3 ? "Créer mon espace" : "\(artists.count) artiste\(artists.count > 1 ? "s" : "")", symbol: "sparkles", loading: taste.saving) {
                    Task { if await taste.save(genres: genres, artists: artists), editing { dismiss() } }
                }.disabled(artists.count < 3 || taste.saving).opacity(artists.count >= 3 ? 1 : 0.45)
            }
        }
    }

    private func artistCard(_ artist: ArtistChoice) -> some View {
        let selected = artists.contains(where: { $0.id == artist.id })
        return Button {
            if selected { artists.removeAll { $0.id == artist.id } } else { artists.append(artist) }
        } label: {
            VStack(spacing: 9) {
                ZStack {
                    Circle().fill(LinearGradient(colors: NW.colors[artist.colorIndex], startPoint: .topLeading, endPoint: .bottomTrailing))
                    if let url = URL(string: artist.imageUrl), !artist.imageUrl.isEmpty {
                        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.28))) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill().transition(.opacity)
                            case .empty: ProgressView().tint(.white.opacity(0.8))
                            case .failure: initials(artist.name)
                            @unknown default: initials(artist.name)
                            }
                        }.clipShape(Circle())
                    } else { initials(artist.name) }
                    Circle().stroke(selected ? NW.blue : .white.opacity(0.12), lineWidth: selected ? 3 : 1)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.bold()).foregroundStyle(.white)
                            .frame(width: 27, height: 27).background(NW.blue.gradient, in: Circle())
                            .overlay(Circle().stroke(NW.background, lineWidth: 3))
                            .offset(x: 31, y: 31)
                    }
                }.frame(height: 92).scaleEffect(selected ? 1.04 : 1)
                Text(artist.name).font(.caption.bold()).lineLimit(1)
                if !artist.imageUrl.isEmpty { Text("VÉRIFIÉ").font(.system(size: 7, weight: .bold)).tracking(1.1).foregroundStyle(NW.blue.opacity(0.85)) }
            }
        }.buttonStyle(PressStyle()).animation(.spring(response: 0.35, dampingFraction: 0.76), value: selected)
    }

    private func initials(_ name: String) -> some View { Text(String(name.prefix(1))).font(.title.bold()).foregroundStyle(.white) }

    private func search(_ value: String) {
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = featuredArtists.isEmpty ? MusicTasteStore.featuredNames.map { ArtistChoice(name: $0) } : featuredArtists
            searching = false
            return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let values = await ArtistDiscoveryService.search(trimmed)
            guard !Task.isCancelled else { return }
            await MainActor.run { suggestions = values; searching = false }
        }
    }

    private func loadFeaturedArtists() async {
        let values = await ArtistDiscoveryService.featured()
        guard !values.isEmpty else { return }
        featuredArtists = values
        if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 { suggestions = values }
    }
}

struct ArtistIdentifier: Identifiable, Hashable {
    var id: String { spotifyId.map { "sp-\($0)" } ?? name.lowercased() }
    let name: String
    let spotifyId: String?
    let imageUrl: String?

    init(name: String, spotifyId: String? = nil, imageUrl: String? = nil) {
        self.name = name
        self.spotifyId = spotifyId
        self.imageUrl = imageUrl
    }
}

@MainActor final class ArtistRouter: ObservableObject {
    @Published var selectedArtist: ArtistIdentifier?

    func open(name: String, spotifyId: String? = nil, imageUrl: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedArtist = ArtistIdentifier(name: trimmed, spotifyId: spotifyId, imageUrl: imageUrl)
    }

    func open(artist: ArtistChoice) {
        open(name: artist.name, spotifyId: artist.spotifyId.isEmpty ? nil : artist.spotifyId, imageUrl: artist.imageUrl.isEmpty ? nil : artist.imageUrl)
    }
}
