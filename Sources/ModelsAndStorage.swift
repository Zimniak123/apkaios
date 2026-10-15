import Foundation
import Security
import SwiftUI

// MARK: - Kategorie Mediów
enum MediaCategory: String, CaseIterable, Codable, Identifiable {
    case movie = "Filmy"
    case series = "Seriale"
    case book = "Książki"
    case music = "Muzyka"
    case game = "Gry"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .movie: return "film.fill"
        case .series: return "tv.fill"
        case .book: return "book.closed.fill"
        case .music: return "opticaldisc.fill"
        case .game: return "gamecontroller.fill"
        }
    }
    
    var accentColor: Color {
        switch self {
        case .movie: return .indigo
        case .series: return .purple
        case .book: return .orange
        case .music: return .pink
        case .game: return .mint
        }
    }
}

// MARK: - Uniwersalny Status z dopasowaniem nazewnictwa do kategorii
enum ConsumptionStatus: String, CaseIterable, Codable, Identifiable {
    case completed = "completed"
    case inProgress = "in_progress"
    case planned = "planned"
    case dropped = "dropped"
    
    var id: String { rawValue }
    
    func localizedTitle(for category: MediaCategory) -> String {
        switch (self, category) {
        case (.completed, .movie), (.completed, .series): return "Obejrzane"
        case (.completed, .book): return "Przeczytane"
        case (.completed, .music): return "Przesłuchane"
        case (.completed, .game): return "Ukończone"
            
        case (.inProgress, .movie), (.inProgress, .series): return "Oglądam"
        case (.inProgress, .book): return "Czytam"
        case (.inProgress, .music): return "Słucham"
        case (.inProgress, .game): return "Gram teraz"
            
        case (.planned, .movie), (.planned, .series): return "Planowane"
        case (.planned, .book): return "Chcę przeczytać"
        case (.planned, .music): return "Do przesłuchania"
        case (.planned, .game): return "W kolejce (Backlog)"
            
        case (.dropped, _): return "Porzucone"
        }
    }
    
    var systemIcon: String {
        switch self {
        case .completed: return "checkmark.circle.fill"
        case .inProgress: return "play.circle.fill"
        case .planned: return "bookmark.fill"
        case .dropped: return "xmark.circle.fill"
        }
    }
}

// MARK: - Model Pozycji Multimedialnej
struct MediaItem: Identifiable, Codable, Hashable {
    var id: String
    var externalID: String
    var title: String
    var creator: String
    var category: MediaCategory
    var releaseYear: String
    var genres: [String]
    var overview: String
    var coverURL: String?
    
    // Oceny społeczności (skala 1.0 - 10.0, zgodna z PassportDex)
    var communityScore: Double?
    var communityVotesCount: Int?
    var dataSourceName: String
    
    // Dane użytkownika
    var userRating: Double?
    var userReview: String
    var privateNote: String
    var status: ConsumptionStatus?
    var updatedAt: Date
    var syncedOnPassportDex: Bool
    
    var passportDexSearchURL: URL? {
        let query = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://passportdex.com/pl?q=\(query)")
    }
}

// MARK: - Model Opinii Społeczności
struct CommunityReview: Identifiable, Codable, Hashable {
    var id: String
    var mediaTitle: String
    var mediaCategory: MediaCategory
    var authorName: String
    var ratingOutOfTen: Double?
    var content: String
    var createdAt: String
    var sourceLabel: String
    var isFromPassportDex: Bool
}

// MARK: - Status Synchronizacji z PassportDex
struct PassportDexProfileInfo: Codable {
    var username: String = "zimniak"
    var profileURL: String = "https://passportdex.com/zimniak"
    var lastSyncDate: Date?
    var isReachable: Bool = false
    var detectedBioOrTitle: String = "Brak pobranych metadanych"
    var statusMessage: String = "Gotowy do synchronizacji"
}

// MARK: - Bezpieczny Keychain (przechowywanie kluczy i tokenów)
final class KeychainService {
    static let shared = KeychainService()
    private init() {}
    
    func save(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }
    
    func read(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Główny Menedżer Stanu i Biblioteki Użytkownika
@MainActor
final class LibraryStore: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var profileInfo = PassportDexProfileInfo()
    @Published var isSyncingProfile = false
    @Published var lastErrorMessage: String?
    
    private let storageFileName = "passport_zimniak_library.json"
    private let profileFileName = "passport_zimniak_profile.json"
    
    init() {
        loadFromDisk()
    }
    
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }
    
    func saveOrUpdate(_ item: MediaItem) {
        var updated = item
        updated.updatedAt = Date()
        if let index = items.firstIndex(where: { $0.id == updated.id }) {
            items[index] = updated
        } else {
            items.insert(updated, at: 0)
        }
        persistToDisk()
    }
    
    func remove(itemID: String) {
        items.removeAll { $0.id == itemID }
        persistToDisk()
    }
    
    func existingItem(for id: String) -> MediaItem? {
        items.first { $0.id == id }
    }
    
    func exportLibraryJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return jsonString
    }
    
    func importLibraryJSON(_ jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "ImportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nieprawidłowy format tekstu UTF-8."])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let importedItems = try decoder.decode([MediaItem].self, from: data)
        for item in importedItems {
            saveOrUpdate(item)
        }
    }
    
    // Bezpieczne sprawdzenie i odczyt publicznych metadanych z https://passportdex.com/zimniak
    func syncWithPassportDexProfile() async {
        isSyncingProfile = true
        lastErrorMessage = nil
        defer { isSyncingProfile = false }
        
        guard let url = URL(string: profileInfo.profileURL) else {
            lastErrorMessage = "Nieprawidłowy adres URL profilu PassportDex."
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse else { return }
            
            if httpResp.statusCode == 200, let html = String(data: data, encoding: .utf8) {
                profileInfo.isReachable = true
                profileInfo.lastSyncDate = Date()
                
                // Wyciągamy tytuł/opis OpenGraph z publicznej strony Next.js
                let titleMatch = Self.extractMetaContent(from: html, property: "og:title")
                    ?? Self.extractHtmlTitle(from: html)
                    ?? "Profil @\(profileInfo.username) aktywny"
                let descMatch = Self.extractMetaContent(from: html, property: "og:description")
                
                if let desc = descMatch, !desc.isEmpty {
                    profileInfo.detectedBioOrTitle = "\(titleMatch) - \(desc)"
                } else {
                    profileInfo.detectedBioOrTitle = titleMatch
                }
                
                // Próba wyodrębnienia publicznych wpisów z __NEXT_DATA__ jeśli profil udostępnia je publicznie
                let parsedItems = Self.parseNextDataItemsIfPresent(from: html)
                for parsed in parsedItems {
                    if existingItem(for: parsed.id) == nil {
                        saveOrUpdate(parsed)
                    }
                }
                
                profileInfo.statusMessage = parsedItems.isEmpty
                    ? "Połączono z passportdex.com/\(profileInfo.username). Do dwustronnego zapisu ocen użyj wbudowanego mostka autoryzacyjnego OAuth."
                    : "Zsynchronizowano \(parsedItems.count) publicznych pozycji z profilu."
                persistToDisk()
            } else {
                profileInfo.isReachable = false
                profileInfo.statusMessage = "Serwer zwrócił kod HTTP \(httpResp.statusCode)."
            }
        } catch {
            profileInfo.isReachable = false
            lastErrorMessage = "Błąd połączenia z PassportDex: \(error.localizedDescription)"
            profileInfo.statusMessage = "Brak połączenia z serwerem."
        }
    }
    
    private static func extractMetaContent(from html: String, property: String) -> String? {
        let pattern = "<meta[^>]+(?:property|name)=[\"']\(property)[\"'][^>]+content=[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
    }
    
    private static func extractHtmlTitle(from html: String) -> String? {
        let pattern = "<title>([^<]+)</title>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func parseNextDataItemsIfPresent(from html: String) -> [MediaItem] {
        let pattern = "<script id=\"__NEXT_DATA__\" type=\"application/json\">(.*?)</script>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html),
              let jsonData = String(html[range]).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return []
        }
        // Bezpieczny odczyt ewentualnych publicznych wpisów z props.pageProps
        var discovered: [MediaItem] = []
        if let props = root["props"] as? [String: Any],
           let pageProps = props["pageProps"] as? [String: Any],
           let entries = pageProps["entries"] as? [[String: Any]] {
            for entry in entries {
                if let title = entry["title"] as? String {
                    let rating = entry["rating"] as? Double
                    let item = MediaItem(
                        id: "pdex-\(title.lowercased())",
                        externalID: title,
                        title: title,
                        creator: (entry["creator"] as? String) ?? "PassportDex",
                        category: .game,
                        releaseYear: (entry["year"] as? String) ?? "",
                        genres: [],
                        overview: (entry["review"] as? String) ?? "Zaimportowano z profilu PassportDex.",
                        coverURL: entry["coverUrl"] as? String,
                        communityScore: rating,
                        communityVotesCount: nil,
                        dataSourceName: "PassportDex",
                        userRating: rating,
                        userReview: (entry["review"] as? String) ?? "",
                        privateNote: "",
                        status: .completed,
                        updatedAt: Date(),
                        syncedOnPassportDex: true
                    )
                    discovered.append(item)
                }
            }
        }
        return discovered
    }
    
    private func persistToDisk() {
        let fm = FileManager.default
        try? fm.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            try? data.write(to: documentsDirectory.appendingPathComponent(storageFileName))
        }
        if let profileData = try? encoder.encode(profileInfo) {
            try? profileData.write(to: documentsDirectory.appendingPathComponent(profileFileName))
        }
    }
    
    private func loadFromDisk() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let itemsURL = documentsDirectory.appendingPathComponent(storageFileName)
        if let data = try? Data(contentsOf: itemsURL),
           let decoded = try? decoder.decode([MediaItem].self, from: data) {
            self.items = decoded
        }
        let profileURL = documentsDirectory.appendingPathComponent(profileFileName)
        if let pData = try? Data(contentsOf: profileURL),
           let pDecoded = try? decoder.decode(PassportDexProfileInfo.self, from: pData) {
            self.profileInfo = pDecoded
        }
    }
}
