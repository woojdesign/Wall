import XCTest
import SwiftUI
import SnapshotTesting
@testable import Wall

/// Visual regression for key views. Reference images live in __Snapshots__ next
/// to this file and are committed; CI diffs against them.
///
/// Determinism notes:
/// - Fonts: Charter is a system font (present locally + on the CI runner); Geist
///   isn't installed anywhere, so it falls back to the system font consistently.
/// - These views carry no dates / disk / timezone state, so they're stable. The
///   Archive (dated, dynamic) needs an injected clock before it can be snapshotted
///   reliably — tracked as a follow-up.
@MainActor
final class SnapshotTests: XCTestCase {

    private var sessionFile: URL? { FileManager.wallSupport?.appendingPathComponent("session.json") }

    override func setUp() {
        super.setUp()
        // No restored session — keep the model at its deterministic defaults.
        if let f = sessionFile { try? FileManager.default.removeItem(at: f) }
    }
    override func tearDown() {
        if let f = sessionFile { try? FileManager.default.removeItem(at: f) }
        super.tearDown()
    }

    private func model() -> SessionModel { SessionModel(blocker: MockBlocker()) }

    /// Render with SwiftUI's `ImageRenderer` at a *fixed* scale, so the output
    /// is identical regardless of the machine's screen scale (a retina dev Mac
    /// vs. the CI runner). NSHostingController would inherit the screen scale and
    /// mismatch dimensions across environments.
    private func assertView<V: View>(_ view: V, size: CGSize,
                                     testName: String = #function,
                                     dark: Bool = false,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, dark ? .dark : .light)
        )
        renderer.scale = 2
        // Palette's dark variants resolve off the *drawing* appearance, so force
        // it while rasterizing — colorScheme alone doesn't drive a dynamic NSColor.
        var image: NSImage?
        if dark {
            let previous = NSApplication.shared.appearance
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
            image = renderer.nsImage
            NSApplication.shared.appearance = previous
        } else {
            image = renderer.nsImage
        }
        guard let image else {
            XCTFail("ImageRenderer produced no image", file: file, line: line)
            return
        }
        assertSnapshot(
            of: image,
            as: .image(precision: 0.98, perceptualPrecision: 0.96),
            file: file, testName: testName, line: line
        )
    }

    func testStartView() {
        assertView(StartView().environmentObject(model()),
                   size: CGSize(width: 880, height: 740))
    }

    // (No StartView dark snapshot: ImageRenderer can't rasterize the segmented
    // CountMode picker under a forced dark appearance — it draws an "unrenderable"
    // placeholder. The control is fine in the real dark app; DoneView dark below
    // covers the dark palette without a segmented control.)
    func testDoneViewDark() {
        let view = ZStack { Palette.ground; DoneView().environmentObject(model()) }
        assertView(view, size: CGSize(width: 880, height: 740), dark: true)
    }

    func testDoneView() {
        assertView(DoneView().environmentObject(model()),
                   size: CGSize(width: 880, height: 740))
    }

    /// First-session confirmation, rendered over the start screen it dims.
    func testFirstSessionSheet() {
        let view = ZStack {
            StartView().environmentObject(model())
            FirstSessionSheet(minutes: 20, target: 1250, unit: "words", keepOnline: false, onBegin: {}, onCancel: {})
        }
        assertView(view, size: CGSize(width: 880, height: 740))
    }
}
