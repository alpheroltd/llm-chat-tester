#!/usr/bin/env python3
"""PostToolUse:Edit|Write|MultiEdit — format the file that just changed and
lint only that file, feeding any diagnostics back as additionalContext.

Scoped to one file on purpose. A whole-repo lint on every edit is slow and
floods the context with output about files Claude never touched.
"""
import os
import sys

from _common import (add_context, load_config, load_payload, matches_any, rel,
                     repo_root, run, trim)

WRITE_TOOLS = {"Edit", "Write", "MultiEdit"}


def main():
    payload = load_payload()
    if payload.get("tool_name") not in WRITE_TOOLS:
        return 0

    tool_input = payload.get("tool_input") or {}
    path = tool_input.get("file_path", "")
    if not path or not os.path.exists(path):
        return 0

    root = repo_root(payload)
    relative = rel(path, root)
    config = load_config()
    checks = config.get("fileChecks", [])
    if not checks:
        return 0

    findings = []
    for check in checks:
        if not matches_any(relative, check.get("paths", [])):
            continue
        template = check.get("command", "")
        if "{file}" not in template:
            continue
        cmd = template.replace("{file}", _quote(relative))
        code, output = run(cmd, root, timeout=check.get("timeout", 60))
        if code == 0:
            continue
        if code == 127:
            continue  # Tool not installed — stay silent rather than nag.
        label = check.get("name", cmd.split()[0])
        findings.append("[%s] %s" % (label, output or "exited %s" % code))

    if findings:
        add_context(
            "PostToolUse",
            trim("Checks failed on %s. Fix these before moving on:\n\n%s"
                 % (relative, "\n\n".join(findings))),
        )
    return 0


def _quote(path):
    return "'" + path.replace("'", "'\\''") + "'"


if __name__ == "__main__":
    sys.exit(main())
