#!/usr/bin/env bash
# 0.2.0: the package moves from .mono to packages/monomono.
# Rewrites the submodule path, the justfile import, the buck2 cell, and mono.toml.
set -euo pipefail
cd "$MONO_ROOT"
[[ -d .mono ]] || { echo "  no .mono to move"; exit 0; }
mkdir -p packages
if [[ -f .gitmodules ]] && grep -q 'path = .mono' .gitmodules; then
  git mv .mono packages/monomono
  git config -f .gitmodules submodule.monomono.path packages/monomono
  git submodule sync -q -- packages/monomono 2>/dev/null || true
else
  mv .mono packages/monomono
fi
sed -i.bak "s#import '.mono/mono.just'#import 'packages/monomono/mono.just'#" justfile && rm -f justfile.bak
sed -i.bak 's#^\(\s*monomono\s*=\s*\)\.mono$#\1packages/monomono#' .buckconfig && rm -f .buckconfig.bak
sed -i.bak 's#^path = ".mono"$#path = "packages/monomono"#' mono.toml && rm -f mono.toml.bak
grep -q '^path = ' mono.toml || sed -i.bak 's#^mode = \(.*\)$#mode = \1\npath = "packages/monomono"#' mono.toml && rm -f mono.toml.bak
grep -rl '`\.mono' .agents/AGENTS.md scripts/AGENTS.md packages/AGENTS.md CLAUDE.md 2>/dev/null | xargs -I{} sed -i.bak 's#\.mono/#packages/monomono/#g; s#`\.mono`#`packages/monomono`#g' {} ; find . -maxdepth 3 -name '*.bak' -delete
echo "  moved .mono -> packages/monomono"
