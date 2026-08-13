#!/usr/bin/env bash
# agent-sync — single-file cross-machine sync for coding agents.
#
# Syncs memory / sessions / skills across machines for three agents:
#   claude   (Claude Code)  sessions + auto-memory -> symlink into .claude/sessions/
#   opencode (opencode)     sessions -> export/import into .opencode/sessions/ + `oc` alias
#   codex    (Codex CLI)    sessions -> copy filtered by cwd; memories/skills -> snapshot
#
# Usage (copy this file into your project root, then run):
#   ./setup.sh                              show this help (no args -> help)
#   ./setup.sh claude [opencode] [codex]    init any combination of tools
#   ./setup.sh all                          init all three
#   ./setup.sh sync                         collect latest codex data (run BEFORE git commit+push)
#   ./setup.sh oc                           wrapper: launch opencode, then export sessions to git
#   ./setup.sh --help                       this help
#
# Idempotent: safe to re-run. Never writes API keys.
#
# PRIVACY: session transcripts record everything you type (including API keys).
# Use a PRIVATE repo for this project while developing; don't push the synced
# .claude/sessions, .opencode/sessions or .codex/sessions to a public repo.
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() { printf '==> %s\n' "$*"; }
ok()   { printf '    [ok] %s\n' "$*"; }
warn() { printf '    [!!] %s\n' "$*" >&2; }

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"
}

# --- helpers ----------------------------------------------------------------

# Idempotent symlink: link path (in ~/.claude) -> real dir inside the project.
ensure_symlink() {  # $1 = link path, $2 = real dir in project
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

# Idempotent cwd-aware `oc` wrapper: finds the nearest agent-sync project from
# $PWD (via the .agent-sync marker) and runs its setup.sh oc. No single global
# alias fighting over which project it points to.
write_oc_func() {
  local zshrc="$HOME/.zshrc"
  touch "$zshrc"
  python3 - "$zshrc" <<'PYEOF'
import re, sys
path = sys.argv[1]
s = open(path).read()
s = re.sub(r'^alias oc=.*\n', '', s, flags=re.M)
s = re.sub(r'^# >>> agent-sync: oc >>>\n.*?^# <<< agent-sync: oc <<<\n', '', s, flags=re.M | re.S)
block = (
    '# >>> agent-sync: oc >>>\n'
    'oc() {\n'
    '  local p="$PWD"\n'
    '  while [ "$p" != "/" ]; do\n'
    '    if [ -f "$p/.agent-sync" ]; then\n'
    '      "$p/setup.sh" oc "$@"; return $?\n'
    '    fi\n'
    '    p="$(dirname "$p")"\n'
    '  done\n'
    '  echo "oc: not in an agent-sync project (run setup.sh first)" >&2\n'
    '  return 1\n'
    '}\n'
    '# <<< agent-sync: oc <<<\n'
)
s = s.rstrip() + "\n\n" + block
open(path, 'w').write(s)
PYEOF
  ok "wrote cwd-aware oc() to ~/.zshrc  (run 'source ~/.zshrc' to activate)"
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

# Bidirectional add-only snapshot of a GLOBAL dir into the project (no symlink,
# so multiple projects don't fight over ~/.codex/...).
sync_global_dir() {  # $1 = global dir, $2 = project dir
  local g="$1" p="$2"
  mkdir -p "$g" "$p"
  cp -Rnp "$g/." "$p/" 2>/dev/null || true   # global -> project (add missing)
  cp -Rnp "$p/." "$g/" 2>/dev/null || true   # project -> global (restore on new machine)
  ok "snapshot synced: $p"
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
  touch "$PROJECT/.agent-sync"
  write_oc_func
}

# --- codex ------------------------------------------------------------------

init_codex() {
  info "codex (Codex CLI)"
  seed_dir "$PROJECT/.codex/sessions"  "Codex CLI sessions for THIS project only (filtered by cwd)."
  seed_dir "$PROJECT/.codex/memories"  "Snapshot of global ~/.codex/memories."
  seed_dir "$PROJECT/.codex/skills"    "Snapshot of global ~/.codex/skills (bundled .system/ gitignored)."

  # memories + skills are global per-user; snapshot them (no symlink, no competition).
  sync_global_dir "$HOME/.codex/memories" "$PROJECT/.codex/memories"
  sync_global_dir "$HOME/.codex/skills"   "$PROJECT/.codex/skills"
  if [ ! -f "$PROJECT/.codex/skills/.gitignore" ]; then
    printf '.system/\n' > "$PROJECT/.codex/skills/.gitignore"
    ok "gitignored .codex/skills/.system/"
  fi

  # sessions: codex stores them globally (not per-project), so filter by cwd
  # and COPY only this project's rollouts into the repo.
  sync_codex_sessions
}

# Print the cwd recorded in a rollout's session_meta line (empty if none).
codex_rollout_cwd() {  # $1 = rollout jsonl path
  python3 - "$1" <<'PYEOF'
import json, sys
cwd = ""
for line in open(sys.argv[1], errors="replace"):
    if '"session_meta"' not in line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("type") == "session_meta":
        cwd = d.get("payload", {}).get("cwd") or ""
        break
print(cwd)
PYEOF
}

sync_codex_sessions() {
  local src="$HOME/.codex/sessions" dst="$PROJECT/.codex/sessions" n=0 cwd name
  if [ ! -d "$src" ] || [ -L "$src" ]; then
    warn "~/.codex/sessions missing or is a symlink (left by an old agent-sync); restore it, then re-run"
    return 0
  fi
  mkdir -p "$dst"
  while IFS= read -r f; do
    cwd="$(codex_rollout_cwd "$f")"
    if [ -n "$cwd" ] && { [ "$cwd" = "$PROJECT" ] || [[ "$cwd" == "$PROJECT/"* ]]; }; then
      name="$(basename "$f")"
      if [ ! -e "$dst/$name" ]; then
        cp -p "$f" "$dst/$name"
        n=$((n+1))
      fi
    fi
  done < <(find -L "$src" -name 'rollout-*.jsonl' 2>/dev/null)
  ok "copied $n codex session(s) for this project (re-run to pick up new ones)"
}

# --- sync -------------------------------------------------------------------

# Collect the latest agent data before you commit + push. claude/opencode are
# already live (symlink / export-on-exit); only codex needs re-scanning. No git
# commands run here — commit + push manually afterwards.
sync_all() {
  info "sync (collect latest agent data)"
  sync_global_dir "$HOME/.codex/memories" "$PROJECT/.codex/memories"
  sync_global_dir "$HOME/.codex/skills"   "$PROJECT/.codex/skills"
  sync_codex_sessions
  info "claude / opencode already live — nothing to collect."
  echo
  info "now commit + push manually to sync across machines:"
  info "  git add .claude .opencode .codex && git commit -m 'sync agent data' && git push"
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

if [ $# -eq 0 ]; then
  usage; exit 0
fi

case "${1:-}" in
  --help|-h|help) usage; exit 0 ;;
  oc) shift; run_oc "$@"; exit 0 ;;
  sync) sync_all; exit 0 ;;
esac

for a in "$@"; do
  case "$a" in
    claude)   init_claude ;;
    opencode) init_opencode ;;
    codex)    init_codex ;;
    all)      init_claude; init_opencode; init_codex ;;
    *) warn "unknown tool: $a"; usage; exit 1 ;;
  esac
done

echo
info "done. 完成。"
info "usage / 用法:"
info "  claude / codex  -> 直接运行 (run directly)"
info "  opencode        -> 用 'oc' 运行,不要跑 opencode，需要做一层包装 (use 'oc', NOT bare 'opencode')"
info "  keep this repo PRIVATE while developing / 开发期请用私有仓库 — 待开发完成后删除跨级共享session"
