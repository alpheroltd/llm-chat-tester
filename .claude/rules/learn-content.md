---
description: Editing the Learn tab's course content
paths:
  - "macos/Packages/TesterCore/Sources/TesterCore/LearnContent/**"
---

# Learn content

- The format is in `macos/CONTENT_GUIDE.md`. Read it before you add or restructure a lesson, quiz, glossary entry or cheat sheet.
- A lesson's `id` must match its `lessons/<id>.json` and `lessons/<id>.md` file names, and it must be listed in `course.json`.
- New or rewritten lessons stay `"status": "draft"`. Only a QA lead sets `"reviewed"`.
- Don't start a lesson's Markdown with a `#` title, because the app already shows the title.
- After any change, run the content check: `cd macos/Packages/TesterCore && swift test`.
