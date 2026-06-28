import SwiftUI
import AppKit

/// The writing surface — a TextKit 2 `NSTextView` wrapped for SwiftUI.
///
/// Replaces SwiftUI's `TextEditor`, which can't reach the bar a focused-writing
/// app needs: control over caret, leading, input latency, typewriter scrolling,
/// and (next) sentence focus. Plain text only — what you write is a `.md` file.
struct WritingSurface: NSViewRepresentable {
    @Binding var text: String

    var font: NSFont
    var textColor: NSColor
    var caretColor: NSColor
    var lineSpacing: CGFloat
    /// Inset from the scroll view's top-leading to the first glyph. Paired with
    /// the placeholder's padding so they sit exactly on top of each other.
    var topInset: CGFloat = 8
    /// Pin the active line at a fixed height and scroll the text beneath it.
    var typewriter: Bool = true
    /// Where the active line sits, as a fraction of the viewport height.
    var anchor: CGFloat = 0.45
    /// Dim everything except the sentence the caret is in ("what's here right now?").
    var focusMode: Bool = true
    /// Color for the dimmed (out-of-focus) text.
    var dimColor: NSColor = .tertiaryLabelColor

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 2 (the modern layout stack).
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.insertionPointColor = caretColor
        textView.textContainerInset = NSSize(width: 0, height: topInset)
        // Smart substitutions arrive in a later step (inline markdown + smart
        // typography); keep the surface literal until then.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        textView.string = text
        context.coordinator.apply(typographyTo: textView)
        context.coordinator.applyFocus(to: textView)

        let scroll = NSScrollView()
        // A clip view that allows over-scroll past the top/bottom edges, so the
        // first and last lines can still reach the typewriter anchor.
        let clip = TypewriterClipView()
        clip.anchor = anchor
        clip.typewriter = typewriter
        scroll.contentView = clip
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.documentView = textView
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            context.coordinator.recenter()
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if let clip = scroll.contentView as? TypewriterClipView {
            clip.anchor = anchor
            clip.typewriter = typewriter
        }
        // Only overwrite on an *external* change (reset/restore); a programmatic
        // set doesn't fire the delegate, so there's no edit loop.
        if textView.string != text {
            textView.string = text
            context.coordinator.apply(typographyTo: textView)
            context.coordinator.recenter()
        }
        context.coordinator.applyFocus(to: textView)
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
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyFocus(to: textView)
            recenter()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let textView = notification.object as? NSTextView { applyFocus(to: textView) }
            recenter()
        }

        /// Dim the whole text, then restore full color to the sentence the caret
        /// is in. Falls back to no dimming when the caret sits between sentences
        /// (e.g. trailing whitespace), which reads fine.
        func applyFocus(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            if parent.focusMode, storage.length > 0 {
                storage.addAttribute(.foregroundColor, value: parent.dimColor, range: full)
                let focus = sentenceRange(in: textView.string,
                                          caret: textView.selectedRange().location)
                storage.addAttribute(.foregroundColor, value: parent.textColor, range: focus)
            } else {
                storage.addAttribute(.foregroundColor, value: parent.textColor, range: full)
            }
            storage.endEditing()
        }

        /// The UTF-16 range of the sentence containing `caret`, via the locale's
        /// sentence tokenizer. Whole-text fallback if none contains the caret.
        private func sentenceRange(in text: String, caret: Int) -> NSRange {
            var result = NSRange(location: 0, length: (text as NSString).length)
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex,
                                     options: .bySentences) { _, range, _, stop in
                let ns = NSRange(range, in: text)
                if caret >= ns.location && caret <= ns.location + ns.length {
                    result = ns
                    stop = true
                }
            }
            return result
        }

        /// Scroll so the caret line sits at the typewriter anchor.
        func recenter() {
            guard parent.typewriter,
                  let textView,
                  let scroll = textView.enclosingScrollView,
                  let clip = scroll.contentView as? TypewriterClipView,
                  textView.window != nil
            else { return }
            let caret = caretRectInView(textView)
            guard caret != .zero else { return }
            let h = clip.bounds.height
            let target = caret.midY - h * parent.anchor
            clip.scroll(to: NSPoint(x: 0, y: target))
            scroll.reflectScrolledClipView(clip)
        }

        /// The caret rect in the text view's coordinate space. `firstRect` is
        /// TextKit-version agnostic (returns screen coords), so this works under
        /// TextKit 2 without poking at layout fragments directly.
        private func caretRectInView(_ tv: NSTextView) -> NSRect {
            guard let window = tv.window else { return .zero }
            let screen = tv.firstRect(forCharacterRange: tv.selectedRange(), actualRange: nil)
            guard screen != .zero else { return .zero }
            let inWindow = window.convertFromScreen(screen)
            return tv.convert(inWindow, from: nil)
        }
    }
}

/// Clip view that permits scrolling past the document's top and bottom edges by
/// the amount needed for the first/last lines to reach the typewriter anchor.
final class TypewriterClipView: NSClipView {
    var typewriter = true
    var anchor: CGFloat = 0.45

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        let rect = super.constrainBoundsRect(proposedBounds)
        guard typewriter, let docView = documentView else { return rect }
        let h = rect.height
        let overscrollTop = h * anchor
        let overscrollBottom = h * (1 - anchor)
        let minY = -overscrollTop
        let maxY = max(minY, docView.frame.height - h + overscrollBottom)
        var out = rect
        out.origin.y = min(max(proposedBounds.origin.y, minY), maxY)
        return out
    }
}
