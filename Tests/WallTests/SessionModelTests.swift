import XCTest
@testable import Wall

@MainActor
final class SessionModelTests: XCTestCase {

    /// SessionModel persists to ~/Library/Application Support/Wall/session.json
    /// and reloads it on init. Clear it around every test so lifecycle tests
    /// (which call begin()) stay isolated and leave no residue on the machine.
    private var sessionFile: URL? {
        FileManager.wallSupport?.appendingPathComponent("session.json")
    }
    override func setUp() {
        super.setUp()
        if let f = sessionFile { try? FileManager.default.removeItem(at: f) }
    }
    override func tearDown() {
        if let f = sessionFile { try? FileManager.default.removeItem(at: f) }
        super.tearDown()
    }

    /// A session model wired to the no-op blocker — exercises pure derived
    /// state without touching pf or the network.
    private func makeModel() -> SessionModel {
        SessionModel(blocker: MockBlocker())
    }

    // MARK: Counting

    func testWordCount() {
        let m = makeModel()
        m.settings.countMode = .words
        m.text = "the quick brown fox"
        XCTAssertEqual(m.count, 4)
    }

    func testWordCountCollapsesWhitespace() {
        let m = makeModel()
        m.settings.countMode = .words
        m.text = "  spaced   out \n words  "
        XCTAssertEqual(m.count, 3)
    }

    func testWordCountEmpty() {
        let m = makeModel()
        m.settings.countMode = .words
        m.text = "   \n\t "
        XCTAssertEqual(m.count, 0)
    }

    func testCharacterCount() {
        let m = makeModel()
        m.settings.countMode = .characters
        m.text = "hello"
        XCTAssertEqual(m.count, 5)
    }

    // MARK: Word gate

    func testWordGateMetAtTarget() {
        let m = makeModel()
        m.settings.wordTarget = 3
        m.text = "one two three"
        XCTAssertTrue(m.wordGateMet)
        XCTAssertEqual(m.wordsRemaining, 0)
    }

    func testWordGateNotMetBelowTarget() {
        let m = makeModel()
        m.settings.wordTarget = 5
        m.text = "one two"
        XCTAssertFalse(m.wordGateMet)
        XCTAssertEqual(m.wordsRemaining, 3)
    }

    func testWordProgressClampsToOne() {
        let m = makeModel()
        m.settings.wordTarget = 2
        m.text = "one two three four"
        XCTAssertEqual(m.wordProgress, 1.0, accuracy: 0.0001)
    }

    func testWordProgressIsProportional() {
        let m = makeModel()
        m.settings.wordTarget = 4
        m.text = "one two"
        XCTAssertEqual(m.wordProgress, 0.5, accuracy: 0.0001)
    }

    // MARK: Time gate

    /// A zero-minute duration makes totalDuration == 0, so the time gate is
    /// satisfied immediately — a deterministic way to test gate combination
    /// without waiting on the wall clock.
    func testTimeGateMetWhenDurationZero() {
        let m = makeModel()
        m.settings.durationMinutes = 0
        XCTAssertTrue(m.timeGateMet)
    }

    func testBothGatesMetRequiresWordsToo() {
        let m = makeModel()
        m.settings.durationMinutes = 0   // time gate satisfied
        m.settings.wordTarget = 3
        m.text = "one two"               // word gate not yet
        XCTAssertTrue(m.timeGateMet)
        XCTAssertFalse(m.wordGateMet)
        XCTAssertFalse(m.bothGatesMet)

        m.text = "one two three"         // now both
        XCTAssertTrue(m.bothGatesMet)
    }

    // MARK: Lifecycle

    func testBeginActivatesSession() {
        let m = makeModel()
        XCTAssertEqual(m.phase, .idle)
        m.begin()
        XCTAssertEqual(m.phase, .active)
    }

    func testStartNewSessionResetsState() {
        let m = makeModel()
        m.text = "draft"
        m.settings.keepOnline = true
        m.begin()
        m.startNewSession()
        XCTAssertEqual(m.phase, .idle)
        XCTAssertEqual(m.text, "")
        XCTAssertFalse(m.settings.keepOnline)
    }

    func testFinishCompletesSession() {
        let m = makeModel()
        m.begin()
        m.finish()
        XCTAssertEqual(m.phase, .complete)
    }
}

final class WallSettingsTests: XCTestCase {

    func testDefaults() {
        let s = WallSettings()
        XCTAssertEqual(s.durationMinutes, 20)
        XCTAssertEqual(s.wordTarget, 250)
        XCTAssertEqual(s.countMode, .words)
        XCTAssertFalse(s.keepOnline)
    }

    func testCodableRoundTrip() throws {
        var s = WallSettings()
        s.durationMinutes = 40
        s.wordTarget = 750
        s.countMode = .characters
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(WallSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testCountModeLabels() {
        XCTAssertEqual(CountMode.words.label, "words")
        XCTAssertEqual(CountMode.characters.label, "characters")
    }
}
