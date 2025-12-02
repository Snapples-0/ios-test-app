import SwiftUI
import Combine

// MARK: - Models

struct Novel: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let author: String
    let coverURL: String
    let source: String
    let summary: String
    var tags: [String]
    var url: String? // URL to scrape/fetch content from
    
    // For local library tracking
    var lastReadChapter: Int = 0
    var totalChapters: Int = 0
}

struct Chapter {
    let title: String
    let content: String
}

// MARK: - Services (Networking & Scraping)

class NovelService: ObservableObject {
    @Published var searchResults: [Novel] = []
    @Published var isSearching: Bool = false
    
    // 1. Gutenberg API
    func searchGutenberg(query: String) {
        guard let url = URL(string: "https://gutendex.com/books?search=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else { return }
        
        isSearching = true
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            defer { DispatchQueue.main.async { self.isSearching = false } }
            guard let data = data else { return }
            
            do {
                // Parse Gutendex JSON structure
                let result = try JSONDecoder().decode(GutendexResponse.self, from: data)
                let novels = result.results.map { book -> Novel in
                    let cover = book.formats["image/jpeg"] ?? ""
                    let textURL = book.formats["text/plain; charset=utf-8"] ?? book.formats["text/plain"]
                    
                    return Novel(
                        id: "gut-\(book.id)",
                        title: book.title,
                        author: book.authors.first?.name.replacingOccurrences(of: ", ", with: " ") ?? "Unknown",
                        coverURL: cover,
                        source: "Gutenberg",
                        summary: "Classic Literature. Downloads: \(book.download_count)",
                        tags: book.subjects.prefix(2).map { $0.components(separatedBy: " -- ").first ?? "" },
                        url: textURL
                    )
                }
                
                DispatchQueue.main.async {
                    self.searchResults = novels.filter { $0.url != nil }
                }
            } catch {
                print("JSON Error: \(error)")
            }
        }.resume()
    }
    
    // 2. Fetch Content
    func fetchContent(for novel: Novel, chapterIndex: Int, completion: @escaping (String) -> Void) {
        guard let urlString = novel.url, let url = URL(string: urlString) else {
            completion("Error: No valid URL found.")
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let text = String(data: data, encoding: .utf8) else {
                completion("Failed to load content.")
                return
            }
            
            // Basic logic to split massive Gutenberg text files into "Chapters"
            // In a real app, you would use Regex to find "Chapter I", "Chapter II", etc.
            let chunks = text.components(separatedBy: "CHAPTER")
            
            DispatchQueue.main.async {
                if chunks.count > 1 {
                    // Return the requested chunk, or the first one if out of bounds
                    let index = (chapterIndex + 1) < chunks.count ? (chapterIndex + 1) : 0
                    completion("CHAPTER " + chunks[index])
                } else {
                    // Fallback for short stories
                    completion(text)
                }
            }
        }.resume()
    }
}

// Helper Structs for JSON
struct GutendexResponse: Codable {
    let results: [GutendexBook]
}
struct GutendexBook: Codable {
    let id: Int
    let title: String
    let authors: [GutendexAuthor]
    let formats: [String: String]
    let download_count: Int
    let subjects: [String]
}
struct GutendexAuthor: Codable {
    let name: String
}

// MARK: - View Models

class LibraryViewModel: ObservableObject {
    @Published var savedNovels: [Novel] = []
    
    func toggleLibrary(novel: Novel) {
        if let index = savedNovels.firstIndex(where: { $0.id == novel.id }) {
            savedNovels.remove(at: index)
        } else {
            savedNovels.append(novel)
        }
    }
    
    func isSaved(_ novel: Novel) -> Bool {
        return savedNovels.contains(where: { $0.id == novel.id })
    }
}

// MARK: - Views

struct ContentView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }
            
            BrowseView()
                .tabItem {
                    Label("Browse", systemImage: "magnifyingglass")
                }
            
            Text("Settings")
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        // Inject the library environment
        .environmentObject(LibraryViewModel())
        .environmentObject(NovelService())
    }
}

struct LibraryView: View {
    @EnvironmentObject var libraryVM: LibraryViewModel
    
    var body: some View {
        NavigationView {
            if libraryVM.savedNovels.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("Your library is empty")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else {
                List(libraryVM.savedNovels) { novel in
                    NavigationLink(destination: NovelDetailView(novel: novel)) {
                        HStack {
                            AsyncImage(url: URL(string: novel.coverURL)) { phase in
                                if let image = phase.image {
                                    image.resizable()
                                } else {
                                    Color.gray.opacity(0.3)
                                }
                            }
                            .frame(width: 50, height: 75)
                            .cornerRadius(6)
                            
                            VStack(alignment: .leading) {
                                Text(novel.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(novel.author)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(novel.source)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                .navigationTitle("Library")
            }
        }
    }
}

struct BrowseView: View {
    @EnvironmentObject var service: NovelService
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            List(service.searchResults) { novel in
                NavigationLink(destination: NovelDetailView(novel: novel)) {
                    HStack {
                        AsyncImage(url: URL(string: novel.coverURL)) { phase in
                            if let image = phase.image {
                                image.resizable()
                            } else {
                                Color.gray.opacity(0.3)
                            }
                        }
                        .frame(width: 60, height: 90)
                        .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(novel.title)
                                .font(.headline)
                                .lineLimit(2)
                            Text(novel.author)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack {
                                ForEach(novel.tags.prefix(2), id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2)
                                        .padding(4)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search Gutenberg...")
            .onSubmit(of: .search) {
                service.searchGutenberg(query: searchText)
            }
            .navigationTitle("Browse")
            .overlay {
                if service.isSearching {
                    ProgressView("Searching...")
                }
            }
        }
    }
}

struct NovelDetailView: View {
    @EnvironmentObject var libraryVM: LibraryViewModel
    let novel: Novel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .top, spacing: 20) {
                    AsyncImage(url: URL(string: novel.coverURL)) { phase in
                        if let image = phase.image {
                            image.resizable()
                        } else {
                            Color.gray.opacity(0.3)
                        }
                    }
                    .frame(width: 120, height: 180)
                    .cornerRadius(12)
                    .shadow(radius: 5)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(novel.title)
                            .font(.title2)
                            .bold()
                        Text(novel.author)
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            libraryVM.toggleLibrary(novel: novel)
                        }) {
                            Label(
                                libraryVM.isSaved(novel) ? "In Library" : "Add to Library",
                                systemImage: libraryVM.isSaved(novel) ? "checkmark.circle.fill" : "plus.circle"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(libraryVM.isSaved(novel) ? Color.green : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .padding(.top, 10)
                    }
                }
                
                Text("Summary")
                    .font(.headline)
                Text(novel.summary)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
                
                Divider()
                
                Text("Read")
                    .font(.headline)
                
                // Simple Chapter List
                ForEach(0..<20) { index in
                    NavigationLink(destination: ReaderView(novel: novel, chapterIndex: index)) {
                        HStack {
                            Text("Chapter \(index + 1)")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ReaderView: View {
    @EnvironmentObject var service: NovelService
    let novel: Novel
    let chapterIndex: Int
    
    @State private var content: String = ""
    @State private var isLoading = true
    @State private var fontSize: CGFloat = 18
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading Content...")
            } else {
                ScrollView {
                    Text(content)
                        .font(.system(size: fontSize, design: .serif))
                        .lineSpacing(8)
                        .padding()
                        .padding(.bottom, 50)
                }
            }
        }
        .navigationTitle("Chapter \(chapterIndex + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Increase Font") { fontSize += 2 }
                    Button("Decrease Font") { fontSize -= 2 }
                } label: {
                    Image(systemName: "textformat.size")
                }
            }
        }
        .onAppear {
            service.fetchContent(for: novel, chapterIndex: chapterIndex) { text in
                self.content = text
                self.isLoading = false
            }
        }
    }
}

// Preview Provider
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


