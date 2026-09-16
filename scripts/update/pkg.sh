#!/usr/bin/env bash
# Ecosystems live under packages/<eco>. Each has an adapter: packages/<eco>/.eco names a shipped
# adapter (adapters/<name>.sh) or packages/<eco>/adapter.sh is a local one. Adapters implement
# ensure | add | update | sync with PKG_DIR set. Nothing is assumed about which ecosystems exist.

source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  just pkg                           # ecosystems and their adapters
  just pkg adapters                  # adapters the package ships
  just pkg init <eco> <adapter>      # packages/<eco> managed by <adapter>
  just pkg add <eco> <name...>
  just pkg update <eco> [name...]
  just pkg sync [eco]
  just pkg ensure                    # every ecosystem: create manifests if missing
USAGE
  exit 2
}

adapter_for() {
  local eco=$1 dir="$MONO_PACKAGES/$1"
  if [[ -x $dir/adapter.sh ]]; then
    echo "$dir/adapter.sh"
  elif [[ -f $dir/.eco ]]; then
    local name
    name=$(tr -d '[:space:]' <"$dir/.eco")
    [[ -f $MONO_HOME/adapters/$name.sh ]] || die "packages/$eco names unknown adapter: $name"
    echo "$MONO_HOME/adapters/$name.sh"
  else
    return 1
  fi
}

run_adapter() {
  local eco=$1 verb=$2
  shift 2
  local adapter
  adapter=$(adapter_for "$eco") || die "packages/$eco has no adapter (just pkg init $eco <adapter>)"
  PKG_DIR="$MONO_PACKAGES/$eco" PKG_ECO="$eco" MONO_ROOT="$MONO_ROOT" bash "$adapter" "$verb" "$@"
}

cmd_list() {
  printf '%s\t%s\n' eco adapter
  local dir
  for dir in "$MONO_PACKAGES"/*/; do
    [[ -d $dir && $(basename "$dir") != monomono ]] || continue
    local eco name="none"
    eco=$(basename "$dir")
    [[ -x $dir/adapter.sh ]] && name="local"
    [[ -f $dir/.eco ]] && name=$(tr -d '[:space:]' <"$dir/.eco")
    printf '%s\t%s\n' "$eco" "$name"
  done
}

cmd_adapters() {
  local f
  for f in "$MONO_HOME"/adapters/*.sh; do
    printf '%-8s %s\n' "$(basename "$f" .sh)" "$(sed -n '2s/^# *//p' "$f")"
  done
}

cmd_init() {
  local eco=${1-} adapter=${2-}
  [[ -n $eco && -n $adapter ]] || usage
  is_slug "$eco" || die "eco must be kebab-case: $eco"
  [[ -f $MONO_HOME/adapters/$adapter.sh ]] || die "unknown adapter: $adapter (just pkg adapters)"
  mkdir -p "$MONO_PACKAGES/$eco"
  echo "$adapter" >"$MONO_PACKAGES/$eco/.eco"
  run_adapter "$eco" ensure
  echo "packages/$eco managed by $adapter"
}

cmd_ensure() {
  local dir
  for dir in "$MONO_PACKAGES"/*/; do
    [[ -d $dir && $(basename "$dir") != monomono ]] || continue
    adapter_for "$(basename "$dir")" >/dev/null 2>&1 || continue
    run_adapter "$(basename "$dir")" ensure
  done
}

action=${1:-list}
shift || true
case "$action" in
  list) cmd_list ;;
  adapters) cmd_adapters ;;
  init) cmd_init "$@" ;;
  add|update) eco=${1-}; [[ -n $eco ]] || usage; shift; run_adapter "$eco" "$action" "$@" ;;
  sync)
    if [[ -n ${1-} ]]; then run_adapter "$1" sync
    else for dir in "$MONO_PACKAGES"/*/; do [[ -d $dir && $(basename "$dir") != monomono ]] && adapter_for "$(basename "$dir")" >/dev/null 2>&1 && run_adapter "$(basename "$dir")" sync; done; fi ;;
  ensure) cmd_ensure ;;
  *) usage ;;
esac
