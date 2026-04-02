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
    var currentSetId: UUID?
    var currentIndex: Int = 0
    var isPresenting: Bool = false
    var zoomLevel: Double = 1.0

    func zoomIn() { zoomLevel = min(zoomLevel + 0.1, 5.0) }
    func zoomOut() { zoomLevel = max(zoomLevel - 0.1, 0.3) }
    func zoomReset() { zoomLevel = 1.0 }

    private static let autosaveKey = "presentAutosavedSets"
    private static let currentSetKey = "presentCurrentSetId"

    init() {
        loadFromDisk()
        // Fallback: si no hay datos, crear un set por defecto
        if presentationSets.isEmpty {
            let defaultSet = PresentationSet(name: "Default")
            presentationSets.append(defaultSet)
            currentSetId = defaultSet.id
        }
        // Asegurar que currentSetId es válido
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
        guard presentationSets.count > 1 else { return } // No eliminar el único set
        presentationSets.removeAll { $0.id == id }
        if currentSetId == id {
            currentSetId = presentationSets.first?.id
            currentIndex = 0
        }
    }

    func renameSet(id: UUID, newName: String) {
        if let index = presentationSets.firstIndex(where: { $0.id == id }) {
            presentationSets[index].name = newName
            saveToDisk()
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
        if let setIndex = presentationSets.firstIndex(where: { $0.id == currentSetId }) {
            presentationSets[setIndex].slides.remove(at: index)
        }
    }

    func moveSlide(from source: IndexSet, to destination: Int) {
        if let setIndex = presentationSets.firstIndex(where: { $0.id == currentSetId }) {
            presentationSets[setIndex].slides.move(fromOffsets: source, toOffset: destination)
        }
    }

    func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(presentationSets)
            UserDefaults.standard.set(data, forKey: Self.autosaveKey)
            if let setId = currentSetId {
                UserDefaults.standard.set(setId.uuidString, forKey: Self.currentSetKey)
            }
        } catch {
            print("Error saving presentation sets: \(error)")
        }
    }

    func loadFromDisk() {
        // Intentar cargar nuevo formato (PresentationSet)
        if let data = UserDefaults.standard.data(forKey: Self.autosaveKey) {
            do {
                presentationSets = try JSONDecoder().decode([PresentationSet].self, from: data)
                if let setIdString = UserDefaults.standard.string(forKey: Self.currentSetKey),
                   let setId = UUID(uuidString: setIdString) {
                    currentSetId = setId
                }
                return
            } catch {
                print("Error decoding presentation sets: \(error)")
            }
        }

        // Fallback: migrar desde formato antiguo (array de URLs)
        if let urls = UserDefaults.standard.stringArray(forKey: "presentAutosavedURLs"), !urls.isEmpty {
            let defaultSet = PresentationSet(
                name: "Default",
                slides: urls.map { Slide(url: $0) }
            )
            presentationSets = [defaultSet]
            currentSetId = defaultSet.id
            saveToDisk() // Guardar en nuevo formato
            UserDefaults.standard.removeObject(forKey: "presentAutosavedURLs")
        }
    }

    func loadFromFile(_ url: URL) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let lines = contents.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return false }

        // Crear un nuevo set basado en el nombre del archivo
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
