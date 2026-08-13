# agent-sync

总是在不同的主机上面开发同一个项目，苦于agent的历史session无法随项目迁移？这个工具让你不用每次在新主机上重开agent上下文对话。

单文件跨机同步工具 —— 让 [Claude Code](https://claude.com/claude-code)、[opencode](https://opencode.ai)、[Codex CLI](https://github.com/openai/codex) 的 **memory / sessions / skills** 在多台机器间保持一致。

把单个 `setup.sh` 拷进你的项目,运行一次,这些 agent 的状态就存进仓库(git 跟踪),跟着 `git clone` 到处走。

## 同步什么

| Agent | Sessions | Memory | Skills |
|-------|----------|--------|--------|
| Claude Code | `.claude/sessions/`(软链) | auto-memory(同一软链下) | `.claude/skills/` |
| opencode | `.opencode/sessions/`(导入导出) | `.claude/memory/` | `.claude/skills/`(经 `opencode.json`) |
| Codex CLI | `.codex/sessions/`(软链) | `.codex/memories/`(软链) | `.codex/skills/`(软链) |

## 快速开始

```bash
# 把 setup.sh 拷进项目根目录
cp /path/to/agent-sync/setup.sh ./setup.sh
chmod +x setup.sh

# 运行(无参数 = 三个 agent 全量)
./setup.sh

# 或指定子集
./setup.sh claude
./setup.sh opencode codex
```

然后把生成的目录提交进 git,实现共享:

```bash
git add .claude .opencode .codex
git commit -m "agent-sync: init sync dirs"
```

在新机器上只需:

```bash
git clone <你的仓库>
cd <你的仓库>
./setup.sh          # 重新建立软链 / 导入会话
```

## 原理

- **Claude Code** 把会话(和 auto-memory)存在 `~/.claude/projects/<编码路径>/`。`setup.sh` 把该目录软链到 `.claude/sessions/`,转录内容直接写进仓库。
- **opencode** 的会话存在全局 sqlite 里,无法按项目软链。`setup.sh` 装一个 `oc` 别名:启动 opencode,退出时把本项目会话导出到 `.opencode/sessions/` 并 git add。
- **Codex CLI** 的状态在 `~/.codex/` 下。`setup.sh` 把 `sessions`、`memories`、`skills` 软链进 `.codex/`。

## 命令

```bash
./setup.sh              # 初始化全部三个
./setup.sh claude       # 只 claude
./setup.sh opencode     # 只 opencode
./setup.sh codex        # 只 codex
./setup.sh oc           #(别名目标)启动 opencode,退出时导出会话
./setup.sh --help       # 帮助
```

## 注意事项

- **codex 状态是全局的**(`~/.codex/` 不按项目分)。codex 这一步只在一个「主项目」里跑,否则多项目会话会互相混。
- **会话可能含密钥。** 转录会记录你输入的一切——包括 API key。绝不要把 key 粘进对话,把它们放在环境变量 / `~/.claude/settings.json` 里。`setup.sh` 不写、不存任何 key。
- `oc` 别名只往 `~/.zshrc` 写一行 alias(不写 key),运行 `source ~/.zshrc` 生效。
- 幂等,可重复运行。

## API key

`setup.sh` 不管理 API key。opencode 的 `oc` 别名复用环境变量 `ANTHROPIC_AUTH_TOKEN`,回退读 `~/.claude/settings.json`。每台机器配置一次即可。
