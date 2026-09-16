#!/usr/bin/env bash
# The Lua dev loop over the graph. The interpreter is toolchains//:lua, so every verb is hermetic.

source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
require_cmd buck2
cd "$MONO_ROOT"

usage() {
  cat >&2 <<'USAGE'
usage:
  just lua repl <lua_library target>            # interpreter with that library on the path
  just lua run <lua_binary target> [args...]     # same as just run
  just lua cover <lua_test|lua_binary> [args]    # line coverage -> coverage.txt (MONO_COVERAGE_OUT)
  just lua profile <lua_binary> [args]           # top functions by inclusive time
  just lua meta <lua_library|lua_meta target>    # write .luarc.json + .lua-meta/ at the repo root
  just lua fmt [lua_format target]               # stylua in place (default //...:fmt targets)
  just lua trace <feature test target>           # run Gherkin scenarios, print the span tree, write trace.json
  just lua observe <feature test target>         # run scenarios, read the trace back as Gherkin
  just lua script <file.lua> [args...]           # run a repo script under the hermetic interpreter
  just lua version
USAGE
  exit 2
}

interp() { lua_bin; }
stdlib_dir() { buck2_out "monomono//rules/lua:lib"; }

verb=${1-}
shift || true
case "$verb" in
  repl) [[ -n ${1-} ]] || usage; t=$1; shift; exec buck2 run "${t%%\[*}[repl]" -- "$@" ;;
  run) exec buck2 run "$@" ;;
  cover) [[ -n ${1-} ]] || usage; [[ -n $(interp) ]] || die "cover needs an interpreter (lua, lua-config); under lua-host the host owns instrumentation"; t=$1; shift; MONO_LUA_HOOK=cover MONO_COVERAGE_OUT="${MONO_COVERAGE_OUT:-$MONO_ROOT/coverage.txt}" buck2 run "$t" -- "$@" ;;
  profile) [[ -n ${1-} ]] || usage; [[ -n $(interp) ]] || die "profile needs an interpreter (lua, lua-config); under lua-host the host owns instrumentation"; t=$1; shift; MONO_LUA_HOOK=profile buck2 run "$t" -- "$@" ;;
  meta)
    [[ -n ${1-} ]] || usage
    t=$1
    out=""
    if [[ $t != *"["* ]]; then out=$(buck2 build "$t[meta]" --show-simple-output 2>/dev/null | tail -n 1 || true); fi
    [[ -n $out ]] || out=$(buck2 build "$t" --show-simple-output 2>/dev/null | tail -n 1)
    [[ -n $out && -f $out/.luarc.json ]] || die "$t is not a lua_library or lua_meta target"
    rm -rf "$MONO_ROOT/.lua-meta"; cp -RL "$out" "$MONO_ROOT/.lua-meta"
    # library paths become absolute for the editor; "." becomes the copied stubs
    sed -e 's#^    "\."#    ".lua-meta"#' -e "s#\"buck-out/#\"$MONO_ROOT/buck-out/#g" "$out/.luarc.json" >"$MONO_ROOT/.luarc.json"
    rm -f "$MONO_ROOT/.lua-meta/.luarc.json"
    echo "wrote .luarc.json and .lua-meta/ ($(find "$MONO_ROOT/.lua-meta" -name '*.lua' | wc -l | tr -d ' ') stubs)"
    ;;
  fmt)
    if [[ -n ${1-} ]]; then exec buck2 run "${1%%\[*}[fix]"; fi
    while read -r t; do [[ -n $t ]] && buck2 run "$t[fix]"; done < <(buck2 uquery "kind('lua_format', //...)" 2>/dev/null)
    ;;
  trace) [[ -n ${1-} ]] || usage; MONO_TRACE=1 MONO_TRACE_OUT="${MONO_TRACE_OUT:-$MONO_ROOT/trace.json}" buck2 run "$1" 2>&1 | grep -vE '^\[20'; echo "otlp -> ${MONO_TRACE_OUT:-trace.json}" ;;
  observe) [[ -n ${1-} ]] || usage; MONO_OBSERVE=1 buck2 run "$1" 2>&1 | grep -vE '^\[20' ;;
  script)
    [[ -n ${1-} ]] || usage
    f=$1; shift
    lua_run "$f" "$@"
    ;;
  version) b=$(interp); [[ -n $b ]] && "$b" -v || echo "no interpreter; host = $(lua_host)" ;;
  *) usage ;;
esac
