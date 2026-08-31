import Foundation

@Observable
class Slide: Identifiable, Codable {
    let id: UUID
    var url: String
    var displayName: String?

    init(id: UUID = UUID(), url: String = "https://example.com", displayName: String? = nil) {
        self.id = id
        self.url = url
        self.displayName = displayName
    }

    var label: String {
        displayName ?? url
    }

    enum CodingKeys: String, CodingKey {
        case id, url, displayName
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(displayName, forKey: .displayName)
    }
}

struct PresentationSet: Identifiable, Codable {
    let id: UUID
    var name: String
    var slides: [Slide]
    var createdAt: Date

    init(id: UUID = UUID(), name: String = "Untitled", slides: [Slide] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.slides = slides
        self.createdAt = createdAt
    }
}

@Observable
class PresentationState {
    var presentationSets: [PresentationSet] = [] {
        didSet { saveToDisk() }
    }
    var currentSetId: UUID? {
        didSet { saveToDisk() }
    }
    var currentIndex: Int = 0
    var isPresenting: Bool = false
    var zoomLevel: Double = 1.0

    func zoomIn() { zoomLevel = min(zoomLevel + 0.1, 5.0) }
    func zoomOut() { zoomLevel = max(zoomLevel - 0.1, 0.3) }
    func zoomReset() { zoomLevel = 1.0 }

    /// Everything that is persisted, written as a single atomic unit so the
    /// selected list can never get out of sync with the lists themselves.
    private struct StoredDocument: Codable {
        var sets: [PresentationSet]
        var currentSetId: UUID?
    }

    /// Suppresses autosave while `loadFromDisk()` populates the properties.
    private var isLoading = false

    private static let legacySetsKey = "presentAutosavedSets"
    private static let legacyCurrentSetKey = "presentCurrentSetId"
    private static let legacyURLsKey = "presentAutosavedURLs"

    static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Present", isDirectory: true)
            .appendingPathComponent("presentations.json")
    }

    init() {
        loadFromDisk()
        // Fallback: with no data at all, start with one empty list.
        if presentationSets.isEmpty {
            let defaultSet = PresentationSet(name: "Default")
            presentationSets.append(defaultSet)
            currentSetId = defaultSet.id
        }
        // Make sure currentSetId still points at a list that exists.
        if currentSetId == nil || presentationSets.first(where: { $0.id == currentSetId }) == nil {
            currentSetId = presentationSets.first?.id
        }
    }

    var currentSet: PresentationSet? {
        guard let setId = currentSetId else { return nil }
        return presentationSets.first { $0.id == setId }
    }

    var slides: [Slide] {
        currentSet?.slides ?? []
    }

    var currentSlide: Slide? {
        guard !slides.isEmpty, currentIndex >= 0, currentIndex < slides.count else { return nil }
        return slides[currentIndex]
    }

    func goToNext() {
        guard !slides.isEmpty else { return }
        currentIndex = (currentIndex + 1) % slides.count
    }

    func goToPrevious() {
        guard !slides.isEmpty else { return }
        currentIndex = (currentIndex - 1 + slides.count) % slides.count
    }

    func createSet(name: String) {
        let newSet = PresentationSet(name: name)
        presentationSets.append(newSet)
        currentSetId = newSet.id
        currentIndex = 0
    }

    func deleteSet(id: UUID) {
        guard presentationSets.count > 1 else { return } // Never delete the last list
        presentationSets.removeAll { $0.id == id }
        if currentSetId == id {
            currentSetId = presentationSets.first?.id
            currentIndex = 0
        }
    }

    func renameSet(id: UUID, newName: String) {
        if let index = presentationSets.firstIndex(where: { $0.id == id }) {
            presentationSets[index].name = newName
        }
    }

    func switchToSet(id: UUID) {
        if presentationSets.first(where: { $0.id == id }) != nil {
            currentSetId = id
            currentIndex = 0
        }
    }

    func addSlide(_ slide: Slide) {
        if let index = presentationSets.firstIndex(where: { $0.id == currentSetId }) {
            presentationSets[index].slides.append(slide)
        }
    }

    func removeSlide(at index: Int) {
        if let setIndex = presentationSets.firstIndex(where: { $0.id == currentSetId }),
           presentationSets[setIndex].slides.indices.contains(index) {
            presentationSets[setIndex].slides.remove(at: index)
        }
    }

    func moveSlide(from source: IndexSet, to destination: Int) {
        if let setIndex = presentationSets.firstIndex(where: { $0.id == currentSetId }) {
            presentationSets[setIndex].slides.move(fromOffsets: source, toOffset: destination)
        }
    }

    /// `Slide` is a reference type, so editing one in place does not touch the
    /// `presentationSets` array and never fires its `didSet`. Route edits
    /// through here so callers cannot forget to persist them.
    func updateSlide(_ slide: Slide, url: String, displayName: String?) {
        slide.url = url
        slide.displayName = displayName
        saveToDisk()
    }

    func saveToDisk() {
        guard !isLoading else { return }
        let document = StoredDocument(sets: presentationSets, currentSetId: currentSetId)
        let url = Self.storeURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: url, options: .atomic)
        } catch {
            print("Present: error saving presentations: \(error)")
        }
    }

    private func loadFromDisk() {
        isLoading = true
        let migrated = loadStoredDocument()
        isLoading = false
        if migrated { saveToDisk() }
    }

    /// Populates the state from the newest store available.
    /// Returns `true` when the data came from a legacy store and needs
    /// rewriting in the current format.
    private func loadStoredDocument() -> Bool {
        if let data = try? Data(contentsOf: Self.storeURL) {
            do {
                let document = try JSONDecoder().decode(StoredDocument.self, from: data)
                presentationSets = document.sets
                currentSetId = document.currentSetId
                return false
            } catch {
                print("Present: error decoding presentations.json: \(error)")
            }
        }

        let defaults = UserDefaults.standard

        // Legacy store 1: sets kept in UserDefaults.
        if let data = defaults.data(forKey: Self.legacySetsKey) {
            do {
                presentationSets = try JSONDecoder().decode([PresentationSet].self, from: data)
                if let idString = defaults.string(forKey: Self.legacyCurrentSetKey),
                   let id = UUID(uuidString: idString) {
                    currentSetId = id
                }
                return true
            } catch {
                print("Present: error decoding legacy presentation sets: \(error)")
            }
        }

        // Legacy store 2: upstream's flat array of URLs.
        if let urls = defaults.stringArray(forKey: Self.legacyURLsKey), !urls.isEmpty {
            let defaultSet = PresentationSet(name: "Default", slides: urls.map { Slide(url: $0) })
            presentationSets = [defaultSet]
            currentSetId = defaultSet.id
            return true
        }

        return false
    }

    func loadFromFile(_ url: URL) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let lines = contents.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return false }

        // Each opened file becomes a new list, named after the file.
        let fileName = url.deletingPathExtension().lastPathComponent
        var newSet = PresentationSet(name: fileName)
        newSet.slides = lines.map { Slide(url: $0) }

        presentationSets.append(newSet)
        currentSetId = newSet.id
        currentIndex = 0
        return true
    }

    func saveToFile(_ url: URL) -> Bool {
        guard let currentSet else { return false }
        let contents = currentSet.slides.map { $0.url }.joined(separator: "\n") + "\n"
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
