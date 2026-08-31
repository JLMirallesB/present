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
