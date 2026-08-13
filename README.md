# agent-sync

Single-file cross-machine sync for coding agents — keep your **memory**, **sessions**, and **skills** in sync across machines for [Claude Code](https://claude.com/claude-code), [opencode](https://opencode.ai), [Codex CLI](https://github.com/openai/codex), and [dsh](https://github.com/deepseek-ai/deepseek-harness) (DeepSeek Harness).

Copy the single `setup.sh` into your project, run it once, and your agents' state is stored inside the repo (git-tracked) so it follows you wherever you `git clone`.

> **Privacy:** session transcripts record everything you type — including API keys. Keep your project repo **private** while developing, and never commit secrets.

## What it syncs

| Agent | Sessions | Memory | Skills |
|-------|----------|--------|--------|
| Claude Code | `.claude/sessions/` (snapshot) | auto-memory (under the same snapshot) | `.claude/skills/` |
| opencode | `.opencode/sessions/` (export/import) | `.claude/memory/` | `.claude/skills/` |
| Codex CLI | `.codex/sessions/` (copy, cwd-filtered) | `.codex/memories/` (snapshot) | `.codex/skills/` (snapshot, `.system/` excluded) |
| dsh (DeepSeek Harness) | `.dsh/sessions/` (snapshot) | — | — |

## Quick start

```bash
# copy setup.sh into your project root
cp /path/to/agent-sync/setup.sh ./setup.sh
chmod +x setup.sh

# init all four
./setup.sh all

# or any combination
./setup.sh claude
./setup.sh opencode codex dsh
```

Before switching machines, refresh the snapshots then commit + push:

```bash
./setup.sh sync                         # collect the latest agent data
git add .claude .opencode .codex .dsh
git commit -m "agent-sync: sync agent data"
git push
```

On a new machine:

```bash
git clone <your-repo>
cd <your-repo>
./setup.sh          # restores snapshots / imports sessions
```

## How it works

- **Claude Code** stores sessions (and auto-memory) in `~/.claude/projects/<encoded-path>/`. `setup.sh` snapshots that directory into `.claude/sessions/` (copies, never symlinks), so `claude` keeps working exactly as before while the transcripts land in the repo for git.
- **opencode** keeps sessions in a global sqlite DB that can't be symlinked per-project. `setup.sh` installs a cwd-aware `oc` wrapper (finds the nearest project via the `.agent-sync` marker) that launches opencode and, on exit, exports this project's sessions to `.opencode/sessions/` and stages them in git. Use `oc`, not bare `opencode`.
- **Codex CLI** keeps sessions globally under `~/.codex/sessions/` (not per-project). `setup.sh` filters them by the `cwd` in each rollout and copies only this project's sessions into `.codex/sessions/`. Global `memories` and `skills` are snapshotted (add-only, both directions) so multiple projects don't fight over `~/.codex`.
- **dsh (DeepSeek Harness)** stores sessions per-project under `~/.dsh/sessions/<projectKey>/` (zstd-compressed JSONL). `setup.sh` snapshots that directory into `.dsh/sessions/` (copies, never symlinks).

## Commands

```bash
./setup.sh                          # show help (no args)
./setup.sh claude opencode dsh      # init any combination
./setup.sh all                      # init all four
./setup.sh sync                     # collect latest agent data (run before commit+push)
./setup.sh oc                       # launch opencode, export sessions on exit
./setup.sh --help                   # help
```

## Caveats

- **Use a private repo** while developing — transcripts can contain secrets.
- Codex sessions are picked up by re-running `./setup.sh codex` (they're snapshots, not live).
- The `oc` alias writes only an alias line to `~/.zshrc` (never a key). Run `source ~/.zshrc` to activate it.
- Idempotent: safe to re-run.

## API key

`setup.sh` does not manage API keys. For opencode, the `oc` alias reuses `ANTHROPIC_AUTH_TOKEN` from the environment, falling back to `~/.claude/settings.json`. Configure your key there once per machine.
