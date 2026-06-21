# aihot-news

每 5 分钟轮询 [AI Hot](https://aihot.virxact.com) 精选 AI 新闻，增量推送到飞书/Lark 群聊。

也可以作为 agent Skill 安装使用。安装后让 agent 触发 `$aihot-news`，它会按本仓库的固定流程引导用户配置 `config.sh`、手动测试、排查权限问题并设置 cron。

## 效果

```
🔹（6月18日 00:40）GPT-5 发布路线图曝光
📂 模型 · The Verge
OpenAI CEO 在最新访谈中透露了下一代模型的发布时间表…
🔗 https://example.com/gpt5

🔹（6月18日 00:35）Claude 推出新功能
📂 产品 · Anthropic Blog
新增交互式数据分析能力，支持图表生成与多文件对比…
🔗 https://example.com/claude
```

## 前置条件

| 依赖 | 说明 |
|------|------|
| **Python 3** | 系统自带或 `brew install python3` |
| **lark-cli** | 飞书/Lark CLI，已登录且有发消息权限 |
| **飞书/Lark 机器人** | 在目标群中且有发言权限 |
| **macOS / Linux** | 脚本依赖 bash、curl、mktemp |

### lark-cli 准备

```bash
# 安装 lark-cli
npm install -g @anthropic/lark-cli

# 登录
lark-cli login

# 如果使用 cron 定时运行，需要将密钥降级到文件
# （cron 环境无法访问 macOS Keychain）
lark-cli config keychain-downgrade
```

## 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/Manji-i/aihot-news.git
cd aihot-news

# 2. 创建配置文件
cp config.sh.example config.sh

# 3. 编辑 config.sh，填入你的配置
#    - CHAT_ID：目标飞书群的 chat_id
nano config.sh

# 4. 给脚本执行权限
chmod +x poll.sh cron-wrapper.sh

# 5. 手动测试一次
./cron-wrapper.sh

# 6. 加入 crontab（每 5 分钟）
crontab -e
# 添加这一行：
# */5 * * * * /path/to/aihot-news/cron-wrapper.sh
```

## 作为 Skill 使用

把本仓库作为 Skill 安装源交给支持 Skill 的 agent：

```text
请安装并使用这个 Skill：
https://github.com/Manji-i/aihot-news
```

安装后可以这样触发：

```text
用 $aihot-news 帮我配置 AI Hot 轮询，推送到我的飞书群。
```

Skill 不会替你猜测配置。它会引导确认 `CHAT_ID`、`lark-cli` 登录状态，以及 cron 在 macOS 下可能需要的权限。

## 配置文件说明

`config.sh` 中的关键配置项：

| 配置 | 必填 | 说明 |
|------|------|------|
| `CHAT_ID` | ✅ | 目标群聊的 chat_id |
| `API_BASE` | 否 | API 地址，默认 `https://aihot.virxact.com` |
| `MAX_PER_MESSAGE` | 否 | 每条消息最多几条新闻，默认 3 |
| `PAGE_SIZE` | 否 | 每页拉取条数，默认 50 |

## 文件结构

```
aihot-news/
├── poll.sh              # 主脚本：拉取 → 格式化 → 发送
├── cron-wrapper.sh      # cron 入口：加载配置并设置 PATH
├── config.sh.example    # 配置模板
├── SKILL.md             # agent Skill 入口
├── agents/openai.yaml   # Codex UI 元数据
├── config.sh            # 你的配置（gitignore，不提交）
├── state.json           # 游标（自动生成，不提交）
├── poll.log             # 运行日志（自动生成，不提交）
├── .gitignore
└── README.md
```

## 如何获取 CHAT_ID

```bash
# 方法 1：用 lark-cli 列出最近会话
lark-cli im +messages-list-recent

# 方法 2：在飞书开发者后台 → 机器人 → 事件订阅 中查看
# 方法 3：把机器人拉到目标群，在群里发一条消息，然后查事件日志
```

## 日志

运行日志写入 `poll.log`（脚本所在目录）。建议配置 logrotate 或定期清理：

```bash
# 手动轮转
mv poll.log poll.log.old && touch poll.log
```

## 常见问题

| 症状 | 原因 | 解决 |
|------|------|------|
| `keychain Get failed` | cron 环境无法访问 macOS Keychain | `lark-cli config keychain-downgrade` |
| `Operation not permitted` | macOS 沙箱阻止 cron 访问脚本目录 | 把仓库放在 `~/.local/share/` 或 `/usr/local/opt/` 下；或给 `/usr/sbin/cron` 全磁盘访问权限 |
| `mktemp: File exists` | 上次异常退出残留临时文件 | `rm -f /tmp/aihot_items.* /tmp/aihot_sorted.*` |
| `command not found: lark-cli` | cron 的 PATH 不含 lark-cli | 在 `cron-wrapper.sh` 的 PATH 中加入 lark-cli 所在目录 |

## License

MIT
