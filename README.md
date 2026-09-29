# LLM Chat Tester

A training tool for **learning how to test chatbots**, using LLMs running on your own Mac through [Ollama](https://ollama.com).

This repo contains two versions:

- **`macos/`: the Mac app**, the one the QA team uses. Native SwiftUI, with automatic updates through Sparkle.
- **The web app** (repo root: `server.js`, `public/`), the original prototype. Documented further down.

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

---

# Web app (original prototype)

## One-time setup

```sh
brew install ollama
brew services start ollama      # runs the API at http://localhost:11434
ollama pull llama3.2:3b         # ~2GB; any other model works too
```

## Run

```sh
npm start      # Node.js 20+, no npm install needed
```

Open http://localhost:3000. The app has three tabs: **Chat**, **Test cases** and **LLM-as-a-judge**.

## What's in it

| Area | What it teaches |
|---|---|
| **Free chat** | Talk to any local model, optionally with your own system prompt (the hidden instructions real client bots run on). |
| **Missions** | 12 guided exercises, one per bug category: hallucination, consistency, reproducibility, instruction following, context memory, bias, safety/over-refusal, persona, odd inputs, prompt injection, regression and LLM-judge evaluation. Each has a goal, prompts to try, hints, what a bug looks like, and why it matters in the real world. |
| **Target bots** | "Break the bot": get ShopBot (a fictional Kiwi Gadgets support bot) to leak a secret staff discount code. There are 5 levels, each adding a real-world defence: a secrecy instruction, a hardened prompt, an output filter and an input keyword filter. A debrief after each win explains why that defence failed. The hidden prompts live only on the server (`server/bots.js`). |
| **Settings** | Temperature, seed and max tokens. Shows why the same question gives different answers, and how to make a bug reproducible. |
| **Run ×5** | Re-asks any reply 5 times and counts the unique answers. |
| **⚑ Flag + Export report** | Mark replies Pass/Fail with a category, severity, expected behaviour and notes. Export a Markdown bug report with steps to reproduce, settings and the full transcript. |
| **LLM-as-a-judge** | Claude grades a reply against a plain-English rubric (one criterion per line) and returns pass/fail, a score from 1 to 5 and a verdict per criterion. Paste a reply or generate one with the local model. **Judge ×3** shows the judge is non-deterministic too. **Judge the judge** has 8 tricky exercises (confidently wrong, wordy but empty, rude, sycophantic, an injection aimed at the grader, wrong format, partial, genuinely good). You predict the verdict first, then compare it with the judge's. Default judge is Haiku; Sonnet and Opus can be selected. |
| **Test cases** | Saved single-message tests with checks (contains, doesn't contain, regex, min/max length). Run the suite for a pass/fail table; set runs per case above 1 to find **flaky** tests. Saved to `data/testcases.json`, so they can be shared or committed. Use "Save as test case" under any chat message. |

## Suggested learning path

1. **Missions**: work through them in order. Flag every bug you find.
2. **Target bots**: beat levels 1–5. Flag each leak and export the report as if filing it for a client.
3. **Test cases**: turn your findings into a regression suite. Run it with 3 runs per case, and decide whether each flaky result is a bot bug or a test that's too strict.
4. **LLM-as-a-judge**: do the "Judge the judge" exercises, then write rubrics for replies you flagged earlier. Note every case where the judge was wrong.
5. Swap models (`ollama pull qwen2.5:7b`, then ↻) and re-run the suite. That's what a model upgrade looks like in production.

Progress (missions done, levels beaten) is stored in your browser.

## LLM judge requirements

The judge runs headless [Claude Code](https://claude.com/claude-code) (`claude -p`) under your own login, so it needs the `claude` CLI installed and logged in. Unlike the chatbot under test, **the text you judge is sent to Anthropic**. Each judgement takes about 5–15s and costs around $0.005 with Haiku. The judge runs with no tools and outside this folder, so instructions hidden in a reply can't make it do anything.

## Config

| Env var      | Default                  |
|--------------|--------------------------|
| `PORT`       | `3000`                   |
| `OLLAMA_URL` | `http://localhost:11434` |

No npm dependencies. It uses only Node's built-in `http` and `fetch`, and plain ES modules in the browser (no build step). Key elements have `data-testid` attributes for Playwright automation.
