# AGENT instructions

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**livlog** is an app that helps users track and rate their experiences with movies, books, games, and other activities. The app features AI-powered smart entry with automatic metadata and image fetching via LLM.

Project consist of:
- iOS App: SwiftUI-based iOS application (`./livloios`)
- Backend: Golang-based backend service (`./backend`)

## Sub-agent routing rules

**Parallel dispatch** (ALL conditions met):
- 3+ unrelated tasks or independent domains
- No shared state between tasks
- Clear file boundaries with no overlap

**Sequential dispatch** (ANY condition):
- Tasks have dependencies (B needs A's output)
- Shared files or state (merge conflict risk)
- Unclear scope requiring analysis first

**Direct execution** (no subagent needed):
- Simple, bounded task affecting a single component
- Quick fixes under ~20 lines
- Tasks where spawning a subagent adds overhead without value

**Routing by intent**:
- New feature request / bug → system-analyst first, then software-engineer
- Already-scoped task with clear spec → software-engineer directly
- Refactoring → code-reviewer for analysis, then software-engineer

### Key concepts

* Entry — the main unit for storing info in the app. Users add entries to remember which movies they’ve watched or which books they want to read.
* Collection — entries are grouped into collections. These are folders you can share with friends.

#### Screens

* ContentView — the main screen for browsing the entries collection. From here you can create new entries, view them, delete them, and use filters.
* AddEntryView — the entry creation screen, where you can choose the type and use the AI assistant.

## Agreements

### Definition of Done

**MANDATORY**: After completing ANY code changes, you MUST run the following checks in order:

1. **Linting**: Call the linter and fix all errors and warnings
2. **Build**: Call the builder and ensure project compiles
3. **Tests**: Run all tests and verify all of these pass
4. **Documentation**: All documentation must be written in English in stored in `./docs/`

**Do NOT consider a task complete until all three checks pass successfully.** If any check fails, fix the issues before proceeding or asking for further instructions.

### Code Standards

#### Swift / SwiftUI
- Use `@Environment`, `@State`, `@Binding` appropriately — prefer environment over prop drilling
- Prefer `async/await` over completion handlers
- Use `guard let` / `if let` for optionals — no force-unwrapping
- Keep Views small — extract subviews when body exceeds ~30 lines
- Follow modifier order: layout → styling → behavior

### Go / Backend
- Return errors — never panic in library code
- Use context propagation for cancellation
- Keep handler functions thin — delegate to service layer

## Project build and verify commands

### iOS project commands

```bash
# Build the project
xcodebuild -scheme livlogios -configuration Debug build

# Run tests
xcodebuild test -scheme livlogios -destination 'platform=iOS Simulator,name=iPhone 15'

# Run unit tests only
xcodebuild test -scheme livlogios -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:livlogiosTests

# Run UI tests only
xcodebuild test -scheme livlogios -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:livlogiosUITests

# Clean build artifacts
xcodebuild clean -scheme livlogios
```

### Go / Backend project commands

```bash
# Build the project
just --justfile ./backend/Justfile --working-directory ./backend build

# Run tests
just --justfile ./backend/Justfile --working-directory ./backend lint

# Run unit tests only
just --justfile ./backend/Justfile --working-directory ./backend test
```
