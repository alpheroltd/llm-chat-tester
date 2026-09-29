#!/usr/bin/env python3
"""Writes the public download page (index.html) from the Sparkle appcast.

Usage: download_page.py <appcast.xml> <index.html> <owner/repo>
"""
import html
import sys
import xml.etree.ElementTree as ET

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def main() -> None:
    appcast, out, repo = sys.argv[1:4]
    items = ET.parse(appcast).getroot().findall("channel/item")
    if not items:
        sys.exit("The appcast has no releases")
    latest = items[0]
    version = latest.findtext(f"{SPARKLE}shortVersionString", "")
    notes = latest.findtext("description", "")
    date = latest.findtext("pubDate", "")
    latest_url = f"https://github.com/{repo}/releases/latest/download/LLM-Chat-Tester.zip"
    older = "".join(
        f'<li><a href="{html.escape(i.find("enclosure").get("url"))}">Version {html.escape(i.findtext(f"{SPARKLE}shortVersionString", ""))}</a></li>'
        for i in items[1:]
    )

    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LLM Chat Tester</title>
<style>
  :root {{ --bg: #f6f7f9; --panel: #fff; --text: #1c1f24; --muted: #6b7280; --border: #e2e5ea; --accent: #2563eb; }}
  @media (prefers-color-scheme: dark) {{ :root {{ --bg: #111317; --panel: #1a1d23; --text: #e6e8eb; --muted: #9aa1ab; --border: #2a2f37; }} }}
  body {{ margin: 0; background: var(--bg); color: var(--text); font: 16px/1.55 system-ui, -apple-system, sans-serif; }}
  main {{ max-width: 720px; margin: 0 auto; padding: 48px 16px; }}
  h1 {{ margin: 0 0 4px; font-size: 32px; }}
  .muted {{ color: var(--muted); }}
  .card {{ background: var(--panel); border: 1px solid var(--border); border-radius: 12px; padding: 20px 24px; margin-top: 24px; }}
  .button {{ display: inline-block; background: var(--accent); color: #fff; text-decoration: none; font-weight: 600;
             padding: 12px 22px; border-radius: 10px; margin: 16px 0 4px; }}
  a {{ color: var(--accent); }}
  code {{ background: var(--bg); padding: 2px 6px; border-radius: 4px; font-size: 14px; }}
  ol li {{ margin-bottom: 8px; }}
</style>
</head>
<body>
<main>
  <h1>LLM Chat Tester</h1>
  <p class="muted">A training tool for testing chatbots, for the Alphero QA team. macOS 15 or later.</p>

  <a class="button" href="{html.escape(latest_url)}">Download version {html.escape(version)}</a>
  <div class="muted">Released {html.escape(date)} · after installing, updates arrive automatically.</div>

  <div class="card">
    <h2>Install</h2>
    <ol>
      <li>Install <a href="https://ollama.com/download">Ollama</a> and open it (it runs the chatbots on your Mac).</li>
      <li>Open the downloaded zip and drag <b>LLM Chat Tester</b> into <b>Applications</b>.</li>
      <li>Open it. macOS will say it can't check the app for malicious software. That's expected for this internal tool.</li>
      <li>Go to <b>System Settings → Privacy &amp; Security</b>, scroll down and click <b>Open Anyway</b>. You only do this once.</li>
      <li>Optional, for the LLM judge: install <a href="https://claude.com/claude-code">Claude Code</a> and run <code>claude</code> once in Terminal to log in.</li>
    </ol>
    <p class="muted">Full guide: <a href="https://github.com/{html.escape(repo)}/blob/main/macos/INSTALL.md">INSTALL.md</a></p>
  </div>

  <div class="card">
    <h2>What's new in {html.escape(version)}</h2>
    {notes}
  </div>

  {f'<div class="card"><h2>Older versions</h2><ul>{older}</ul></div>' if older else ''}
</main>
</body>
</html>
"""
    with open(out, "w", encoding="utf-8") as f:
        f.write(page)
    print(f"    download page: version {version}")


if __name__ == "__main__":
    main()
