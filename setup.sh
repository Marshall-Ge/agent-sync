#!/usr/bin/env bash
# agent-sync — single-file cross-machine sync for coding agents.
#
# Syncs memory / sessions / skills across machines for three agents:
#   claude   (Claude Code)  sessions + auto-memory -> symlink into .claude/sessions/
#   opencode (opencode)     sessions -> export/import into .opencode/sessions/ + `oc` alias
#   codex    (Codex CLI)    sessions/memories/skills -> symlink into .codex/
#
# Usage (copy this file into your project root, then run):
#   ./setup.sh                  init all three
#   ./setup.sh claude           init claude only
#   ./setup.sh opencode codex   init a subset
#   ./setup.sh oc               alias target: launch opencode, then export sessions to git
#   ./setup.sh --help           this help
#
# Idempotent: safe to re-run. Never writes API keys anywhere.
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() { printf '==> %s\n' "$*"; }
ok()   { printf '    [ok] %s\n' "$*"; }
warn() { printf '    [!!] %s\n' "$*" >&2; }

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"
}

# --- helpers ----------------------------------------------------------------

# Idempotent symlink: link path (in ~/.claude or ~/.codex) -> real dir inside repo.
# If a real dir already exists at $link, merge its contents into the repo first.
ensure_symlink() {  # $1 = link path, $2 = real dir in repo
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

# Create a dir with a one-line README so git tracks it even when empty.
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

# --- claude -----------------------------------------------------------------

init_claude() {
  info "claude (Claude Code)"
  seed_dir "$PROJECT/.claude/sessions" "Claude Code session transcripts + auto-memory. Symlinked from ~/.claude/projects/<encoded>."
  seed_dir "$PROJECT/.claude/skills"   "Shared skills; auto-loaded by Claude Code, referenced by opencode via skills.paths."
  seed_dir "$PROJECT/.claude/memory"   "Long-lived project notes; git-tracked."
  local encoded
  encoded="$(printf '%s' "$PROJECT" | sed 's|[^A-Za-z0-9]|-|g')"
  ensure_symlink "$HOME/.claude/projects/$encoded" "$PROJECT/.claude/sessions"
}

# --- opencode ---------------------------------------------------------------

init_opencode() {
  info "opencode"
  seed_dir "$PROJECT/.opencode/sessions" "Exported opencode sessions (JSON). Auto-exported by the oc alias after each run."
  if ! command -v opencode >/dev/null 2>&1; then
    warn "opencode not installed (brew install opencode-ai); skipping import"
  else
    local db="${OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}" n=0 id
    for f in "$PROJECT"/.opencode/sessions/*.json; do
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
  seed_dir "$PROJECT/.codex/sessions"  "Codex CLI rollout transcripts. Symlinked from ~/.codex/sessions."
  seed_dir "$PROJECT/.codex/memories"  "Codex CLI long-term memory. Symlinked from ~/.codex/memories."
  seed_dir "$PROJECT/.codex/skills"    "Codex CLI skills. Symlinked from ~/.codex/skills."
  warn "codex state under ~/.codex is GLOBAL (not per-project); run this in one primary project"
  ensure_symlink "$HOME/.codex/sessions" "$PROJECT/.codex/sessions"
  ensure_symlink "$HOME/.codex/memories" "$PROJECT/.codex/memories"
  ensure_symlink "$HOME/.codex/skills"   "$PROJECT/.codex/skills"
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

  local db="$HOME/.local/share/opencode/opencode.db" sess_dir="$PROJECT/.opencode/sessions" count=0 id
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
    git add "$sess_dir" 2>/dev/null || true
    if [ "${OC_AUTOCOMMIT:-0}" = "1" ]; then
      git commit -m "sync opencode sessions ($(date +%F))" 2>/dev/null || true
      ok "exported + committed $count session(s)"
    else
      ok "exported $count session(s) -> .opencode/sessions/ (staged; set OC_AUTOCOMMIT=1 to auto-commit)"
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
info "done. commit the created dirs to git to share them across machines:"
info "  git add .claude .opencode .codex && git commit -m 'agent-sync: init sync dirs'"
