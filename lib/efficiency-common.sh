#!/usr/bin/env bash

ceh_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ceh_version_ge() {
  local actual="$1"
  local required="$2"

  if ceh_command_exists python3; then
    python3 - "$actual" "$required" <<'PY'
import re
import sys


def parts(value):
    return [int(x) for x in re.findall(r"\d+", value)]


actual = parts(sys.argv[1])
required = parts(sys.argv[2])
length = max(len(actual), len(required))
actual += [0] * (length - len(actual))
required += [0] * (length - len(required))
sys.exit(0 if actual >= required else 1)
PY
    return $?
  fi

  local first
  first="$(printf '%s\n%s\n' "$required" "$actual" | sort -V | head -n 1)"
  [ "$first" = "$required" ]
}

ceh_repo_root() {
  local start="${1:-$PWD}"
  local root
  if root="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s\n' "$root"
    return 0
  fi
  if [ -d "$start" ]; then
    (cd "$start" && pwd -P)
  else
    printf '%s\n' "$start"
  fi
}

ceh_has_codegraph_tools() {
  ceh_command_exists codegraph_explore &&
    ceh_command_exists codegraph_node &&
    ceh_command_exists codegraph_search
}

ceh_has_codegraph_index() {
  local repo="${1:-$PWD}"
  [ -d "$repo/.codegraph" ]
}

ceh_replace_marked_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local content_file="$4"
  local dry_run="${5:-true}"
  local tmp
  tmp="$(mktemp)"

  if [ -f "$file" ] && grep -Fq "$begin" "$file" && grep -Fq "$end" "$file"; then
    awk -v begin="$begin" -v end="$end" -v content_file="$content_file" '
      $0 == begin {
        print begin
        while ((getline line < content_file) > 0) print line
        close(content_file)
        in_block = 1
        next
      }
      $0 == end {
        print end
        in_block = 0
        next
      }
      !in_block { print }
    ' "$file" > "$tmp"
  else
    {
      [ -f "$file" ] && cat "$file"
      printf '\n%s\n' "$begin"
      cat "$content_file"
      printf '%s\n' "$end"
    } > "$tmp"
  fi

  if [ "$dry_run" = "true" ]; then
    if [ -f "$file" ]; then
      diff -u "$file" "$tmp" || true
    else
      diff -u /dev/null "$tmp" || true
    fi
    rm -f "$tmp"
  else
    mkdir -p "$(dirname "$file")"
    mv "$tmp" "$file"
  fi
}
