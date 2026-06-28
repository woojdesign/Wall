import SwiftUI
import AppKit

/// The writing surface — an NSTextView wrapped for SwiftUI, with typewriter
/// scrolling and sentence focus.
///
/// Deliberately **TextKit 1** (NSLayoutManager), not TextKit 2. TextKit 2 lays
/// out lazily by viewport and *estimates* off-screen height; those estimates
/// jitter as you scroll/type, so any code that reads an absolute caret position
/// (like typewriter centering) fights a moving coordinate space — the jumping
/// that worsens with document length. TextKit 1 lays the whole document out
/// eagerly, so glyph/line rects are stable. Worth it for a focused-writing app
/// with session-sized documents.
struct WritingSurface: NSViewRepresentable {
    @Binding var text: String

    var font: NSFont
    var textColor: NSColor
    var caretColor: NSColor
    var lineSpacing: CGFloat
    var placeholder: String = ""
    var typewriter: Bool = true
    /// Dim everything except the sentence the caret is in.
    var focusMode: Bool = true
    var dimColor: NSColor = .tertiaryLabelColor

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // Build an explicit TextKit 1 stack so the view never silently uses
        // TextKit 2 (NSTextView() defaults to TextKit 2 on modern macOS).
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = TypewriterTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.insertionPointColor = caretColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        textView.typewriter = typewriter
        textView.lineSpacingValue = lineSpacing
        textView.placeholder = placeholder
        textView.placeholderColor = dimColor

        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.apply(typographyTo: textView)
        context.coordinator.applyFocus(to: textView)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.documentView = textView

        // Recompute the overscroll inset (and recenter) whenever the viewport
        // resizes — the inset depends on viewport height.
        scroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            textView, selector: #selector(TypewriterTextView.viewportChanged),
            name: NSView.frameDidChangeNotification, object: scroll.contentView)

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.updateOverscrollInset()
            textView.recenter()
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? TypewriterTextView else { return }
        context.coordinator.parent = self
        textView.typewriter = typewriter
        textView.lineSpacingValue = lineSpacing
        // React only to an *external* text change (reset/restore). We do NOT
        // recolor or recenter on every SwiftUI re-render — per-keystroke work
        // lives in the AppKit delegate.
        if textView.string != text {
            textView.string = text
            context.coordinator.apply(typographyTo: textView)
            context.coordinator.applyFocus(to: textView)
            textView.scheduleRecenter()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WritingSurface
        weak var textView: NSTextView?

        init(_ parent: WritingSurface) { self.parent = parent }

        func apply(typographyTo textView: NSTextView) {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = parent.lineSpacing
            let attrs: [NSAttributedString.Key: Any] = [
                .font: parent.font,
                .foregroundColor: parent.textColor,
                .paragraphStyle: style,
            ]
            textView.typingAttributes = attrs
            textView.insertionPointColor = parent.caretColor
            if let storage = textView.textStorage, storage.length > 0 {
                storage.addAttributes(attrs, range: NSRange(location: 0, length: storage.length))
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? TypewriterTextView else { return }
            parent.text = textView.string
            textView.needsDisplay = true   // refresh placeholder visibility
            textView.scheduleRecenter()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? TypewriterTextView else { return }
            applyFocus(to: textView)
            textView.scheduleRecenter()
        }

        /// Dim the whole text, then restore full color to the sentence the caret
        /// is in. Whole-text fallback when the caret sits between sentences.
        func applyFocus(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            if parent.focusMode, storage.length > 0 {
                storage.addAttribute(.foregroundColor, value: parent.dimColor, range: full)
                let focus = FocusBoundary.sentenceRange(in: textView.string,
                                                        caret: textView.selectedRange().location)
                storage.addAttribute(.foregroundColor, value: parent.textColor, range: focus)
            } else {
                storage.addAttribute(.foregroundColor, value: parent.textColor, range: full)
            }
            storage.endEditing()
        }

    }
}

/// Which run of text counts as the "active sentence" for focus dimming.
///
/// Deterministic on purpose: a sentence ends at `.`, `!`, `?`, `…`, or a
/// newline — never dependent on what follows. The locale sentence tokenizer
/// (`enumerateSubstrings(.bySentences)`) treats "period + capital" as a
/// boundary but "period + lowercase" as an abbreviation, which made the dimming
/// feel inconsistent while writing. When the caret sits right after a
/// terminator, the just-finished sentence stays lit until the next one starts.
enum FocusBoundary {
    static let terminators = Set(".!?…\n".unicodeScalars)

    static func sentenceRange(in text: String, caret: Int) -> NSRange {
        let ns = text as NSString
        let len = ns.length
        guard len > 0 else { return NSRange(location: 0, length: 0) }
        let c = min(max(caret, 0), len)

        func isBoundary(_ idx: Int) -> Bool {
            guard idx >= 0, idx < len, let s = Unicode.Scalar(ns.character(at: idx)) else { return false }
            return terminators.contains(s)
        }

        // End (exclusive). If the caret just landed after a terminator, the
        // active sentence is the one that terminator ends.
        var end = len
        if c > 0 && isBoundary(c - 1) {
            end = c
        } else {
            var j = c
            while j < len { if isBoundary(j) { end = j + 1; break }; j += 1 }
        }
        // Start: just past the previous boundary (skip the terminator at end-1).
        var start = 0
        var i = end - 2
        while i >= 0 { if isBoundary(i) { start = i + 1; break }; i -= 1 }
        // Don't light leading whitespace/newlines.
        while start < end,
              let s = Unicode.Scalar(ns.character(at: start)),
              CharacterSet.whitespacesAndNewlines.contains(s) { start += 1 }

        return NSRange(location: start, length: max(0, end - start))
    }
}

/// NSTextView that keeps the active line vertically centered (typewriter mode)
/// using stable TextKit 1 geometry, and draws a placeholder where text begins.
final class TypewriterTextView: NSTextView {
    var typewriter = true
    var lineSpacingValue: CGFloat = 0
    var placeholder = ""
    var placeholderColor: NSColor = .placeholderTextColor

    // MARK: Overscroll

    /// Symmetric top/bottom inset of ~half the viewport so the first and last
    /// lines can reach the center. As a bonus this starts an empty document
    /// centered, so the placeholder/first line sit mid-screen.
    func updateOverscrollInset() {
        guard typewriter, let clip = enclosingScrollView?.contentView else {
            textContainerInset = NSSize(width: 0, height: 8)
            return
        }
        let inset = max(8, floor((clip.bounds.height - activeLineHeight()) / 2))
        textContainerInset = NSSize(width: 0, height: inset)
    }

    @objc func viewportChanged() {
        updateOverscrollInset()
        recenter()
    }

    private func activeLineHeight() -> CGFloat {
        guard let lm = layoutManager, let f = font else { return 21 }
        return lm.defaultLineHeight(for: f) + lineSpacingValue
    }

    // MARK: Typewriter centering (coalesced)

    private var recenterScheduled = false
    func scheduleRecenter() {
        guard typewriter, !recenterScheduled else { return }
        recenterScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.recenterScheduled = false
            self?.recenter()
        }
    }

    /// Scroll so the caret's line fragment is centered in the viewport. Reads
    /// the line rect from the (eagerly laid-out, stable) layout manager.
    func recenter() {
        guard typewriter,
              let lm = layoutManager,
              let container = textContainer,
              let scroll = enclosingScrollView,
              window != nil
        else { return }

        guard let line = caretLineRect(lm, container) else { return }
        let viewLine = line.offsetBy(dx: 0, dy: textContainerOrigin.y)
        let h = scroll.contentView.bounds.height
        let target = viewLine.midY - h / 2
        let clip = scroll.contentView
        // No-op if we're already there — typing along one line shouldn't
        // re-scroll. With stable TextKit 1 coordinates this guard actually
        // holds, which is what kills the feedback loop.
        if abs(clip.bounds.origin.y - target) < 0.5 { return }
        clip.scroll(to: NSPoint(x: 0, y: target))
        scroll.reflectScrolledClipView(clip)
    }

    /// Line-fragment rect (container coords) for the line the caret is on,
    /// handling the caret at end-of-document / on the trailing empty line.
    private func caretLineRect(_ lm: NSLayoutManager, _ container: NSTextContainer) -> NSRect? {
        let charLen = (string as NSString).length
        let loc = min(selectedRange().location, charLen)
        if loc >= charLen, lm.extraLineFragmentTextContainer != nil {
            return lm.extraLineFragmentRect
        }
        if lm.numberOfGlyphs == 0 {
            // Empty document with no extra fragment — center on the insertion origin.
            return NSRect(origin: .zero, size: NSSize(width: 0, height: activeLineHeight()))
        }
        let glyphIndex = min(lm.glyphIndexForCharacter(at: loc), lm.numberOfGlyphs - 1)
        return lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    }

    // MARK: Placeholder

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let pad = textContainer?.lineFragmentPadding ?? 0
        let origin = NSPoint(x: textContainerOrigin.x + pad, y: textContainerOrigin.y)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 21),
            .foregroundColor: placeholderColor,
        ]
        (placeholder as NSString).draw(at: origin, withAttributes: attrs)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
