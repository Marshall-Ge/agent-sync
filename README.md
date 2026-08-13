# agent-sync

Single-file cross-machine sync for coding agents — keep your **memory**, **sessions**, and **skills** in sync across machines for [Claude Code](https://claude.com/claude-code), [opencode](https://opencode.ai), and [Codex CLI](https://github.com/openai/codex).

Copy the single `setup.sh` into your project, run it once, and your agents' state is stored inside the repo (git-tracked) so it follows you wherever you `git clone`.

> **Privacy:** session transcripts record everything you type — including API keys. Keep your project repo **private** while developing, and never commit secrets.

## What it syncs

| Agent | Sessions | Memory | Skills |
|-------|----------|--------|--------|
| Claude Code | `.claude/sessions/` (symlink) | auto-memory (under the same symlink) | `.claude/skills/` |
| opencode | `.opencode/sessions/` (export/import) | `.claude/memory/` | `.claude/skills/` |
| Codex CLI | `.codex/sessions/` (copy, cwd-filtered) | `.codex/memories/` (snapshot) | `.codex/skills/` (snapshot, `.system/` excluded) |

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
git commit -m "agent-sync: sync agent data"
```

On a new machine:

```bash
git clone <your-repo>
cd <your-repo>
./setup.sh          # re-creates the symlinks / imports sessions / restores snapshots
```

## How it works

- **Claude Code** stores sessions (and auto-memory) in `~/.claude/projects/<encoded-path>/`. `setup.sh` symlinks that directory to `.claude/sessions/`, so transcripts are written straight into the repo.
- **opencode** keeps sessions in a global sqlite DB that can't be symlinked per-project. `setup.sh` installs an `oc` alias that launches opencode and, on exit, exports this project's sessions to `.opencode/sessions/` and stages them in git.
- **Codex CLI** keeps sessions globally under `~/.codex/sessions/` (not per-project). `setup.sh` filters them by the `cwd` in each rollout and copies only this project's sessions into `.codex/sessions/`. Global `memories` and `skills` are snapshotted (add-only, both directions) so multiple projects don't fight over `~/.codex`.

## Commands

```bash
./setup.sh              # init all three
./setup.sh claude       # claude only
./setup.sh opencode     # opencode only
./setup.sh codex        # codex only
./setup.sh oc           # launch opencode, export sessions on exit
./setup.sh --help       # help
```

## Caveats

- **Use a private repo** while developing — transcripts can contain secrets.
- Codex sessions are picked up by re-running `./setup.sh codex` (they're snapshots, not live).
- The `oc` alias writes only an alias line to `~/.zshrc` (never a key). Run `source ~/.zshrc` to activate it.
- Idempotent: safe to re-run.

## API key

`setup.sh` does not manage API keys. For opencode, the `oc` alias reuses `ANTHROPIC_AUTH_TOKEN` from the environment, falling back to `~/.claude/settings.json`. Configure your key there once per machine.
