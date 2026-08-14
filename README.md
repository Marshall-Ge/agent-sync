# agent-sync

Single-file cross-machine sync for coding agents — keep your **memory**, **sessions**, and **skills** in sync across machines for [Claude Code](https://claude.com/claude-code), [opencode](https://opencode.ai), and [dsh](https://github.com/deepseek-ai/deepseek-harness) (DeepSeek Harness). [Codex CLI](https://github.com/openai/codex) is supported as an **experimental** feature.

Copy the single `setup.sh` into your project, run it once, and your agents' state is stored inside the repo (git-tracked) so it follows you wherever you `git clone`.

> **Privacy:** session transcripts record everything you type — including API keys. Keep your project repo **private** while developing, and never commit secrets.

## What it syncs

| Agent | Sessions | Memory | Skills | Status |
|-------|----------|--------|--------|--------|
| Claude Code | `.claude/sessions/` (snapshot) | auto-memory (under the same snapshot) | `.claude/skills/` | stable |
| opencode | `.opencode/sessions/` (export/import) | `.claude/memory/` | `.claude/skills/` | stable |
| dsh (DeepSeek Harness) | `.dsh/sessions/` (snapshot) | — | — | stable |
| Codex CLI | `.codex/sessions/` (copy, cwd-filtered) | `.codex/memories/` (snapshot) | `.codex/skills/` (snapshot, `.system/` excluded) | experimental |

## Quick start

```bash
# copy setup.sh into your project root
cp /path/to/agent-sync/setup.sh ./setup.sh
chmod +x setup.sh

# init the stable tools (claude + opencode + dsh)
./setup.sh all

# or any combination
./setup.sh claude
./setup.sh opencode dsh

# codex is experimental — enable it separately
./setup.sh codex
```

Before switching machines, refresh the snapshots then commit + push:

```bash
./setup.sh sync                         # collect latest data + re-import opencode
git add .claude .opencode .dsh          # (+ .codex if you enabled codex)
git commit -m "agent-sync: sync agent data"
git push
```

On a new machine:

```bash
git clone <your-repo>
cd <your-repo>
./setup.sh all    # restores snapshots / imports sessions
```

## How it works

- **Claude Code** stores sessions (and auto-memory) in `~/.claude/projects/<encoded-path>/`. `setup.sh` snapshots that directory into `.claude/sessions/` (copies, never symlinks), so `claude` keeps working exactly as before while the transcripts land in the repo for git.
- **opencode** keeps sessions in a global sqlite DB that can't be symlinked per-project. `setup.sh` installs a cwd-aware `oc` wrapper (finds the nearest project via the `.agent-sync` marker) that launches opencode and, on exit, exports this project's sessions to `.opencode/sessions/` and stages them in git. `setup.sh sync` also re-imports sessions that were updated on another machine. Use `oc`, not bare `opencode`.
- **dsh (DeepSeek Harness)** stores sessions per-project under `~/.dsh/sessions/<projectKey>/` (zstd-compressed JSONL). `setup.sh` snapshots that directory into `.dsh/sessions/` (copies, never symlinks).
- **Codex CLI (experimental)** keeps sessions globally under `~/.codex/`. `setup.sh codex` copies this project's sessions into `.codex/sessions/` and resets codex's `backfill_state` so the next `codex` launch re-indexes them. However, codex's newer "paginated" sessions store conversation content in a sqlite table, so content added by *continuing* a session on another machine may not sync back — this is why codex is opt-in and experimental.

## Commands

```bash
./setup.sh                    # show help (no args)
./setup.sh claude opencode    # init any combination
./setup.sh all                # init claude + opencode + dsh
./setup.sh codex              # init codex (experimental)
./setup.sh sync               # collect latest data (run before commit+push)
./setup.sh oc                 # launch opencode, export sessions on exit
./setup.sh --help             # help
```

## Caveats

- **Use a private repo** while developing — transcripts can contain secrets.
- **Codex is experimental**: `./setup.sh codex` prints a warning; its "continue" content sync is incomplete for new paginated sessions.
- The `oc` alias writes only an alias line to `~/.zshrc` (never a key). Run `source ~/.zshrc` to activate it.
- Idempotent: safe to re-run.

## API key

`setup.sh` does not manage API keys. For opencode, the `oc` alias reuses `ANTHROPIC_AUTH_TOKEN` from the environment, falling back to `~/.claude/settings.json`. Configure your key there once per machine.
