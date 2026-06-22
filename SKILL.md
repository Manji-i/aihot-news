---
name: aihot-news
description: 当普通用户想要安装、配置、测试、排查故障或调度 AI Hot 新闻轮询任务，把精选 AI 动态推送到飞书/Lark 群聊时使用本 Skill。
---

# AI Hot News

## 本 Skill 做什么

引导普通用户把本 Skill 配套的脚本跑起来：每 5 分钟拉取 [AI Hot](https://aihot.virxact.com) 的精选条目，按北京时间格式化后，通过本机已登录的 `lark-cli` 增量发送到飞书/Lark 群。脚本默认回看最近 12 小时，并用 `sent_item_ids` 去重，避免 AI Hot 后补精选时漏推。

这是 cron 式定时自动化，不是聊天总结。不要自行编造新闻内容，一切以 API 和脚本输出为准。

## 关键约定：定位 Skill 目录

本 Skill 的所有脚本都在 **SKILL.md 所在目录**。你（agent）执行命令时，一律用这个目录作为基准，不要假设它在 `/path/to/aihot-news` 或任何固定路径。先确定它：

```bash
SKILL_DIR="$(cd "$(dirname "${SKILL.md}")" && pwd)"
```

如果上面取不到，就用你加载本 Skill 时已知的安装路径。后续所有命令都在 `$SKILL_DIR` 下执行。

## 目录内容

```text
$SKILL_DIR/
├── SKILL.md             # 本文件
├── poll.sh              # 主脚本：拉取 → 格式化 → 发送 → 更新游标
├── cron-wrapper.sh      # cron 入口：加载 config.sh 并设置 PATH
├── config.sh.example    # 配置模板
└── agents/openai.yaml   # Codex UI 元数据
```

运行时还会自动生成（已 gitignore，不要提交）：`config.sh`、`state.json`、`poll.log`。`state.json` 同时保存 `last_published_at` 和 `sent_item_ids`。

## 执行流程

按顺序执行，每一步都需要时停下来和用户确认。

### 1. 检查前置依赖

逐个检查，缺哪个报哪个。**未经用户同意不要全局安装任何东西。**

```bash
command -v bash python3 curl lark-cli
```

- `lark-cli` 缺失：告诉用户需要先安装并登录飞书/Lark（这是账号授权操作，你替不了，只能给步骤）。
- 其余缺失：报给用户，按用户指示补。

### 2. 创建配置文件

仅当 `config.sh` 不存在时才创建，**不要覆盖已有的**：

```bash
cd "$SKILL_DIR"
[ -f config.sh ] || cp config.sh.example config.sh
```

### 3. 引导用户填写 config.sh

打开 `config.sh` 给用户看需要填的字段，**不要替用户猜值**，逐项确认：

| 字段 | 必填 | 怎么定 |
|------|------|--------|
| `CHAT_ID` | ✅ | 用下方「获取 CHAT_ID」方法查；查不到就问用户要 |
| `API_BASE` | 否 | 默认 `https://aihot.virxact.com`，一般不用改 |
| `MAX_PER_MESSAGE` / `PAGE_SIZE` | 否 | 默认 3 / 50，用户无特殊需求不动 |
| `STATE_FILE` / `POLL_LOG` | 否 | 默认放 `$SKILL_DIR` 下，用户无特殊需求不动 |
| `LOOKBACK_HOURS` | 否 | 默认 12；用于补抓后补精选，用户无特殊需求不动 |
| `MAX_SENT_IDS` | 否 | 默认 1000；用于保留已发送 ID 去重，用户无特殊需求不动 |

**安全**：不要把授权信息或完整 `config.sh` 打印回聊天。

### 4. 给脚本执行权限并校验

```bash
cd "$SKILL_DIR"
chmod +x poll.sh cron-wrapper.sh
bash -n poll.sh cron-wrapper.sh
```

语法报错就修脚本，不要绕过。

### 5. 手动测试一次

```bash
cd "$SKILL_DIR"
./cron-wrapper.sh
tail -n 50 poll.log
```

**判断成功**：
- 日志出现「无新增。」→ 正常，说明流程跑通了，只是当前没有新内容。
- 日志出现发送消息记录后跟「完成。」→ 正常，已推送。

**首次运行可能推一批旧条目**：因为脚本默认从 `last_published_at` 往前回看 12 小时并用 ID 去重。运行前提醒用户这一点；只有用户明确想调起点时，才在征得同意后改 `state.json`。

需要验证但不发消息时，用 dry-run：

```bash
AIHOT_DRY_RUN=1 ./cron-wrapper.sh
```

**报错处理**：见下方「故障排查」。

### 6. 配置 cron 定时

手动测试成功后再排程。帮用户把这一行加进 crontab（路径替换成实际的 `$SKILL_DIR`）：

```cron
*/5 * * * * /实际路径/cron-wrapper.sh
```

加的方法：

```bash
( crontab -l 2>/dev/null; echo "*/5 * * * * $SKILL_DIR/cron-wrapper.sh" ) | crontab -
```

加完后 `crontab -l` 确认。

**macOS 权限提醒**：如果 cron 跑出 `Operation not permitted`，是 `/usr/sbin/cron` 没有全磁盘访问权限——告诉用户去「系统设置 → 隐私与安全性 → 全磁盘访问」加 `/usr/sbin/cron`，或把 Skill 目录移到 cron 能访问的位置（如 `~/.local/share/aihot-news`）。**不要替用户改系统隐私设置。**

## 获取 CHAT_ID

优先用对用户环境影响最小的方式：

```bash
lark-cli im +messages-list-recent
```

从输出里找目标群的 chat_id。找不到就问用户要，**不要主动给随机群发测试消息**。

## 故障排查

| 症状 | 原因 | 处理 |
|------|------|------|
| `keychain Get failed` | cron 无法访问 macOS Keychain | 引导用户按其 lark-cli 版本执行 keychain/文件 token 降级（账号相关，用户自己做） |
| `command not found: lark-cli` | cron 的 PATH 找不到 lark-cli | 在 `cron-wrapper.sh` 的 `PATH` 里加入 lark-cli 所在目录 |
| `API 响应异常` | API_BASE 错 / 没网 | 看 `poll.log` 里前 200 字符响应，检查 `API_BASE` 和网络 |
| 一直没消息发出 | 没有未发送的精选条目，或 `sent_item_ids` 已记录 | 用 `AIHOT_DRY_RUN=1 ./cron-wrapper.sh` 看当前窗口内是否有待发条目；必要时检查 `state.json` |
| 精选页有但群里没推 | 旧版单游标跳过了后补精选 | 升级新版；新版回看窗口并按 `sent_item_ids` 去重 |
| 消息重复 | 多实例并跑 | 查是否有多条 crontab 或多份副本用了不同 `STATE_FILE` |

## 安全规则

- 永远不要提交 `config.sh`、`state.json`、`poll.log`。
- 永远不要在聊天里打印 token、含密钥的 profile 路径或完整 `config.sh`。
- 发消息默认 `--as bot`。
- 未经询问不要删除 `state.json` 或 `poll.log`——删了可能造成通知重放或丢失排查证据。
- 账号授权、系统权限、全局安装这三类操作替不了用户，只能给步骤。
