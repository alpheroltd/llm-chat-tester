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
