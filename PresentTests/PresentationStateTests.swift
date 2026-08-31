import XCTest

/// The model is pure Foundation, so these run without launching the app.
final class PresentationStateTests: XCTestCase {

    private var directory: URL!
    private var store: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PresentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = directory.appendingPathComponent("presentations.json")

        suiteName = "PresentTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeState() -> PresentationState {
        PresentationState(storeURL: store, defaults: defaults)
    }

    // MARK: - Persistence

    func testColdStartCreatesOneSetAndWritesTheStore() {
        let state = makeState()
        XCTAssertEqual(state.presentationSets.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path))
    }

    /// Regression: createSet() appended to the array (firing its didSet) before
    /// assigning the new id, so the autosave persisted the *previous* one.
    func testCreateSetPersistsTheNewSetId() {
        let state = makeState()
        state.createSet(name: "Charla A")
        let created = state.currentSetId

        let reopened = makeState()
        XCTAssertEqual(reopened.currentSetId, created)
        XCTAssertEqual(reopened.presentationSets.count, 2)
    }

    /// Regression: currentSetId had no didSet, so switching lists persisted
    /// nothing and the app always reopened on the previous one.
    func testSwitchToSetSurvivesRelaunch() {
        let target: UUID
        do {
            let state = makeState()
            state.createSet(name: "Charla A")
            state.createSet(name: "Charla B")
            target = state.presentationSets[0].id
        }

        // Switching lists must persist on its own. Done in a fresh instance
        // with no other mutation, so no array write can save the id by accident.
        do {
            let state = makeState()
            XCTAssertNotEqual(state.currentSetId, target, "fixture: the target must not be current already")
            state.switchToSet(id: target)
        }

        XCTAssertEqual(makeState().currentSetId, target)
    }

    /// Regression: Slide is a reference type, so editing one never touched the
    /// presentationSets array and never fired its didSet.
    func testEditingASlidePersists() {
        let state = makeState()
        state.addSlide(Slide(url: "https://ejemplo.test"))
        state.updateSlide(state.slides[0], url: "https://jlmirall.es", displayName: "Portada")

        let reopened = makeState()
        XCTAssertEqual(reopened.slides.first?.url, "https://jlmirall.es")
        XCTAssertEqual(reopened.slides.first?.displayName, "Portada")
    }

    func testDeletingTheCurrentSetLeavesAValidSelection() {
        let state = makeState()
        state.createSet(name: "Charla A")
        state.deleteSet(id: state.currentSetId!)

        let reopened = makeState()
        XCTAssertTrue(reopened.presentationSets.contains { $0.id == reopened.currentSetId })
    }

    func testTheLastSetCannotBeDeleted() {
        let state = makeState()
        state.deleteSet(id: state.currentSetId!)
        XCTAssertEqual(state.presentationSets.count, 1)
    }

    // MARK: - Migration

    func testMigratesUpstreamFlatURLArray() {
        defaults.set(["https://a.test", "https://b.test"], forKey: "presentAutosavedURLs")

        let state = makeState()
        XCTAssertEqual(state.slides.map(\.url), ["https://a.test", "https://b.test"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path))

        // Once migrated the data must stand on its own.
        defaults.removeObject(forKey: "presentAutosavedURLs")
        XCTAssertEqual(makeState().slides.count, 2)
    }

    func testMigratesSetsPreviouslyKeptInUserDefaults() throws {
        let set = PresentationSet(name: "Antigua", slides: [Slide(url: "https://a.test", displayName: "A")])
        defaults.set(try JSONEncoder().encode([set]), forKey: "presentAutosavedSets")
        defaults.set(set.id.uuidString, forKey: "presentCurrentSetId")

        let state = makeState()
        XCTAssertEqual(state.currentSet?.name, "Antigua")
        XCTAssertEqual(state.slides.first?.displayName, "A")
    }

    // MARK: - Navigation

    func testNavigationWrapsAround() {
        let state = makeState()
        state.addSlide(Slide(url: "https://a.test"))
        state.addSlide(Slide(url: "https://b.test"))

        state.currentIndex = 0
        state.goToPrevious()
        XCTAssertEqual(state.currentIndex, 1)
        state.goToNext()
        XCTAssertEqual(state.currentIndex, 0)
    }

    func testNavigationOnAnEmptyListIsSafe() {
        let state = makeState()
        state.goToNext()
        state.goToPrevious()
        XCTAssertEqual(state.currentIndex, 0)
        XCTAssertNil(state.currentSlide)
    }

    // MARK: - Reordering

    /// moveSlide must match SwiftUI's move(fromOffsets:toOffset:) semantics,
    /// where the destination is an insertion point in the *original* list.
    func testMoveSlideMatchesSwiftUISemantics() {
        let state = makeState()
        for name in ["a", "b", "c", "d"] {
            state.addSlide(Slide(url: name))
        }

        state.moveSlide(from: IndexSet(integer: 0), to: 3)   // a between c and d
        XCTAssertEqual(state.slides.map(\.url), ["b", "c", "a", "d"])

        state.moveSlide(from: IndexSet(integer: 3), to: 0)   // d to the front
        XCTAssertEqual(state.slides.map(\.url), ["d", "b", "c", "a"])

        state.moveSlide(from: IndexSet([0, 1]), to: 4)       // two at once, to the end
        XCTAssertEqual(state.slides.map(\.url), ["c", "a", "d", "b"])
    }

    func testMoveSlideIgnoresOutOfRangeInput() {
        let state = makeState()
        state.addSlide(Slide(url: "a"))
        state.moveSlide(from: IndexSet(integer: 7), to: 0)
        state.moveSlide(from: IndexSet(integer: 0), to: 99)
        XCTAssertEqual(state.slides.map(\.url), ["a"])
    }

    func testRemoveSlideIgnoresOutOfRangeIndex() {
        let state = makeState()
        state.addSlide(Slide(url: "a"))
        state.removeSlide(at: 5)
        XCTAssertEqual(state.slides.count, 1)
    }

    // MARK: - Plain text file format

    func testTextSlidesSurviveAFileRoundTrip() throws {
        let state = makeState()
        state.addSlide(Slide(url: "https://jlmirall.es"))
        state.addSlide(Slide.textSlide("# Título\n\nCon *énfasis* y \"comillas\""))

        let file = directory.appendingPathComponent("charla.txt")
        XCTAssertTrue(state.saveToFile(file))

        let reopened = makeState()
        XCTAssertTrue(reopened.loadFromFile(file))
        XCTAssertEqual(reopened.slides.count, 2)
        XCTAssertEqual(reopened.slides[0].url, "https://jlmirall.es")
        XCTAssertEqual(reopened.slides[1].text, "# Título\n\nCon *énfasis* y \"comillas\"")
    }

    func testOpeningAFileNamesTheListAfterIt() throws {
        let file = directory.appendingPathComponent("Congreso 2026.txt")
        try "https://a.test\n".write(to: file, atomically: true, encoding: .utf8)

        let state = makeState()
        XCTAssertTrue(state.loadFromFile(file))
        XCTAssertEqual(state.currentSet?.name, "Congreso 2026")
    }

    func testParsesKcarnoldStyleQuotedTextLines() {
        let slide = PresentationState.parseLine(##""# Hola\nmundo""##)
        XCTAssertEqual(slide?.text, "# Hola\nmundo")
        XCTAssertTrue(slide?.isTextSlide == true)
    }

    func testBlankLinesAreSkippedWhenParsing() {
        XCTAssertNil(PresentationState.parseLine("   "))
        XCTAssertEqual(PresentationState.parseLine("  https://a.test  ")?.url, "https://a.test")
    }
}

// MARK: - File formats

final class FileFormatTests: XCTestCase {

    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PresentFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "PresentFileTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeState() -> PresentationState {
        PresentationState(
            storeURL: directory.appendingPathComponent("\(UUID().uuidString).json"),
            defaults: defaults
        )
    }

    /// The slides used to check that nothing is dropped on the way out and back.
    private func seed(_ state: PresentationState) {
        state.addSlide(Slide(url: "https://jlmirall.es", displayName: "Portada"))
        state.addSlide(Slide(url: "https://example.com/a.png"))
        state.addSlide(Slide.textSlide("# Título\n\nCon *énfasis*", displayName: "Sección"))
    }

    private func assertRoundTrips(_ file: URL, line: UInt = #line) {
        let source = makeState()
        seed(source)
        XCTAssertTrue(source.saveToFile(file), line: line)

        let target = makeState()
        XCTAssertTrue(target.loadFromFile(file), line: line)
        XCTAssertEqual(target.slides.count, 3, line: line)
        XCTAssertEqual(target.slides.map(\.url), source.slides.map(\.url), line: line)
        XCTAssertEqual(target.slides.map(\.displayName), source.slides.map(\.displayName), line: line)
        XCTAssertEqual(target.slides.map(\.text), source.slides.map(\.text), line: line)
    }

    /// The whole point of category 3: Save must not silently drop data.
    func testJSONRoundTripKeepsEverything() {
        assertRoundTrips(directory.appendingPathComponent("charla.json"))
    }

    func testPlainTextRoundTripKeepsEverything() {
        assertRoundTrips(directory.appendingPathComponent("charla.txt"))
    }

    func testJSONFileCarriesTheListName() {
        let state = makeState()
        state.createSet(name: "Congreso")
        state.addSlide(Slide(url: "https://a.test"))
        let file = directory.appendingPathComponent("cualquiera.json")
        XCTAssertTrue(state.saveToFile(file))

        let reopened = makeState()
        XCTAssertTrue(reopened.loadFromFile(file))
        XCTAssertEqual(reopened.currentSet?.name, "Congreso")
    }

    // MARK: Escaping in the plain text format

    func testPipesInNamesAndURLsSurvive() {
        let slide = Slide(url: "https://a.test/?q=x%7Cy|z", displayName: "A | B")
        let parsed = PresentationState.parseLine(PresentationState.formatLine(slide))
        XCTAssertEqual(parsed?.displayName, "A | B")
        XCTAssertEqual(parsed?.url, "https://a.test/?q=x%7Cy|z")
    }

    func testPipesInsideTextSlidesAreNotReadAsASeparator() {
        let slide = Slide.textSlide("a | b\nc", displayName: "T")
        let parsed = PresentationState.parseLine(PresentationState.formatLine(slide))
        XCTAssertEqual(parsed?.displayName, "T")
        XCTAssertEqual(parsed?.text, "a | b\nc")
    }

    func testBackslashesSurvive() {
        let slide = Slide(url: "https://a.test/c:\\path", displayName: "back\\slash")
        let parsed = PresentationState.parseLine(PresentationState.formatLine(slide))
        XCTAssertEqual(parsed?.displayName, "back\\slash")
        XCTAssertEqual(parsed?.url, "https://a.test/c:\\path")
    }

    /// Upstream files are bare URLs, one per line, and must still open.
    func testUpstreamPlainFilesStillOpen() throws {
        let file = directory.appendingPathComponent("upstream.txt")
        try "https://a.test\nhttps://b.test\n".write(to: file, atomically: true, encoding: .utf8)

        let state = makeState()
        XCTAssertTrue(state.loadFromFile(file))
        XCTAssertEqual(state.slides.map(\.url), ["https://a.test", "https://b.test"])
        XCTAssertNil(state.slides[0].displayName)
    }

    func testFormatIsChosenByExtension() {
        let state = makeState()
        state.addSlide(Slide(url: "https://a.test", displayName: "A"))

        let json = directory.appendingPathComponent("x.json")
        let text = directory.appendingPathComponent("x.txt")
        state.saveToFile(json)
        state.saveToFile(text)

        XCTAssertTrue((try? String(contentsOf: json, encoding: .utf8))?.hasPrefix("{") == true)
        XCTAssertEqual(try? String(contentsOf: text, encoding: .utf8), "A | https://a.test\n")
    }

    func testOpeningTheSameFileTwiceDoesNotReuseSlideIDs() {
        let state = makeState()
        state.addSlide(Slide(url: "https://a.test"))
        let file = directory.appendingPathComponent("x.json")
        state.saveToFile(file)

        let target = makeState()
        XCTAssertTrue(target.loadFromFile(file))
        let firstIDs = target.slides.map(\.id)
        XCTAssertTrue(target.loadFromFile(file))
        XCTAssertTrue(Set(firstIDs).isDisjoint(with: target.slides.map(\.id)))
    }

    func testOpeningRubbishFails() throws {
        let file = directory.appendingPathComponent("empty.txt")
        try "\n   \n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertFalse(makeState().loadFromFile(file))
    }

    // MARK: Save vs Save As

    func testSaveTracksTheFileAndClearsTheEditedMarker() {
        let state = makeState()
        state.addSlide(Slide(url: "https://a.test"))
        XCTAssertNil(state.currentFileURL)

        let file = directory.appendingPathComponent("x.json")
        XCTAssertTrue(state.saveToFile(file))
        XCTAssertEqual(state.currentFileURL, file)
        XCTAssertFalse(state.hasUnsavedFileChanges)

        state.addSlide(Slide(url: "https://b.test"))
        XCTAssertTrue(state.hasUnsavedFileChanges)

        XCTAssertTrue(state.saveToFile(file))
        XCTAssertFalse(state.hasUnsavedFileChanges)
    }

    func testOpeningAFileAssociatesItWithoutMarkingItEdited() {
        let source = makeState()
        source.addSlide(Slide(url: "https://a.test"))
        let file = directory.appendingPathComponent("x.json")
        source.saveToFile(file)

        let target = makeState()
        XCTAssertTrue(target.loadFromFile(file))
        XCTAssertEqual(target.currentFileURL, file)
        XCTAssertFalse(target.hasUnsavedFileChanges)
    }

    /// The file belongs to the list, so switching lists must let go of it —
    /// otherwise Cmd+S would overwrite it with a different presentation.
    func testSwitchingListsReleasesTheFile() {
        let state = makeState()
        state.addSlide(Slide(url: "https://a.test"))
        state.saveToFile(directory.appendingPathComponent("x.json"))
        XCTAssertNotNil(state.currentFileURL)

        state.createSet(name: "Otra")
        XCTAssertNil(state.currentFileURL)
    }

    func testAFreshListIsNotMarkedEdited() {
        let state = makeState()
        state.addSlide(Slide(url: "https://a.test"))
        XCTAssertFalse(state.hasUnsavedFileChanges, "no file to be dirty against")
    }
}
