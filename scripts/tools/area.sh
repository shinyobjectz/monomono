#!/usr/bin/env bash
# Top-level areas. An area is a folder with an AGENTS.md and a BUCK file.

source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  just area list
  just area add <name> [one-line purpose...]
USAGE
  exit 2
}

cmd_list() {
  local dir name
  printf '%s\t%s\n' area rules
  for dir in "$MONO_ROOT"/*/; do
    name=$(basename "$dir")
    [[ -f $dir/AGENTS.md ]] || continue
    printf '%s\t%s\n' "$name" "$(sed -n '3p' "$dir/AGENTS.md" | cut -c1-70)"
  done
}

cmd_add() {
  local name=${1-}
  [[ -n $name ]] || usage
  shift
  is_slug "$name" || die "area must be kebab-case: $name"
  local purpose="${*:-What this area owns.}"
  local dest="$MONO_ROOT/$name"
  [[ ! -e $dest ]] || die "already exists: $name/"
  mkdir -p "$dest"
  local title
  title=$(echo "$name" | sed -E 's/(^|-)([a-z])/\1\u\2/g' | tr '-' ' ')
  cat >"$dest/AGENTS.md" <<MD
# ${title}

${purpose}

## Rules

- Build outputs are buck2 targets in this tree's \`BUCK\` files. No ad-hoc build scripts.
- Dependencies come from \`packages/\`. Do not add a manifest or lockfile here.
- Reusable code belongs in \`library/\`; this area consumes it as a target.
- Keep this file under 200 lines. Add a nested \`AGENTS.md\` only when a subfolder has distinct rules.
MD
  cat >"$dest/BUCK" <<BUCK
# ${name}: targets for this area. See AGENTS.md.
BUCK
  echo "created $name/ (AGENTS.md, BUCK)"
  echo "next: add a row to .agents/AGENTS.md under Folders, and a just route if the area has verbs"
}

action=${1:-list}
shift || true
case "$action" in
  list) cmd_list ;;
  add) cmd_add "$@" ;;
  *) usage ;;
esac
