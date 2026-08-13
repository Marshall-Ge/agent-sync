# agent-sync

总是在不同的主机上面开发同一个项目，苦于agent的历史session无法随项目迁移？这个工具让你不用每次在新主机上重开agent上下文对话。

单文件跨机同步工具 —— 让 [Claude Code](https://claude.com/claude-code)、[opencode](https://opencode.ai)、[Codex CLI](https://github.com/openai/codex) 的 **memory / sessions / skills** 在多台机器间保持一致。

会话和 memory 可能含密钥，所以它们只存在于**一个私有 vault 仓库**(`~/.agent-vault`)，不进你的项目仓库。各 agent 的真实存储位置软链进 vault；项目里只留非敏感的 skills 和 project memory。

## 原理

```
~/.agent-vault/                          # 私有 git 仓库
├── claude/<编码路径>/                    # 每个项目的 Claude session + auto-memory
├── codex/{sessions,memories,skills}/    # 全局 codex 状态
└── opencode/<编码路径>/                  # 每个项目导出的 opencode session
```

```
~/.claude/projects/<编码>  ->  ~/.agent-vault/claude/<编码>/
~/.codex/sessions          ->  ~/.agent-vault/codex/sessions/
~/.codex/memories          ->  ~/.agent-vault/codex/memories/
~/.codex/skills            ->  ~/.agent-vault/codex/skills/
```

## 快速开始

```bash
# 1. 让 vault 成为私有仓库(一次性)
mkdir -p ~/.agent-vault && git -C ~/.agent-vault init
#   ... 建一个【私有】GitHub 仓库并 add remote ...

# 2. 把 setup.sh 拷进项目根目录并运行
cp /path/to/agent-sync/setup.sh ./setup.sh
./setup.sh              # 或 ./setup.sh claude / opencode / codex
```

新机器上:

```bash
git clone <私有vault地址> ~/.agent-vault   # vault
git clone <项目地址> ...                    # 项目
cd <项目> && ./setup.sh                     # 重建软链
```

## 谁在哪

| | 项目仓库(可公开) | vault(必须私有) |
|---|---|---|
| Claude | `.claude/skills/`、`.claude/memory/` | sessions + auto-memory |
| opencode | — | 导出的 sessions |
| Codex | — | sessions、memories、skills |

## 命令

```bash
./setup.sh              # 初始化全部三个
./setup.sh claude       # 只 claude
./setup.sh opencode     # 只 opencode
./setup.sh codex        # 只 codex
./setup.sh oc           # 启动 opencode，退出导出会话到 vault
./setup.sh --help       # 帮助
```

## 注意事项

- **vault 必须私有。** 转录记录你输入的一切——包括 API key。绝不要把 `~/.agent-vault` 设成公开。
- `oc` 别名只往 `~/.zshrc` 写一行 alias(不写 key)，`source ~/.zshrc` 生效。
- 幂等，可重复运行。
- 可用 `AGENT_VAULT` 环境变量覆盖 vault 路径。

## API key

`setup.sh` 不管理 API key。opencode 的 `oc` 别名复用 `ANTHROPIC_AUTH_TOKEN`，回退读 `~/.claude/settings.json`。每台机器配一次即可。
