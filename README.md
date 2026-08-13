# agent-sync

Single-file cross-machine sync for coding agents — keep your **memory**, **sessions**, and **skills** in sync across machines for [Claude Code](https://claude.com/claude-code), [opencode](https://opencode.ai), and [Codex CLI](https://github.com/openai/codex).

Sessions and memory can contain secrets, so they live in **one private vault repo** (`~/.agent-vault`), not in your project repos. Each agent's real storage location is symlinked into the vault; only non-sensitive skills and project memory stay in the project.

## How it works

```
~/.agent-vault/                          # PRIVATE git repo
├── claude/<encoded>/                    # per-project Claude sessions + auto-memory
├── codex/{sessions,memories,skills}/    # global codex state
└── opencode/<encoded>/                  # per-project opencode exports
```

```
~/.claude/projects/<encoded>  ->  ~/.agent-vault/claude/<encoded>/
~/.codex/sessions             ->  ~/.agent-vault/codex/sessions/
~/.codex/memories             ->  ~/.agent-vault/codex/memories/
~/.codex/skills               ->  ~/.agent-vault/codex/skills/
```

## Quick start

```bash
# 1. make the vault a private repo (one time)
mkdir -p ~/.agent-vault && git -C ~/.agent-vault init
#   ... create a PRIVATE GitHub repo and add it as remote ...

# 2. copy setup.sh into your project root and run it
cp /path/to/agent-sync/setup.sh ./setup.sh
./setup.sh              # or: ./setup.sh claude / opencode / codex
```

On a new machine:

```bash
git clone <private-vault-url> ~/.agent-vault   # the vault
git clone <your-project> ...                    # the project
cd <your-project> && ./setup.sh                 # re-create the symlinks
```

## What stays where

| | Project repo (can be public) | Vault (must be PRIVATE) |
|---|---|---|
| Claude | `.claude/skills/`, `.claude/memory/` | sessions + auto-memory |
| opencode | — | exported sessions |
| Codex | — | sessions, memories, skills |

## Commands

```bash
./setup.sh              # init all three
./setup.sh claude       # claude only
./setup.sh opencode     # opencode only
./setup.sh codex        # codex only
./setup.sh oc           # launch opencode, export sessions to the vault
./setup.sh --help       # help
```

## Caveats

- **Keep the vault PRIVATE.** Transcripts record everything typed — including API keys. Never make `~/.agent-vault` public.
- The `oc` alias writes only an alias line to `~/.zshrc` (never a key). Run `source ~/.zshrc` to activate it.
- Idempotent: safe to re-run.
- Set `AGENT_VAULT` to override the vault location.

## API key

`setup.sh` does not manage API keys. For opencode, the `oc` alias reuses `ANTHROPIC_AUTH_TOKEN` from the environment, falling back to `~/.claude/settings.json`. Configure your key there once per machine.
