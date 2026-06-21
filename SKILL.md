---
name: aihot-news
description: 当用户想要安装、配置、测试、排查故障或调度 AI Hot 新闻轮询任务，把精选 AI 动态推送到飞书/Lark 群聊时使用本 Skill。
---

# AI Hot News

## 本 Skill 做什么

引导用户或其他 agent 把本仓库作为本地的 AI Hot 轮询任务运行。脚本会拉取新的 AI Hot 精选条目，按北京时间格式化后，通过 `lark-cli` 增量批量发送到飞书/Lark 群。

这本质上是一个 cron 式定时自动化任务，不是纯聊天总结型 Skill。不要自行编造新闻内容，一切以 API 和脚本输出为准。

## 仓库结构

假设 Skill 根目录即本仓库：

```text
aihot-news/
├── poll.sh
├── cron-wrapper.sh
├── config.sh.example
├── README.md
├── SKILL.md
└── agents/openai.yaml
```

运行时文件默认生成在脚本同级目录（除非另行配置）：`config.sh`、`state.json`、`poll.log`。

## 配置流程

1. 确认仓库已存在并进入目录。

```bash
cd /path/to/aihot-news
```

2. 检查前置依赖，未经用户同意不要全局安装任何东西。

```bash
command -v bash
command -v python3
command -v curl
command -v lark-cli
```

3. 仅当 `config.sh` 不存在时才创建。

```bash
cp config.sh.example config.sh
```

不要打印或提交 `config.sh`。引导用户设置：

- `CHAT_ID`：目标飞书/Lark 群的 chat_id。
- `LARK_CHANNEL`、`LARK_CHANNEL_HOME`、`LARK_CHANNEL_PROFILE`、`LARKSUITE_CLI_CONFIG_DIR`：仅在使用 lark-channel bridge 模式时填写。
- `API_BASE`：默认 `https://aihot.virxact.com`。
- `MAX_PER_MESSAGE` 和 `PAGE_SIZE`：可选的发送控制项。
- `STATE_FILE` 和 `POLL_LOG`：可选的自定义运行时路径。

如果用户不使用 lark-channel，告诉对方注释掉所有 `LARK_CHANNEL*` 和 `LARKSUITE_CLI_CONFIG_DIR` 行，使用本机普通的 `lark-cli` 配置即可。

4. 如有必要给脚本加执行权限。

```bash
chmod +x poll.sh cron-wrapper.sh
```

5. 校验 shell 语法。

```bash
bash -n poll.sh cron-wrapper.sh
```

6. 排程前先手动测试一次。

```bash
./cron-wrapper.sh
tail -n 50 poll.log
```

成功的标志是出现「无新增。」，或先有发送消息日志、最后出现「完成。」。如果首次运行就发送了一批旧条目，说明 `state.json` 默认从一小时前开始；只有在用户同意后才调整 `STATE_FILE` 或 `state.json`。

## 获取 `CHAT_ID`

优先用对用户环境影响最小的方式：

```bash
lark-cli im +messages-list-recent
```

如果看不到目标群，请用户提供群聊 ID，或请求授权查看最近的 Lark 消息。不要主动给随机群聊发私信或测试消息。

## 用 cron 排程

手动测试成功后，建议添加：

```cron
*/5 * * * * /path/to/aihot-news/cron-wrapper.sh
```

在 macOS 上，优先把仓库放到 cron 能访问的位置，例如 `~/.local/share/aihot-news`。如果 cron 日志出现 `Operation not permitted`，说明 `/usr/sbin/cron` 需要全磁盘访问权限，或仓库需要移到可访问位置。未经用户操作或明确授权，不要改动系统隐私设置。

## 故障排查

- `keychain Get failed`：cron 无法访问 macOS Keychain。引导用户按所用 lark-cli 版本执行 keychain/文件 token 降级配置。
- `command not found: lark-cli`：在 `cron-wrapper.sh` 的 `PATH` 里加入 lark-cli 所在目录，或经用户同意后安装 lark-cli。
- `API 响应异常`：检查 `API_BASE`、网络连通性，以及 `poll.log` 里的前 200 字符响应。
- 没有消息发出：检查 `state.json`；脚本只发送比 `last_published_at` 更新的条目。
- 消息重复：检查是否存在多条 crontab 记录、或多份仓库副本用了不同 `STATE_FILE` 路径同时运行。
- lark-channel bound 模式报错：不要 unset bridge 变量、不要切回普通 profile。请用户重启 bridge 或运行 bridge doctor/preflight。

## 安全规则

- 永远不要提交 `config.sh`、`state.json`、`poll.log`。
- 永远不要在聊天里打印 token、含密钥的私有 profile 路径或完整配置文件。
- 发送消息默认用 `--as bot`，除非用户明确要求以用户身份发送。
- 未经询问不要删除运行时状态或日志；否则可能造成通知重放或丢失排查证据。
