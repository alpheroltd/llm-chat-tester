---
description: Test conventions for TesterCore and the UI tests
paths:
  - "macos/Packages/TesterCore/Tests/**"
  - "macos/UITests/**"
---

# Testing

- TesterCore tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`), not XCTest. Run them with `cd macos/Packages/TesterCore && swift test`, or a single suite with `--filter <SuiteName>`.
- Fixture course files live in `Tests/TesterCoreTests/Fixtures/` and are copied as a folder resource (see `Package.swift`).
- `macos/UITests/` is XCUITest. It runs against the real app and a local Ollama, launch arguments pin the settings, and it takes about 8 minutes and takes over the mouse. Don't run it unless asked.
- `Fixtures/saved-data/` holds files exactly as a shipped version wrote them to testers' Macs. Never edit or regenerate one. When a saved format changes, add a new fixture beside it and keep the old ones decoding (see `CompatibilityTests.swift`).
- `StableIDTests` lists the ids that progress is saved against. Change a list only when the rename is deliberate.
- `SuiteRunnerTests` stubs Ollama with `StubOllama` (a `URLProtocol`). Use it rather than a live server for runner behaviour.
