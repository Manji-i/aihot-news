# Project Rules

## Purpose

This repository packages `aihot-news`, a local polling script that fetches new
AI Hot selected items and pushes them to a Lark/Feishu chat. It can also be
installed as an agent Skill so another agent can guide setup, testing, and
cron deployment.

## Structure

- `SKILL.md`: agent-facing Skill instructions.
- `agents/openai.yaml`: Codex UI metadata for the Skill.
- `poll.sh`: main poll, format, send, and state update script.
- `cron-wrapper.sh`: cron entrypoint that loads `config.sh` and sets runtime
  environment.
- `config.sh.example`: safe configuration template.
- `README.md`: human-facing usage instructions.

Runtime files are intentionally local-only:

- `config.sh`
- `state.json`
- `poll.log`
- `poll.log.*`

## Conventions

- User-facing documentation is Chinese.
- Do not commit secrets, tokens, real chat IDs, or local profile paths.
- Do not edit a user's real `config.sh` unless explicitly asked.
- Keep the script usable without installing the Skill.
- Validate changes with `bash -n poll.sh cron-wrapper.sh` and Skill metadata
  validation when `SKILL.md` changes.
- Do not require global dependency installation unless the user explicitly
  approves it.

