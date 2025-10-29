# Repository Guidelines

## Project Structure & Module Organization
- `Package.swift` publishes the `USDConverter` library and `usdconv` CLI executable; update products here when exposing new targets.
- `Sources/USDConverter` contains the reusable conversion engine plus helper modules for Model/MTL parsing—keep public API surface in `USDConverter.swift`.
- `Sources/USDConverterCLI` wraps the library with a Swift ArgumentParser command; mirror new options here after API changes.
- `Sources/USDConverter/ModelFile` implements material deduplication and texture export helpers; add new semantics alongside existing utilities.
- `Tests/USDConverterTests` holds XCTest coverage; store reusable sample fixtures in nested folders by format.

## Build, Test, and Development Commands
- `swift build` compiles both the library and CLI; use `-c release` for shipping binaries.
- `swift run usdconv sample.usdz --png` quickly validates CLI usage against fixture assets.
- `swift test` executes XCTest coverage; add targeted regression tests before shipping parser or texture changes.
- If dependency resolution fails offline, run `swift package resolve` once online to cache packages locally.

## Coding Style & Naming Conventions
- Match the existing Swift style: tab indentation, braces on the same line, `PascalCase` for types, `camelCase` for functions and properties.
- Keep parsing, file-system helpers, and texture transforms separated; prefer focused extensions over sprawling utility types.
- Use `ArgumentParser` idioms (`ParsableCommand`, short+long flags) for CLI surface changes.
- Brief inline comments are welcome near non-obvious Model I/O quirks; avoid verbose block commentary.

## Testing Guidelines
- Tests live in `Tests/USDConverterTests`; group fixtures under `Tests/Fixtures/<Format>` for clarity.
- Name methods `testFeatureExpectation` and focus on deterministic conversions (OBJ contents, texture manifests).
- Run `swift test` locally before opening a PR; consider adding fixture-based integration tests for new CLI options.
- Add at least one regression test when touching conversion logic, texture export, or argument parsing paths.

## Commit & Pull Request Guidelines
- Follow repo precedent: short (≤72 char) subject lines in Title Case, present tense (`Fix Material Deduplication`).
- Reference related issues in the message body and summarize user-facing impact plus validation steps taken.
- PRs should link back to the motivating issue, outline CLI usage changes, and attach before/after snippets or sample outputs.
- Include build or manual run notes so reviewers can reproduce validation quickly.
