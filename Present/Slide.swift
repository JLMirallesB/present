import Foundation

/// A request from the remote for the visible slide to scroll. Carries a
/// sequence number because the same `dy` twice in a row is two scrolls, not one.
struct ScrollRequest: Equatable {
    var sequence: Int = 0
    var dy: Double = 0
}

/// What a slide actually renders. Kept in the model rather than in `WebView`
/// so the decision is testable without spinning up a view.
enum SlideContent: Hashable {
    /// A web page, at an absolute URL.
    case web(String)
    /// An image, shown letterboxed on black, at an absolute URL.
    case image(String)
    /// Markdown, rendered by the app itself.
    case text(String)

    var isImage: Bool {
        if case .image = self { return true }
        return false
    }
}

@Observable
class Slide: Identifiable, Codable {
    let id: UUID
    var url: String
    var displayName: String?
    /// When non-nil, this is a text slide and `url` is ignored.
    var text: String?

    init(id: UUID = UUID(), url: String = "https://example.com", displayName: String? = nil, text: String? = nil) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.text = text
    }

    /// A text slide, ready to edit.
    static func textSlide(_ text: String = "", displayName: String? = nil) -> Slide {
        Slide(url: "", displayName: displayName, text: text)
    }

    var isTextSlide: Bool { text != nil }

    var content: SlideContent {
        if let text { return .text(text) }
        if Self.looksLikeImage(url) { return .image(Self.absoluteURL(url)) }
        return .web(Self.absoluteURL(url))
    }

    /// What the sidebar shows: the display name, else the first meaningful
    /// line of a text slide, else the raw URL.
    var label: String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            return displayName
        }
        if let text {
            let firstLine = text
                .components(separatedBy: .newlines)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if let firstLine {
                return firstLine.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
            }
            return "Empty text slide"
        }
        return url
    }

    private static let imageExtensions = ["png", "gif", "jpg", "jpeg", "webp", "svg"]

    /// Extension check on the path only, so a query string does not hide it.
    static func looksLikeImage(_ url: String) -> Bool {
        let path = url.lowercased().split(separator: "?").first.map(String.init) ?? url.lowercased()
        return imageExtensions.contains { path.hasSuffix(".\($0)") }
    }

    /// Bare hosts typed without a scheme are assumed to be https.
    static func absoluteURL(_ raw: String) -> String {
        if let parsed = URL(string: raw), parsed.scheme != nil { return raw }
        return "https://\(raw)"
    }

    enum CodingKeys: String, CodingKey {
        case id, url, displayName, text
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        text = try container.decodeIfPresent(String.self, forKey: .text)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(text, forKey: .text)
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
    /// Set by the remote; the visible slide watches it.
    private(set) var scrollRequest = ScrollRequest()
    /// Screen blanked mid-talk, so the room looks at you and not at the slide.
    var isBlackedOut: Bool = false
    /// Which display to present on. Session only: monitors come and go.
    var preferredScreenIndex: Int?

    /// The file the current list came from, or was last written to. Session
    /// only: under the sandbox, access to a user-picked file does not outlive
    /// the launch that granted it, so remembering the path would just produce
    /// a Save that fails.
    private(set) var currentFileURL: URL?
    /// Whether the current list has changed since it was last written to that
    /// file. Meaningless without one, so it stays false until there is one.
    private(set) var hasUnsavedFileChanges = false

    func requestScroll(dy: Double) {
        scrollRequest = ScrollRequest(sequence: scrollRequest.sequence + 1, dy: dy)
    }

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

    static var defaultStoreURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Present", isDirectory: true)
            .appendingPathComponent("presentations.json")
    }

    /// Where this instance persists. Injectable so tests get a temp directory
    /// instead of the real Application Support folder.
    let storeURL: URL
    private let defaults: UserDefaults

    init(storeURL: URL = PresentationState.defaultStoreURL, defaults: UserDefaults = .standard) {
        self.storeURL = storeURL
        self.defaults = defaults
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
        hasUnsavedFileChanges = false
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

    /// The slides to have ready: the next one, and the previous one for when
    /// you step back. Wraps around, like navigation does.
    var neighbourContents: [SlideContent] {
        guard slides.count > 1 else { return [] }
        let next = (currentIndex + 1) % slides.count
        let previous = (currentIndex - 1 + slides.count) % slides.count
        var result = [slides[next].content]
        if previous != next { result.append(slides[previous].content) }
        return result
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
        detachFromFile()
    }

    func deleteSet(id: UUID) {
        guard presentationSets.count > 1 else { return } // Never delete the last list
        presentationSets.removeAll { $0.id == id }
        if currentSetId == id {
            currentSetId = presentationSets.first?.id
            currentIndex = 0
            detachFromFile()
        }
    }

    func renameSet(id: UUID, newName: String) {
        if let index = presentationSets.firstIndex(where: { $0.id == id }) {
            presentationSets[index].name = newName
        }
    }

    func switchToSet(id: UUID) {
        if presentationSets.first(where: { $0.id == id }) != nil, id != currentSetId {
            currentSetId = id
            currentIndex = 0
            detachFromFile()
        }
    }

    /// The file belongs to the list it was opened as, not to the app.
    private func detachFromFile() {
        currentFileURL = nil
        hasUnsavedFileChanges = false
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

    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, spelled out
    /// here so the model stays pure Foundation and can be tested on its own.
    func moveSlide(from source: IndexSet, to destination: Int) {
        guard let setIndex = presentationSets.firstIndex(where: { $0.id == currentSetId }) else { return }
        var slides = presentationSets[setIndex].slides
        guard source.allSatisfy({ slides.indices.contains($0) }),
              (0...slides.count).contains(destination) else { return }

        // Remove high index first so the lower ones stay valid.
        let moved = source.sorted(by: >).map { slides.remove(at: $0) }.reversed()
        let insertAt = destination - source.filter { $0 < destination }.count
        slides.insert(contentsOf: moved, at: insertAt)
        presentationSets[setIndex].slides = slides
    }

    /// `Slide` is a reference type, so editing one in place does not touch the
    /// `presentationSets` array and never fires its `didSet`. Route edits
    /// through here so callers cannot forget to persist them.
    func updateSlide(_ slide: Slide, url: String, displayName: String?, text: String? = nil) {
        slide.url = url
        slide.displayName = displayName
        slide.text = text
        saveToDisk()
    }

    func saveToDisk() {
        guard !isLoading else { return }
        if currentFileURL != nil { hasUnsavedFileChanges = true }
        let document = StoredDocument(sets: presentationSets, currentSetId: currentSetId)
        let url = storeURL
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
        if let data = try? Data(contentsOf: storeURL) {
            do {
                let document = try JSONDecoder().decode(StoredDocument.self, from: data)
                presentationSets = document.sets
                currentSetId = document.currentSetId
                return false
            } catch {
                print("Present: error decoding presentations.json: \(error)")
            }
        }

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

    // MARK: - File formats
    //
    // Two of them, both lossless:
    //
    //   .json  the native format. Carries display names, text slides and the
    //          list name. What Save writes unless you ask for otherwise.
    //
    //   .txt   one slide per line, kept compatible with upstream and with
    //          kcarnold's fork. A quoted line is a text slide; an optional
    //          "Name | " prefix carries the display name. `\` and `|` are
    //          backslash-escaped in every field, so neither can be mistaken
    //          for the separator.

    enum FileFormat {
        case json
        case plainText

        static func inferred(from url: URL) -> FileFormat {
            url.pathExtension.lowercased() == "json" ? .json : .plainText
        }
    }

    /// One presentation list, as written to a .json file.
    struct PresentationFile: Codable {
        var name: String
        var slides: [Slide]
    }

    static func parseLine(_ line: String) -> Slide? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var displayName: String?
        var body = trimmed
        if let separator = indexOfUnescapedPipe(in: trimmed) {
            let name = unescapeField(String(trimmed[trimmed.startIndex..<separator]))
                .trimmingCharacters(in: .whitespaces)
            displayName = name.isEmpty ? nil : name
            body = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
        }
        guard !body.isEmpty else { return nil }

        if body.count >= 2, body.hasPrefix("\""), body.hasSuffix("\"") {
            let text = unescapeField(String(body.dropFirst().dropLast()))
            return Slide.textSlide(text, displayName: displayName)
        }
        return Slide(url: unescapeField(body), displayName: displayName)
    }

    static func formatLine(_ slide: Slide) -> String {
        let body: String
        if let text = slide.text {
            body = "\"\(escapeField(text, alsoEscaping: "\"\n"))\""
        } else {
            body = escapeField(slide.url)
        }

        guard let name = slide.displayName,
              !name.trimmingCharacters(in: .whitespaces).isEmpty else { return body }
        return "\(escapeField(name)) | \(body)"
    }

    /// The first `|` that is not preceded by a backslash, if any.
    private static func indexOfUnescapedPipe(in text: String) -> String.Index? {
        var escaped = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Always escapes `\` and `|`; text bodies also escape quotes and newlines.
    private static func escapeField(_ text: String, alsoEscaping extras: String = "") -> String {
        var out = ""
        for character in text {
            switch character {
            case "\\": out += "\\\\"
            case "|": out += "\\|"
            case "\"" where extras.contains("\""): out += "\\\""
            case "\n" where extras.contains("\n"): out += "\\n"
            case "\t" where extras.contains("\n"): out += "\\t"
            default: out.append(character)
            }
        }
        return out
    }

    private static func unescapeField(_ raw: String) -> String {
        var out = ""
        var escaped = false
        for character in raw {
            if escaped {
                switch character {
                case "n": out.append("\n")
                case "t": out.append("\t")
                default: out.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                out.append(character)
            }
        }
        if escaped { out.append("\\") }
        return out
    }

    func loadFromFile(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        let fallbackName = url.deletingPathExtension().lastPathComponent

        var newSet: PresentationSet
        if let file = try? JSONDecoder().decode(PresentationFile.self, from: data) {
            // Fresh ids, so opening the same file twice does not collide.
            let slides = file.slides.map {
                Slide(url: $0.url, displayName: $0.displayName, text: $0.text)
            }
            let name = file.name.trimmingCharacters(in: .whitespaces)
            newSet = PresentationSet(name: name.isEmpty ? fallbackName : name, slides: slides)
        } else {
            guard let contents = String(data: data, encoding: .utf8) else { return false }
            let slides = contents.components(separatedBy: .newlines).compactMap(Self.parseLine)
            newSet = PresentationSet(name: fallbackName, slides: slides)
        }
        guard !newSet.slides.isEmpty else { return false }

        presentationSets.append(newSet)
        currentSetId = newSet.id
        currentIndex = 0
        currentFileURL = url
        hasUnsavedFileChanges = false
        return true
    }

    @discardableResult
    func saveToFile(_ url: URL, format: FileFormat? = nil) -> Bool {
        guard let currentSet else { return false }
        do {
            switch format ?? .inferred(from: url) {
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let file = PresentationFile(name: currentSet.name, slides: currentSet.slides)
                try encoder.encode(file).write(to: url, options: .atomic)
            case .plainText:
                let contents = currentSet.slides.map(Self.formatLine).joined(separator: "\n") + "\n"
                try contents.write(to: url, atomically: true, encoding: .utf8)
            }
            currentFileURL = url
            hasUnsavedFileChanges = false
            return true
        } catch {
            print("Present: error writing \(url.lastPathComponent): \(error)")
            return false
        }
    }
}
