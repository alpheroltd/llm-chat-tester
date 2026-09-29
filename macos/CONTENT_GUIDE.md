# Editing the Learn tab

The Learn tab's course is plain text files, so your team can write and edit lessons without touching Swift.
Everything lives in:

```
macos/Packages/TesterCore/Sources/TesterCore/LearnContent/
  course.json            the modules, and which lessons are in each, in order
  lessons/<id>.json      a lesson's details: title, key terms, practice links, quiz
  lessons/<id>.md        the lesson's reading, in Markdown
  glossary.json          the glossary
  cheatsheets/index.json the cheat sheets list
  cheatsheets/<id>.md    each cheat sheet, in Markdown
  images/                optional pictures used in lessons
```

After any change, **run the content check** (it takes about 20 seconds):

```sh
cd macos/Packages/TesterCore && swift test
```

If something is wrong (a typo in an id, a quiz answer that points nowhere, a missing file), the test tells you the file and what to fix.
Then build and open the app to read your lesson as testers will see it.

## Add a lesson

1. Pick a short id with lowercase letters and dashes, e.g. `voice-and-tone`.
2. Create `lessons/voice-and-tone.json`:

```json
{
  "id": "voice-and-tone",
  "title": "Voice and tone",
  "summary": "One sentence shown under the title.",
  "minutes": 6,
  "status": "draft",
  "keyTerms": ["persona", "system-prompt"],
  "practice": [
    { "kind": "mission", "id": "persona", "label": "Mission: Stay in character" }
  ],
  "quiz": [
    {
      "question": "Which of these is a tone bug?",
      "options": ["A correct but sarcastic reply", "A correct, friendly reply"],
      "answer": 0,
      "explanation": "Correct facts delivered rudely still embarrass the client's brand."
    }
  ]
}
```

3. Create `lessons/voice-and-tone.md` with the reading (see **Writing the reading** below).
4. Add `"voice-and-tone"` to a module's `lessons` list in `course.json`. The order there is the order learners see.
5. Run the content check.

### Lesson fields

| Field | What it is |
|---|---|
| `id` | Must match the file names. |
| `minutes` | Rough reading time, shown to learners. |
| `status` | `"draft"` shows a "Draft content" banner and a DRAFT tag; change it to `"reviewed"` once a QA lead has signed it off. |
| `keyTerms` | Glossary ids shown as clickable terms at the end of the lesson. Each one must exist in `glossary.json`. |
| `practice` | "Practice this" buttons. See the table below. |
| `quiz` | Optional. `answer` is the **position** of the correct option, **counting from 0** (0 = first option, 1 = second, and so on). |

### Practice links

| `kind` | `id` | Opens |
|---|---|---|
| `mission` | a mission id, e.g. `hallucination` | Chat, in Missions mode, with that mission selected |
| `bot` | `shopbot-1` … `shopbot-5` | Chat, in Target bots mode, at that level |
| `judgeExercise` | an exercise id, e.g. `confident-wrong` | LLM-as-a-judge, with that exercise loaded |
| `testCases` | (none) | the Test cases tab |
| `judge` | (none) | the LLM-as-a-judge tab |
| `freeChat` | (none) | Chat, in Free chat mode |

Mission ids are in `Resources/missions.json` and exercise ids in `Resources/judge-exercises.json`.
The `label` is the button text, e.g. "Mission: Catch it making things up".

## Writing the reading

Lesson and cheat-sheet text is Markdown. The app supports:

```markdown
## A section heading
### A smaller heading

A paragraph with **bold**, *italic*, `code` and [a link](https://example.com).

- a bullet
- another bullet

1. a numbered step
2. another step

> **Tip:** shown as a green box.
> **Note:** a blue box. **Warning:** a red box. **Draft:** an orange box.

![Description for screen readers](images/diagram.png)

---   (a divider line)
```

Don't repeat the lesson title as a `#` heading: the app shows the title already. Start with a short intro paragraph, then use `##` sections.

## Glossary

Each entry in `glossary.json`:

```json
{ "id": "flaky-test", "term": "Flaky test", "definition": "One or two sentences.", "seeAlso": ["assertion"] }
```

`seeAlso` lists other glossary ids. The content check makes sure they exist.

## Converting your team's material

For material in Google Docs or Slides, Claude can read it and draft the lessons and quizzes in this format. Then:

1. Review each lesson in the app. Check facts, tone and fit with how your team works.
2. Change `"status"` to `"reviewed"`.
3. Release a new version (see the README). Testers get the new content through the automatic update.
