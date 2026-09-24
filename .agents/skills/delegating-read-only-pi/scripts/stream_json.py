#!/usr/bin/env python3
"""Emit minimal Pi progress to stderr and the final assistant response to stdout."""

from __future__ import annotations

import json
import sys
from typing import Any


def assistant_text(message: Any) -> str:
    if not isinstance(message, dict) or message.get("role") != "assistant":
        return ""
    content = message.get("content")
    if not isinstance(content, list):
        return ""
    parts = [
        item.get("text", "")
        for item in content
        if isinstance(item, dict) and item.get("type") == "text"
    ]
    return "\n".join(part for part in parts if part)


def progress(message: str) -> None:
    print(f"[read-only child] {message}", file=sys.stderr, flush=True)


def main() -> int:
    final_text = ""
    completed = False

    for line_number, raw_line in enumerate(sys.stdin, start=1):
        try:
            event = json.loads(raw_line)
        except json.JSONDecodeError as error:
            progress(f"invalid JSON event at line {line_number}: {error.msg}")
            return 2

        event_type = event.get("type")
        if event_type == "agent_start":
            progress("started")
        elif event_type == "auto_retry_start":
            progress(f"retry {event.get('attempt', '?')} started")
        elif event_type == "message_end":
            message = event.get("message")
            # A terminal message that ended in error carries no trustworthy
            # answer; drop any stale text from an earlier successful message
            # instead of reporting it as the child's result.
            stop_reason = message.get("stopReason") if isinstance(message, dict) else None
            if stop_reason == "error":
                final_text = ""
                progress("assistant message ended with stopReason=error")
            else:
                candidate = assistant_text(message)
                if candidate:
                    final_text = candidate
        elif event_type == "agent_end":
            messages = event.get("messages")
            if isinstance(messages, list):
                for message in reversed(messages):
                    candidate = assistant_text(message)
                    if candidate:
                        final_text = candidate
                        break
            completed = True

    if not completed:
        progress("event stream ended before agent completion")
        return 2
    if not final_text.strip():
        progress("completed without a final answer")
        return 1

    sys.stdout.write(final_text)
    if not final_text.endswith("\n"):
        sys.stdout.write("\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
