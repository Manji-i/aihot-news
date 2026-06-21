# 项目规则

## 目的

本仓库打包 `aihot-news`：一个本地轮询脚本，拉取新的 AI Hot 精选条目并推送到飞书/Lark 群。它也可以作为 agent Skill 安装，让其他 agent 引导完成配置、测试和 cron 部署。

## 结构

- `SKILL.md`：面向 agent 的 Skill 指令。
- `agents/openai.yaml`：Skill 的 Codex UI 元数据。
- `poll.sh`：主脚本，负责轮询、格式化、发送和状态更新。
- `cron-wrapper.sh`：cron 入口，加载 `config.sh` 并设置运行时环境。
- `config.sh.example`：安全的配置模板。
- `README.md`：面向人类用户的使用说明。

以下运行时文件刻意只保留在本地：

- `config.sh`
- `state.json`
- `poll.log`
- `poll.log.*`

## 约定

- 面向用户的文档用中文。
- 不要提交密钥、token、真实 chat_id 或本地 profile 路径。
- 未经明确要求不要修改用户的真实 `config.sh`。
- 保持脚本在未安装 Skill 的情况下也能独立使用。
- 改动后用 `bash -n poll.sh cron-wrapper.sh` 校验；`SKILL.md` 变更时一并校验 Skill 元数据。
- 未经用户明确同意，不要要求安装全局依赖。
