#!/usr/bin/env bash
# Compose toolchains/BUCK from fragments. Nothing is assumed; each toolchain is added on purpose.

source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

FRAGMENTS="$MONO_HOME/toolchains"
TARGET="$MONO_TOOLCHAINS/BUCK"

usage() {
  cat >&2 <<'USAGE'
usage:
  just toolchain list            # toolchains declared in toolchains/BUCK
  just toolchain available       # fragments the package ships
  just toolchain add <name>      # append a fragment (loads hoisted to the top)
USAGE
  exit 2
}

cmd_list() {
  [[ -f $TARGET ]] || die "missing toolchains/BUCK"
  grep -E '^# monomono:toolchain ' "$TARGET" | awk '{print $3}'
  echo "--"
  grep -E '^\s*name\s*=' "$TARGET" | sed -E 's/.*name\s*=\s*"([^"]+)".*/toolchains\/\/:\1/'
}

cmd_available() {
  local f
  for f in "$FRAGMENTS"/*.BUCK; do
    printf '%-18s %s\n' "$(basename "$f" .BUCK)" "$(sed -n '1s/^# *//p' "$f")"
  done
}

cmd_add() {
  local name=${1-}
  [[ -n $name ]] || usage
  local frag="$FRAGMENTS/$name.BUCK"
  [[ -f $frag ]] || die "no fragment named $name (just toolchain available)"
  [[ -f $TARGET ]] || die "missing toolchains/BUCK"
  if grep -q "^# monomono:toolchain $name\$" "$TARGET"; then
    echo "toolchain $name already declared"
    return 0
  fi
  local loads body tmp
  loads=$(grep -E '^load\(' "$frag" || true)
  body=$(grep -vE '^load\(' "$frag" | sed '/^# /d')
  tmp=$(mktemp)
  {
    grep -E '^load\(' "$TARGET" || true
    [[ -n $loads ]] && printf '%s\n' "$loads"
  } | awk '!seen[$0]++' >"$tmp"
  {
    grep -vE '^load\(' "$TARGET"
    echo
    echo "# monomono:toolchain $name"
    printf '%s\n' "$body"
  } >>"$tmp"
  mv "$tmp" "$TARGET"
  echo "added toolchain $name to toolchains/BUCK"
}

action=${1:-list}
shift || true
case "$action" in
  list) cmd_list ;;
  available) cmd_available ;;
  add) cmd_add "$@" ;;
  *) usage ;;
esac
