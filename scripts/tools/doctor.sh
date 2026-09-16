#!/usr/bin/env bash
# Required binaries and repo shape. Domain-free: checks the contract, not a product.

source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

ok=0; warn=0; fail=0
pass() { echo "ok    $*"; ok=$((ok + 1)); }
note() { echo "warn  $*"; warn=$((warn + 1)); }
bad()  { echo "fail  $*" >&2; fail=$((fail + 1)); }

need() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "$1 $($1 --version 2>/dev/null | head -n 1 | tr -s ' ' | cut -c1-60)"
  else
    bad "missing $1${2:+ ($2)}"
  fi
}

need just
need git
need buck2 "just setup installs it"
need python3

if mono_module context; then
  need sqlite3 "context module"
fi

if [[ -f $MONO_MANIFEST ]]; then
  pinned=$(toml_get monomono version || true)
  if [[ $pinned == "$MONO_VERSION" ]]; then
    pass "mono.toml $pinned matches .mono"
  else
    bad "mono.toml says ${pinned:-none}, .mono is $MONO_VERSION; just mono migrate"
  fi
else
  bad "mono.toml missing; run .mono/bin/monomono init"
fi

if [[ $MONO_HOME != "$MONO_ROOT" ]]; then
  if [[ -f $MONO_ROOT/.gitmodules ]] && grep -q 'path = .mono' "$MONO_ROOT/.gitmodules"; then
    pass ".mono is a submodule ($(git -C "$MONO_HOME" describe --tags --always 2>/dev/null))"
  elif [[ $(toml_get monomono mode) == vendor ]]; then
    pass ".mono is vendored"
  else
    note ".mono is neither a submodule nor marked vendor in mono.toml"
  fi
fi

if [[ $(toml_get monomono mode) == self ]]; then
  pass "package self-mode; buck2 project checks skipped"
else
  for f in .buckroot .buckconfig BUCK toolchains/BUCK; do
    [[ -e $MONO_ROOT/$f ]] && pass "$f" || bad "$f missing; just mono sync"
  done
  if [[ -f $MONO_ROOT/.buckconfig ]] && grep -qE '^\s*monomono\s*=' "$MONO_ROOT/.buckconfig"; then
    pass ".buckconfig declares the monomono cell"
  else
    note ".buckconfig has no monomono cell; @monomono// rules unavailable"
  fi
fi

if [[ -f $MONO_ROOT/justfile ]] && grep -qE "^import .*mono\.just" "$MONO_ROOT/justfile"; then
  pass "justfile imports mono.just"
else
  bad "justfile must import the package recipes (import '.mono/mono.just')"
fi

if [[ -L $MONO_ROOT/AGENTS.md && $(readlink "$MONO_ROOT/AGENTS.md") == .agents/AGENTS.md ]]; then
  pass "AGENTS.md -> .agents/AGENTS.md"
elif [[ -f $MONO_ROOT/AGENTS.md ]] && cmp -s "$MONO_ROOT/AGENTS.md" "$MONO_AGENTS/AGENTS.md"; then
  pass "AGENTS.md is a copy of .agents/AGENTS.md"
else
  bad "AGENTS.md is not linked; just agents sync"
fi
[[ -f $MONO_ROOT/CLAUDE.md ]] && pass "CLAUDE.md bootstrap" || note "CLAUDE.md missing (Claude Code bootstrap)"
for host in .cursor .claude .codex; do
  [[ -d $MONO_ROOT/$host ]] && note "$host/ exists; standing rules belong in .agents/"
done

if [[ -f $MONO_ROOT/.gitignore ]] && grep -qE '^\.env$' "$MONO_ROOT/.gitignore"; then
  pass ".gitignore blocks .env"
else
  bad ".gitignore must ignore .env"
fi
if [[ -f $MONO_ROOT/.gitignore ]] && grep -qE '^buck-out/?$' "$MONO_ROOT/.gitignore"; then
  pass ".gitignore blocks buck-out"
else
  bad ".gitignore must ignore buck-out/"
fi

# Ecosystem manifests belong under packages/<eco>. Anything else is a stray toolchain root.
strays=$(cd "$MONO_ROOT" && find . \
  \( -path ./.git -o -path ./.mono -o -path ./packages -o -path ./submodules -o -path ./buck-out -o -name node_modules -o -name target -o -name _build -o -name deps -o -name .venv \) -prune -o \
  -type f \( -name package.json -o -name Cargo.toml -o -name mix.exs -o -name pyproject.toml -o -name go.mod -o -name Gemfile -o -name Package.swift -o -name '*.lock' -o -name '*.lockb' \) -print \
  | grep -vE '^\./(buck-out|BUCK)' | sed 's#^\./##' | head -n 10 || true)
if [[ -n $strays ]]; then
  note "ecosystem manifests outside packages/: $(echo "$strays" | tr '\n' ' ')"
else
  pass "no ecosystem manifests outside packages/"
fi

if [[ -d $MONO_PACKAGES ]]; then
  for eco in "$MONO_PACKAGES"/*/; do
    [[ -d $eco ]] || continue
    name=$(basename "$eco")
    if [[ -f $eco/.eco || -x $eco/adapter.sh ]]; then
      pass "packages/$name adapter $(cat "$eco/.eco" 2>/dev/null || echo local)"
    else
      note "packages/$name has no adapter; just pkg init $name <adapter>"
    fi
  done
fi

for area in "$MONO_ROOT"/*/; do
  name=$(basename "$area")
  case "$name" in buck-out|node_modules|submodules|toolchains) continue ;; esac
  [[ -d $area ]] || continue
  [[ -f $area/AGENTS.md ]] || note "$name/ has no AGENTS.md"
done

if [[ -d $MONO_CI/github ]]; then
  if "$MONO_HOME/scripts/tools/ci.sh" status --quiet; then
    pass ".github/workflows matches git/ci/github"
  else
    note ".github/workflows out of date; just ci sync"
  fi
fi

if [[ -f $MONO_AGENTS/skills/AGENTS.md ]]; then
  pass "generated skills present"
else
  note "skills not generated; just agents sync"
fi

if mono_module context && command -v sqlite3 >/dev/null 2>&1; then
  "$MONO_HOME/scripts/tools/context/db.sh" init
  pass "context.sqlite initialized"
fi

echo
echo "ok=$ok warn=$warn fail=$fail"
[[ $fail -eq 0 ]]
