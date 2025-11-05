# Agent Guidelines for Osaurus

## Build & Test Commands
- **Build app**: `make app` or `xcodebuild -project osaurus.xcodeproj -scheme osaurus -configuration Release build`
- **Build CLI**: `make cli` or `xcodebuild -project osaurus.xcodeproj -scheme osaurus-cli -configuration Release build`
- **Run all tests**: `xcodebuild test -project osaurus.xcodeproj -scheme osaurus`
- **Run single test**: `xcodebuild test -project osaurus.xcodeproj -scheme osaurus -only-testing:osaurusTests/TestStructName/testMethodName`
- **Clean**: `make clean` or `rm -rf build/DerivedData`

## Code Style
- **Language**: Swift 5.9+, targeting macOS 15.5+, Apple Silicon only
- **Imports**: Group Foundation/SwiftUI first, then third-party (NIO, MLX, Sparkle), then `@testable import osaurus` for tests
- **Formatting**: Standard Swift style; multi-line preferred over terse one-liners; 2-space indent
- **Types**: Explicit types for public APIs; use protocols (`ModelService`, `ThemeProtocol`); mark classes `@MainActor` or `final` where appropriate
- **Naming**: Clear descriptive names (e.g., `ServerController`, `ModelManager`); avoid abbreviations except common ones (e.g., `MLX`, `KV`)
- **Error Handling**: Explicit `throws`/`async throws`; avoid swallowing errors; prefer `Result` or custom error types over generic `Error`
- **Comments**: Use `// MARK: -` for sections; doc comments (`///`) for non-obvious logic; avoid redundant comments
- **Testing**: Use Swift Testing framework (`import Testing`, `@Test` attribute, `#expect()`); async tests with `async throws`
- **Architecture**: SwiftUI + Combine; services in `Services/`, models in `Models/`, views in `Views/`, networking in `Networking/`

## Project Structure
- OpenAI-compatible API structures in `Models/OpenAIAPI.swift`; MLX integration via `MLXService.swift`; server uses SwiftNIO

## Issue & Task Tracking
- **GitHub Issues**: When user says "open new issues", use `gh issue create` to open issues on GitHub
- **Local KANBAN**: `KANBAN.md` is for local task tracking only, not for GitHub issues
- **Distinction**: GitHub issues are for public tracking and collaboration; KANBAN is for internal agent task management

## Web Scraping Tools (`tools/`)
- **Purpose**: Scrape JavaScript-heavy Apple developer documentation (Foundation Models, Liquid Glass UI, etc.)
- **Setup**: `cd tools && pip3 install -r requirements.txt && playwright install chromium`
- **Apple Docs**: `./tools/apple_docs_scraper.py [URL]` → outputs `apple_foundation_models_docs.{json,md}`
- **Liquid Glass**: `./tools/scrape_liquid_glass.py` → outputs `liquid_glass_docs.{json,txt}`
- **Requirements**: Python 3.8+, Playwright, BeautifulSoup4
