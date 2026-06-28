# Wall — best-in-class focused writing

The north star: **the writing surface is so good you'd use it even without the
wall — and the wall makes it unbeatable.** iA Writer earns focus through
*restraint*; Wall earns it through *enforcement* (network wall + gates + ritual).
Best-in-class Wall = iA Writer's surface craft fused onto Wall's enforcement.

## Build sequence (each step shippable)

- [ ] **1. Real text engine.** Replace SwiftUI `TextEditor` with a TextKit 2
      `NSTextView` surface. Nail input latency + typography. Everything else
      rides on this. *(Open decision: writing voice — Charter serif vs a
      mono/duospace. Lean duospace for drafting; keep Charter for reading.)*
- [ ] **2. Typewriter scrolling.** Pin the active line at a fixed height; text
      scrolls beneath it. Eyes stop climbing the screen.
- [ ] **3. Sentence focus / dimming.** Dim all but the current sentence — this
      *is* Wall's placeholder, "what's here right now?" The signature move.
- [ ] **4. Immersion mode.** Full-screen, menu bar hidden, tied to the session
      lifecycle. iA can dim distractions; only Wall can *remove* them.
- [ ] **5. Inline markdown + smart typography.** Subtle live styling that keeps
      the syntax visible; curly quotes, em-dashes, ellipses as you type.

## Discipline — what we refuse (half the answer)

No formatting toolbar, no rich text, no font/theme gallery. No multi-doc tabs or
file tree (Archive stays read-only). No folding/outlines/plugins/AI-rewrite. One
opinionated default over a wall of preferences. (Save-location is the one allowed
preference — it's about trust/portability, not styling.)

## The ritual

begin → the world narrows (net down, screen taken, focus dims, line pins) →
write → the wall comes down → you're back. Spend WoojMotion on the transitions;
entering/leaving a session should feel deliberate, not like a screen swap.
