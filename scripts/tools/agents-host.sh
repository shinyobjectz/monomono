#!/usr/bin/env bash
# Expose .agents/AGENTS.md as the root AGENTS.md, then generate .agents/skills.
# Claude Code reads AGENTS.md in the repo; it does not read .agents/. Cursor and Codex read AGENTS.md.
# Never touches CLAUDE.md.

source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

source_rel=".agents/AGENTS.md"
source_abs="$MONO_ROOT/$source_rel"
link="$MONO_ROOT/AGENTS.md"
action="sync"
force=0

usage() {
  echo "usage: just agents [sync|status|skills|check] [--force]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    sync|status|skills|check) action=$1 ;;
    --force) force=1 ;;
    *) usage ;;
  esac
  shift
done

is_current() {
  if [[ -L $link ]]; then
    [[ $(readlink "$link") == "$source_rel" ]]
  elif [[ -f $link ]]; then
    cmp -s "$link" "$source_abs"
  else
    return 1
  fi
}

link_or_copy() {
  local tmp="$link.mono.$$"
  rm -f "$link"
  if ln -sfn "$source_rel" "$tmp" 2>/dev/null && [[ -L $tmp ]]; then
    mv -f "$tmp" "$link"
    echo "symlinked AGENTS.md -> $source_rel"
  else
    rm -f "$tmp"
    cp "$source_abs" "$link"
    echo "copied AGENTS.md (symlink unavailable)"
  fi
}

skills() {
  "$MONO_HOME/scripts/update/skills.sh" --root "$MONO_ROOT" "$@"
}

case "$action" in
  sync)
    [[ -f $source_abs ]] || die "missing $source_rel"
    if is_current && [[ $force -eq 0 ]]; then
      echo "AGENTS.md already tracks $source_rel"
    else
      link_or_copy
    fi
    skills
    ;;
  skills) skills ;;
  check) skills --check ;;
  status)
    echo "source    $source_rel"
    if [[ -L $link ]]; then echo "AGENTS.md symlink:$(readlink "$link")"
    elif [[ -f $link ]]; then echo "AGENTS.md copy"
    else echo "AGENTS.md missing"; fi
    echo "skills    $(find "$MONO_AGENTS/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ') SKILL.md"
    ;;
esac
