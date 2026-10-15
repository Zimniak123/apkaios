import SwiftUI
import WebKit

@main
struct PassportHubApp: App {
    @StateObject private var store = LibraryStore()
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Główny Widok Zakładek (5 sekcji)
struct MainTabView: View {
    @State private var selectedTab: Int = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeDashboardView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Strona główna", systemImage: "house.fill")
                }
                .tag(0)
            
            DiscoverCatalogView()
                .tabItem {
                    Label("Odkrywaj", systemImage: "magnifyingglass")
                }
                .tag(1)
            
            MyLibraryView()
                .tabItem {
                    Label("Biblioteka", systemImage: "books.vertical.fill")
                }
                .tag(2)
            
            CommunityReviewsTabView()
                .tabItem {
                    Label("Opinie", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(3)
            
            ProfileAndSyncView()
                .tabItem {
                    Label("Profil", systemImage: "person.crop.rectangle.stack.fill")
                }
                .tag(4)
        }
        .tint(.indigo)
    }
}

// MARK: - 1. Zakładka: Strona Główna
struct HomeDashboardView: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var selectedTab: Int
    @State private var showPassportWebSheet = false
    
    private var inProgressItems: [MediaItem] {
        store.items.filter { $0.status == .inProgress }
    }
    
    private var recentlyRatedItems: [MediaItem] {
        store.items.filter { $0.userRating != nil }.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Karta statusu PassportDex
                    passportStatusBanner
                    
                    // Szybkie skróty kategorii
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Kategorie rozrywki")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(MediaCategory.allCases) { category in
                                    let count = store.items.filter { $0.category == category }.count
                                    Button {
                                        selectedTab = 1
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: category.iconName)
                                                .foregroundStyle(category.accentColor)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(category.rawValue)
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.white)
                                                Text("\(count) w bibliotece")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                }
                            }
                        }
                    }
                    
                    // Aktualnie w trakcie (Oglądam / Gram / Czytam / Słucham)
                    if !inProgressItems.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Aktualnie w trakcie")
                                .font(.headline)
                            ForEach(inProgressItems.prefix(4)) { item in
                                NavigationLink(destination: MediaDetailView(item: item)) {
                                    MediaRowCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Ostatnio ocenione pozycje
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Ostatnie oceny i aktywność")
                                .font(.headline)
                            Spacer()
                            if !store.items.isEmpty {
                                Button("Zobacz wszystkie") {
                                    selectedTab = 2
                                }
                                .font(.caption.bold())
                            }
                        }
                        
                        if recentlyRatedItems.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "star.leadinghalf.filled")
                                    .font(.largeTitle)
                                    .foregroundStyle(.indigo)
                                Text("Twoja biblioteka oczekuje na pierwsze oceny")
                                    .font(.subheadline.bold())
                                Text("Przejdź do zakładki Odkrywaj, wyszukaj film, serial, książkę, płytę lub grę i wystaw ocenę w skali 1-10.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Button {
                                    selectedTab = 1
                                } label: {
                                    Text("Wyszukaj pierwszy tytuł")
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 10)
                                        .background(Color.indigo)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        } else {
                            ForEach(recentlyRatedItems.prefix(6)) { item in
                                NavigationLink(destination: MediaDetailView(item: item)) {
                                    MediaRowCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Passport @\(store.profileInfo.username)")
            .sheet(isPresented: $showPassportWebSheet) {
                PassportDexWebBridgeSheet(url: URL(string: store.profileInfo.profileURL)!)
            }
        }
    }
    
    private var passportStatusBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(store.profileInfo.isReachable ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text("PASSPORTDEX: @\(store.profileInfo.username.uppercased())")
                            .font(.caption.bold())
                            .foregroundStyle(.indigo)
                    }
                    Text(store.profileInfo.detectedBioOrTitle)
                        .font(.subheadline.bold())
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    Task { await store.syncWithPassportDexProfile() }
                } label: {
                    if store.isSyncingProfile {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.body.bold())
                            .padding(10)
                            .background(Color.indigo.opacity(0.2))
                            .clipShape(Circle())
                    }
                }
            }
            
            Text(store.profileInfo.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 10) {
                Button {
                    showPassportWebSheet = true
                } label: {
                    Label("Otwórz paszport zimniak (OAuth)", systemImage: "globe")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.indigo)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                
                Text("Oceniono: \(store.items.filter { $0.userRating != nil }.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.indigo.opacity(0.22), Color(.secondarySystemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - 2. Zakładka: Odkrywaj (Wyszukiwarka na żywo dla 5 kategorii)
struct DiscoverCatalogView: View {
    @State private var selectedCategory: MediaCategory = .movie
    @State private var searchText: String = ""
    @State private var searchResults: [MediaItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Przełącznik kategorii
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MediaCategory.allCases) { category in
                            Button {
                                selectedCategory = category
                                triggerSearch(immediately: true)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: category.iconName)
                                    Text(category.rawValue)
                                }
                                .font(.subheadline.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selectedCategory == category ? category.accentColor : Color(.secondarySystemBackground))
                                .foregroundStyle(selectedCategory == category ? .white : .primary)
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                
                if isLoading {
                    Spacer()
                    ProgressView("Przeszukiwanie katalogu (\(selectedCategory.rawValue))...")
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Nie udało się pobrać wyników")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Spróbuj ponownie") {
                            triggerSearch(immediately: true)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    Spacer()
                } else if searchResults.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: selectedCategory.iconName)
                            .font(.system(size: 44))
                            .foregroundStyle(selectedCategory.accentColor)
                        Text("Wyszukaj \(selectedCategory.rawValue.lowercased())")
                            .font(.headline)
                        Text("Wpisz tytuł powyżej. Aplikacja pobiera dane na żywo z oficjalnych źródeł (TMDb/iTunes, TVMaze, Open Library, Apple Music oraz Steam).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                } else {
                    List(searchResults) { item in
                        NavigationLink(destination: MediaDetailView(item: item)) {
                            MediaRowCard(item: item)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Odkrywaj")
            .searchable(text: $searchText, prompt: "Szukaj: film, serial, książka, album, gra...")
            .onChange(of: searchText) { _, _ in
                triggerSearch(immediately: false)
            }
        }
    }
    
    private func triggerSearch(immediately: Bool) {
        searchTask?.cancel()
        let currentQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentQuery.isEmpty else {
            searchResults = []
            errorMessage = nil
            return
        }
        
        searchTask = Task {
            if !immediately {
                try? await Task.sleep(nanoseconds: 450_000_000) // 450ms debounce
            }
            guard !Task.isCancelled else { return }
            isLoading = true
            errorMessage = nil
            do {
                let items = try await MediaAPIService.shared.search(query: currentQuery, category: selectedCategory)
                if !Task.isCancelled {
                    searchResults = items
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            if !Task.isCancelled {
                isLoading = false
            }
        }
    }
}

// MARK: - 3. Zakładka: Moja Biblioteka (Filtry i Sortowanie)
struct MyLibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var selectedCategory: MediaCategory? = nil
    @State private var selectedStatus: ConsumptionStatus? = nil
    @State private var sortByRatingDescending: Bool = true
    @State private var filterText: String = ""
    
    private var filteredItems: [MediaItem] {
        store.items.filter { item in
            let matchesCat = (selectedCategory == nil || item.category == selectedCategory)
            let matchesStatus = (selectedStatus == nil || item.status == selectedStatus)
            let matchesQuery = filterText.isEmpty || item.title.localizedCaseInsensitiveContains(filterText)
            return matchesCat && matchesStatus && matchesQuery
        }
        .sorted { a, b in
            if sortByRatingDescending {
                return (a.userRating ?? 0) > (b.userRating ?? 0)
            } else {
                return a.updatedAt > b.updatedAt
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                // Pasek filtrów kategorii i statusów
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "Wszystkie (\(store.items.count))", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        ForEach(MediaCategory.allCases) { cat in
                            FilterChip(title: cat.rawValue, isSelected: selectedCategory == cat) {
                                selectedCategory = (selectedCategory == cat) ? nil : cat
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ConsumptionStatus.allCases) { st in
                            let label = st.localizedTitle(for: selectedCategory ?? .movie)
                            FilterChip(title: label, isSelected: selectedStatus == st) {
                                selectedStatus = (selectedStatus == st) ? nil : st
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                if filteredItems.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "Brak pasujących pozycji",
                        systemImage: "tray",
                        description: Text("Zmień filtry lub dodaj nowe oceny w zakładce Odkrywaj.")
                    )
                    Spacer()
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            NavigationLink(destination: MediaDetailView(item: item)) {
                                MediaRowCard(item: item)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                store.remove(itemID: filteredItems[index].id)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Moja biblioteka")
            .searchable(text: $filterText, prompt: "Filtruj zapisane tytuły...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sortByRatingDescending.toggle()
                    } label: {
                        Label(
                            sortByRatingDescending ? "Wg oceny" : "Wg daty",
                            systemImage: sortByRatingDescending ? "star.fill" : "clock.fill"
                        )
                        .font(.caption.bold())
                    }
                }
            }
        }
    }
}

// MARK: - 4. Zakładka: Opinie Innych Użytkowników
struct CommunityReviewsTabView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var aggregatedReviews: [CommunityReview] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    ContentUnavailableView(
                        "Brak tytułów do pobrania opinii",
                        systemImage: "text.bubble",
                        description: Text("Dodaj lub wyszukaj interesujące Cię gry i filmy, aby czytać recenzje społeczności oraz porównywać je z własną oceną.")
                    )
                } else if isLoading && aggregatedReviews.isEmpty {
                    ProgressView("Pobieranie opinii społeczności...")
                } else if aggregatedReviews.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                            .font(.largeTitle)
                            .foregroundStyle(.indigo)
                        Text("Otwórz dowolną pozycję, aby pobrać recenzje")
                            .font(.headline)
                        Button("Pobierz recenzje dla mojej biblioteki") {
                            Task { await loadFeedForLibrary() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    List(aggregatedReviews) { rev in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(rev.mediaTitle)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.indigo)
                                Spacer()
                                if let score = rev.ratingOutOfTen {
                                    Text(String(format: "%.1f / 10", score))
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundStyle(.green)
                                        .clipShape(Capsule())
                                }
                            }
                            Text(rev.content)
                                .font(.footnote)
                                .lineLimit(6)
                            HStack {
                                Text("Autor: \(rev.authorName)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(rev.sourceLabel)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(rev.isFromPassportDex ? Color.indigo.opacity(0.25) : Color.secondary.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("Opinie społeczności")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadFeedForLibrary() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                if aggregatedReviews.isEmpty && !store.items.isEmpty {
                    await loadFeedForLibrary()
                }
            }
        }
    }
    
    private func loadFeedForLibrary() async {
        isLoading = true
        var collected: [CommunityReview] = []
        for item in store.items.prefix(6) {
            let result = await MediaAPIService.shared.fetchCommunityReviews(for: item)
            collected.append(contentsOf: result.reviews.prefix(3))
        }
        aggregatedReviews = collected
        isLoading = false
    }
}

// MARK: - 5. Zakładka: Profil i Synchronizacja z PassportDex
struct ProfileAndSyncView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var tmdbApiKey: String = KeychainService.shared.read(forKey: "tmdb_api_key") ?? ""
    @State private var showWebBridge = false
    @State private var showImportExportSheet = false
    @State private var jsonBuffer: String = ""
    @State private var feedbackBanner: String?
    
    private var averageUserRating: Double {
        let rated = store.items.compactMap { $0.userRating }
        guard !rated.isEmpty else { return 0.0 }
        return rated.reduce(0, +) / Double(rated.count)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Profil PassportDex") {
                    HStack {
                        Label("Nazwa użytkownika", systemImage: "person.fill")
                        Spacer()
                        Text("@\(store.profileInfo.username)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Adres paszportu", systemImage: "link")
                        Spacer()
                        Text("passportdex.com/zimniak")
                            .font(.caption)
                            .foregroundStyle(.indigo)
                    }
                    Button {
                        Task { await store.syncWithPassportDexProfile() }
                    } label: {
                        Label("Sprawdź i synchronizuj profil publiczny", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        showWebBridge = true
                    } label: {
                        Label("Otwórz autoryzowany mostek PassportDex (Zapis ocen)", systemImage: "lock.shield.fill")
                    }
                }
                
                Section("Statystyki Twojej Biblioteki") {
                    HStack {
                        Text("Wszystkie zapisane pozycje")
                        Spacer()
                        Text("\(store.items.count)").bold()
                    }
                    HStack {
                        Text("Wystawione oceny (1-10)")
                        Spacer()
                        Text("\(store.items.filter { $0.userRating != nil }.count)").bold()
                    }
                    HStack {
                        Text("Średnia Twoich ocen")
                        Spacer()
                        Text(String(format: "%.2f / 10", averageUserRating))
                            .foregroundStyle(.green)
                            .bold()
                    }
                }
                
                Section(
                    header: Text("Klucz TMDb API (Opcjonalny - przechowywany w Keychain)"),
                    footer: Text("Domyślnie aplikacja wyszukuje filmy, seriale, książki, muzykę i gry bez żadnych kluczy. Jeśli dodasz darmowy klucz TMDb, filmy będą pobierane bezpośrednio z tej samej bazy, której używa PassportDex.")
                ) {
                    SecureField("Wklej klucz API v3 TMDb...", text: $tmdbApiKey)
                    Button("Zapisz bezpiecznie w iOS Keychain") {
                        KeychainService.shared.save(tmdbApiKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "tmdb_api_key")
                        feedbackBanner = "Klucz TMDb został zaszyfrowany w Keychain."
                    }
                }
                
                Section("Kopia zapasowa i wymiana danych (JSON)") {
                    Button {
                        jsonBuffer = store.exportLibraryJSON()
                        showImportExportSheet = true
                    } label: {
                        Label("Eksportuj / Importuj bibliotekę JSON", systemImage: "square.and.arrow.up.on.square")
                    }
                }
                
                if let msg = feedbackBanner {
                    Section {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Profil i Synchronizacja")
            .sheet(isPresented: $showWebBridge) {
                PassportDexWebBridgeSheet(url: URL(string: store.profileInfo.profileURL)!)
            }
            .sheet(isPresented: $showImportExportSheet) {
                NavigationStack {
                    VStack(spacing: 12) {
                        Text("Dane kolekcji w formacie JSON. Możesz je skopiować lub wkleić tutaj wyeksportowaną listę i kliknąć Zaimportuj.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        TextEditor(text: $jsonBuffer)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                        HStack(spacing: 16) {
                            Button("Kopiuj do schowka") {
                                UIPasteboard.general.string = jsonBuffer
                                feedbackBanner = "Skopiowano JSON do schowka."
                                showImportExportSheet = false
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Zaimportuj JSON") {
                                do {
                                    try store.importLibraryJSON(jsonBuffer)
                                    feedbackBanner = "Pomyślnie zaimportowano dane."
                                    showImportExportSheet = false
                                } catch {
                                    feedbackBanner = "Błąd importu: \(error.localizedDescription)"
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.bottom)
                    }
                    .navigationTitle("Kopia JSON")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Zamknij") { showImportExportSheet = false }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Widok Szczegółów Tytułu + Wystawianie Oceny + Opinie
struct MediaDetailView: View {
    @EnvironmentObject var store: LibraryStore
    let item: MediaItem
    
    @State private var workingItem: MediaItem
    @State private var communityReviews: [CommunityReview] = []
    @State private var isLoadingReviews = false
    @State private var showRatingSheet = false
    @State private var showPassportDexWebSheet = false
    
    init(item: MediaItem) {
        self.item = item
        _workingItem = State(initialValue: item)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Nagłówek z okładką i metadanymi
                HStack(alignment: .top, spacing: 16) {
                    AsyncCoverImage(urlString: workingItem.coverURL, icon: workingItem.category.iconName)
                        .frame(width: 115, height: 168)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(radius: 6)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(workingItem.category.rawValue.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(workingItem.category.accentColor)
                        Text(workingItem.title)
                            .font(.title3.bold())
                        Text(workingItem.creator)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(workingItem.releaseYear)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if !workingItem.genres.isEmpty {
                            Text(workingItem.genres.joined(separator: " • "))
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                        }
                        
                        // Średnia ocena użytkowników
                        if let commScore = workingItem.communityScore {
                            HStack(spacing: 6) {
                                Image(systemName: "person.3.fill")
                                    .font(.caption2)
                                Text(String(format: "Średnia: %.1f / 10", commScore))
                                    .font(.caption.bold())
                                if let votes = workingItem.communityVotesCount {
                                    Text("(\(votes) ocen)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.green)
                            .padding(.top, 4)
                        }
                    }
                }
                
                // Główne przyciski akcji (Ocenianie i Synchronizacja z PassportDex)
                HStack(spacing: 12) {
                    Button {
                        showRatingSheet = true
                    } label: {
                        HStack {
                            Image(systemName: workingItem.userRating != nil ? "star.fill" : "plus.circle.fill")
                            Text(workingItem.userRating != nil
                                 ? String(format: "Twoja ocena: %.1f / 10", workingItem.userRating!)
                                 : "Oceń i dodaj do profilu")
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.indigo)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Button {
                        showPassportDexWebSheet = true
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.up.right.square.fill")
                            Text("PassportDex")
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                
                // Karta własnej oceny, statusu, recenzji i prywatnej notatki
                if workingItem.status != nil || workingItem.userRating != nil || !workingItem.userReview.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Twój zapis w bibliotece (@zimniak)")
                                .font(.subheadline.bold())
                            Spacer()
                            if let status = workingItem.status {
                                Label(status.localizedTitle(for: workingItem.category), systemImage: status.systemIcon)
                                    .font(.caption.bold())
                                    .foregroundStyle(.indigo)
                            }
                        }
                        if !workingItem.userReview.isEmpty {
                            Text("Recenzja: \(workingItem.userReview)")
                                .font(.footnote)
                        }
                        if !workingItem.privateNote.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text("Prywatna notatka: \(workingItem.privateNote)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                
                // Opis fabuły / wydania
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Opis pozycji")
                            .font(.headline)
                        Spacer()
                        Text("Źródło: \(workingItem.dataSourceName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(workingItem.overview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                // Sekcja opinii i recenzji innych użytkowników
                VStack(alignment: .leading, spacing: 12) {
                    Text("Opinie i recenzje innych użytkowników")
                        .font(.headline)
                    
                    if isLoadingReviews {
                        ProgressView("Pobieranie recenzji użytkowników...")
                    } else if communityReviews.isEmpty {
                        Text("Brak publicznych recenzji tekstowych dla tego tytułu w bieżącym kanale API. Możesz sprawdzić stronę tytułu bezpośrednio w PassportDex powyżej.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(communityReviews) { rev in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(rev.authorName)
                                        .font(.caption.bold())
                                    Spacer()
                                    if let r = rev.ratingOutOfTen {
                                        Text(String(format: "%.1f / 10", r))
                                            .font(.caption.bold())
                                            .foregroundStyle(.green)
                                    }
                                }
                                Text(rev.content)
                                    .font(.footnote)
                                HStack {
                                    Text(rev.createdAt)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(rev.sourceLabel)
                                        .font(.caption2)
                                        .foregroundStyle(.indigo)
                                }
                            }
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(workingItem.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRatingSheet) {
            RatingFormSheet(item: $workingItem) { savedItem in
                store.saveOrUpdate(savedItem)
            }
        }
        .sheet(isPresented: $showPassportDexWebSheet) {
            if let url = workingItem.passportDexSearchURL {
                PassportDexWebBridgeSheet(url: url)
            }
        }
        .task {
            if let existing = store.existingItem(for: item.id) {
                workingItem = existing
            }
            isLoadingReviews = true
            let fetched = await MediaAPIService.shared.fetchCommunityReviews(for: workingItem)
            communityReviews = fetched.reviews
            if let s = fetched.updatedScore { workingItem.communityScore = s }
            if let v = fetched.updatedVotes { workingItem.communityVotesCount = v }
            isLoadingReviews = false
        }
    }
}

// MARK: - Formularz Wystawiania Oceny (Skala PassportDex 1.0 - 10.0)
struct RatingFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var item: MediaItem
    var onSave: (MediaItem) -> Void
    
    @State private var ratingValue: Double = 8.0
    @State private var hasRating: Bool = true
    @State private var selectedStatus: ConsumptionStatus = .completed
    @State private var reviewText: String = ""
    @State private var privateNoteText: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Status dla kategorii: \(item.category.rawValue)") {
                    Picker("Status", selection: $selectedStatus) {
                        ForEach(ConsumptionStatus.allCases) { status in
                            Label(status.localizedTitle(for: item.category), systemImage: status.systemIcon)
                                .tag(status)
                        }
                    }
                    .pickerStyle(.inline)
                }
                
                Section("Ocena w skali PassportDex (1.0 - 10.0)") {
                    Toggle("Wystaw ocenę liczbową", isOn: $hasRating)
                    if hasRating {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Twoja nota:")
                                Spacer()
                                Text(String(format: "%.1f / 10", ratingValue))
                                    .font(.title2.bold())
                                    .foregroundStyle(.indigo)
                            }
                            Slider(value: $ratingValue, in: 1.0...10.0, step: 0.5)
                                .tint(.indigo)
                        }
                    }
                }
                
                Section("Publiczna recenzja (opcjonalnie)") {
                    TextEditor(text: $reviewText)
                        .frame(minHeight: 90)
                }
                
                Section(
                    header: Text("Prywatna notatka (Private Note)"),
                    footer: Text("Widoczna wyłącznie dla Ciebie w aplikacji, zgodnie z funkcją Private Notes w PassportDex.")
                ) {
                    TextField("Dodaj prywatną uwagę...", text: $privateNoteText)
                }
            }
            .navigationTitle("Oceń tytuł")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        item.status = selectedStatus
                        item.userRating = hasRating ? ratingValue : nil
                        item.userReview = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
                        item.privateNote = privateNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(item)
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                if let r = item.userRating {
                    ratingValue = r
                    hasRating = true
                }
                if let st = item.status {
                    selectedStatus = st
                }
                reviewText = item.userReview
                privateNoteText = item.privateNote
            }
        }
    }
}

// MARK: - Wbudowany Mostek Autoryzacyjny PassportDex (WKWebView)
struct PassportDexWebBridgeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    
    var body: some View {
        NavigationStack {
            PassportWebViewRepresentable(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("PassportDex Bridge")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Zamknij") { dismiss() }
                    }
                }
        }
    }
}

struct PassportWebViewRepresentable: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // Zachowuje sesję OAuth użytkownika między uruchomieniami
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Komponenty Pomocnicze UI
struct MediaRowCard: View {
    let item: MediaItem
    
    var body: some View {
        HStack(spacing: 14) {
            AsyncCoverImage(urlString: item.coverURL, icon: item.category.iconName)
                .frame(width: 62, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: item.category.iconName)
                        .font(.caption2)
                        .foregroundStyle(item.category.accentColor)
                    Text(item.category.rawValue)
                        .font(.caption2.bold())
                        .foregroundStyle(item.category.accentColor)
                    if let status = item.status {
                        Text("• \(status.localizedTitle(for: item.category))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(item.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                
                Text("\(item.creator) • \(item.releaseYear)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 10) {
                    if let userScore = item.userRating {
                        Label(String(format: "Ty: %.1f", userScore), systemImage: "star.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.yellow)
                    }
                    if let commScore = item.communityScore {
                        Label(String(format: "Śr: %.1f", commScore), systemImage: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct AsyncCoverImage: View {
    let urlString: String?
    let icon: String
    
    var body: some View {
        if let str = urlString, let url = URL(string: str) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    ZStack {
                        Color(.tertiarySystemBackground)
                        ProgressView()
                    }
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }
    
    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemBackground)
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? Color.indigo : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
