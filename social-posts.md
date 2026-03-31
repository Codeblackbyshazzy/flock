# Flock Launch Posts -- April 1, 2026

---

## 1. Show HN

**Title:** Show HN: Flock -- macOS terminal multiplexer for parallel Claude Code sessions (Swift/AppKit)

**Body:**

i built flock because running multiple claude code sessions in tmux or iterm2 tabs was getting painful. you can't see activity state, token usage, or which agent is stuck waiting for input without clicking into each one. so i built a purpose-built multiplexer for it.

it's a native macOS app written in swift/appkit. no electron. ~15k lines of swift. some of the more interesting technical bits:

- terminal rendering uses SwiftTerm (libvterm-based terminal emulator in swift)
- claude code's --output-format stream-json gets parsed in real time for structured status/activity data (custom stream-json parser that handles partial JSON chunks)
- prompt compression via wren, a small LoRA fine-tuned 1.5B model that rewrites prompts to use fewer tokens before sending. saves roughly 40-60% on input tokens
- agent mode runs up to 3 parallel claude code processes with --resume for follow-up messages, feeding results into a kanban board UI

other stuff: 7 themes, command palette, broadcast mode (type once into all panes), session restore, global hotkey, usage tracking against your anthropic plan limits.

free, MIT licensed, signed and notarized.

landing page: https://divagation.github.io/flock/
github: https://github.com/Divagation/flock

happy to answer questions about the architecture or any of the gnarlier swift/appkit problems (tab dragging with event-tracking loops, CALayer rendering order, etc).

---

## 2. X/Twitter

> built a native macos app for running parallel claude code sessions. split panes, agent kanban, prompt compression, 7 themes. swift/appkit, no electron. free and open source. launching on product hunt tomorrow https://divagation.github.io/flock/

<!-- 271 chars -->

---

## 3. Reddit r/ClaudeAI

**Title:** i built a free macOS app for running multiple Claude Code sessions side by side

**Body:**

if you run claude code a lot you've probably hit the same wall i did. you want one session building a feature, another writing tests, another refactoring something else. so you open three terminal tabs and spend half your time clicking between them trying to remember which one is doing what.

tmux works but you can't see token usage, activity state, or which session is waiting for input at a glance. iterm2 split panes are better but still just dumb terminals with no awareness of what claude code is doing inside them.

so i built flock. it's a macOS app specifically designed for running multiple claude code sessions in parallel. each pane shows real-time activity indicators and token cost. there's a command palette for fast switching, broadcast mode to type into all panes at once, and session restore so you pick up where you left off after a restart.

the feature i use most is agent mode. you throw a list of tasks at it and it spins up parallel claude code sessions as workers, tracking progress on a kanban board. each agent gets its own cost tracking.

it also has built-in prompt compression via wren (a small LoRA model) that cuts input tokens by 40-60%, which helps if you're watching your usage limits.

it's free, open source (MIT), native swift. no electron. signed and notarized so macos doesn't complain.

github: https://github.com/Divagation/flock
landing page: https://divagation.github.io/flock/
launching on product hunt tomorrow: will drop the link in comments when it's live

curious what other workflows people are running with claude code that would benefit from parallelism.
