#!/usr/bin/env bash
# The package itself: scaffold, status, update, migrate, sync.

source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  just mono status              # version pinned, version installed, mode, modules
  just mono version             # installed package version
  just mono update [ref]        # submodule mode: move packages/monomono to <ref> (default: latest tag), migrate, sync
                                #   vendor mode refuses (never fetches): replace the copy yourself, then just mono migrate; just mono sync
  just mono migrate             # run migrations from mono.toml version to packages/monomono/VERSION
  just mono sync                # relink hosts, regenerate skills, copy ci, add new template files
  just mono diff                # template files the repo does not have yet
USAGE
  exit 2
}

# Copy template files that do not exist yet. Never overwrite.
scaffold() {
  local name=$1 src dest rel added=0
  while IFS= read -r src; do
    rel=${src#"$MONO_TEMPLATE"/}
    dest="$MONO_ROOT/$rel"
    [[ -e $dest || -L $dest ]] && continue
    mkdir -p "$(dirname "$dest")"
    sed "s/__NAME__/$name/g" "$src" >"$dest"
    [[ -x $src ]] && chmod +x "$dest"
    echo "added   $rel"
    added=$((added + 1))
  done < <(find "$MONO_TEMPLATE" -type f | sort)
  echo "scaffold: $added file(s) added"
}

cmd_init() {
  local mode="submodule" repo="$MONO_REPO_URL" name="" provider="" context="true"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode) mode=$2; shift 2 ;;
      --repo) repo=$2; shift 2 ;;
      --name) name=$2; shift 2 ;;
      --provider) provider=$2; shift 2 ;;
      --no-context) context="false"; shift ;;
      *) usage ;;
    esac
  done
  [[ -n $name ]] || name=$(basename "$MONO_ROOT")
  name=$(kebab "$name")
  scaffold "$name"
  toml_set monomono version "$MONO_VERSION"
  toml_set monomono mode "$mode"
  toml_set monomono path "$(rel "$MONO_HOME")"
  toml_set monomono repo "$repo"
  [[ -z $provider ]] || toml_set monomono provider "$provider"
  [[ $context == true ]] || toml_set modules context "$context"
  toml_set repo name "$name"
  cmd_sync
  echo
  echo "monomono $MONO_VERSION is attached. Next:"
  echo "  just setup      # buck2, hosts, stores"
  echo "  just doctor"
  echo "  just check"
}

cmd_status() {
  local pinned mode
  pinned=$(toml_get monomono version || true)
  mode=$(toml_get monomono mode || true)
  echo "package     $(rel "$MONO_HOME")"
  echo "installed   $MONO_VERSION"
  echo "manifest    ${pinned:-none}"
  echo "mode        ${mode:-unknown}"
  local provider; provider=$(toml_get monomono provider || true)
  [[ -z $provider ]] || echo "provider    $provider"
  echo "repo        $(mono_repo_name)"
  if [[ -d $MONO_HOME/.git || -f $MONO_HOME/.git ]]; then
    echo "git         $(git -C "$MONO_HOME" describe --tags --always 2>/dev/null)"
  fi
  echo "modules"
  awk '/^\[modules\]/ { on = 1; next } /^\[/ { on = 0 } on && NF { print "  " $0 }' "$MONO_MANIFEST" 2>/dev/null || true
  if [[ -n $pinned && $pinned != "$MONO_VERSION" ]]; then
    echo
    echo "manifest says $pinned but packages/monomono is $MONO_VERSION; run just mono migrate"
  fi
}

run_migrations() {
  local from=$1 to=$2 file ver ran=0
  for file in "$MONO_HOME"/migrations/*.sh; do
    [[ -f $file ]] || continue
    ver=$(basename "$file" .sh)
    if version_lt "$from" "$ver" && ! version_lt "$to" "$ver"; then
      echo "migrate $ver"
      MONO_FROM="$from" MONO_TO="$to" bash "$file"
      ran=$((ran + 1))
    fi
  done
  echo "migrations run: $ran ($from -> $to)"
}

cmd_migrate() {
  local from
  from=$(toml_get monomono version || true)
  [[ -n $from ]] || from="0.0.0"
  run_migrations "$from" "$MONO_VERSION"
  toml_set monomono version "$MONO_VERSION"
}

cmd_update() {
  local ref=${1-} mode from repo provider
  provider=$(toml_get monomono provider || true)
  if [[ -n $provider ]]; then
    die "monomono is provided by $provider; update the app, not the package"
  fi
  mode=$(toml_get monomono mode || true)
  repo=$(toml_get monomono repo || true)
  [[ -n $repo ]] || repo=$MONO_REPO_URL
  from=$(toml_get monomono version || true)
  [[ -n $from ]] || from="0.0.0"
  case "${mode:-submodule}" in
    submodule)
      git -C "$MONO_HOME" fetch -q --tags origin
      [[ -n $ref ]] || ref=$(git -C "$MONO_HOME" tag --list 'v*' --sort=-v:refname | head -n 1)
      [[ -n $ref ]] || die "no release tags found in $repo"
      git -C "$MONO_HOME" checkout -q "$ref"
      ;;
    vendor)
      # a vendored copy is replaced by whoever put it there; this never fetches (no git ls-remote, no clone)
      die "monomono is vendored (mode = \"vendor\" in mono.toml); replace $(rel "$MONO_HOME") with the release you want, then run just mono migrate and just mono sync"
      ;;
    *) die "unknown mode in mono.toml: $mode" ;;
  esac
  MONO_VERSION=$(tr -d '[:space:]' <"$MONO_HOME/VERSION")
  echo "monomono $from -> $MONO_VERSION ($ref)"
  run_migrations "$from" "$MONO_VERSION"
  # a migration may relocate the package; follow mono.toml
  local newpath
  newpath=$(toml_get monomono path || true)
  if [[ -n $newpath && -f $MONO_ROOT/$newpath/VERSION ]]; then
    MONO_HOME="$MONO_ROOT/$newpath"
    export MONO_HOME
  fi
  toml_set monomono version "$MONO_VERSION"
  scaffold "$(mono_repo_name)"
  cmd_sync
  if in_git_repo; then
    git -C "$MONO_ROOT" add mono.toml packages/monomono 2>/dev/null || true
    echo "staged mono.toml and packages/monomono; commit when ready"
  fi
}

cmd_sync() {
  mono_drop_legacy_link
  "$MONO_HOME/scripts/tools/agents-host.sh" sync
  if [[ -d $MONO_CI/github ]]; then
    "$MONO_HOME/scripts/tools/ci.sh" sync
  fi
}

cmd_diff() {
  local src rel missing=0
  while IFS= read -r src; do
    rel=${src#"$MONO_TEMPLATE"/}
    if [[ ! -e $MONO_ROOT/$rel ]]; then
      echo "missing  $rel"
      missing=$((missing + 1))
    fi
  done < <(find "$MONO_TEMPLATE" -type f | sort)
  echo "$missing template file(s) not in repo (just mono sync adds them)"
}

action=${1:-status}
shift || true
case "$action" in
  init) cmd_init "$@" ;;
  status) cmd_status ;;
  version) echo "$MONO_VERSION" ;;
  update) cmd_update "$@" ;;
  migrate) cmd_migrate ;;
  sync) cmd_sync; scaffold "$(mono_repo_name)" ;;
  diff) cmd_diff ;;
  -h|--help) usage ;;
  *) usage ;;
esac
