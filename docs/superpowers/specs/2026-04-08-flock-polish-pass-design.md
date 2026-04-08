# Flock Polish Pass — Design

**Date:** 2026-04-08
**Target version:** v0.9.6 (or v1.0 if combined with upcoming features)
**Status:** Approved scope, awaiting spec review

## Goal

A focused polish pass before adding marquee 1.0 features (Diff/Git pane, Session sharing). The codebase just had two large bug-fix sweeps (v0.9.4 fixed 13 issues, v0.9.5 fixed 17), so crash-tier and race-condition bugs are handled. This pass targets the **user-facing UX surface** that those sweeps did not cover: onboarding for new users, discoverability of existing features, visual consistency across surfaces, and a handful of tactical improvements.

The pass is intentionally scoped so all 14 items can ship as a single coherent release rather than dribble out across multiple versions.

## Non-goals

- **No refactors.** TabBarView (887 lines) and CommandPalette (673 lines) both mix concerns and would benefit from being split, but that is its own ticket. This pass touches them surgically only.
- **No new pane types.** Diff/Git pane is the next sub-project, separate spec.
- **No networking changes.** Session sharing is the third sub-project, separate spec.
- **No theme additions.** All 7 existing themes stay; we only fix coverage gaps.

## Themes and items

### Theme 1 — Onboarding & empty states

New users (PH launch is bringing them in) currently land in a bare Claude pane with no orientation, and several first-touch surfaces show blank space instead of guidance.

**1.1 First-launch welcome card**
- A one-time card overlay on the main window the first time the app launches with no restored session.
- Content: short headline, 4–5 key bindings (`⌘K` palette, `⌘D` split, `⌘⇧M` memory, `⌘⇧A` agent mode, `⌘,` prefs), one line about themes.
- Visual: theme-aware card using `Theme.surface` and `Theme.borderRest`, sized to feel like a small printed card rather than a full modal. Backdrop dims the rest of the window slightly (matches the existing CommandPalette overlay pattern).
- **Animated pixel bird.** A small pixel-art bird flies across the top of the card, ported directly from the marketing site (`docs/index.html` lines 148–176). The site draws each bird from `box-shadow` pixels and swaps between two frames every 0.4s with `steps(1)` to flap. Same approach in Cocoa:
  - New view: `PixelBirdView: NSView`. No image asset needed.
  - Two frames hard-coded as `[(Int, Int)]` pixel coordinates on a 7×3 grid:
    - **Frame 0 (wings up):** `[(0,0),(6,0),(1,1),(5,1),(2,2),(3,2),(4,2)]`
    - **Frame 1 (wings down):** `[(2,0),(3,0),(4,0),(1,1),(5,1),(0,2),(6,2)]`
  - `draw(_:)` fills each pixel as a small square (e.g., 4pt × 4pt) in `Theme.textPrimary`. Total bird size ≈ 28×12pt.
  - A `Timer` (or `CADisplayLink` equivalent) flips a `frame: Int` every 0.4s and calls `setNeedsDisplay`.
  - **Flight path:** a `CABasicAnimation` on `position.x` translates the bird from off-card-left to off-card-right over ~6s, looping infinitely. One bird is enough for the card; the marketing site uses 7 because the hero is full-screen, but a single bird carries the same charm at this scale.
  - **Hover interaction:** hovering the card (any part, via `NSTrackingArea`) speeds the flap timer up briefly to 0.2s for ~1s, then eases back. Tiny moment of delight that says the card knows you're there.
- Dismissable via "Got it" button or `Esc`. Sets `Settings.shared.hasSeenWelcome = true` and never appears again.
- New files: `WelcomeCard.swift` (overlay view), `PixelBirdView.swift` (the bird view, kept separate so it can be reused — e.g., later as a loading indicator or empty-state decoration). Wired in `main.swift` after pane creation, gated on `!Settings.shared.hasSeenWelcome && paneManager.panes.count == 1`.
- **Continuity bonus:** because this is the same bird from the website hero, a user who installed via the marketing site sees the exact same character on first launch. Brand echo for free.

**1.2 Empty Agent sidebar hint**
- When `TaskStore.shared.tasks.isEmpty` and Agent Mode is active, show a centered placeholder in `AgentSidebarView`: short instruction line plus the `⌘N` shortcut.
- Theme-aware text colors (`Theme.textSecondary` for instruction, `Theme.textTertiary` for shortcut).
- Edit: `AgentSidebarView.swift` — add an empty-state branch in the body where the task list renders.

**1.3 Empty Memory hint**
- Replace the bare "No memories yet" string in `MemoryView.swift:369-377` with a one-line why-and-how: e.g., "Pin a thought, paste, or task summary so Claude can pick it up later. ⌘⇧M to add."
- Same theme-aware treatment as 1.2.

**1.4 Empty status bar on first launch**
- `StatusBarView.swift:92-101` returns blank when `paneManager.panes.isEmpty`. Replace with a tertiary-colored hint: "⌘T for a new pane".

### Theme 2 — Discoverability

Several real features are unreachable without already knowing they exist.

**2.1 Markdown pane menu items**
- File menu currently lacks "New Markdown File" and "Open Markdown File…". Add both.
- Assign shortcuts: `⌘N` for New Markdown, `⌘O` for Open Markdown. (Verified unbound: pane creation uses `⌘T`/`⌘⇧T`.)
- Update `CommandPalette.swift:134-139` entries to display the new shortcuts.
- Edit: `main.swift` (menu construction), `CommandPalette.swift`.

**2.2 Split commands in View menu**
- The View menu should have "Split Right" (`⌘D`) and "Split Down" (`⌘⇧D`) so they're discoverable from the menu bar, not only the right-click context menu.
- Bindings already exist in `main.swift:278-291`; this just adds menu surface.

**2.3 Pane navigation in palette**
- Arrow shortcuts (`⌘←/↑/→/↓`) for moving focus between panes work but show empty in the Command Palette listing (`main.swift:305-312`).
- Populate the palette entries with their bindings so they appear in fuzzy search.

**2.4 Promoted agent activity dot**
- The current red ✱ indicator is buried inside the tab label string in `TabBarView.swift:407-423`.
- Replace with a discrete colored dot rendered next to the tab title (like Mail's unread dot). Color: `Theme.accent` when running, hidden when idle.
- Animate fade in/out on state change (200ms).

### Theme 3 — Visual consistency

**3.1 Modal pattern unification**
- `PreferencesView.swift:39-56` opens as a separate `NSPanel`. `CommandPalette` and `GlobalFindView` use a backdrop overlay on the main window. Pick one pattern and migrate the odd one out.
- **Decision:** migrate Preferences to the backdrop-overlay pattern. Reasons: matches the rest of Flock, no separate-window state to manage, looks more native to the app, click-outside-to-dismiss is consistent.
- Edit: `PreferencesView.swift` — convert from `NSPanel` to a `BackdropOverlayView`-style host inside the main window. Reuse the same backdrop infrastructure as `CommandPalette`.

**3.2 Tab bar opacity**
- `TabBarView.swift:87` hardcodes `withAlphaComponent(0.88)` for the tab bar background. Every other overlay uses `Theme.surface.withAlphaComponent(0.97)`.
- Switch the tab bar to the same value for visual consistency. Verify across all 7 themes.

**3.3 `accentSubtle` token adoption**
- `Theme.accentSubtle` is defined consistently across all 7 themes (each at `alpha: 0x26`) but `MemoryView.swift` and `AgentSidebarView.swift` invent their own hover colors with `withAlphaComponent(0.5)`.
- Replace ad-hoc hover colors with `Theme.accentSubtle` so themes actually drive hover state.

### Theme 4 — Tactical improvements

**4.1 Live font-size preview**
- `PreferencesView.swift:152-169` updates a "13 pt" label live but doesn't push the new size to open terminals until preference is saved.
- On slider change, broadcast a `NotificationCenter` event (`.flockFontSizeChanged` or similar) that `TerminalPane`/`FlockTerminalView` listen for and apply immediately, mirroring how theme switching already works.

**4.2 Terminology rename: "Add Agent" → "New Task"**
- `AgentSidebarView.swift:441` button label is "Add Agent". The model is: agents are runners (we cap them at 3 parallel), tasks are units of work (the kanban cards).
- Rename button to "New Task". Audit nearby labels for the same confusion and rename if found.

**4.3 Long-running command warning**
- `StatusBarView.swift:134-149` shows "Running: 45s" forever in the same style.
- Past 5 minutes, switch the elapsed-time label color from `Theme.textSecondary` to `Theme.accent`. Past 15 minutes, additionally bold it. Helps catch hung processes without being a notification.
- No new color tokens needed; reuses existing theme values so each theme picks its own emphasis tone.

## Out of scope (flagged for separate work)

- **TabBarView refactor.** 887 lines mixing tab rendering, drag-reorder, context menus, and accent pickers. Real but separate.
- **CommandPalette refactor.** 673 lines mixing action definitions, fuzzy search, backdrop, card UI. Same.
- **First-run preferences walkthrough.** Could come later if welcome card alone proves insufficient.
- **Tooltips on every preference.** Some have hints already; comprehensive tooltips are a separate documentation pass.

## Files touched (estimated)

- `WelcomeCard.swift` — new
- `PixelBirdView.swift` — new (reusable pixel bird, ported from marketing site)
- `main.swift` — menu items, welcome wiring
- `Settings.swift` — `hasSeenWelcome` flag
- `AgentSidebarView.swift` — empty state, button rename, hover token
- `MemoryView.swift` — empty state hint, hover token
- `StatusBarView.swift` — first-launch hint, long-run warning
- `TabBarView.swift` — opacity unify, activity dot
- `PreferencesView.swift` — backdrop migration, live font preview wiring
- `CommandPalette.swift` — markdown shortcut display, arrow nav display
- `TerminalPane.swift` / `FlockTerminalView.swift` — font-size notification listener

Roughly 10 files, all surgical edits except `WelcomeCard.swift` (new) and `PreferencesView.swift` (modal pattern migration is the largest single change).

## Testing approach

- Manual smoke test of each item against all 7 themes.
- Specifically verify the welcome card on a fresh launch by deleting `~/Library/Preferences/com.divagation.flock.plist` (or whatever the bundle ID resolves to) before testing.
- Visual diff check on tab bar across themes for the opacity unification.

## Risk

Low. No threading changes, no networking, no new dependencies. The riskiest single item is the Preferences modal-pattern migration (3.1) since it touches a frequently-used surface; everything else is additive or surface-level.
