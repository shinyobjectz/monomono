#!/usr/bin/env bash
# Public or reusable repos under submodules/. Registry is .gitmodules at the root.

source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  just submodule add <url> [name]
  just submodule update
  just submodule list
  just submodule sync
USAGE
  exit 2
}

cmd_add() {
  local url=${1-} name=${2-}
  [[ -n $url ]] || usage
  if [[ -z $name ]]; then
    name=$(basename "$url")
    name=${name%.git}
  fi
  name=$(kebab "$name")
  is_slug "$name" || die "name must be kebab-case: $name"
  [[ ! -e $MONO_SUBMODULES/$name ]] || die "already exists: submodules/$name"
  in_git_repo || git -C "$MONO_ROOT" init -q
  mkdir -p "$MONO_SUBMODULES"
  git -C "$MONO_ROOT" -c protocol.file.allow=always submodule add --name "$name" "$url" "submodules/$name"
}

cmd_update() {
  in_git_repo || return 0
  [[ -f $MONO_ROOT/.gitmodules ]] || { echo "no submodules registered"; return 0; }
  git -C "$MONO_ROOT" submodule update --init --recursive
}

cmd_list() {
  [[ -f $MONO_ROOT/.gitmodules ]] || { echo "none"; return 0; }
  git -C "$MONO_ROOT" submodule status --recursive
}

cmd_sync() {
  [[ -f $MONO_ROOT/.gitmodules ]] || { echo "no submodules registered"; return 0; }
  git -C "$MONO_ROOT" submodule sync --recursive
  git -C "$MONO_ROOT" submodule update --init --recursive
}

action=${1:-list}
shift || true
case "$action" in
  add) cmd_add "$@" ;;
  update) cmd_update ;;
  list) cmd_list ;;
  sync) cmd_sync ;;
  *) usage ;;
esac
