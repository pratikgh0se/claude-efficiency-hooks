#!/usr/bin/env bash
# Idempotent installer for Claude/Codex efficiency autopilot.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/efficiency-common.sh
. "$SCRIPT_DIR/lib/efficiency-common.sh"

REPO="$PWD"
DRY_RUN_DEFAULT=true
DRY_RUN=true
APPLY=false
INSTALL_TOOLS=false
SKIP_TOOL_INSTALL=false
PORTABLE=false
INIT_REPO=""
BEGIN_MARKER="<!-- BEGIN claude-efficiency-hooks -->"
END_MARKER="<!-- END claude-efficiency-hooks -->"
BACKUP_ROOT="$HOME/.claude-efficiency-hooks/backups"
BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d%H%M%S)"

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --dry-run              Preview writes and tool actions
  --apply                Apply user-level Claude setup
  --install-tools        Audit known tool installs; run only with approval
  --skip-tool-install    Skip tool install audit in apply/init modes
  --portable             Print new-laptop bootstrap commands
  --repo PATH            Repository used for dry-run/apply context
  --init-repo PATH       Initialize a target repo with instructions/hooks
  -h, --help             Show help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      DRY_RUN_DEFAULT=false
      shift
      ;;
    --apply)
      APPLY=true
      DRY_RUN=false
      DRY_RUN_DEFAULT=false
      shift
      ;;
    --install-tools)
      INSTALL_TOOLS=true
      shift
      ;;
    --skip-tool-install)
      SKIP_TOOL_INSTALL=true
      shift
      ;;
    --portable)
      PORTABLE=true
      shift
      ;;
    --repo)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      REPO="$2"
      shift 2
      ;;
    --init-repo)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      INIT_REPO="$2"
      if [ "$DRY_RUN_DEFAULT" = "true" ]; then
        DRY_RUN=false
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

REPO="$(ceh_repo_root "$REPO")"

log() {
  printf '%s\n' "$*"
}

planned() {
  if [ "$DRY_RUN" = "true" ]; then
    printf 'DRY RUN: %s\n' "$*"
  else
    printf '%s\n' "$*"
  fi
}

ensure_parent() {
  local path="$1"
  if [ "$DRY_RUN" = "true" ]; then
    planned "mkdir -p $(dirname "$path")"
  else
    mkdir -p "$(dirname "$path")"
  fi
}

backup_file() {
  local path="$1"
  [ -f "$path" ] || return 0
  if [ "$DRY_RUN" = "true" ]; then
    planned "backup $path"
    return 0
  fi
  mkdir -p "$BACKUP_DIR"
  cp "$path" "$BACKUP_DIR/$(basename "$path").bak"
}

copy_file() {
  local src="$1"
  local dst="$2"
  if [ "$DRY_RUN" = "true" ]; then
    planned "copy $src -> $dst"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  chmod +x "$dst"
}

merge_block() {
  local target="$1"
  local template="$2"
  planned "merge claude-efficiency-hooks block into $target"
  ensure_parent "$target"
  backup_file "$target"
  ceh_replace_marked_block "$target" "$BEGIN_MARKER" "$END_MARKER" "$template" "$DRY_RUN"
}

copy_skill_tree() {
  local src_root="$1"
  local dst_root="$2"
  [ -d "$src_root" ] || return 0
  if [ "$DRY_RUN" = "true" ]; then
    planned "copy skills $src_root -> $dst_root"
    return 0
  fi
  mkdir -p "$dst_root"
  cp -R "$src_root"/. "$dst_root"/
}

merge_claude_settings() {
  local settings="$HOME/.claude/settings.json"
  planned "merge Claude hook entries into $settings"
  ensure_parent "$settings"
  backup_file "$settings"
  if [ "$DRY_RUN" = "true" ]; then
    return 0
  fi

  python3 - "$settings" <<'PY'
import json
import os
import sys
import tempfile

path = sys.argv[1]
if os.path.exists(path):
    with open(path) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as error:
            raise SystemExit(f"Refusing to replace invalid JSON in {path}: {error}")
else:
    data = {}

hooks = data.setdefault("hooks", {})


def add(event, matcher, command, async_value=None):
    entries = hooks.setdefault(event, [])
    hook = {"type": "command", "command": command}
    if async_value is not None:
        hook["async"] = async_value
    item = {"matcher": matcher, "hooks": [hook]}
    for existing in entries:
        if existing.get("matcher") == matcher:
            existing_hooks = existing.setdefault("hooks", [])
            if not any(h.get("command") == command for h in existing_hooks):
                existing_hooks.append(hook)
            return
    entries.append(item)


home = "$HOME"
add("Stop", "*", f"{home}/.claude/hooks/context-monitor-stop.sh", False)
add("PreToolUse", "Bash", f"{home}/.claude/hooks/bash-cat-block.sh")
add("PreToolUse", "Read", f"{home}/.claude/hooks/reread-warn.sh")
add("PreToolUse", "Grep", f"{home}/.claude/hooks/graph-first-block.sh")
add("PreToolUse", "Glob", f"{home}/.claude/hooks/graph-first-block.sh")
add("PreToolUse", "Read", f"{home}/.claude/hooks/graph-first-block.sh")

os.makedirs(os.path.dirname(path), exist_ok=True)
fd, tmp_path = tempfile.mkstemp(
    dir=os.path.dirname(path), prefix=".claude-efficiency-hooks-", suffix=".tmp"
)
try:
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp_path, path)
except BaseException:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    raise
PY
}

install_hooks() {
  local hooks_dir="$HOME/.claude/hooks"
  local hook
  for hook in context-monitor-stop.sh bash-cat-block.sh reread-warn.sh graph-first-block.sh; do
    copy_file "$SCRIPT_DIR/$hook" "$hooks_dir/$hook"
  done
}

install_global() {
  planned "install claude-efficiency-hooks user setup"
  install_hooks
  copy_skill_tree "$SCRIPT_DIR/.claude/skills" "$HOME/.claude/skills"
  merge_block "$HOME/.claude/CLAUDE.md" "$SCRIPT_DIR/templates/claude-efficiency-block.md"
  merge_claude_settings
}

merge_codex_hooks() {
  local target_repo="$1"
  local target="$target_repo/.codex/hooks.json"
  planned "merge claude-efficiency-hooks hooks into $target"
  ensure_parent "$target"
  backup_file "$target"
  if [ "$DRY_RUN" = "false" ]; then
    python3 - "$target" "$SCRIPT_DIR/templates/codex-hooks.json" <<'PY'
import copy
import json
import os
import sys
import tempfile

path, template_path = sys.argv[1:3]

if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except json.JSONDecodeError as error:
        raise SystemExit(f"Refusing to replace invalid JSON in {path}: {error}")
else:
    data = {}

with open(template_path) as f:
    template = json.load(f)

if not isinstance(data, dict):
    raise SystemExit(f"Refusing to merge non-object JSON in {path}")
if not isinstance(template, dict) or not isinstance(template.get("hooks"), dict):
    raise SystemExit(f"Invalid Codex hook template: {template_path}")

hooks = data.setdefault("hooks", {})
if not isinstance(hooks, dict):
    raise SystemExit(f"Refusing to merge non-object hooks in {path}")

for event, template_entries in template["hooks"].items():
    entries = hooks.setdefault(event, [])
    if not isinstance(entries, list):
        raise SystemExit(f"Refusing to merge non-list {event} hooks in {path}")
    for template_entry in template_entries:
        matcher = template_entry.get("matcher")
        existing = next((entry for entry in entries if entry.get("matcher") == matcher), None)
        if existing is None:
            entries.append(copy.deepcopy(template_entry))
            continue
        existing_hooks = existing.setdefault("hooks", [])
        if not isinstance(existing_hooks, list):
            raise SystemExit(f"Refusing to merge malformed {event} hook entry in {path}")
        for hook in template_entry.get("hooks", []):
            if not any(current.get("command") == hook.get("command") for current in existing_hooks if isinstance(current, dict)):
                existing_hooks.append(copy.deepcopy(hook))

fd, tmp_path = tempfile.mkstemp(
    dir=os.path.dirname(path), prefix=".claude-efficiency-hooks-", suffix=".tmp"
)
try:
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp_path, path)
except BaseException:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    raise
PY
  fi
}

install_codex_helper_bundle() {
  local target_repo="$1"
  local target_dir="$target_repo/.codex/claude-efficiency-hooks"
  local helper
  for helper in bash-cat-block.sh graph-first-block.sh reread-warn.sh context-monitor-stop.sh; do
    copy_file "$SCRIPT_DIR/$helper" "$target_dir/$helper"
  done
  copy_file "$SCRIPT_DIR/lib/efficiency-common.sh" "$target_dir/lib/efficiency-common.sh"
}

write_codex_hooks() {
  local target_repo="$1"
  merge_codex_hooks "$target_repo"
  install_codex_helper_bundle "$target_repo"
}

init_repo() {
  local target_repo="$1"
  [ -d "$target_repo" ] || {
    if [ "$DRY_RUN" = "true" ]; then
      planned "mkdir -p $target_repo"
    else
      mkdir -p "$target_repo"
    fi
  }
  target_repo="$(cd "$target_repo" && pwd -P)"
  planned "initialize repo $target_repo"
  merge_block "$target_repo/CLAUDE.md" "$SCRIPT_DIR/templates/claude-efficiency-block.md"
  merge_block "$target_repo/AGENTS.md" "$SCRIPT_DIR/templates/agents-efficiency-block.md"
  write_codex_hooks "$target_repo"
  copy_skill_tree "$SCRIPT_DIR/.agents/skills" "$target_repo/.agents/skills"
  copy_skill_tree "$SCRIPT_DIR/.claude/skills" "$target_repo/.claude/skills"
}

rtk_version() {
  rtk --version 2>/dev/null | grep -Eo '[0-9]+([.][0-9]+)+' | sed -n '1p' || true
}

approval_required() {
  local name="$1"
  local command="$2"
  printf 'APPROVAL REQUIRED: %s\n' "$name"
  printf '  %s\n' "$command"
  if [ "$DRY_RUN" = "false" ] && [ "${CEH_APPROVE_TOOL_INSTALL:-false}" = "true" ]; then
    sh -c "$command"
  else
    printf '  Skipped. Re-run after approval with CEH_APPROVE_TOOL_INSTALL=true.\n'
  fi
}

tool_install_report() {
  local version
  log "Tool install audit"

  if ceh_command_exists rtk; then
    version="$(rtk_version)"
    if [ -n "$version" ] && ceh_version_ge "$version" "0.43.0"; then
      log "PASS RTK: $(rtk --version 2>/dev/null | sed -n '1p')"
    else
      approval_required "RTK >= 0.43.0" "curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh"
    fi
  else
    approval_required "RTK" "curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh"
  fi

  if ceh_command_exists caveman || [ -d "$HOME/.agents/skills/caveman" ] || [ -d "$HOME/.claude/skills/caveman" ]; then
    log "PASS Caveman: available"
  else
    approval_required "Caveman and Ponytail init" "curl -fsSL https://raw.githubusercontent.com/JuliusBrussee/caveman/main/src/tools/caveman-init.js | node -"
  fi

  log "Ponytail: installed as local instructions/skills by --apply and --init-repo."

  if jq -e '.graph.install.known_source == true and (.graph.install.command | length > 0)' "$SCRIPT_DIR/bootstrap/tools.json" >/dev/null 2>&1; then
    command="$(jq -r '.graph.install.command' "$SCRIPT_DIR/bootstrap/tools.json")"
    approval_required "CodeGraph" "$command"
  else
    log "CodeGraph: install source is not configured in bootstrap/tools.json; not installing."
  fi
}

portable_instructions() {
  cat <<EOF
New laptop flow:
1. git clone <this-repo-url> claude-efficiency-hooks
2. cd claude-efficiency-hooks
3. ./doctor.sh --repo .
4. ./install.sh --dry-run --repo .
5. ./install.sh --apply --install-tools --repo .
6. ./install.sh --init-repo /absolute/path/to/repo
EOF
}

if [ "$DRY_RUN" = "true" ]; then
  log "DRY RUN: claude-efficiency-hooks"
else
  log "APPLY: claude-efficiency-hooks"
fi
log "Repo: $REPO"

if [ "$PORTABLE" = "true" ]; then
  portable_instructions
fi

if [ "$APPLY" = "true" ]; then
  install_global
fi

if [ -n "$INIT_REPO" ]; then
  init_repo "$INIT_REPO"
fi

if [ "$INSTALL_TOOLS" = "true" ] && [ "$SKIP_TOOL_INSTALL" = "false" ]; then
  tool_install_report
fi

if [ "$APPLY" = "false" ] && [ -z "$INIT_REPO" ] && [ "$INSTALL_TOOLS" = "false" ] && [ "$PORTABLE" = "false" ]; then
  planned "merge claude-efficiency-hooks block into $HOME/.claude/CLAUDE.md"
  planned "copy hooks into $HOME/.claude/hooks"
  planned "merge Claude settings hooks"
fi
