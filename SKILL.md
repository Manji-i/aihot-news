---
name: aihot-news
description: Use when a user wants to install, configure, test, troubleshoot, or schedule AI Hot news polling to push selected AI updates into a Lark or Feishu chat.
---

# AI Hot News

## What This Skill Does

Guide a user or another agent to run this repository as a local AI Hot polling
task. The scripts fetch new selected AI Hot items, format them with Beijing
time, and send incremental batches to a Lark/Feishu chat through `lark-cli`.

This is primarily a cron-style automation, not a chat-only summarization skill.
Do not invent news content; use the API and script output.

## Repository Layout

Assume the Skill root is this repository:

```text
aihot-news/
├── poll.sh
├── cron-wrapper.sh
├── config.sh.example
├── README.md
├── SKILL.md
└── agents/openai.yaml
```

Runtime files are created beside the scripts unless configured otherwise:
`config.sh`, `state.json`, and `poll.log`.

## Setup Flow

1. Confirm the repository is present and enter it.

```bash
cd /path/to/aihot-news
```

2. Check prerequisites without installing anything globally unless the user
   approves it.

```bash
command -v bash
command -v python3
command -v curl
command -v lark-cli
```

3. Create `config.sh` only if missing.

```bash
cp config.sh.example config.sh
```

Do not print or commit `config.sh`. Guide the user to set:

- `CHAT_ID`: target Lark/Feishu chat ID.
- `LARK_CHANNEL`, `LARK_CHANNEL_HOME`, `LARK_CHANNEL_PROFILE`,
  `LARKSUITE_CLI_CONFIG_DIR`: only when using lark-channel bridge mode.
- `API_BASE`: defaults to `https://aihot.virxact.com`.
- `MAX_PER_MESSAGE` and `PAGE_SIZE`: optional sending controls.
- `STATE_FILE` and `POLL_LOG`: optional custom runtime paths.

If the user is not using lark-channel, tell them to comment out all
`LARK_CHANNEL*` and `LARKSUITE_CLI_CONFIG_DIR` lines and use their normal
`lark-cli` profile.

4. Make scripts executable if needed.

```bash
chmod +x poll.sh cron-wrapper.sh
```

5. Validate shell syntax.

```bash
bash -n poll.sh cron-wrapper.sh
```

6. Test once before scheduling.

```bash
./cron-wrapper.sh
tail -n 50 poll.log
```

Success means either "无新增。" or a sent-message log followed by "完成。".
If it sends old items on first run, explain that `state.json` starts from one
hour ago by default; adjust `STATE_FILE` or `state.json` only with user consent.

## Getting `CHAT_ID`

Prefer the least disruptive method available in the user's environment:

```bash
lark-cli im +messages-list-recent
```

If that does not reveal the target chat, ask the user for the group chat ID or
for permission to inspect recent Lark messages. Do not DM or post test messages
to random chats.

## Scheduling With Cron

After one manual test succeeds, suggest:

```cron
*/5 * * * * /path/to/aihot-news/cron-wrapper.sh
```

On macOS, prefer placing the repository somewhere cron can access, such as
`~/.local/share/aihot-news`. If cron logs `Operation not permitted`, explain
that `/usr/sbin/cron` needs Full Disk Access or the repo must move to an
accessible location. Do not change system privacy settings without user action
or explicit permission.

## Troubleshooting

- `keychain Get failed`: cron cannot access macOS Keychain. Guide the user to
  run the documented `lark-cli` keychain/file-token setup for their CLI version.
- `command not found: lark-cli`: add the lark-cli directory to `PATH` in
  `cron-wrapper.sh` or install lark-cli after user approval.
- `API 响应异常`: inspect `API_BASE`, network access, and the first 200
  response characters in `poll.log`.
- No messages sent: check `state.json`; the script only sends items newer than
  `last_published_at`.
- Duplicate messages: check whether multiple crontab entries or multiple repo
  copies are running with different `STATE_FILE` paths.
- lark-channel bound-mode errors: do not unset bridge variables or switch to a
  normal profile. Ask the user to restart bridge or run bridge doctor/preflight.

## Safety Rules

- Never commit `config.sh`, `state.json`, or `poll.log`.
- Never print tokens, private profile paths containing secrets, or full config
  files back to chat.
- Use `--as bot` for sending unless the user explicitly requests user identity.
- Do not delete runtime state or logs without asking; that can cause replayed
  notifications or loss of debugging evidence.

