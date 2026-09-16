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

# Output path of a buck2 target (sub-targets allowed). Non-root cells need the platform stated.
buck2_out() {
  (cd "$MONO_ROOT" && buck2 build "$1" --target-platforms prelude//platforms:default --show-simple-output 2>/dev/null | tail -n 1)
}

# buckconfig_get <section> <key>: .buckconfig.local first, then .buckconfig (what read_root_config sees)
buckconfig_get() {
  local f
  for f in "$MONO_ROOT/.buckconfig.local" "$MONO_ROOT/.buckconfig"; do
    [[ -f $f ]] || continue
    local v
    v=$(awk -v s="[$1]" -v k="$2" '/^\[/ { insec = ($0 == s) } insec && $1 == k { sub(/^[^=]*=[ \t]*/, ""); print; exit }' "$f")
    [[ -z $v ]] || { printf '%s\n' "$v"; return 0; }
  done
  return 1
}

# The interpreter behind toolchains//:lua, whichever fragment declared it: hermetic build, PATH, or [lua] bin. Empty under lua-host alone.
lua_bin() {
  local tc="$MONO_TOOLCHAINS/BUCK"
  [[ -f $tc ]] || return 0
  if grep -qE '^# monomono:toolchain (lua|lua-5\.[13]|luajit)$' "$tc"; then
    local p; p=$(buck2_out "toolchains//:lua-build[lua]"); [[ -z $p ]] || printf '%s\n' "$MONO_ROOT/$p"
  elif grep -q '^# monomono:toolchain lua-system$' "$tc"; then
    command -v lua || true
  else
    buckconfig_get lua bin || true
  fi
}

# The host command under lua-host, as an array: <host> [host_args...] <file> -- args. Sets HOST_CMD.
lua_host_cmd() {
  HOST_CMD=()
  local h; h=$(buckconfig_get lua host || true)
  [[ -n $h ]] || return 0
  HOST_CMD=("$h")
  local extra; extra=$(buckconfig_get lua host_args || true)
  if [[ -n $extra ]]; then local extra_arr; read -r -a extra_arr <<<"$extra"; HOST_CMD+=("${extra_arr[@]}"); fi
}
lua_host() { lua_host_cmd; printf '%s\n' "${HOST_CMD[0]-}"; }

# lua_run <file> [args]: run a repo Lua file the way toolchains//:lua would, with the mono stdlib on the path.
lua_run() {
  local file=$1; shift
  local lib; lib=$(buck2_out "monomono//rules/lua:lib")
  [[ -n $lib ]] || die "cannot build the mono stdlib (monomono//rules/lua:lib)"
  export LUA_PATH="$MONO_ROOT/scripts/lib/?.lua;$MONO_ROOT/scripts/lib/?/init.lua;$MONO_ROOT/$lib/lib/?.lua;$MONO_ROOT/$lib/lib/?/init.lua;${LUA_PATH:-;}"
  local bin host
  bin=$(lua_bin); lua_host_cmd
  if [[ ${#HOST_CMD[@]} -gt 0 && -f $MONO_TOOLCHAINS/BUCK ]] && grep -q '^# monomono:toolchain lua-host$' "$MONO_TOOLCHAINS/BUCK"; then exec "${HOST_CMD[@]}" "$file" -- "$@"   # lua-host: the host wins, as for tests
  elif [[ -n $bin ]]; then exec "$bin" "$file" "$@"
  elif [[ ${#HOST_CMD[@]} -gt 0 ]]; then exec "${HOST_CMD[@]}" "$file" -- "$@"
  else die "toolchains//:lua is not declared (just toolchain add lua, lua-config, or lua-host)"; fi
}
