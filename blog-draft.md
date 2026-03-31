---
title: "A Flock of Claudes"
date: "2026-03-29"
description: "I built a native macOS app to run a whole flock of Claude agents at once and it's pretty wild to watch"
tags: ["tools", "ai", "process", "flock"]
published: false
---

## the itch

I was running like 4 Claude Code sessions in separate terminal tabs and it was annoying.  Switching back and forth, losing track of which one was doing what, no way to see them all at the same time.  So I built an app for it.  Native Swift, no Electron, no web views pretending to be a desktop app.  Just AppKit and a terminal library called SwiftTerm and like 10,000 lines of code that turned into something I actually use every single day now

The whole thing started cause I wanted to see all my agents at once.  That's it.  That was the whole motivation.  Cmd+T a few times and suddenly you've got four Claudes working on four different things and you're just watching them go.  One's thinking, one's editing files, one's running commands, and the last one is waiting for you to say something.  It shows you the state of each one in real time so you always know what's happening

## the native thing

I'm not gonna sit here and pretend I had some grand philosophy about native apps.  I just wanted it to be fast.  Electron apps have that half-second delay on everything and I use this thing for hours a day so that was never gonna work.  Swift on macOS means it launches instantly, the terminal rendering is smooth, it uses basically no memory, and it just feels like it belongs on the machine.  It's fast because it's not pretending to be a website

The only real dependency is SwiftTerm for the terminal emulation.  Everything else is just AppKit.  The themes, the command palette, the split panes, the kanban board, all of it.  37 Swift files

## agent mode

This is the thing I'm most hyped about honestly.  You hit Cmd+Shift+A and flock turns into a task manager.  You throw tasks at a queue, they show up on a kanban board, and agents pick them up and run them in parallel.  Backlog, in progress, done, failed.  Each agent gets a live timeline showing every single action in real time.  What it's reading, what it's writing, what commands it's running.  You can watch three agents building three different features at the same time and it's kind of mesmerizing

You can send follow-up messages to running agents too.  Or resume a finished conversation later.  And it tracks the cost per task so you know exactly what you're spending

## the small stuff

I spent way too much time on the themes.  7 of them, each with a full 16-color ANSI palette so the terminal colors actually look good and match the rest of the UI.  Flock (warm cream), Claude (terracotta), Midnight, Ember, Vesper, Overcast, Linen.  You can switch between them from the command palette and the whole app repaints instantly

There's also Wren compression built in which is this LoRA model I trained that compresses your prompts 50-80% before sending them.  Saves tokens.  Toggle it on in preferences and forget about it

Global hotkey, broadcast mode where you type once and every pane hears it, find across all panes at once, session restore, memory system that syncs context to a file so Claude remembers things across sessions.  Cmd+K command palette if you've used Raycast or Arc you already know how it works

## free and open source

Flock is free.  Signed, notarized, just download it and go.  The source is all on GitHub if you want to build it yourself.  `git clone`, `./build.sh`, done

I don't know where this goes from here.  I've been using it to run my other projects and it's gotten to the point where I can't really go back to regular terminal tabs.  Every time I open iTerm now it feels wrong lol
