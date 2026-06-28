import SwiftUI
import AppKit

/// The writing surface — a TextKit 2 `NSTextView` wrapped for SwiftUI.
///
/// Replaces SwiftUI's `TextEditor`, which can't reach the bar a focused-writing
/// app needs: control over caret, leading, measure, input latency, and (next)
/// typewriter scrolling and sentence focus. This is the foundation those build
/// on. Plain text only — what you write is a `.md` file, nothing rich.
struct WritingSurface: NSViewRepresentable {
    @Binding var text: String

    var font: NSFont
    var textColor: NSColor
    var caretColor: NSColor
    var lineSpacing: CGFloat
    /// Inset from the scroll view's top-leading to the first glyph. Paired with
    /// the placeholder's padding so they sit exactly on top of each other.
    var topInset: CGFloat = 8

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 2 (the modern layout stack) — `usingTextLayoutManager: true`.
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

        // Wrap to the scroll view's width; grow vertically with content.
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        textView.string = text
        context.coordinator.apply(typographyTo: textView)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.documentView = textView
        context.coordinator.textView = textView

        // Take focus once the view is in a window.
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        // Only overwrite on an *external* change (reset/restore); a programmatic
        // set doesn't fire the delegate, so there's no edit loop.
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.apply(typographyTo: textView)
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
        }
    }
}
