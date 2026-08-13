#!/usr/bin/env bash
# agent-sync — single-file cross-machine sync for coding agents (vault edition).
#
# Session/memory transcripts can contain secrets, so they live in ONE private
# vault repo (~/.agent-vault by default), NOT in your project repos. Each agent's
# real storage location is symlinked into the vault:
#
#   claude   ~/.claude/projects/<encoded>            ->  $VAULT/claude/<encoded>/
#   codex    ~/.codex/{sessions,memories,skills}     ->  $VAULT/codex/...
#   opencode (exported)                              ->  $VAULT/opencode/<encoded>/
#
# Only non-sensitive project files stay in the project: .claude/skills/ and
# .claude/memory/. Make ~/.agent-vault a PRIVATE git repo and push it to sync.
#
# Usage (copy this file into your project root, then run):
#   ./setup.sh                  init all three
#   ./setup.sh claude           init claude only
#   ./setup.sh opencode         init opencode only
#   ./setup.sh codex            init codex only
#   ./setup.sh oc               launch opencode, then export sessions to the vault
#   ./setup.sh --help           this help
#
# Idempotent: safe to re-run. Never writes API keys.
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT="${AGENT_VAULT:-$HOME/.agent-vault}"

info() { printf '==> %s\n' "$*"; }
ok()   { printf '    [ok] %s\n' "$*"; }
warn() { printf '    [!!] %s\n' "$*" >&2; }

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"
}

# --- helpers ----------------------------------------------------------------

# Idempotent symlink: link path -> real dir inside the vault.
# If a real dir already exists at $link, merge its contents into the vault first.
ensure_symlink() {  # $1 = link path, $2 = real dir in vault
  local link="$1" real="$2"
  mkdir -p "$real"
  if [ -L "$link" ]; then
    ok "symlink already present: $link"
  elif [ -e "$link" ]; then
    warn "real dir at $link; merging into $real"
    cp -Rnp "$link/." "$real/" 2>/dev/null || true
    rm -rf "$link"
    ln -s "$real" "$link"
    ok "merged + symlinked: $link -> $real"
  else
    mkdir -p "$(dirname "$link")"
    ln -s "$real" "$link"
    ok "symlinked: $link -> $real"
  fi
}

# Idempotent zsh alias writer.
write_alias() {  # $1 = alias name, $2 = raw command
  local name="$1" cmd="$2" zshrc="$HOME/.zshrc"
  touch "$zshrc"
  python3 - "$zshrc" "$name" "$cmd" <<'PYEOF'
import re, sys
path, name, cmd = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
s = re.sub(rf'^alias {re.escape(name)}=.*\n', '', s, flags=re.M)
s = re.sub(rf'^# agent-sync: {re.escape(name)} alias\n', '', s, flags=re.M)
s = s.rstrip() + f"\n\n# agent-sync: {name} alias\nalias {name}='{cmd}'\n"
open(path, 'w').write(s)
PYEOF
  ok "alias $name -> $cmd  (run 'source ~/.zshrc' to activate)"
}

# Create a project dir with a one-line README so git tracks it even when empty.
seed_dir() {  # $1 = dir, $2 = description
  local dir="$1" desc="$2"
  mkdir -p "$dir"
  if [ ! -f "$dir/README.md" ]; then
    printf '# %s (agent-sync)\n\n%s\n' "$(basename "$dir")" "$desc" > "$dir/README.md"
    ok "created $dir/"
  else
    ok "$dir/ already exists"
  fi
}

# Ensure the vault exists and is a git repo.
init_vault() {
  mkdir -p "$VAULT"
  if [ ! -d "$VAULT/.git" ]; then
    git -C "$VAULT" init -q 2>/dev/null || true
    ok "initialized vault git repo: $VAULT"
  fi
  if [ ! -f "$VAULT/README.md" ]; then
    printf '# agent-vault\n\nPrivate store for coding-agent sessions/memory.\nKeep this repo PRIVATE — transcripts can contain secrets.\n' > "$VAULT/README.md"
  fi
}

# The encoded project path Claude Code uses as its per-project storage dir name.
encoded() { printf '%s' "$PROJECT" | sed 's|[^A-Za-z0-9]|-|g'; }

# --- claude -----------------------------------------------------------------

init_claude() {
  info "claude (Claude Code)"
  init_vault
  seed_dir "$PROJECT/.claude/skills" "Shared skills (non-secret, stays in the project)."
  seed_dir "$PROJECT/.claude/memory" "Project memory (non-secret, stays in the project)."
  mkdir -p "$VAULT/claude/$(encoded)"
  ensure_symlink "$HOME/.claude/projects/$(encoded)" "$VAULT/claude/$(encoded)"
}

# --- opencode ---------------------------------------------------------------

init_opencode() {
  info "opencode"
  init_vault
  local sess_dir="$VAULT/opencode/$(encoded)"
  mkdir -p "$sess_dir"
  if ! command -v opencode >/dev/null 2>&1; then
    warn "opencode not installed (brew install opencode-ai); skipping import"
  else
    local db="${OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}" n=0 id
    for f in "$sess_dir"/*.json; do
      [ -e "$f" ] || continue
      id="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("info",{}).get("id",""))' "$f" 2>/dev/null || true)"
      if [ -n "$id" ] && [ -f "$db" ] && sqlite3 "$db" "SELECT 1 FROM session WHERE id='$id';" 2>/dev/null | grep -q 1; then
        ok "skip existing session $id"; continue
      fi
      if opencode import "$f" >/dev/null 2>&1; then
        ok "imported session $id"; n=$((n+1))
      else
        warn "import failed: $(basename "$f")"
      fi
    done
    info "  imported $n opencode session(s)"
  fi
  write_alias oc "$PROJECT/setup.sh oc"
}

# --- codex ------------------------------------------------------------------

init_codex() {
  info "codex (Codex CLI)"
  init_vault
  mkdir -p "$VAULT/codex/sessions" "$VAULT/codex/memories" "$VAULT/codex/skills"
  ensure_symlink "$HOME/.codex/sessions" "$VAULT/codex/sessions"
  ensure_symlink "$HOME/.codex/memories" "$VAULT/codex/memories"
  ensure_symlink "$HOME/.codex/skills"   "$VAULT/codex/skills"
  if [ ! -f "$VAULT/codex/skills/.gitignore" ]; then
    printf '.system/\n' > "$VAULT/codex/skills/.gitignore"
    ok "gitignored $VAULT/codex/skills/.system/"
  fi
}

# --- oc launcher ------------------------------------------------------------

run_oc() {
  cd "$PROJECT"
  # Single source of truth for the key: env first, then ~/.claude/settings.json.
  if [ -z "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
    ANTHROPIC_AUTH_TOKEN="$(python3 -c 'import json,os;p=os.path.expanduser("~/.claude/settings.json");d=json.load(open(p)) if os.path.exists(p) else {};print(d.get("env",{}).get("ANTHROPIC_AUTH_TOKEN",""))' 2>/dev/null || true)"
  fi
  export ANTHROPIC_AUTH_TOKEN

  case "${1:-}" in
    run|serve|web|attach|export|import|models|session|agent|db|plugin|mcp|acp|stats|github|pr|upgrade|uninstall|completion|debug|providers|auth)
      opencode "$@" ;;
    *)
      opencode --auto "$@" ;;
  esac

  local db="$HOME/.local/share/opencode/opencode.db" sess_dir="$VAULT/opencode/$(encoded)" count=0 id
  mkdir -p "$sess_dir"
  if [ ! -f "$db" ]; then
    warn "no opencode db found; nothing exported"; return 0
  fi
  local ids
  ids="$(sqlite3 "$db" "SELECT id FROM session WHERE (directory = '$PROJECT' OR directory LIKE '$PROJECT/%') AND parent_id IS NULL ORDER BY time_updated DESC;")"
  for id in $ids; do
    if opencode export "$id" 2>/dev/null > "$sess_dir/$id.json" && [ -s "$sess_dir/$id.json" ]; then
      count=$((count+1))
    else
      warn "export failed for session $id"
    fi
  done
  if [ "$count" -gt 0 ]; then
    git -C "$VAULT" add "$sess_dir" 2>/dev/null || true
    if [ "${OC_AUTOCOMMIT:-0}" = "1" ]; then
      git -C "$VAULT" commit -m "sync opencode sessions ($(date +%F))" 2>/dev/null || true
      ok "exported + committed $count session(s) to vault"
    else
      ok "exported $count session(s) -> $sess_dir (staged in vault; set OC_AUTOCOMMIT=1 to auto-commit)"
    fi
  else
    info "no opencode sessions to export"
  fi
}

# --- dispatch ---------------------------------------------------------------

case "${1:-}" in
  --help|-h|help) usage; exit 0 ;;
  oc) shift; run_oc "$@"; exit 0 ;;
esac

if [ $# -eq 0 ]; then
  init_claude
  init_opencode
  init_codex
else
  for a in "$@"; do
    case "$a" in
      claude)   init_claude ;;
      opencode) init_opencode ;;
      codex)    init_codex ;;
      *) warn "unknown tool: $a"; usage; exit 1 ;;
    esac
  done
fi

echo
info "done. session data now lives in the vault: $VAULT"
info "commit skills/memory in the project, and the vault separately:"
info "  # project (non-secret)"
info "  git add .claude && git commit -m 'agent-sync: init project dirs'"
info "  # vault (private) — push to a PRIVATE remote to sync across machines"
info "  git -C $VAULT add -A && git -C $VAULT commit -m 'sync agent data'"
