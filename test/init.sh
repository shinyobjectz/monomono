#!/usr/bin/env bash
# Scaffold a throwaway consumer from this checkout, then prove the contract holds:
# init, doctor, buck2 build/test, feature lifecycle, toolchain add, package adapter, update path.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export PATH="$HOME/.local/bin:$PATH"

step() { echo; echo "== $*"; }

step "init consumer at $work/demo from $here"
mkdir -p "$work/demo"
git -C "$work/demo" init -q
git -C "$work/demo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
MONO_REPO_URL="$here" "$here/bin/monomono" init "$work/demo" --ref "$(git -C "$here" rev-parse HEAD)" --name demo
cd "$work/demo"

step "recipes"
just --list >/dev/null
just mono status

step "doctor"
just doctor

step "buck2 targets + build"
just targets
just build

step "feature lifecycle"
just context project new demo-app
just context feature new demo-app hello
just context feature check
just context feature test demo-app hello first-red
if just test //context/projects/demo-app/features/hello:hello >/dev/null 2>&1; then
  echo "expected the red test to fail" >&2; exit 1
fi
echo "red test is red"
cat > context/projects/demo-app/features/hello/test/first-red.sh <<'SH'
#!/usr/bin/env bash
test -f mono.toml
SH
just test //context/projects/demo-app/features/hello:hello
echo "green test is green"

step "toolchain add"
just toolchain add cxx
just toolchain list
just targets toolchains//: >/dev/null

step "lua: hermetic toolchain, library, test, bundle, embed, C host"
just toolchain add lua
mkdir -p library/greet/util app/hello
cat > library/greet/BUCK <<'BUCK'
load("@monomono//rules/lua:defs.bzl", "lua_library", "lua_test")
lua_library(name = "greet", srcs = ["greet.lua", "util/init.lua"], visibility = ["PUBLIC"])
lua_test(name = "test", src = "test_greet.lua", deps = [":greet"])
BUCK
printf 'local M = {}\nfunction M.hello(n) return "hello, " .. n end\nreturn M\n' > library/greet/greet.lua
printf 'return { shout = function(s) return s:upper() .. "!" end }\n' > library/greet/util/init.lua
printf 'local g = require("greet")\nlocal u = require("util")\nassert(u.shout(g.hello("x")) == "HELLO, X!")\n' > library/greet/test_greet.lua
cat > app/hello/BUCK <<'BUCK'
load("@monomono//rules/lua:defs.bzl", "lua_binary", "lua_bundle", "lua_embed")
load("@monomono//rules/lua:toolchain.bzl", "lua_cxx_library")
lua_binary(name = "hello", main = "main.lua", deps = ["//library/greet:greet"])
lua_bundle(name = "bundle", main = "main.lua", deps = ["//library/greet:greet"], bytecode = True)
lua_embed(name = "embedded", src = ":bundle", symbol = "hello_lua")
lua_cxx_library(name = "liblua")
cxx_binary(name = "host", srcs = ["host.c"], headers = [":embedded"], header_namespace = "", deps = [":liblua"])
BUCK
printf 'local g = require("greet")\nprint(require("util").shout(g.hello(arg and arg[1] or "world")))\n' > app/hello/main.lua
cat > app/hello/host.c <<'C'
#include <stdio.h>
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "embedded.h"
int main(void) {
  lua_State *L = luaL_newstate(); luaL_openlibs(L);
  if (luaL_loadbuffer(L, (const char *)hello_lua, hello_lua_len, "embedded") || lua_pcall(L, 0, 0, 0)) { fprintf(stderr, "%s\n", lua_tostring(L, -1)); return 1; }
  lua_close(L); return 0; }
C
just test //library/greet:test
[[ "$(just run //app/hello:hello -- buck 2>/dev/null | tail -n 1)" == "HELLO, BUCK!" ]]
[[ "$(just run //app/hello:host 2>/dev/null | tail -n 1)" == "HELLO, WORLD!" ]]
echo "lua binary and embedded C host both print through the bundle"
just context feature test demo-app hello lua-red --lua
if just test //context/projects/demo-app/features/hello:hello-lua-red >/dev/null 2>&1; then echo "expected lua red test to fail" >&2; exit 1; fi
printf 'assert(1 + 1 == 2)\n' > context/projects/demo-app/features/hello/test/lua-red.lua
just test //context/projects/demo-app/features/hello:hello
echo "lua feature test red then green"

step "area add"
just area add server "Internal API."
test -f server/AGENTS.md

step "agents"
just agents sync
test -f .agents/skills/features/demo-app/hello/SKILL.md
just agents check

step "check (definition of green)"
just check

step "update path (same ref, exercises migrate + sync)"
git -C packages/monomono checkout -q "$(git -C "$here" rev-parse HEAD)"
just mono migrate
just mono status

echo
echo "selftest ok"
