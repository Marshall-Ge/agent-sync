# agent-sync

总是在不同的主机上面开发同一个项目，苦于agent的历史session无法随项目迁移？这个工具让你不用每次在新主机上重开agent上下文对话。

单文件跨机同步工具 —— 让 [Claude Code](https://claude.com/claude-code)、[opencode](https://opencode.ai)、[dsh](https://github.com/deepseek-ai/deepseek-harness)(DeepSeek Harness) 的 **memory / sessions / skills** 在多台机器间保持一致。[Codex CLI](https://github.com/openai/codex) 作为**实验功能**支持。

把单个 `setup.sh` 拷进你的项目，运行一次，这些 agent 的状态就存进仓库（git 跟踪），跟着 `git clone` 到处走。

> **隐私提示:** 会话转录会记录你输入的一切——包括 API key。开发期请把项目仓库设为**私有**，绝不要把密钥提交进去。

## 同步什么

| Agent | Sessions | Memory | Skills | 状态 |
|-------|----------|--------|--------|------|
| Claude Code | `.claude/sessions/`(快照) | auto-memory(同一快照下) | `.claude/skills/` | 稳定 |
| opencode | `.opencode/sessions/`(导入导出) | `.claude/memory/` | `.claude/skills/` | 稳定 |
| dsh (DeepSeek Harness) | `.dsh/sessions/`(快照) | — | — | 稳定 |
| Codex CLI | `.codex/sessions/`(复制,按 cwd 过滤) | `.codex/memories/`(快照) | `.codex/skills/`(快照,排除 `.system/`) | 实验 |

## 快速开始

```bash
# 把 setup.sh 拷进项目根目录
cp /path/to/agent-sync/setup.sh ./setup.sh
chmod +x setup.sh

# 初始化稳定工具(claude + opencode + dsh)
./setup.sh all

# 或任意组合
./setup.sh claude
./setup.sh opencode dsh

# codex 是实验功能 —— 单独开启
./setup.sh codex
```

跨机前先刷新快照，再 commit + push：

```bash
./setup.sh sync                         # 收集最新数据 + 重导入 opencode
git add .claude .opencode .dsh          # (+ .codex，如果开启了 codex)
git commit -m "agent-sync: sync agent data"
git push
```

在新机器上：

```bash
git clone <你的仓库>
cd <你的仓库>
./setup.sh all    # 恢复快照 / 导入会话
```

## 原理

- **Claude Code** 把会话(和 auto-memory)存在 `~/.claude/projects/<编码路径>/`。`setup.sh` 把该目录**快照(复制)**进 `.claude/sessions/`，绝不软链，所以 `claude` 行为完全不变，同时转录进仓库供 git 同步。
- **opencode** 的会话在全局 sqlite 里，无法按项目软链。`setup.sh` 装一个 cwd 感知的 `oc` 包装函数（通过 `.agent-sync` 标记定位最近的项目）：启动 opencode，退出时把本项目会话导出到 `.opencode/sessions/` 并 git add。`setup.sh sync` 也会重新导入另一台机器更新过的会话。用 `oc`，不要裸跑 `opencode`。
- **dsh (DeepSeek Harness)** 的会话按项目存在 `~/.dsh/sessions/<projectKey>/`(zstd 压缩的 JSONL)。`setup.sh` 把该目录**快照(复制)**进 `.dsh/sessions/`，绝不软链。
- **Codex CLI(实验)** 的会话全局存在 `~/.codex/`。`setup.sh codex` 把本项目会话复制进 `.codex/sessions/`，并重置 codex 的 `backfill_state`，让下一次启动 `codex` 时重新建索引。但 codex 较新的「paginated」会话把对话内容存在 sqlite 表里，所以**在另一台机器「继续」会话新增的内容可能同步不回来**——这正是 codex 被列为可选实验功能的原因。

## 命令

```bash
./setup.sh                    # 显示帮助(无参数)
./setup.sh claude opencode    # 初始化任意组合
./setup.sh all                # 初始化 claude + opencode + dsh
./setup.sh codex              # 初始化 codex(实验)
./setup.sh sync               # 收集最新数据(跨机前先跑,再 git commit+push)
./setup.sh oc                 # 启动 opencode，退出导出会话
./setup.sh --help             # 帮助
```

## 注意事项

- **开发期用私有仓库**——转录可能含密钥。
- **codex 是实验功能**：`./setup.sh codex` 会打印警告；其「继续」内容同步对新的 paginated 会话不完整。
- `oc` 别名只往 `~/.zshrc` 写一行 alias(不写 key)，`source ~/.zshrc` 生效。
- 幂等，可重复运行。

## API key

`setup.sh` 不管理 API key。opencode 的 `oc` 别名复用 `ANTHROPIC_AUTH_TOKEN`，回退读 `~/.claude/settings.json`。每台机器配一次即可。
