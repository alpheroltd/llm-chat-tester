---
name: release
description: Release the current head of main as a new version of the LLM Chat Tester Mac app. Checks main is clean and pushed, drafts the CHANGELOG section from what changed since the last tag, then (after approval) commits it, tags, pushes and watches the release workflow until the GitHub release and Sparkle appcast are live.
argument-hint: "[version]"
disable-model-invocation: true
---

# Release LLM Chat Tester

Releases `HEAD` of `main` on `alpheroltd/llm-chat-tester`. Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`, which tests, builds, signs the update with the `SPARKLE_PRIVATE_KEY` secret and publishes `LLM-Chat-Tester.zip` and `appcast.xml` as a GitHub Release. The `## X.Y.Z` section of `macos/CHANGELOG.md` is both the release notes and what testers see in the update window.

Stop and report at the first failed check. Don't work around it.

## 1. Preflight

1. `git fetch origin --tags`.
2. The current branch is `main`, `git status --porcelain` is empty, and `git rev-parse HEAD` equals `git rev-parse origin/main`. If local is ahead, ask whether to push first.
3. `gh secret list -R alpheroltd/llm-chat-tester` lists `SPARKLE_PRIVATE_KEY`. Without it the workflow fails after the tag is pushed.

## 2. What changed

1. Last release: `git describe --tags --abbrev=0 --match 'v*'`.
2. If `git rev-list LAST..HEAD --count` is 0, stop: nothing to release.
3. Read `git log --no-merges --format='%h %s%n%b' LAST..HEAD -- macos` and `git diff --stat LAST..HEAD -- macos`, and the diff itself wherever a commit message doesn't make the user-visible effect clear. Only `macos/` ships in the app; changes to the web version (`public/`, `server/`, `server.js`) don't belong in the notes.

## 3. Draft the version and notes

**Version** (semver, pre-1.0): new features bump the minor version (`0.2.0` → `0.3.0`), fixes only bump the patch (`0.2.0` → `0.2.1`). A version passed as the argument wins. It must be greater than the last tag.

**Notes:** bullets for what a tester would notice in the app since the last release, and nothing else.

- One sentence per bullet: what changed and where it shows up. Bold the feature name as the existing sections do.
- Leave out refactors, tests, CI, tooling and docs unless they change something for testers.
- Only claim what the diff shows. UK English, same tone as the existing CHANGELOG, no marketing words.
- If nothing user-facing changed, say so and ask whether to release anyway.

Show the version and the exact section with AskUserQuestion: release as shown, change the version, or edit the notes. **Their approval is the explicit instruction to commit, tag and push for this run.** Without it, don't commit.

## 4. Commit, tag, push

1. Insert the section below the intro paragraph of `macos/CHANGELOG.md`, above the previous `## ` section: `## X.Y.Z`, a blank line, then the bullets.
2. `git add macos/CHANGELOG.md && git commit -m "Release X.Y.Z."`. Commit only that file.
3. `git tag -a vX.Y.Z -m "LLM Chat Tester X.Y.Z"`
4. `git push --atomic origin main vX.Y.Z`

## 5. Watch and verify

1. Find the run: `gh run list -R alpheroltd/llm-chat-tester --workflow Release --branch vX.Y.Z --json databaseId,status` (retry for up to a minute), then `gh run watch <id> -R alpheroltd/llm-chat-tester --exit-status`.
2. If it fails, show `gh run view <id> -R alpheroltd/llm-chat-tester --log-failed | tail -60` and diagnose. Nothing is published unless `gh release create` ran, so the usual fix is to fix `main`, delete the tag (`git push origin :refs/tags/vX.Y.Z && git tag -d vX.Y.Z`) and tag again. Ask before deleting a tag, and never delete one with a published release: fix forward with a new patch version.
3. Check the result:
   - `gh release view vX.Y.Z -R alpheroltd/llm-chat-tester --json isDraft,isPrerelease,assets`: not a draft or prerelease; assets are `LLM-Chat-Tester.zip` and `appcast.xml`.
   - `curl -fsL https://github.com/alpheroltd/llm-chat-tester/releases/latest/download/appcast.xml | grep -o '<sparkle:shortVersionString>[^<]*' | head -1` shows `X.Y.Z`. This is the feed installed apps check.
4. Report the release URL and the notes published.
