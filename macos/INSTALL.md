# Installing LLM Chat Tester (for testers)

It takes about 10 minutes, and you only do it once. After that, the app updates itself.

## 1. Install Ollama (runs the chatbots locally)

Download it from **https://ollama.com/download**, open it, and leave it running (it lives in the menu bar).
The app can download a model for you on first launch.

## 2. Install the app

1. Download **LLM-Chat-Tester.zip** from the latest release:
   **https://github.com/alpheroltd/llm-chat-tester/releases/latest**
   (or directly: https://github.com/alpheroltd/llm-chat-tester/releases/latest/download/LLM-Chat-Tester.zip)
2. Double-click the zip and drag **LLM Chat Tester** into your **Applications** folder.
3. Open it. macOS will say it *"can't be opened because Apple cannot check it for malicious software"*.
   That's expected: it's an internal tool and isn't registered with Apple.
4. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to
   "LLM Chat Tester was blocked". Confirm with your password or Touch ID.

   Or, in Terminal:
   ```sh
   xattr -dr com.apple.quarantine "/Applications/LLM Chat Tester.app"
   ```
5. Open the app again. The **setup checklist** confirms Ollama is running and offers to download a model.

You only do step 4 once. Updates install without it.

## 3. Optional: Claude Code (for the LLM judge)

The LLM-as-a-judge feature uses **your own** Claude plan through Claude Code:

1. Install Claude Code: https://claude.com/claude-code
2. Open Terminal, run `claude`, and log in.
3. In the app, open **Setup** (toolbar) → **Check again**. It should say "Claude Code … ready".

The chatbots under test run on your Mac, but **the judge doesn't: the reply and rubric you judge are sent to Anthropic**, and each judgement uses a little of your Claude plan. Don't judge anything you couldn't paste into Claude yourself. The judge runs with no tools, so instructions hidden in a reply can't make it do anything.

## Updates

The app checks for updates once a day, or use **LLM Chat Tester → Check for Updates…**
Your chats, test cases and progress are kept when it updates.

## Something wrong?

- **"Ollama isn't reachable":** open the Ollama app (or run `brew services start ollama`), then press ↻ next to the model picker.
- **No models in the list:** run `ollama pull llama3.2:3b` in Terminal, or use the download button in Setup.
- **"Claude Code not found":** if you installed it somewhere unusual, set its path in **Settings → Claude Code**.
