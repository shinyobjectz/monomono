#!/usr/bin/env bash
# 0.4.1: generated-file ignores are anchored to the repo root, so a committed library/.luarc.json is not swallowed;
# the justfile allows your own recipes to shadow package ones (set allow-duplicate-recipes).
set -euo pipefail
cd "$MONO_ROOT"
if [[ -f .gitignore ]]; then
  for p in .buckconfig.local .luarc.json .lua-meta/ coverage.txt trace.json; do
    grep -qxF "$p" .gitignore && sed -i.bak "s|^$(printf '%s' "$p" | sed 's/[.]/\\./g')\$|/$p|" .gitignore && rm -f .gitignore.bak
  done
fi
if [[ -f justfile ]] && ! grep -q '^set allow-duplicate-recipes' justfile; then
  sed -i.bak 's|^set shell := \(.*\)$|set shell := \1\nset allow-duplicate-recipes   # your recipe below wins over the package'"'"'s of the same name|' justfile && rm -f justfile.bak
fi
echo "  .gitignore patterns anchored; justfile allows duplicate recipes"
