# agent-sync

总是在不同的主机上面开发同一个项目，苦于agent的历史session无法随项目迁移？这个工具让你不用每次在新主机上重开agent上下文对话。

单文件跨机同步工具 —— 让 [Claude Code](https://claude.com/claude-code)、[opencode](https://opencode.ai)、[Codex CLI](https://github.com/openai/codex) 的 **memory / sessions / skills** 在多台机器间保持一致。

把单个 `setup.sh` 拷进你的项目，运行一次，这些 agent 的状态就存进仓库（git 跟踪），跟着 `git clone` 到处走。

> **隐私提示:** 会话转录会记录你输入的一切——包括 API key。开发期请把项目仓库设为**私有**，绝不要把密钥提交进去。

## 同步什么

| Agent | Sessions | Memory | Skills |
|-------|----------|--------|--------|
| Claude Code | `.claude/sessions/`(快照) | auto-memory(同一快照下) | `.claude/skills/` |
| opencode | `.opencode/sessions/`(导入导出) | `.claude/memory/` | `.claude/skills/` |
| Codex CLI | `.codex/sessions/`(复制,按 cwd 过滤) | `.codex/memories/`(快照) | `.codex/skills/`(快照,排除 `.system/`) |

## 快速开始

```bash
# 把 setup.sh 拷进项目根目录
cp /path/to/agent-sync/setup.sh ./setup.sh
chmod +x setup.sh

# 初始化全部三个
./setup.sh all

# 或任意组合
./setup.sh claude
./setup.sh opencode codex
```

跨机前先刷新快照，再 commit + push：

```bash
./setup.sh sync                         # 收集最新的 codex 数据
git add .claude .opencode .codex
git commit -m "agent-sync: sync agent data"
git push
```

在新机器上：

```bash
git clone <你的仓库>
cd <你的仓库>
./setup.sh          # 重建软链 / 导入会话 / 恢复快照
```

## 原理

- **Claude Code** 把会话(和 auto-memory)存在 `~/.claude/projects/<编码路径>/`。`setup.sh` 把该目录**快照(复制)**进 `.claude/sessions/`，绝不软链，所以 `claude` 行为完全不变，同时转录进仓库供 git 同步。
- **opencode** 的会话在全局 sqlite 里，无法按项目软链。`setup.sh` 装一个 cwd 感知的 `oc` 包装函数（通过 `.agent-sync` 标记定位最近的项目）：启动 opencode，退出时把本项目会话导出到 `.opencode/sessions/` 并 git add。用 `oc`，不要裸跑 `opencode`。
- **Codex CLI** 的会话全局存在 `~/.codex/sessions/`(不按项目分)。`setup.sh` 按每个 rollout 里的 `cwd` 过滤，只把本项目的会话复制进 `.codex/sessions/`；全局的 `memories`/`skills` 用「双向 add-only 快照」，多项目不抢 `~/.codex`。

## 命令

```bash
./setup.sh                    # 显示帮助(无参数)
./setup.sh claude opencode    # 初始化任意组合
./setup.sh all                # 初始化全部三个
./setup.sh sync               # 收集最新 codex 数据(跨机前先跑,再 git commit+push)
./setup.sh oc                 # 启动 opencode，退出导出会话
./setup.sh --help             # 帮助
```

## 注意事项

- **开发期用私有仓库**——转录可能含密钥。
- codex 会话是快照，新会话需重跑 `./setup.sh codex` 才会被收录。
- `oc` 别名只往 `~/.zshrc` 写一行 alias(不写 key)，`source ~/.zshrc` 生效。
- 幂等，可重复运行。

## API key

`setup.sh` 不管理 API key。opencode 的 `oc` 别名复用 `ANTHROPIC_AUTH_TOKEN`，回退读 `~/.claude/settings.json`。每台机器配一次即可。
