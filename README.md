# LLM Chat Tester

A local webapp for **learning how to test chatbots**, using an LLM running on your own machine through [Ollama](https://ollama.com). Nothing leaves your laptop.

## One-time setup

```sh
brew install ollama
brew services start ollama      # runs the API at http://localhost:11434
ollama pull llama3.2:3b         # ~2GB; any other model works too
```

## Run

```sh
npm start
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
