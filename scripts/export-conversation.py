#!/usr/bin/env python3
"""Export visible user/assistant messages from a Codex JSONL session.

Usage: python3 scripts/export-conversation.py /absolute/path/to/session.jsonl
Only the task conversation starting at its request is exported. System/developer
instructions, tool payloads, private reasoning and environment context are omitted.
"""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
messages = []
started = False
for line in Path(sys.argv[1]).open():
    event = json.loads(line)
    payload = event.get("payload", {})
    if event.get("type") != "response_item" or payload.get("type") != "message":
        continue
    role = payload.get("role")
    if role not in ("user", "assistant"):
        continue
    if role == "assistant" and payload.get("phase") not in ("commentary", "final_answer", "final"):
        continue
    text = "\n".join(item["text"] for item in payload.get("content", []) if item.get("type") in ("input_text", "output_text") and item.get("text"))
    if role == "user" and "Мне нужно выполнить два тестовых задания" in text:
        started = True
    if not started or not text:
        continue
    # Async question replies contain the exact question and the human answer.
    if text.startswith("<send_user_message_question_reply>"):
        raw = text.removeprefix("<send_user_message_question_reply>").split("</send_user_message_question_reply>")[0].strip()
        replies = json.loads(raw)
        text = "\n\n".join(f"Question: {reply['question']}\n\nAnswer: {reply['answer']}" for reply in replies)
    messages.append({"timestamp": event.get("timestamp"), "role": role, "text": text})
if not messages:
    raise SystemExit("No task dialogue found")
(root / "ai").mkdir(exist_ok=True)
(root / "ai/messages.json").write_text(json.dumps(messages, ensure_ascii=False, indent=2) + "\n")
intro = "# AI conversation copy\n\nExport of visible user/assistant messages for this task, up to the export timestamp. Internal instructions, tools and private reasoning are excluded. Async replies show the question and exact human answer. This is a dialogue export, not a reconstructed summary.\n\n"
(root / "ai/conversation.md").write_text(intro + "\n\n".join(f"## {m['role'].title()} — {m['timestamp']}\n\n{m['text']}" for m in messages) + "\n")
print(f"Exported {len(messages)} visible messages")
