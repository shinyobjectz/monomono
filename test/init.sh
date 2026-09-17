#!/usr/bin/env bash
# Scaffold a throwaway consumer from this checkout, then prove the contract holds:
# init, doctor, buck2 build/test, feature lifecycle, toolchains, and the whole Lua layer
# (library/test/bundle/embed/hosts, lint/format/meta/typecheck, Gherkin runner + telemetry,
# coverage/profile, script backend + hooks, other interpreters, host and config toolchains, provider refusal).
#
# MONO_SELFTEST_SKIP=a,b  skips sections by name (rust, wasm, luals, cmod, interpreters, stylua, luacheck).
#
# Under `set -e` a command inverted with `!` never exits the script, so a negative assertion is written
# `refute cmd...` (fails the script when cmd succeeds), never `! cmd`.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export PATH="$HOME/.local/bin:$PATH"

step() { echo; echo "== $*"; }
skip() { [[ ",${MONO_SELFTEST_SKIP-}," == *",$1,"* ]] && { echo "   (skipped: $1)"; return 0; } || return 1; }
have() { command -v "$1" >/dev/null 2>&1; }
quiet() { grep -vE '^\[20[0-9-]+T' || true; }
# expect PATTERN cmd...: run cmd, capture everything, grep the capture (no SIGPIPE from grep -q)
expect() { local p=$1; shift; "$@" >"$work/out" 2>&1 || true; grep -qE -- "$p" "$work/out"; }
# refute cmd...: the command must fail; its stdin is the caller's (refute grep -q x <<<"$out" works)
refute() { if "$@" >/dev/null 2>&1; then echo "expected to fail: $*" >&2; exit 1; fi; }
# overlay DIR: the consumers are scaffolded by cloning this checkout at HEAD; copy the working tree over the
# package (and pin mono.toml to its VERSION) so what is under test is the checkout as it is, not its last
# commit (identical in CI, where the tree is clean)
overlay() {
  rsync -a --delete --exclude .git --exclude buck-out "$here/" "$1/"
  local manifest="$1/../../mono.toml"
  [[ -f $manifest ]] && sed -i.bak "s/^version = \".*\"/version = \"$(tr -d '[:space:]' <"$here/VERSION")\"/" "$manifest" && rm -f "$manifest.bak"
  return 0
}
# toolpath DIR PATTERN...: a directory of symlinks to every tool on PATH except those matching a pattern
toolpath() {
  local dest=$1; shift; mkdir -p "$dest"
  local d f n pat skipit
  for d in $(tr ':' ' ' <<<"$PATH"); do
    for f in "$d"/*; do
      n=$(basename "$f"); skipit=0
      for pat in "$@"; do [[ $n == $pat ]] && skipit=1; done
      [[ $skipit -eq 1 || ! -x $f || -e "$dest/$n" ]] || ln -s "$f" "$dest/$n"
    done
  done 2>/dev/null
  return 0
}
ref=$(git -C "$here" rev-parse HEAD)

step "init consumer at $work/demo from $here"
mkdir -p "$work/demo"
git -C "$work/demo" init -q
git -C "$work/demo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
MONO_REPO_URL="$here" "$here/bin/monomono" init "$work/demo" --ref "$ref" --name demo
overlay "$work/demo/packages/monomono"
cd "$work/demo"

step "no python anywhere in the package"
if grep -rnE '(^|[^a-z_-])python3?( |$)' "$here/scripts" "$here/rules" "$here/template" "$here/bin" "$here/install.sh" "$here/mono.just" | grep -v 'python_bootstrap\|python-bootstrap\|# ' ; then
  echo "python must not be required" >&2; exit 1
fi
echo "bash + awk + lua only"

step "recipes"
just --list >/dev/null
just mono status
printf '\n# a consumer recipe shadows the package one of the same name\ndoctor:\n    @echo "my doctor"\n' >> justfile
[[ "$(just doctor)" == "my doctor" ]]
sed -i.bak '/^# a consumer recipe shadows/,$d' justfile && rm justfile.bak
grep -qx '/.luarc.json' .gitignore && grep -qx '/.buckconfig.local' .gitignore
mkdir -p library && printf '{}\n' > library/.luarc.json && printf '{}\n' > .luarc.json
refute git check-ignore -q library/.luarc.json
git check-ignore -q .luarc.json
rm library/.luarc.json .luarc.json
echo "allow-duplicate-recipes: your recipe wins; ignores are anchored, a committed library/.luarc.json survives (the root one is ignored)"

step "doctor"
just doctor
toolpath "$work/nojust" 'just'
out=$(PATH="$work/nojust" packages/monomono/scripts/tools/doctor.sh 2>&1) || { echo "$out"; echo "doctor must not fail without just on PATH" >&2; exit 1; }
grep -q 'warn  just not on PATH' <<<"$out"
mkdir -p notes targets-only && printf 'a note\n' > notes/README.md && printf '# a folder that holds targets\n' > targets-only/BUCK
out=$(just doctor 2>&1)
refute grep -q 'notes/' <<<"$out"
grep -q 'targets-only/ holds targets but has no AGENTS.md' <<<"$out"
rm -r notes targets-only
echo "doctor warns (not fails) without just; only a folder that holds targets is asked for an AGENTS.md"

step "buck2 targets + build"
just targets
just build

step "feature lifecycle (sh)"
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
just toolchain add lua
just toolchain list
just targets toolchains//: >/dev/null
expect "make \(hermetic lua toolchain\)" just doctor

# --- Lua ----------------------------------------------------------------------

step "lua: library with resources, spec tests (TAP), lua_tests suite"
mkdir -p library/greet/util library/greet/data library/greet/meta app/hello
cat > library/greet/BUCK <<'BUCK'
load("@monomono//rules/lua:defs.bzl", "lua_library", "lua_tests", "lua_lint", "lua_format", "lua_meta", "lua_repl", "lua_typecheck", "lua_bundle")
lua_library(name = "greet", srcs = ["greet.lua", "util/init.lua"], resources = ["data/config.json"], visibility = ["PUBLIC"])
lua_tests(name = "tests", srcs = glob(["test_*.lua"]), deps = [":greet"])
lua_repl(name = "repl", deps = [":greet"])
lua_meta(name = "meta", deps = [":greet"])
lua_meta(name = "meta-provided", deps = [":greet"], provided = ["meta/greet.lua"])
lua_bundle(name = "portable", main = "greet.lua", deps = [":greet"], dialect = "portable")
BUCK
cat > library/greet/greet.lua <<'LUA'
--- Greetings.
local M = {}
--- Greet someone.
---@param n string
---@return string
function M.hello(n) return "hello, " .. n end
--- The greeting word from the resource file.
---@return string
function M.word() return require("mono.resource").read("data/config.json"):match('"word": *"([^"]+)"') end
M.version = "1"
return M
LUA
printf 'return { shout = function(s) return s:upper() .. "!" end }\n' > library/greet/util/init.lua
printf '{ "word": "hi" }\n' > library/greet/data/config.json
cat > library/greet/test_greet.lua <<'LUA'
local spec = require("mono.spec")
local g = require("greet")
local u = require("util")
spec.test("hello greets", function() spec.eq(g.hello("x"), "hello, x") end)
spec.test("shout shouts", function() spec.eq(u.shout("a"), "A!") end)
spec.test("resource is readable", function() spec.eq(g.word(), "hi") end)
spec.test("tables compare", function() spec.same({ a = 1, b = { 2 } }, { a = 1, b = { 2 } }) end)
spec.run()
LUA
cat > library/greet/meta/greet.lua <<'LUA'
---@meta
---@module 'greet'
---@class greet
---@field hello fun(n: string): string
---@field word fun(): string
---@field version string
local greet = {}
return greet
LUA
just test //library/greet:tests
out=$(just run //library/greet:tests-test_greet 2>/dev/null | quiet)
grep -q '^ok 3 - resource is readable' <<<"$out"
grep -q '# 4 passed, 0 failed' <<<"$out"
echo "TAP + resources ok"

step "lua: module prefix (a per-flow BUCK keeps its namespace) + a feature test with your own runner"
mkdir -p library/hourly-check
cat > library/hourly-check/BUCK <<'BUCK'
load("@monomono//rules/lua:defs.bzl", "lua_library", "lua_test", "lua_feature_test")
lua_library(name = "hourly-check", srcs = ["compare.lua"], prefix = "hourly-check", visibility = ["PUBLIC"])
lua_test(name = "test", src = "test_compare.lua", deps = [":hourly-check"])
lua_feature_test(name = "own-runner", features = ["flow.feature"], runner_cmd = ["bash", "library/hourly-check/runner.sh"], deps = [":hourly-check"])
BUCK
printf 'return { same = function(a, b) return a == b end }\n' > library/hourly-check/compare.lua
printf 'assert(require("hourly-check.compare").same(1, 1))\nassert(not pcall(require, "compare"), "the bare name must not be loadable")\nprint("prefixed module ok")\n' > library/hourly-check/test_compare.lua
printf 'Feature: flow\n  Scenario: compares\n    Then it compares\n' > library/hourly-check/flow.feature
cat > library/hourly-check/runner.sh <<'SH'
#!/usr/bin/env bash
# a consumer's own runner: gets only the feature files, from the project root; LUA_PATH carries the deps; the exit code is the verdict
[[ $1 == *.feature ]] || { echo "expected a feature file first, got: $*" >&2; exit 1; }
[[ -f $1 && -f mono.toml ]] || { echo "not run from the project root: $PWD" >&2; exit 1; }
[[ ${LUA_PATH-} == *hourly-check* ]] || { echo "LUA_PATH lacks the deps" >&2; exit 1; }
[[ ${MONO_LUA_ROOTS-} == *hourly-check* ]] || { echo "MONO_LUA_ROOTS lacks the deps" >&2; exit 1; }
echo "own runner ran $# feature(s)"
SH
just test //library/hourly-check:test //library/hourly-check:own-runner
expect "own runner ran 1 feature" just run //library/hourly-check:own-runner
expect "own runner ran 1 feature" just lua observe //library/hourly-check:own-runner
echo "prefix = 'hourly-check' makes compare.lua require-able as hourly-check.compare; own runner needs no steps and sees the same environment under buck2 test and buck2 run"

step "lua: compile check is part of the build"
printf 'local x = = 1\n' > library/greet/util/broken.lua
sed -i.bak 's/"util\/init.lua"\]/"util\/init.lua", "util\/broken.lua"]/' library/greet/BUCK
if just build //library/greet:greet >/dev/null 2>&1; then echo "expected the syntax error to fail the build" >&2; exit 1; fi
mv library/greet/BUCK.bak library/greet/BUCK; rm library/greet/util/broken.lua
echo "syntax error fails the build"

step "lua: repl, meta stubs, .luarc.json"
expect "repl says hello, you" bash -c 'echo "print(\"repl says \" .. require(\"greet\").hello(\"you\"))" | just lua repl //library/greet:greet'
just lua meta //library/greet:greet
test -f .luarc.json && test -f .lua-meta/greet.lua
grep -q '^function M.hello(n) end' .lua-meta/greet.lua && grep -q '@param n string' .lua-meta/greet.lua
just lua meta //library/greet:meta-provided
grep -q '@field version string' .lua-meta/greet.lua
echo "stubs generated and provided stubs win"
mkdir -p library/fnmod
cat > library/fnmod/BUCK <<'BUCK'
load("@monomono//rules/lua:defs.bzl", "lua_library")
lua_library(name = "fnmod", srcs = ["fnmod.lua"], visibility = ["PUBLIC"])
BUCK
printf -- '--- A module that is a function.\n---@param n number\n---@return number\nreturn function(n)\n  return n * 2\nend\n' > library/fnmod/fnmod.lua
just lua meta //library/fnmod:fnmod >/dev/null
grep -q '^return function(n) end' .lua-meta/fnmod.lua && grep -q '@param n number' .lua-meta/fnmod.lua
refute grep -q 'local M' .lua-meta/fnmod.lua
echo "return function(...) modules stub as an annotated function, not a table"

step "lua: typecheck (lua-language-server)"
if ! skip luals; then
  if have lua-language-server; then
    just toolchain add luals
    cat >> library/greet/BUCK <<'BUCK'
lua_typecheck(name = "types", meta = ":meta-provided", path = "library/greet", srcs = glob(["**/*.lua"]))
BUCK
    just test //library/greet:types
    printf 'local g = require("greet")\nreturn g.hello(1)\n' > library/greet/bad.lua
    if just test //library/greet:types >/dev/null 2>&1; then echo "expected the typecheck to fail" >&2; exit 1; fi
    rm library/greet/bad.lua
    echo "typecheck passes clean code and fails g.hello(1) against the stub"
    # the file is not named .luarc.json: LuaLS reads a .luarc.json it finds under the checked path on its own,
    # so only a name it does not discover proves the `luarc` attribute is what was consumed
    cat > library/greet/luarc.json <<'JSON'
{ "runtime.version": "Lua 5.4", "workspace.library": ["meta"], "workspace.ignoreDir": ["meta"], "workspace.checkThirdParty": false, "diagnostics.globals": ["arg"] }
JSON
    # a type that exists only in the hand-written meta dir: green proves the luarc's relative library path was resolved against `path`
    printf -- '---@meta\n---@class greet.only_in_meta\n---@field n number\n' > library/greet/meta/types.lua
    printf -- '---@param x greet.only_in_meta\n---@return number\nlocal function f(x) return x.n end\nreturn f\n' > library/greet/typed.lua
    sed 's/"workspace.library": \["meta"\]/"workspace.library": []/' library/greet/luarc.json > library/greet/luarc-nolib.json
    cat >> library/greet/BUCK <<'BUCK'
lua_typecheck(name = "types-own", luarc = "luarc.json", path = "library/greet", srcs = glob(["**/*.lua"]))
lua_typecheck(name = "types-nolib", luarc = "luarc-nolib.json", path = "library/greet", srcs = glob(["**/*.lua"]))
BUCK
    just test //library/greet:types-own
    if just test //library/greet:types-nolib >/dev/null 2>&1; then echo "expected the typecheck to fail without the luarc's library path" >&2; exit 1; fi
    sed -i.bak '/types-nolib/d' library/greet/BUCK && rm library/greet/BUCK.bak library/greet/luarc-nolib.json   # red on purpose; not part of just check
    echo "lua_typecheck(luarc = ...) uses the library's own .luarc.json verbatim: its workspace.library resolves against path, and without it the same code is red"
  else
    echo "   (lua-language-server not on PATH; typecheck not exercised)"
  fi
fi

step "lua: luacheck lint"
if ! skip luacheck; then
  just toolchain add luacheck
  cat >> library/greet/BUCK <<'BUCK'
lua_lint(name = "lint", srcs = glob(["*.lua", "util/*.lua"]))
BUCK
  just test //library/greet:lint
  printf 'local unused = 1\nreturn {}\n' > library/greet/util/lint-bad.lua
  if just test //library/greet:lint >/dev/null 2>&1; then echo "expected luacheck to fail" >&2; exit 1; fi
  rm library/greet/util/lint-bad.lua
  echo "luacheck passes and fails as expected"
fi

step "lua: stylua format check + fix"
if ! skip stylua; then
  just toolchain add stylua
  cat >> library/greet/BUCK <<'BUCK'
lua_format(name = "fmt", srcs = glob(["*.lua", "util/*.lua"]))
BUCK
  if just test //library/greet:fmt >/dev/null 2>&1; then echo "expected unformatted code to fail the check" >&2; exit 1; fi
  just lua fmt //library/greet:fmt >/dev/null
  just test //library/greet:fmt
  echo "stylua check red, fix, green"
fi

step "lua: portable dialect gate + chunk names + determinism"
just build //library/greet:portable >/dev/null
b=$(buck2 build //library/greet:portable --show-simple-output 2>/dev/null | tail -n 1)
grep -q '"=greet"' "$b"
h1=$(shasum -a 256 "$b" | cut -c1-16)
touch library/greet/greet.lua library/greet/util/init.lua
buck2 build //library/greet:portable >/dev/null 2>&1
h2=$(shasum -a 256 "$(buck2 build //library/greet:portable --show-simple-output 2>/dev/null | tail -n 1)" | cut -c1-16)
[[ $h1 == "$h2" ]]
printf 'return { half = function(n) return n // 2 end }\n' > library/greet/util/intdiv.lua
sed -i.bak 's/"util\/init.lua"\]/"util\/init.lua", "util\/intdiv.lua"]/' library/greet/BUCK
if just build //library/greet:portable >/dev/null 2>&1; then echo "expected // to be rejected by the portable dialect" >&2; exit 1; fi
mv library/greet/BUCK.bak library/greet/BUCK; rm library/greet/util/intdiv.lua
echo "chunk names, byte-identical rebuild, // rejected"

step "lua: C module on LUA_CPATH"
if ! skip cmod; then
  mkdir -p library/cmod
  cat > library/cmod/BUCK <<'BUCK'
load("@monomono//rules/lua:defs.bzl", "lua_library", "lua_test")
genrule(
    name = "so",
    srcs = ["twice.c"],
    out = "cpath",
    bash = 'mkdir -p "$OUT" && cc -shared -undefined dynamic_lookup -I "$(location toolchains//:lua-build[include])" -o "$OUT/twice.so" "$SRCS" 2>/dev/null || cc -shared -fPIC -I "$(location toolchains//:lua-build[include])" -o "$OUT/twice.so" "$SRCS"',
)
lua_library(name = "cmod", srcs = ["usecmod.lua"], cpath = [":so"])
lua_test(name = "test", src = "test_cmod.lua", deps = [":cmod"])
BUCK
  cat > library/cmod/twice.c <<'C'
#include "lua.h"
#include "lauxlib.h"
static int twice(lua_State *L) { lua_pushinteger(L, 2 * luaL_checkinteger(L, 1)); return 1; }
int luaopen_twice(lua_State *L) { lua_newtable(L); lua_pushcfunction(L, twice); lua_setfield(L, -2, "twice"); return 1; }
C
  printf 'return { four = function() return require("twice").twice(2) end }\n' > library/cmod/usecmod.lua
  printf 'assert(require("usecmod").four() == 4)\nprint("c module ok")\n' > library/cmod/test_cmod.lua
  just test //library/cmod:test
  echo "C module loads through LUA_CPATH"
fi

step "lua: binary, bytecode bundle, C host"
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
[[ "$(just run //app/hello:hello -- buck 2>/dev/null | tail -n 1)" == "HELLO, BUCK!" ]]
[[ "$(just run //app/hello:host 2>/dev/null | tail -n 1)" == "HELLO, WORLD!" ]]
echo "lua binary and embedded C host both print through the bundle"

step "lua: Rust host over the hermetic C API"
if ! skip rust; then
  if have rustc; then
    just toolchain add rust
    mkdir -p app/hello-rs
    cat > app/hello-rs/BUCK <<'BUCK'
load("@monomono//rules/lua:defs.bzl", "lua_bundle", "lua_embed")
load("@monomono//rules/lua:toolchain.bzl", "lua_cxx_library")
lua_bundle(name = "bundle", main = "main.lua", deps = ["//library/greet:greet"], dialect = "portable")
lua_embed(name = "embedded", src = ":bundle", lang = "rust", symbol = "hello_lua")
lua_cxx_library(name = "liblua")
rust_binary(name = "host", srcs = ["main.rs"], mapped_srcs = {":embedded": "embedded.rs"}, deps = [":liblua"], crate_root = "main.rs")
BUCK
    printf 'print(require("util").shout(require("greet").hello("rust")))\n' > app/hello-rs/main.lua
    cat > app/hello-rs/main.rs <<'RS'
#![allow(non_camel_case_types)]
use std::ffi::{c_char, c_int, c_void};
mod embedded;
type lua_State = c_void;
extern "C" {
    fn luaL_newstate() -> *mut lua_State;
    fn luaL_openlibs(l: *mut lua_State);
    fn luaL_loadbufferx(l: *mut lua_State, buff: *const c_char, sz: usize, name: *const c_char, mode: *const c_char) -> c_int;
    fn lua_pcallk(l: *mut lua_State, nargs: c_int, nresults: c_int, errfunc: c_int, ctx: isize, k: *const c_void) -> c_int;
    fn lua_tolstring(l: *mut lua_State, idx: c_int, len: *mut usize) -> *const c_char;
    fn lua_close(l: *mut lua_State);
}
fn main() {
    unsafe {
        let l = luaL_newstate();
        luaL_openlibs(l);
        let name = b"embedded\0";
        let rc = luaL_loadbufferx(l, embedded::HELLO_LUA.as_ptr() as *const c_char, embedded::HELLO_LUA.len(), name.as_ptr() as *const c_char, std::ptr::null());
        let rc = if rc == 0 { lua_pcallk(l, 0, 0, 0, 0, std::ptr::null()) } else { rc };
        if rc != 0 {
            let mut n = 0usize;
            let p = lua_tolstring(l, -1, &mut n);
            eprintln!("lua error: {}", std::str::from_utf8(std::slice::from_raw_parts(p as *const u8, n)).unwrap_or("?"));
            std::process::exit(1);
        }
        lua_close(l);
    }
}
RS
    [[ "$(just run //app/hello-rs:host 2>/dev/null | tail -n 1)" == "HELLO, RUST!" ]]
    echo "rust host runs the embedded bundle"
  else
    echo "   (rustc not on PATH; rust host not exercised)"
  fi
fi

step "lua: wasm module for the browser (wasmoon under bun)"
if ! skip wasm; then
  if have bun; then
    mkdir -p app/web
    cat > app/web/BUCK <<'BUCK'
load("@monomono//rules/lua:defs.bzl", "lua_bundle", "lua_wasm")
lua_bundle(name = "bundle", main = "main.lua", deps = ["//library/greet:greet"], dialect = "portable")
lua_wasm(name = "web", src = ":bundle")
BUCK
    printf 'return require("util").shout(require("greet").hello("browser"))\n' > app/web/main.lua
    w=$(buck2 build //app/web:web --show-simple-output 2>/dev/null | tail -n 1)
    mkdir -p "$work/wasm" && cp "$w" "$work/wasm/web.mjs"
    (cd "$work/wasm" && bun add wasmoon@1.16.0 >/dev/null 2>&1 && printf 'import { LuaFactory } from "wasmoon";\nimport { run } from "./web.mjs";\nconst { result } = await run(new LuaFactory());\nconsole.log(result);\n' > run.mjs && [[ "$(bun run run.mjs)" == "HELLO, BROWSER!" ]])
    echo "wasm module runs in wasmoon"
  else
    echo "   (bun not on PATH; wasm not exercised)"
  fi
fi

step "lua: feature tests, Gherkin steps, undefined count, trace / observe / report"
just context feature test demo-app hello lua-red --lua
if just test //context/projects/demo-app/features/hello:hello-lua-red >/dev/null 2>&1; then echo "expected lua red test to fail" >&2; exit 1; fi
printf 'assert(1 + 1 == 2)\n' > context/projects/demo-app/features/hello/test/lua-red.lua
just test //context/projects/demo-app/features/hello:hello
echo "lua feature test red then green"
cat > context/projects/demo-app/features/hello/bdd/greeting.feature <<'FEATURE'
Feature: greeting
  People are greeted by name, loudly when asked.

  Background:
    Given the greeting library

  Scenario: plain greeting
    When "Ada" is greeted
    Then the greeting is "hello, Ada"

  Scenario Outline: shouting
    When "<name>" is greeted loudly
    Then the greeting is "<loud>"

    Examples:
      | name | loud        |
      | Ada  | HELLO, ADA! |
      | Bob  | HELLO, BOB! |
FEATURE
sed -i.bak 's/^mono_feature_tests(/mono_feature_tests(\n    deps = ["\/\/library\/greet:greet"],/' context/projects/demo-app/features/hello/BUCK && rm context/projects/demo-app/features/hello/BUCK.bak
just context feature test demo-app hello --steps
test -f context/projects/demo-app/features/hello/test/steps.lua
grep -q 'is greeted loudly' context/projects/demo-app/features/hello/test/steps.lua
out=$(just run //context/projects/demo-app/features/hello:hello-gherkin 2>&1 | quiet || true)
grep -qE '# 0 passed, [0-9]+ failed, 0 undefined' <<<"$out" && grep -q 'pending' <<<"$out"
echo "skeletons written; pending steps fail, nothing passes by accident"
cat > context/projects/demo-app/features/hello/test/steps.lua <<'LUA'
local steps = require("mono.steps")
steps.given("the greeting library", function(ctx) ctx.g = require("greet"); ctx.u = require("util") end)
steps.when("{string} is greeted", function(ctx, name) ctx.out = ctx.g.hello(name) end)
steps.when("{string} is greeted loudly", function(ctx, name) ctx.out = ctx.u.shout(ctx.g.hello(name)) end)
steps["then"]("the greeting is {string}", function(ctx, want) assert(ctx.out == want, ("got %q"):format(ctx.out)) end)
LUA
out=$(just run //context/projects/demo-app/features/hello:hello-gherkin 2>&1 | quiet || true)
grep -qE '# 3 passed, 0 failed, [1-9][0-9]* undefined' <<<"$out"
echo "unbound sentences (the scaffold's hello.feature) are counted as undefined, not passed"
rm context/projects/demo-app/features/hello/bdd/hello.feature
just test //context/projects/demo-app/features/hello:hello-gherkin
out=$(just run //context/projects/demo-app/features/hello:hello-gherkin 2>&1 | quiet)
grep -q '# 3 passed, 0 failed, 0 undefined' <<<"$out"
out=$(just lua trace //context/projects/demo-app/features/hello:hello-gherkin 2>&1)
grep -q 'monomono.scenario' <<<"$out"
grep -q 'monomono.step' <<<"$out"
test -f trace.json
grep -q '"resourceSpans"' trace.json
grep -q '"monomono.outcome"' trace.json
refute grep -q 'malleable' trace.json
cat > library/greet/profile.lua <<'LUA'
-- a consumer's telemetry profile: its own collector's names (here, an agent harness's) replace monomono's
return {
  version = 1,
  minted = {
    ["malleable.outcome"] = { "passed", "failed", "undefined", "broken", "skipped" },
    ["malleable.undefined"] = "number",
    ["malleable.unclosed"] = "boolean",
    ["malleable.keyword"] = { "given", "when", "then" },
    ["malleable.scenarios"] = "number",
    ["malleable.steps"] = "number",
    ["malleable.passed"] = "number",
    ["malleable.failed"] = "number",
  },
  names = {
    feature = "malleable.feature",
    scenario = "malleable.scenario",
    step = "malleable.step",
    outcome = "malleable.outcome",
    undefined = "malleable.undefined",
    unclosed = "malleable.unclosed",
    keyword = "malleable.keyword",
    scenarios = "malleable.scenarios",
    steps = "malleable.steps",
    passed = "malleable.passed",
    failed = "malleable.failed",
  },
}
LUA
sed -i.bak 's/srcs = \["greet.lua", "util\/init.lua"\]/srcs = ["greet.lua", "util\/init.lua", "profile.lua"]/' library/greet/BUCK && rm library/greet/BUCK.bak
MONO_TELEMETRY_PROFILE=profile MONO_TRACE_OUT="$work/profiled.json" buck2 run //context/projects/demo-app/features/hello:hello-gherkin >/dev/null 2>&1
grep -q '"malleable.scenario ' "$work/profiled.json" && grep -q '"malleable.outcome"' "$work/profiled.json" && grep -q '"malleable.keyword"' "$work/profiled.json"
refute grep -q 'monomono\.' "$work/profiled.json"
just lua fmt //library/greet:fmt >/dev/null
echo "default names are monomono.*; a consumer profile that renames every name leaves no monomono.* key in the trace"
grep -q '"gen_ai' trace.json || true
out=$(just lua observe //context/projects/demo-app/features/hello:hello-gherkin 2>&1)
grep -q 'Scenario: plain greeting' <<<"$out"
grep -q 'Then the greeting is "hello, Ada"' <<<"$out"
MONO_REPORT_OUT="$work/report.json" buck2 run //context/projects/demo-app/features/hello:hello-gherkin >/dev/null 2>&1
grep -q '"outcome":"passed"' "$work/report.json"
grep -q '"line"' "$work/report.json"
echo "span tree, OTLP trace.json, Gherkin observed from the trace, JSON report"

step "lua: coverage + profile"
expect "coverage: [0-9]+/[0-9]+ lines" just lua cover //library/greet:tests-test_greet
grep -q '^SF:' coverage.txt && grep -q 'greet.lua' coverage.txt
expect "profile|ms|calls" just lua profile //library/greet:tests-test_greet
echo "lcov-style coverage.txt and a profile"

step "lua: script backend + pre-build hook"
mkdir -p scripts/hooks
printf 'local mono = require("mono")\nprint("tool says " .. (arg[1] or "nothing") .. " via " .. _VERSION)\n' > scripts/tools/greet.lua
[[ "$(just tool greet hi 2>/dev/null | tail -n 1)" == "tool says hi via Lua 5.4" ]]
printf 'print("hook ran")\n' > scripts/hooks/pre-build.lua
expect "hook ran" just build
rm scripts/hooks/pre-build.lua
echo "just tool runs .lua backends; hooks/pre-build.lua runs before buck2 build"

step "lua: other interpreters (5.1, 5.3, LuaJIT) via the toolchain attr"
if ! skip interpreters; then
  cat >> toolchains/BUCK <<'BUCK'
load("@monomono//rules/lua:toolchain.bzl", "lua_hermetic_toolchain", "luajit_hermetic_toolchain")
lua_hermetic_toolchain(name = "lua51", version = "5.1.5")
lua_hermetic_toolchain(name = "lua53", version = "5.3.6")
luajit_hermetic_toolchain(name = "luajit")
BUCK
  mkdir -p app/multi
  cat > app/multi/BUCK <<'BUCK'
load("@monomono//rules/lua:defs.bzl", "lua_binary", "lua_test", "lua_bundle")
lua_binary(name = "v51", main = "main.lua", deps = ["//library/greet:greet"], toolchain = "toolchains//:lua51")
lua_binary(name = "v53", main = "main.lua", deps = ["//library/greet:greet"], toolchain = "toolchains//:lua53")
lua_binary(name = "vjit", main = "main.lua", deps = ["//library/greet:greet"], toolchain = "toolchains//:luajit")
lua_test(name = "test-jit", src = "test_greet.lua", deps = ["//library/greet:greet"], toolchain = "toolchains//:luajit")
lua_test(name = "test-51", src = "test_greet.lua", deps = ["//library/greet:greet"], toolchain = "toolchains//:lua51")
lua_bundle(name = "bc-jit", main = "main.lua", deps = ["//library/greet:greet"], dialect = "jit", bytecode = True, toolchain = "toolchains//:luajit")
lua_bundle(name = "bc-51", main = "main.lua", deps = ["//library/greet:greet"], dialect = "5.1", bytecode = True, toolchain = "toolchains//:lua51")
BUCK
  printf 'print((jit and jit.version or _VERSION) .. ": " .. require("util").shout(require("greet").hello("world")))\n' > app/multi/main.lua
  cp library/greet/test_greet.lua app/multi/
  [[ "$(just run //app/multi:v51 2>/dev/null | tail -n 1)" == "Lua 5.1: HELLO, WORLD!" ]]
  [[ "$(just run //app/multi:v53 2>/dev/null | tail -n 1)" == "Lua 5.3: HELLO, WORLD!" ]]
  expect 'LuaJIT 2.1.*: HELLO, WORLD!' just run //app/multi:vjit
  just test //app/multi:test-jit //app/multi:test-51
  head -c 3 "$(buck2 build //app/multi:bc-jit --show-simple-output 2>/dev/null | tail -n 1)" | grep -q 'LJ'
  head -c 4 "$(buck2 build //app/multi:bc-51 --show-simple-output 2>/dev/null | tail -n 1)" | grep -q 'Lua'
  echo "5.1, 5.3 and LuaJIT build hermetically; tests and bytecode per target"
fi

step "area add"
just area add server "Internal API."
test -f server/AGENTS.md

step "agents"
just agents sync
test -f .agents/skills/features/demo-app/hello/SKILL.md
just agents check

step "check (definition of green)"
just check

step "update path: a 0.4.0-shaped consumer runs migration 0.4.1 (migrate + sync)"
git -C packages/monomono checkout -q "$ref"
sed -i.bak -e 's|^/\.luarc\.json$|.luarc.json|' -e 's|^/\.lua-meta/$|.lua-meta/|' -e 's|^/coverage\.txt$|coverage.txt|' -e 's|^/trace\.json$|trace.json|' -e 's|^/\.buckconfig\.local$|.buckconfig.local|' .gitignore && rm .gitignore.bak
sed -i.bak '/^set allow-duplicate-recipes/d' justfile && rm justfile.bak
sed -i.bak 's/^version = ".*"/version = "0.4.0"/' mono.toml && rm mono.toml.bak
refute grep -qx '/.luarc.json' .gitignore
refute grep -q '^set allow-duplicate-recipes' justfile
out=$(just mono migrate 2>&1); echo "$out"
grep -q '^migrate 0.4.1$' <<<"$out"
grep -q '^migrations run: 1 (0.4.0 -> ' <<<"$out"
grep -q "^version = \"$(cat packages/monomono/VERSION)\"" mono.toml
just mono status
printf '\n# a consumer recipe shadows the package one of the same name\ndoctor:\n    @echo "my doctor"\n' >> justfile
[[ "$(just doctor)" == "my doctor" ]]
sed -i.bak '/^# a consumer recipe shadows/,$d' justfile && rm justfile.bak
grep -qx '/.luarc.json' .gitignore && grep -qx '/.buckconfig.local' .gitignore
mkdir -p library && printf '{}\n' > library/.luarc.json && printf '{}\n' > .luarc.json
refute git check-ignore -q library/.luarc.json
git check-ignore -q .luarc.json
rm library/.luarc.json .luarc.json
echo "allow-duplicate-recipes: your recipe wins; ignores are anchored, a committed library/.luarc.json survives (the root one is ignored)"

step "provider mode: an app that ships the package refuses just mono update"
cp mono.toml "$work/mono.toml.bak"
sed -i.bak 's/^mode = "submodule"/mode = "submodule"\nprovider = "someapp"/' mono.toml && rm mono.toml.bak
if just mono update >/dev/null 2>&1; then echo "expected update to refuse under a provider" >&2; exit 1; fi
expect "provided by someapp" just mono update
expect "by someapp" just doctor
cp "$work/mono.toml.bak" mono.toml
echo "provider refusal + doctor line"
toolpath "$work/nogit" 'git' 'git-*'
sed -i.bak 's/^mode = "submodule"/mode = "vendor"/' mono.toml && rm mono.toml.bak
if PATH="$work/nogit" MONO_REPO_URL=https://127.0.0.1:9/none just mono update >"$work/out" 2>&1; then echo "expected update to refuse under mode = vendor" >&2; exit 1; fi
grep -q 'monomono is vendored' "$work/out"
cp "$work/mono.toml.bak" mono.toml
echo "mode = vendor alone refuses just mono update, with no git on PATH (it never fetches)"

# --- a second consumer, in a path with a space, without the hermetic interpreter --------

step "lua-host + lua-config: no hermetic interpreter, in a path with a space"
lua_bin=$(buck2 build 'toolchains//:lua-build[lua]' --target-platforms prelude//platforms:default --show-simple-output 2>/dev/null | tail -n 1)
lua_bin="$work/demo/$lua_bin"
mkdir -p "$work/host demo"
git -C "$work/host demo" init -q
git -C "$work/host demo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
MONO_REPO_URL="$here" "$here/bin/monomono" init "$work/host demo" --ref "$ref" --name hostdemo
overlay "$work/host demo/packages/monomono"
cd "$work/host demo"
cat > app-host.sh <<SH
#!/usr/bin/env bash
# host <module> -- args : what an app's sandboxed runtime would do
main=\$1; shift; [[ \${1-} == -- ]] && shift
echo "host: ran \$main inside the app runtime" >&2
exec "$lua_bin" "\$main" "\$@"
SH
chmod +x app-host.sh
just toolchain add lua-host
printf '[lua]\n  host = %s/app-host.sh\n  bin = %s\n' "$work/host demo" "$lua_bin" > .buckconfig.local   # both set: host wins for tests, bin serves bundle/meta
mkdir -p library/x
cat > library/x/BUCK <<'BUCK'
load("@monomono//rules/lua:defs.bzl", "lua_library", "lua_test", "lua_bundle", "lua_meta", "lua_feature_test")
lua_library(name = "x", srcs = ["x.lua"])
lua_test(name = "test", src = "test_x.lua", deps = [":x"])
lua_bundle(name = "bundle", main = "test_x.lua", deps = [":x"], dialect = "portable")
lua_meta(name = "meta", deps = [":x"])
lua_feature_test(name = "gherkin", features = ["x.feature"], steps = "steps.lua", deps = [":x"])
BUCK
printf 'return { two = function() return 2 end }\n' > library/x/x.lua
printf 'assert(require("x").two() == 2)\nprint("x ok")\n' > library/x/test_x.lua
printf 'Feature: x\n  Scenario: two\n    Given two is two\n' > library/x/x.feature
printf 'local steps = require("mono.steps")\nsteps.given("two is two", function(ctx) assert(require("x").two() == 2) end)\n' > library/x/steps.lua
just test //library/x:test
expect "ran .* inside the app runtime" just run //library/x:test
expect "ok=" just doctor
echo "tests run through the host command; doctor does not demand make/cc"
just build //library/x:bundle //library/x:meta
grep -q '"=x"' "$(buck2 build //library/x:bundle --show-simple-output 2>/dev/null | tail -n 1)"
test -f "$(buck2 build //library/x:meta --show-simple-output 2>/dev/null | tail -n 1)/x.lua"
just test //library/x:gherkin
expect "ran .*features.lua inside the app runtime" just run //library/x:gherkin
expect "# 1 passed, 0 failed, 0 undefined" just run //library/x:gherkin
echo "with both host and bin set: bundle and meta build through bin, the bundled feature runner runs through the host"
cp toolchains/BUCK "$work/tc.bak"
sed -i.bak '/^# monomono:toolchain lua-host$/d' toolchains/BUCK && rm toolchains/BUCK.bak
expect 'without a "# monomono:toolchain' just doctor
cp "$work/tc.bak" toolchains/BUCK
echo "a toolchains/BUCK that declares toolchains//:lua without its marker line gets a doctor warning"
mkdir -p scripts/hooks && printf 'print("lua hook ran")\n' > scripts/hooks/pre-build.lua
expect "ran .* inside the app runtime" just build
rm scripts/hooks/pre-build.lua
just context project new p >/dev/null && just context feature new p f >/dev/null
expect "step skeleton" just context feature test p f --steps
echo "under lua-host the .lua hook and the --steps writer run through the host command"
sed -i.bak '/# monomono:toolchain lua-host/,$d' toolchains/BUCK && rm toolchains/BUCK.bak
just toolchain add lua-config
printf '[lua]\n  bin = %s\n' "$lua_bin" > .buckconfig.local
just test //library/x:test
echo "lua-config points toolchains//:lua at a configured interpreter"
printf 'print("config tool says " .. arg[1])\n' > scripts/tools/cfg.lua
[[ "$(just tool cfg hi 2>/dev/null | tail -n 1)" == "config tool says hi" ]]
echo "under lua-config the .lua backends run through [lua] bin"

# --- a third consumer: vendored (the package is a sibling cell, no submodule), no context module, no python on PATH

step "vendored sibling cell in a folder that is not a git repository, --no-context, and a PATH without python or git"
# the package is copied in by the app that ships it (no bin/monomono, no clone); nothing here may need git
mkdir -p "$work/vend/packages"
toolpath "$work/nopy" 'python*' 'pip*' 'git' 'git-*'
[[ ! -e $work/nopy/python3 && ! -e $work/nopy/python && ! -e $work/nopy/git ]]
mkdir -p "$work/vend/packages/monomono" && overlay "$work/vend/packages/monomono"
cd "$work/vend"
test ! -d .git
MONO_HOME="$PWD/packages/monomono" MONO_ROOT="$PWD" PATH="$work/nopy" bash packages/monomono/scripts/tools/mono.sh init --mode vendor --provider selftest --no-context --name vend
test ! -d packages/monomono/.git
grep -q 'context = "false"' mono.toml
grep -q 'mode = "vendor"' mono.toml
PATH="$work/nopy" just toolchain add lua >/dev/null
mkdir -p library/v
printf 'load("@monomono//rules/lua:defs.bzl", "lua_library", "lua_test")\nlua_library(name = "v", srcs = ["v.lua"])\nlua_test(name = "test", src = "t.lua", deps = [":v"])\n' > library/v/BUCK
printf 'return { one = 1 }\n' > library/v/v.lua
printf 'assert(require("v").one == 1)\n' > library/v/t.lua
out=$(PATH="$work/nopy" just doctor 2>&1) || { echo "$out"; exit 1; }
refute grep -q 'sqlite3' <<<"$out"
grep -q 'vendored by selftest' <<<"$out"
grep -q 'git not installed (optional' <<<"$out"
PATH="$work/nopy" just check
expect "provided by selftest" env PATH="$work/nopy" just mono update
echo "vendored @monomono cell loads from packages/monomono in a non-git folder; no sqlite3 asked for; just check green with no python and no git on PATH"

echo
echo "selftest ok"
