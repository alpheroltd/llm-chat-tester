# Changelog

Each `## <version>` section becomes the release notes testers see in the update window.

## 0.2.0

- **Learn tab:** a course on testing LLM chatbots in 9 modules, with lessons, quizzes, a glossary and a test checklist. Each lesson's **Practice this** buttons open the matching mission, bot level or judge exercise. (Sample content: your team's material will replace it.)
- **Test cases:** save single-message tests with checks (contains, doesn't contain, regex, min/max length), run the suite with the sidebar's model and settings, and set runs per case to spot **flaky** tests. Includes 5 example cases, some targeting the ShopBot practice bot.
- **Save as test case** from any message you send in Chat.
- **Import/Export** test suites as JSON, in the same format as the web version.
- **LLM-as-a-judge:** Claude grades a reply against your rubric (pass/fail, a score from 1 to 5, and a verdict per criterion). Pick a rubric preset, paste a reply or generate one with your local model, and use **Judge ×3** to see how consistent the judge is.
- **Judge the judge:** 8 practice exercises where you predict the verdict first, then compare it with the judge's.
- **Missions:** 12 guided exercises, one per kind of chatbot bug, each with a goal, one-click setup, suggested prompts, hints, what a bug looks like, and a real-world example.
- **Target bots:** "break the bot" in 5 levels. Get ShopBot to leak its secret discount code past increasingly strong defences, with a debrief after each win.
- **⚑ Flag** any reply as Pass or Fail, with a category, severity, expected behaviour and notes.
- **Export report…** writes a Markdown bug report with steps to reproduce, settings and the full transcript.
- **History:** every chat is saved automatically. Reopen one to keep going, add flags or export a report.
- The judge uses your own Claude plan through Claude Code by default. An Anthropic API key can be added in Settings instead (stored in your Keychain).

## 0.1.0

- **First release** of the native LLM Chat Tester.
- Chat with local Ollama models, with streaming replies, Stop, and a stats line (time, tokens, speed, settings).
- Settings for temperature, seed and max tokens, plus a system prompt.
- **Run ×5** re-asks a question five times and counts the unique answers.
- A setup checklist that checks Ollama, can download a recommended model, and detects Claude Code.
- Automatic updates.
