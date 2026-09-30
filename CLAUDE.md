# LLM Chat Tester

A native SwiftUI Mac app for learning how to test chatbots, using local LLMs through Ollama. It ships to testers with Sparkle auto-updates.

## Commands

| Task | Command |
|---|---|
| Build core | `cd macos/Packages/TesterCore && swift build` |
| Test core + content check (~20s) | `cd macos/Packages/TesterCore && swift test` |
| Generate Xcode project | `cd macos && xcodegen generate` |
| UI tests (~8 min, takes over the mouse) | `cd macos && xcodebuild test -project LLMChatTester.xcodeproj -scheme LLMChatTester -derivedDataPath build/DerivedData` |
| Release | `/release` on an up-to-date `main` |

## Layout

- `macos/App/`: SwiftUI views, view models and the Sparkle updater
- `macos/Packages/TesterCore/`: all logic, with no UI (Ollama client, Claude judge, bots, test cases, reports, Learn loader)
- `macos/Packages/TesterCore/Sources/TesterCore/LearnContent/`: the Learn course as JSON and Markdown
- `macos/UITests/`: XCUITest suites
- `macos/scripts/`: release tooling, run by `.github/workflows/release.yml` on `v*` tags

## Invariants

- `macos/project.yml` is the source of truth. The `.xcodeproj` is generated and gitignored, so re-run `xcodegen generate` after adding or removing Swift files.
- Put logic in TesterCore so `swift test` covers it. `macos/App/` only builds through Xcode.
- Don't run the UI tests unless asked.
- Only `macos/` ships in the app. The release version comes from the git tag, so don't bump `MARKETING_VERSION` by hand.

## Detail lives elsewhere

- Learn content format: `.claude/rules/learn-content.md` and `macos/CONTENT_GUIDE.md`
- Testing: `.claude/rules/testing.md`
- Release process: `.claude/skills/release/SKILL.md` and `README.md`
