#!/usr/bin/env bash
# Bun workspace. Manifest and lockfile stay in PKG_DIR; members are folders elsewhere in the repo.
set -euo pipefail
cd "$PKG_DIR"
case "${1:-}" in
  ensure)
    command -v bun >/dev/null || { echo "bun not installed" >&2; exit 1; }
    [[ -f package.json ]] || printf '{\n  "name": "%s",\n  "private": true,\n  "workspaces": []\n}\n' "$PKG_ECO" >package.json ;;
  add) shift; bun add "$@" ;;
  update) shift; bun update "$@" ;;
  sync) bun install ;;
  *) echo "bun adapter: ensure|add|update|sync" >&2; exit 2 ;;
esac
