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
