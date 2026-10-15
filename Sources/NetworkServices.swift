import Foundation

@MainActor
final class MediaAPIService: ObservableObject {
    static let shared = MediaAPIService()
    
    private var searchCache: [String: [MediaItem]] = [:]
    private var reviewsCache: [String: [CommunityReview]] = [:]
    
    private init() {}
    
    // MARK: - Uniwersalna Wyszukiwarka dla 5 Kategorii
    func search(query: String, category: MediaCategory) async throws -> [MediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        let cacheKey = "\(category.rawValue)-\(trimmed.lowercased())"
        if let cached = searchCache[cacheKey] {
            return cached
        }
        
        let results: [MediaItem]
        switch category {
        case .movie:
            results = try await searchMovies(query: trimmed)
        case .series:
            results = try await searchSeries(query: trimmed)
        case .book:
            results = try await searchBooks(query: trimmed)
        case .music:
            results = try await searchMusic(query: trimmed)
        case .game:
            results = try await searchGames(query: trimmed)
        }
        
        searchCache[cacheKey] = results
        return results
    }
    
    // MARK: - 1. Filmy (TMDb jeśli podano klucz w Keychain, w przeciwnym razie Apple iTunes Movie API)
    private func searchMovies(query: String) async throws -> [MediaItem] {
        if let tmdbKey = KeychainService.shared.read(forKey: "tmdb_api_key"), !tmdbKey.isEmpty {
            if let tmdbResults = try? await searchMoviesTMDb(query: query, apiKey: tmdbKey), !tmdbResults.isEmpty {
                return tmdbResults
            }
        }
        
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=movie&country=pl&limit=18")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        
        return decoded.results.compactMap { item in
            guard let trackId = item.trackId, let title = item.trackName else { return nil }
            let hiResArt = item.artworkUrl100?.replacingOccurrences(of: "100x100bb", with: "600x600bb")
            let year = item.releaseDate.map { String($0.prefix(4)) } ?? "Brak daty"
            return MediaItem(
                id: "movie-\(trackId)",
                externalID: String(trackId),
                title: title,
                creator: item.artistName ?? "Reżyser nieznany",
                category: .movie,
                releaseYear: year,
                genres: [item.primaryGenreName].compactMap { $0 },
                overview: item.longDescription ?? item.shortDescription ?? "Brak opisu fabuły w bazie katalogowej.",
                coverURL: hiResArt,
                communityScore: nil,
                communityVotesCount: nil,
                dataSourceName: "Apple iTunes Movies",
                userRating: nil,
                userReview: "",
                privateNote: "",
                status: nil,
                updatedAt: Date(),
                syncedOnPassportDex: false
            )
        }
    }
    
    private func searchMoviesTMDb(query: String, apiKey: String) async throws -> [MediaItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "https://api.themoviedb.org/3/search/movie?api_key=\(apiKey)&query=\(encoded)&language=pl-PL")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(TMDbMovieResponse.self, from: data)
        return decoded.results.map { movie in
            let year = movie.release_date.map { String($0.prefix(4)) } ?? ""
            let cover = movie.poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" }
            return MediaItem(
                id: "tmdb-movie-\(movie.id)",
                externalID: String(movie.id),
                title: movie.title,
                creator: "Katalog TMDb",
                category: .movie,
                releaseYear: year,
                genres: ["Film"],
                overview: movie.overview.isEmpty ? "Brak polskiego opisu w bazie TMDb." : movie.overview,
                coverURL: cover,
                communityScore: movie.vote_average,
                communityVotesCount: movie.vote_count,
                dataSourceName: "TMDb (Źródło PassportDex)",
                userRating: nil,
                userReview: "",
                privateNote: "",
                status: nil,
                updatedAt: Date(),
                syncedOnPassportDex: false
            )
        }
    }
    
    // MARK: - 2. Seriale (TVMaze API - darmowe, zwraca oceny w skali 1-10)
    private func searchSeries(query: String) async throws -> [MediaItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "https://api.tvmaze.com/search/shows?q=\(encoded)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode([TVMazeSearchResult].self, from: data)
        
        return decoded.map { wrapper in
            let show = wrapper.show
            let year = show.premiered.map { String($0.prefix(4)) } ?? "Brak daty"
            let cleanSummary = show.summary?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) ?? "Brak opisu serialu."
            let cover = show.image?.original ?? show.image?.medium
            let secureCover = cover?.replacingOccurrences(of: "http://", with: "https://")
            
            return MediaItem(
                id: "series-\(show.id)",
                externalID: String(show.id),
                title: show.name,
                creator: show.network?.name ?? show.webChannel?.name ?? "Produkcja TV",
                category: .series,
                releaseYear: year,
                genres: show.genres ?? [],
                overview: cleanSummary,
                coverURL: secureCover,
                communityScore: show.rating?.average,
                communityVotesCount: nil,
                dataSourceName: "TVMaze Catalog",
                userRating: nil,
                userReview: "",
                privateNote: "",
                status: nil,
                updatedAt: Date(),
                syncedOnPassportDex: false
            )
        }
    }
    
    // MARK: - 3. Książki (Open Library API - oficjalne źródło PassportDex)
    private func searchBooks(query: String) async throws -> [MediaItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "https://openlibrary.org/search.json?q=\(encoded)&limit=16")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(OpenLibrarySearchResponse.self, from: data)
        
        return decoded.docs.map { doc in
            let coverURL = doc.cover_i.map { "https://covers.openlibrary.org/b/id/\($0)-L.jpg" }
            // OpenLibrary ocenia w skali 1-5, przeliczamy na skalę PassportDex 1-10
            let scoreOutOfTen = doc.ratings_average.map { min(10.0, max(1.0, $0 * 2.0)) }
            let year = doc.first_publish_year.map { String($0) } ?? "Brak roku"
            let author = doc.author_name?.first ?? "Autor nieznany"
            let subjects = Array((doc.subject ?? []).prefix(3))
            
            return MediaItem(
                id: "book-\(doc.key.replacingOccurrences(of: "/works/", with: ""))",
                externalID: doc.key,
                title: doc.title,
                creator: author,
                category: .book,
                releaseYear: year,
                genres: subjects,
                overview: doc.first_sentence?.first ?? "Książka skatalogowana w bazie Open Library (\(author), \(year)).",
                coverURL: coverURL,
                communityScore: scoreOutOfTen,
                communityVotesCount: doc.ratings_count,
                dataSourceName: "Open Library (Źródło PassportDex)",
                userRating: nil,
                userReview: "",
                privateNote: "",
                status: nil,
                updatedAt: Date(),
                syncedOnPassportDex: false
            )
        }
    }
    
    // MARK: - 4. Muzyka i Albumy (iTunes Search API - oficjalne źródło PassportDex)
    private func searchMusic(query: String) async throws -> [MediaItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=album&country=pl&limit=18")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        
        return decoded.results.compactMap { album in
            guard let colId = album.collectionId, let name = album.collectionName else { return nil }
            let hiResArt = album.artworkUrl100?.replacingOccurrences(of: "100x100bb", with: "600x600bb")
            let year = album.releaseDate.map { String($0.prefix(4)) } ?? ""
            let trackCountInfo = album.trackCount.map { "Liczba utworów na płycie: \($0)." } ?? ""
            
            return MediaItem(
                id: "music-\(colId)",
                externalID: String(colId),
                title: name,
                creator: album.artistName ?? "Wykonawca nieznany",
                category: .music,
                releaseYear: year,
                genres: [album.primaryGenreName].compactMap { $0 },
                overview: "Album muzyczny wykonawcy \(album.artistName ?? ""). \(trackCountInfo) Wydanie: \(year).",
                coverURL: hiResArt,
                communityScore: nil,
                communityVotesCount: nil,
                dataSourceName: "iTunes / Apple Music (Źródło PassportDex)",
                userRating: nil,
                userReview: "",
                privateNote: "",
                status: nil,
                updatedAt: Date(),
                syncedOnPassportDex: false
            )
        }
    }
    
    // MARK: - 5. Gry (Steam Store API - prawdziwe gry, okładki i bezpośrednie recenzje graczy)
    private func searchGames(query: String) async throws -> [MediaItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "https://store.steampowered.com/api/storesearch/?term=\(encoded)&l=polish&cc=PL")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(SteamStoreSearchResponse.self, from: data)
        
        return decoded.items.map { game in
            let hiResCover = "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(game.id)/library_600x900.jpg"
            let scoreOutOfTen = game.metascore.flatMap { Double($0) }.map { $0 / 10.0 }
            
            return MediaItem(
                id: "game-\(game.id)",
                externalID: String(game.id),
                title: game.name,
                creator: "Katalog gier PC / Konsolowych",
                category: .game,
                releaseYear: "Steam ID: \(game.id)",
                genres: ["Gra wideo"],
                overview: "Tytuł dostępny w bazie gier. Otwórz kartę szczegółów, aby pobrać najnowsze recenzje społeczności graczy oraz średnią ocen.",
                coverURL: hiResCover,
                communityScore: scoreOutOfTen,
                communityVotesCount: nil,
                dataSourceName: "Steam Store API",
                userRating: nil,
                userReview: "",
                privateNote: "",
                status: nil,
                updatedAt: Date(),
                syncedOnPassportDex: false
            )
        }
    }
    
    // MARK: - Pobieranie Prawdziwych Opinii Społeczności dla Wybranego Tytułu
    func fetchCommunityReviews(for item: MediaItem) async -> (reviews: [CommunityReview], updatedScore: Double?, updatedVotes: Int?) {
        if let cached = reviewsCache[item.id] {
            return (cached, item.communityScore, item.communityVotesCount)
        }
        
        var loadedReviews: [CommunityReview] = []
        var computedScore = item.communityScore
        var computedVotes = item.communityVotesCount
        
        // 1. Dla gier: pobieramy żywe recenzje graczy prosto ze Steam Reviews API
        if item.category == .game,
           let url = URL(string: "https://store.steampowered.com/appreviews/\(item.externalID)?json=1&language=all&num_per_page=10") {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let steamResp = try? JSONDecoder().decode(SteamReviewsResponse.self, from: data) {
                if let summary = steamResp.query_summary, let total = summary.total_reviews, total > 0, let pos = summary.total_positive {
                    let ratio = (Double(pos) / Double(total)) * 10.0
                    computedScore = (ratio * 10).rounded() / 10.0
                    computedVotes = total
                }
                for rev in steamResp.reviews ?? [] {
                    let hours = (rev.author.playtime_forever ?? 0) / 60
                    let score: Double = rev.voted_up ? 9.0 : 3.5
                    let date = Date(timeIntervalSince1970: TimeInterval(rev.timestamp_created))
                    let fmt = DateFormatter()
                    fmt.dateStyle = .medium
                    loadedReviews.append(
                        CommunityReview(
                            id: rev.recommendationid,
                            mediaTitle: item.title,
                            mediaCategory: .game,
                            authorName: "Gracz Steam (\(hours)h w grze)",
                            ratingOutOfTen: score,
                            content: rev.review.trimmingCharacters(in: .whitespacesAndNewlines),
                            createdAt: fmt.string(from: date),
                            sourceLabel: "Zewnętrzne API: Steam User Reviews",
                            isFromPassportDex: false
                        )
                    )
                }
            }
        }
        
        // 2. Dla filmów z kluczem TMDb: pobieramy recenzje użytkowników TMDb
        if item.category == .movie,
           let tmdbKey = KeychainService.shared.read(forKey: "tmdb_api_key"), !tmdbKey.isEmpty,
           let url = URL(string: "https://api.themoviedb.org/3/movie/\(item.externalID)/reviews?api_key=\(tmdbKey)") {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let tmdbRev = try? JSONDecoder().decode(TMDbReviewsResponse.self, from: data) {
                for r in tmdbRev.results.prefix(8) {
                    loadedReviews.append(
                        CommunityReview(
                            id: r.id,
                            mediaTitle: item.title,
                            mediaCategory: .movie,
                            authorName: r.author,
                            ratingOutOfTen: r.author_details?.rating,
                            content: r.content,
                            createdAt: String(r.created_at.prefix(10)),
                            sourceLabel: "Zewnętrzne API: TMDb Community",
                            isFromPassportDex: false
                        )
                    )
                }
            }
        }
        
        reviewsCache[item.id] = loadedReviews
        return (loadedReviews, computedScore, computedVotes)
    }
}

// MARK: - Struktury Dekodujące JSON dla API Zewnętrznych
private struct ITunesSearchResponse: Codable {
    let results: [ITunesItem]
}

private struct ITunesItem: Codable {
    let trackId: Int?
    let collectionId: Int?
    let trackName: String?
    let collectionName: String?
    let artistName: String?
    let primaryGenreName: String?
    let releaseDate: String?
    let artworkUrl100: String?
    let shortDescription: String?
    let longDescription: String?
    let trackCount: Int?
}

private struct TMDbMovieResponse: Codable {
    let results: [TMDbMovie]
}

private struct TMDbMovie: Codable {
    let id: Int
    let title: String
    let overview: String
    let poster_path: String?
    let release_date: String?
    let vote_average: Double?
    let vote_count: Int?
}

private struct TMDbReviewsResponse: Codable {
    let results: [TMDbReviewItem]
}

private struct TMDbReviewItem: Codable {
    let id: String
    let author: String
    let content: String
    let created_at: String
    let author_details: TMDbAuthorDetails?
}

private struct TMDbAuthorDetails: Codable {
    let rating: Double?
}

private struct TVMazeSearchResult: Codable {
    let show: TVMazeShow
}

private struct TVMazeShow: Codable {
    let id: Int
    let name: String
    let premiered: String?
    let genres: [String]?
    let summary: String?
    let rating: TVMazeRating?
    let image: TVMazeImage?
    let network: TVMazeNetwork?
    let webChannel: TVMazeNetwork?
}

private struct TVMazeRating: Codable {
    let average: Double?
}

private struct TVMazeImage: Codable {
    let medium: String?
    let original: String?
}

private struct TVMazeNetwork: Codable {
    let name: String?
}

private struct OpenLibrarySearchResponse: Codable {
    let docs: [OpenLibraryDoc]
}

private struct OpenLibraryDoc: Codable {
    let key: String
    let title: String
    let author_name: [String]?
    let first_publish_year: Int?
    let cover_i: Int?
    let ratings_average: Double?
    let ratings_count: Int?
    let subject: [String]?
    let first_sentence: [String]?
}

private struct SteamStoreSearchResponse: Codable {
    let items: [SteamStoreItem]
}

private struct SteamStoreItem: Codable {
    let id: Int
    let name: String
    let metascore: String?
}

private struct SteamReviewsResponse: Codable {
    let query_summary: SteamQuerySummary?
    let reviews: [SteamReviewEntry]?
}

private struct SteamQuerySummary: Codable {
    let total_positive: Int?
    let total_reviews: Int?
}

private struct SteamReviewEntry: Codable {
    let recommendationid: String
    let author: SteamReviewAuthor
    let voted_up: Bool
    let timestamp_created: Int
    let review: String
}

private struct SteamReviewAuthor: Codable {
    let playtime_forever: Int?
}
