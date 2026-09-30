# LLM Chat Tester

A training tool for **learning how to test chatbots**, using LLMs running on your own Mac through [Ollama](https://ollama.com).

It's a native SwiftUI Mac app (in `macos/`), with automatic updates through Sparkle.

## Install the Mac app (testers)

Download **LLM-Chat-Tester.zip** from the [latest release](https://github.com/alpheroltd/llm-chat-tester/releases/latest) and follow [`macos/INSTALL.md`](macos/INSTALL.md). No cloning or Xcode needed. Updates arrive automatically.

## Develop the Mac app

**One-time setup:** macOS 15+, Xcode (open it once, or run `xcodebuild -runFirstLaunch`), then:

```sh
brew install xcodegen                               # generates the Xcode project from macos/project.yml
brew install ollama && brew services start ollama   # the local chatbot
ollama pull llama3.2:3b
```

Optional: install [Claude Code](https://claude.com/claude-code) and run `claude` once to log in (used by the LLM judge).

**Run:**

```sh
cd macos
xcodegen generate                  # re-run after editing project.yml or adding/removing Swift files
open LLMChatTester.xcodeproj       # then ⌘R
```

The `.xcodeproj` isn't committed; it's generated. No Apple Developer account is needed: builds are signed ad-hoc and updates are off in local builds.

**Test:**

```sh
(cd macos/Packages/TesterCore && swift test)   # core logic and content checks, about 20s
cd macos && xcodebuild test -project LLMChatTester.xcodeproj -scheme LLMChatTester -derivedDataPath build/DerivedData
                                                # UI tests: about 8 minutes, and they take over the mouse, so don't use the Mac meanwhile
```

**Where things are:**

| Path | What |
|---|---|
| `macos/App/` | SwiftUI app: views, view models, Sparkle updater |
| `macos/Packages/TesterCore/` | All logic, no UI: Ollama client, Claude judge, target bots, test cases, reports, Learn course loader |
| `macos/Packages/TesterCore/Sources/TesterCore/LearnContent/` | The Learn tab's lessons, quizzes and glossary (JSON + Markdown). See [`macos/CONTENT_GUIDE.md`](macos/CONTENT_GUIDE.md) |
| `macos/UITests/` | XCUITest suites |
| `macos/scripts/` | Release tooling |

## Release a new version of the Mac app

Releases are built and signed by GitHub Actions. In Claude Code, run **`/release`** on an up-to-date `main`: it drafts the `## <version>` section of `macos/CHANGELOG.md` from the changes since the last tag, and once you approve, commits it, pushes a `v<version>` tag and watches the build.

By hand: add the CHANGELOG section, commit and push it, then `git tag -a v0.2.1 -m "LLM Chat Tester 0.2.1" && git push origin v0.2.1`.

The tag runs `.github/workflows/release.yml`, which signs the update with the `SPARKLE_PRIVATE_KEY` repository secret (backed up in 1Password) and runs `macos/scripts/release.sh`. The version comes from the tag and the build number from the published feed, so nothing in `project.yml` needs bumping. To try a build locally without publishing: `cd macos && SPARKLE_PRIVATE_KEY=… DRY_RUN=1 RELEASES_REPO=alpheroltd/llm-chat-tester scripts/release.sh 0.2.1`.

The workflow creates a GitHub Release with the app (`LLM-Chat-Tester.zip`) and the update feed (`appcast.xml`, listing every version) attached. Installed apps read the feed from `https://github.com/alpheroltd/llm-chat-tester/releases/latest/download/appcast.xml`, so they pick the update up within a day, or straight away via **Check for Updates…** No GitHub Pages needed. Never delete old releases: the feed links to their zips.
