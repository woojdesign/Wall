# Wall — best-in-class focused writing

The north star: **the writing surface is so good you'd use it even without the
wall — and the wall makes it unbeatable.** iA Writer earns focus through
*restraint*; Wall earns it through *enforcement* (network wall + gates + ritual).
Best-in-class Wall = iA Writer's surface craft fused onto Wall's enforcement.

## Build sequence (each step shippable)

- [x] **1. Real text engine.** Rebuilt on **TextKit 1** (not 2 — TextKit 2's
      estimated-height layout jittered, causing scroll jumps that worsened with
      length). Stable geometry. *(Open: Charter serif vs a duospace for drafting.)*
- [x] **2. Typewriter scrolling.** Active line centered via `lineFragmentRect`;
      overscroll via symmetric `textContainerInset`.
- [x] **3. Sentence focus / dimming.** Deterministic boundaries (`. ! ? … \n`),
      consistent regardless of capitalization.
- [x] **4. Immersion mode.** Full-screen on session begin, back to a window on
      end; menu bar auto-hidden. Opt-out in Settings.
- [x] **5. Smart typography + markdown headers.** Curly quotes + em/en dashes
      (native); live ATX header styling. *(Bold/italic + ellipsis: follow-up.)*

## Follow-ups / food for thought

- Bold/italic inline styling; `…` substitution.
- Charter vs duospace decision for the drafting voice.
- Let text reach the top of the window (currently a little top padding).
- Spell-check squiggles deliberately off (kept for flow).

## Discipline — what we refuse (half the answer)

No formatting toolbar, no rich text, no font/theme gallery. No multi-doc tabs or
file tree (Archive stays read-only). No folding/outlines/plugins/AI-rewrite. One
opinionated default over a wall of preferences. (Save-location is the one allowed
preference — it's about trust/portability, not styling.)

## The ritual

begin → the world narrows (net down, screen taken, focus dims, line pins) →
write → the wall comes down → you're back. Spend WoojMotion on the transitions;
entering/leaving a session should feel deliberate, not like a screen swap.
