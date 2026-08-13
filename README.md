# agent-sync

Single-file cross-machine sync for coding agents — keep your **memory**, **sessions**, and **skills** in sync across machines for [Claude Code](https://claude.com/claude-code), [opencode](https://opencode.ai), and [Codex CLI](https://github.com/openai/codex).

Copy the single `setup.sh` into your project, run it once, and your agents' state is stored inside the repo (git-tracked) so it follows you wherever you `git clone`.

## What it syncs

| Agent | Sessions | Memory | Skills |
|-------|----------|--------|--------|
| Claude Code | `.claude/sessions/` (symlink) | auto-memory (under the same symlink) | `.claude/skills/` |
| opencode | `.opencode/sessions/` (export/import) | `.claude/memory/` | `.claude/skills/` (via `opencode.json`) |
| Codex CLI | `.codex/sessions/` (copy, filtered by cwd) | `.codex/memories/` (symlink) | `.codex/skills/` (symlink, `.system/` excluded) |

## Quick start

```bash
# copy setup.sh into your project root
cp /path/to/agent-sync/setup.sh ./setup.sh
chmod +x setup.sh

# run it (no args = all three agents)
./setup.sh

# or pick a subset
./setup.sh claude
./setup.sh opencode codex
```

Then commit the generated directories so they're shared:

```bash
git add .claude .opencode .codex
git commit -m "agent-sync: init sync dirs"
```

On a new machine, just:

```bash
git clone <your-repo>
cd <your-repo>
./setup.sh          # re-creates the symlinks / imports sessions locally
```

## How it works

- **Claude Code** stores sessions (and auto-memory) in `~/.claude/projects/<encoded-path>/`. `setup.sh` symlinks that directory to `.claude/sessions/`, so transcripts are written straight into the repo.
- **opencode** keeps sessions in a global sqlite DB that can't be symlinked per-project. `setup.sh` installs an `oc` alias that launches opencode and, on exit, exports this project's sessions to `.opencode/sessions/` and stages them in git.
- **Codex CLI** keeps state under `~/.codex/`. Sessions are stored globally (not per-project), so `setup.sh` filters them by the `cwd` recorded in each rollout and copies only this project's sessions into `.codex/sessions/`; it symlinks `memories` and `skills` (excluding the bundled `.system/` skills).

## Commands

```bash
./setup.sh              # init all three
./setup.sh claude       # claude only
./setup.sh opencode     # opencode only
./setup.sh codex        # codex only
./setup.sh oc           # (alias target) launch opencode, export sessions on exit
./setup.sh --help       # help
```

## Caveats

- **Codex sessions are filtered per-project** (by the `cwd` in each rollout), but `memories` are global by design (a single long-term memory). New codex sessions are only picked up when you re-run `./setup.sh codex`.
- **Sessions may contain secrets.** Transcripts record everything typed — including API keys. Never paste keys into chat; keep them in env vars / `~/.claude/settings.json`. `setup.sh` never writes or stores keys.
- The `oc` alias writes only an alias line to `~/.zshrc` (never a key). Run `source ~/.zshrc` to activate it.
- Idempotent: safe to re-run.

## API key

`setup.sh` does not manage API keys. For opencode, the `oc` alias reuses `ANTHROPIC_AUTH_TOKEN` from the environment, falling back to `~/.claude/settings.json`. Configure your key there once per machine.
