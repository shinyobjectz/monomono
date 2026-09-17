#!/usr/bin/env bash
# Run a consumer script from scripts/<bucket>/<name>.{sh,lua}. Bash runs as before; Lua runs the way toolchains//:lua
# would run it: the hermetic build, [lua] bin, or under lua-host the host command (lib.sh lua_run).
#   run-script.sh <bucket> <name> [args...]

source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

bucket=${1-}; name=${2-}
[[ -n $bucket && -n $name ]] || die "usage: run-script.sh <build|tools|update> <name> [args...]"
shift 2
dir="$MONO_ROOT/scripts/$bucket"
if [[ -f $dir/$name.sh ]]; then
  exec bash "$dir/$name.sh" "$@"
elif [[ -f $dir/$name.lua ]]; then
  exec "$MONO_HOME/scripts/tools/lua.sh" script "$dir/$name.lua" "$@"
elif [[ -x $dir/$name ]]; then
  exec "$dir/$name" "$@"
fi
die "no scripts/$bucket/$name.sh or .lua"
