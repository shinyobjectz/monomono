#!/usr/bin/env bash
# Projects under context/projects/<slug>. A project is something you build or operate.

source "$(cd "$(dirname "$0")/../.." && pwd)/lib.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  just context project new <slug>
  just context project list
USAGE
  exit 2
}

cmd_new() {
  local slug=${1-}
  [[ -n $slug ]] || usage
  is_slug "$slug" || die "slug must be kebab-case: $slug"
  local dest="$MONO_PROJECTS/$slug"
  [[ ! -e $dest ]] || die "project already exists: $slug"
  mkdir -p "$dest/features"
  local title; title=$(echo "$slug" | tr '-' ' ')
  cat >"$dest/PROJECT.md" <<MD
---
name: ${slug}
title: ${title}
description: Use when working the ${title} project.
---

# ${title}

Something we build or operate. Features live in \`features/<slug>/\`. Keep this file under 200 lines.
MD
  echo "created context/projects/$slug"
  echo "next: just context feature new $slug <feature-slug>"
}

cmd_list() {
  printf '%s\t%s\n' project features
  local dir
  for dir in "$MONO_PROJECTS"/*/; do
    [[ -f $dir/PROJECT.md ]] || continue
    printf '%s\t%s\n' "$(basename "$dir")" "$(find "$dir/features" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
  done
}

action=${1:-list}
shift || true
case "$action" in
  new) cmd_new "$@" ;;
  list) cmd_list ;;
  *) usage ;;
esac
