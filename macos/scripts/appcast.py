#!/usr/bin/env python3
"""Adds a release to a Sparkle appcast, creating the appcast if needed.

Usage: appcast.py <appcast.xml> <version> <build> <download-url> '<sign_update output>' <notes.md>

We write the item ourselves (instead of Sparkle's generate_appcast) because each version's zip lives at a
different GitHub Release URL, and older entries must keep their original URLs.
"""
import html
import re
import sys
from email.utils import formatdate
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
MIN_MACOS = "15.0"


def notes_to_html(markdown: str) -> str:
    """Tiny Markdown subset (bullets, paragraphs, **bold**, `code`) for Sparkle's release-notes pane."""
    out, in_list = [], False
    for line in markdown.strip().splitlines():
        text = html.escape(line.strip())
        text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
        text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
        if text.startswith(("- ", "* ")):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{text[2:]}</li>")
        else:
            if in_list:
                out.append("</ul>")
                in_list = False
            if text:
                out.append(f"<p>{text}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def main() -> None:
    appcast_path, version, build, url, sig_attrs, notes_path = sys.argv[1:7]
    signature = re.search(r'sparkle:edSignature="([^"]+)"', sig_attrs)
    length = re.search(r'length="(\d+)"', sig_attrs)
    if not signature or not length:
        sys.exit(f"Could not parse sign_update output: {sig_attrs!r}")

    notes = notes_to_html(Path(notes_path).read_text(encoding="utf-8"))
    item = f"""    <item>
      <title>Version {html.escape(version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{html.escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{MIN_MACOS}</sparkle:minimumSystemVersion>
      <description><![CDATA[{notes}]]></description>
      <enclosure url="{html.escape(url)}" type="application/octet-stream" sparkle:edSignature="{signature.group(1)}" length="{length.group(1)}"/>
    </item>
"""
    path = Path(appcast_path)
    if path.exists():
        existing = path.read_text(encoding="utf-8")
        if f"<sparkle:version>{build}</sparkle:version>" in existing:
            sys.exit(f"Build {build} is already in the appcast")
        marker = existing.find("<item>")
        if marker == -1:
            marker = existing.find("</channel>")
        line_start = existing.rfind("\n", 0, marker) + 1
        updated = existing[:line_start] + item + existing[line_start:]
    else:
        updated = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="{SPARKLE_NS}">
  <channel>
    <title>LLM Chat Tester</title>
{item}  </channel>
</rss>
"""
    path.write_text(updated, encoding="utf-8")
    print(f"    appcast: added {version} (build {build})")


if __name__ == "__main__":
    main()
