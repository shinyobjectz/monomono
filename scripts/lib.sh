#!/usr/bin/env bash
# Shared helpers for monomono scripts. Source only.
# MONO_HOME is the package checkout (packages/monomono in a consumer). MONO_ROOT is the repo it serves.

set -euo pipefail

MONO_HOME="${MONO_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

mono_find_root() {
  local dir
  dir=$(pwd)
  while [[ $dir != / ]]; do
    if [[ -f $dir/mono.toml ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

if [[ -z ${MONO_ROOT:-} ]]; then
  if [[ $(basename "$MONO_HOME") == monomono && -f $MONO_HOME/../../mono.toml ]]; then
    MONO_ROOT=$(cd "$MONO_HOME/../.." && pwd)
  elif MONO_ROOT=$(mono_find_root); then
    :
  else
    MONO_ROOT=$MONO_HOME
  fi
fi
export MONO_HOME MONO_ROOT

MONO_VERSION=$(tr -d '[:space:]' <"$MONO_HOME/VERSION")
MONO_MANIFEST="$MONO_ROOT/mono.toml"
MONO_TEMPLATE="$MONO_HOME/template"
MONO_CONTEXT="$MONO_ROOT/context"
MONO_CONTEXT_DB="$MONO_CONTEXT/dump/context.sqlite"
MONO_PROJECTS="$MONO_CONTEXT/projects"
MONO_PACKAGES="$MONO_ROOT/packages"
MONO_SUBMODULES="$MONO_ROOT/submodules"
MONO_AGENTS="$MONO_ROOT/.agents"
MONO_TOOLCHAINS="$MONO_ROOT/toolchains"
MONO_CI="$MONO_ROOT/git/ci"
MONO_REPO_URL="${MONO_REPO_URL:-https://github.com/shinyobjectz/monomono}"

die() {
  echo "$*" >&2
  exit 1
}

rel() {
  echo "${1#"$MONO_ROOT"/}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

kebab() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

is_slug() {
  [[ $1 =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

mono_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

mono_id() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr "[:upper:]" "[:lower:]"
  elif [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  else
    od -An -N16 -tx1 /dev/urandom | tr -d " \n" | sed -E "s/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/"
  fi
}

sql_quote() {
  local s=${1-}
  s=${s//\'/\'\'}
  printf "%s" "$s"
}

mono_sqlite() {
  local db=$1
  shift
  sqlite3 -batch -noheader "$db" "$@"
}

# toml_get <section> <key>  — flat "key = "value"" lines under [section]
toml_get() {
  [[ -f $MONO_MANIFEST ]] || return 1
  awk -v s="[$1]" -v k="$2" '
    /^\[/ { insec = ($0 == s) }
    insec && $1 == k { sub(/^[^=]*=[ \t]*/, ""); gsub(/^"|"$/, ""); print; exit }
  ' "$MONO_MANIFEST"
}

# toml_set <section> <key> <value>  — rewrite in place, append if absent
toml_set() {
  local section=$1 key=$2 value=$3 tmp
  tmp=$(mktemp)
  awk -v s="[$1]" -v k="$2" -v v="$3" '
    /^\[/ {
      if (insec && !done) { print k " = \"" v "\""; done = 1 }
      insec = ($0 == s); seen = seen || insec
    }
    insec && $1 == k && !done { print k " = \"" v "\""; done = 1; next }
    { print }
    END {
      if (!done) {
        if (!seen) print "\n" s
        print k " = \"" v "\""
      }
    }
  ' "$MONO_MANIFEST" >"$tmp"
  mv "$tmp" "$MONO_MANIFEST"
}

mono_module() {
  [[ $(toml_get modules "$1") == true ]]
}

mono_repo_name() {
  local n
  n=$(toml_get repo name)
  [[ -n $n ]] || n=$(basename "$MONO_ROOT")
  echo "$n"
}

# semver compare: returns 0 if $1 < $2
version_lt() {
  [[ $1 != "$2" ]] && [[ $(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1) == "$1" ]]
}

in_git_repo() {
  git -C "$MONO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# After the 0.2.0 move a migration leaves `.mono -> packages/monomono` so the old updater can finish.
mono_drop_legacy_link() {
  if [[ -L $MONO_ROOT/.mono && $(cd "$MONO_ROOT/.mono" 2>/dev/null && pwd -P) == "$(cd "$MONO_HOME" && pwd -P)" ]]; then
    rm -f "$MONO_ROOT/.mono"
    git -C "$MONO_ROOT" rm -q --cached .mono 2>/dev/null || true
    echo "removed legacy .mono link"
  fi
}
